import os
import time
import json
import asyncio
import tempfile
import wave
from typing import Dict, Any
from fastapi import WebSocket
from logging_config import log
from auth import validate_token
from engine.base_engine import BaseEngine
from security.governance import SecurityGovernance, MAX_CONNECTIONS, IDLE_TIMEOUT_SECONDS, HANDSHAKE_TIMEOUT_SECONDS, NO_AUDIO_GRACE_SECONDS
from security.sanitizer import Sanitizer
from collections import defaultdict

# Max buffer size (in bytes) for 5 minutes of 16kHz, 16-bit mono audio
MAX_BUFFER_SIZE = int(os.getenv("MAX_BUFFER_SIZE", "9600000"))

class ConnectionManager:
    """Manages WebSocket connection lifecycle, protocol state, and audio processing."""
    def __init__(self, engine: BaseEngine, app_version: str, min_client_version: str = "0.0.0", sec_client_version: str = "0.0.0"):
        self.active_connections: Dict[WebSocket, Dict[str, Any]] = {}
        self.engine = engine
        self.app_version = app_version
        self.min_client_version = min_client_version
        self.sec_client_version = sec_client_version
        self.governance = SecurityGovernance()
        self.last_tracker_cleanup = time.time()
        
        # Identity-Pinned Concurrency (IPC) Guard: 1 transcription per user at a time
        self.user_semaphores = defaultdict(lambda: asyncio.Semaphore(1))
        
        # Performance & Throughput Monitoring
        self.bytes_received: Dict[WebSocket, int] = defaultdict(int)
        
        # Start background cleanup — guard against sync contexts (tests, scripts)
        _coro = self._cleanup_inactive_connections()
        try:
            self.cleanup_task = asyncio.create_task(_coro)
        except RuntimeError:
            _coro.close()
            self.cleanup_task = None
        log.info(f"ConnectionManager initialized. Proxy-Ready. Max Connections: {MAX_CONNECTIONS}")

    async def connect(self, websocket: WebSocket):
        ip = websocket.client.host
        
        # 1. Check for Active Bans
        is_banned, remaining = self.governance.is_ip_banned(ip)
        if is_banned:
            log.warning(f"BANNED CLIENT: {ip} rejected. Active ban in effect. Retry in {remaining}s.")
            await websocket.accept()
            await websocket.send_json({"event": "error", "code": 1008, "message": f"IP Banned. Cooldown: {remaining}s"})
            await websocket.close(code=1008, reason=f"IP Banned. Cooldown: {remaining}s")
            return

        # 2. Max Connections Check
        if len(self.active_connections) >= MAX_CONNECTIONS:
            log.warning(f"Connection rejected for {websocket.client}: Max connections reached.")
            await websocket.accept()
            await websocket.send_json({"event": "error", "code": 1008, "message": "Max concurrent connections reached"})
            await websocket.close(code=1008, reason="Max concurrent connections reached")
            return

        # 3. Track Attempt
        self.governance.record_connection_attempt(ip)

        await websocket.accept()
        conn_id = str(id(websocket))[-4:]
        now = time.time()
        self.active_connections[websocket] = {
            "buffer": bytearray(),
            "last_activity": now,
            "connected_at": now,
            "last_audio_received": None,
            "handshake_completed": False,
            "id": conn_id,
            "incognito": False
        }
        log.info(f"[{conn_id}] WebSocket client connected from {ip}")
        
        await websocket.send_json({
            "event": "hello",
            "server": "WhisperDoc Backend",
            "version": self.app_version,
            "min_version": self.min_client_version,
            "sec_version": self.sec_client_version,
            "status": "ready" if self.engine.is_loaded() else "idle",
            "cid": conn_id
        })

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            conn_id = self.active_connections[websocket].get("id", "????")
            del self.active_connections[websocket]
            if websocket in self.bytes_received:
                del self.bytes_received[websocket]
            log.info(f"[{conn_id}] WebSocket client disconnected: {websocket.client}")

    async def _cleanup_inactive_connections(self):
        while True:
            try:
                await asyncio.sleep(10)
                now = time.time()
                to_disconnect = []

                for websocket, data in self.active_connections.items():
                    idle_time = now - data["last_activity"]
                    
                    if not data["handshake_completed"] and idle_time > HANDSHAKE_TIMEOUT_SECONDS:
                        log.warning(f"Closing un-handshaked connection from {websocket.client} (Timeout)")
                        to_disconnect.append((websocket, 1008, "Handshake timeout"))
                        self.governance.record_protocol_violation(websocket.client.host)
                        continue

                    if idle_time > IDLE_TIMEOUT_SECONDS:
                        log.warning(f"Closing inactive connection for client {websocket.client}")
                        to_disconnect.append((websocket, 4000, "Inactivity timeout"))
                        continue

                    # Anti-slot-hogging: kick authenticated connections with no audio activity.
                    # Catches clients that hold a slot via keep-alive pings without ever transcribing.
                    # Uses last_audio_received (set only on binary audio chunks) rather than a
                    # lifetime throughput average, which false-positives on short push-to-talk clips.
                    if data["handshake_completed"]:
                        connection_age = now - data["connected_at"]
                        last_audio = data.get("last_audio_received")
                        no_audio_ever = last_audio is None and connection_age > NO_AUDIO_GRACE_SECONDS
                        audio_stale = last_audio is not None and (now - last_audio) > IDLE_TIMEOUT_SECONDS
                        if no_audio_ever or audio_stale:
                            log.warning(f"Closing slot-hogging connection from {websocket.client} (no audio activity)")
                            to_disconnect.append((websocket, 4001, "No audio activity"))

                for websocket, code, reason in to_disconnect:
                    try:
                        await websocket.close(code=code, reason=reason)
                    except Exception as e:
                        log.debug(f"Error closing WebSocket ({reason}): {e}")
                    self.disconnect(websocket)
                    
                # Robust Tracker Cleanup: Every 1 hour
                if now - self.last_tracker_cleanup > 3600:
                    self.governance.clear_old_trackers()
                    # Prune IPC semaphores for users with no active connections to prevent unbounded growth
                    active_user_ids = {d.get("user_id") for d in self.active_connections.values() if d.get("user_id")}
                    stale_ids = [uid for uid in self.user_semaphores if uid not in active_user_ids]
                    for uid in stale_ids:
                        del self.user_semaphores[uid]
                    if stale_ids:
                        log.debug(f"Maintenance: Pruned {len(stale_ids)} stale IPC semaphore(s).")
                    self.last_tracker_cleanup = now
                    log.debug("Maintenance: Security trackers cleared.")

            except Exception as e:
                log.error(f"Error in cleanup task: {e}")

    async def handle_message(self, websocket: WebSocket, message):
        connection_data = self.active_connections.get(websocket)
        if not connection_data: return

        connection_data["last_activity"] = time.time()
        conn_id = connection_data.get("id", "????")
        handshake_done = connection_data.get("handshake_completed", False)
        ip = websocket.client.host

        if isinstance(message, str):
            try:
                try: data = json.loads(message)
                except json.JSONDecodeError:
                    log.warning(f"[{conn_id}] Protocol Violation: Malformed JSON.")
                    self.governance.record_protocol_violation(ip)
                    await websocket.send_json({"event": "error", "code": 1008, "message": "Malformed JSON"})
                    await websocket.close(code=1008, reason="Malformed JSON")
                    return

                event = data.get("event")

                if not handshake_done:
                    if event != "hello":
                        log.warning(f"[{conn_id}] Protocol Violation: Expected 'hello', got '{event}'.")
                        self.governance.record_protocol_violation(ip)
                        await websocket.send_json({"event": "error", "code": 1008, "message": "Handshake required"})
                        await websocket.close(code=1008, reason="Handshake required")
                        return

                    token = data.get("token")
                    auth_type = data.get("auth_type", "api_key")
                    client_version = data.get("version", "0.0.0")
                    client_type = data.get("client", "unknown")

                    # 1. Version Validation (Hardened Gate)
                    def is_lower(v1, v2):
                        try:
                            v1_parts = [int(p) for p in v1.split('+')[0].split('-')[0].split('.')]
                            v2_parts = [int(p) for p in v2.split('+')[0].split('-')[0].split('.')]
                            for i in range(3):
                                p1 = v1_parts[i] if i < len(v1_parts) else 0
                                p2 = v2_parts[i] if i < len(v2_parts) else 0
                                if p1 < p2: return True
                                if p1 > p2: return False
                            return False
                        except: 
                            # Fail-Secure: Invalid version format is treated as "Outdated/Rejected"
                            return True

                    if is_lower(client_version, self.min_client_version):
                        log.warning(f"[{conn_id}] BLOCKED: Outdated client ({client_version}) < MIN ({self.min_client_version})")
                        await websocket.send_json({
                            "event": "error", 
                            "code": 1008, 
                            "message": f"Update required: v{self.min_client_version} (Client: {client_version})"
                        })
                        await websocket.close(code=1008)
                        self.governance.record_protocol_violation(ip)
                        return
                    
                    if is_lower(client_version, self.sec_client_version):
                        log.info(f"[{conn_id}] ADVISORY: Outdated client ({client_version}) < SEC ({self.sec_client_version})")
                    else:
                        log.debug(f"[{conn_id}] HANDSHAKE: Client version {client_version} verified.")

                    if auth_type == "oidc":
                        # Validate JWT and extract identity
                        from auth.oidc import validate_oidc_token
                        payload = validate_oidc_token(token)
                        if not payload:
                            log.warning(f"[{conn_id}] OIDC Authentication Failed.")
                            self.governance.record_protocol_violation(ip)
                            await websocket.send_json({"event": "error", "code": 403, "message": "OIDC Authentication failed"})
                            await websocket.close(code=1008)
                            return
                        
                        # Identify user by OIDC 'sub' claim
                        connection_data["user_id"] = payload.get("sub")
                        connection_data["user_email"] = payload.get("email")
                        log.info(f"[{conn_id}] OIDC Verified for: {connection_data['user_email']}")
                    else:
                        # Fallback to static API key validation
                        if not validate_token(token):
                            log.warning(f"[{conn_id}] API Key Authentication Failed.")
                            self.governance.record_protocol_violation(ip)
                            await websocket.send_json({"event": "error", "code": 403, "message": "API Key Authentication failed"})
                            await websocket.close(code=1008)
                            return
                        connection_data["user_id"] = "static_apiKey"

                    connection_data["handshake_completed"] = True
                    connection_data["auth_type"] = auth_type
                    connection_data["incognito"] = data.get("incognito", False)
                    log.info(f"[{conn_id}] Handshake Verified ({auth_type}) | {client_type} (v{client_version}) | Incognito: {connection_data['incognito']}")

                    await websocket.send_json({"event": "authenticated", "status": "success", "cid": conn_id})

                    # TRIGGER WARMUP: Load model in background if not already loaded.
                    # Guard skips the task entirely for reconnecting clients whose model is still hot,
                    # avoiding a pointless thread spawn and last_used timestamp churn.
                    if not self.engine.is_loaded():
                        asyncio.create_task(self._warmup_model())
                    return

                if event == "hello":
                    await websocket.close(code=1008, reason="Handshake already completed")
                    return
                
                if event == "end-of-stream":
                    log.info(f"[{conn_id}] Received EOS.")
                    await self.transcribe_and_send(websocket)
                elif event == "ping":
                    await websocket.send_json({"event": "pong"})
                else:
                    await websocket.close(code=1008, reason=f"Invalid event: {event}")
            
            except Exception as e:
                log.error(f"[{conn_id}] Error in text handler: {e}")
                try:
                    await websocket.close(code=1011)
                except Exception as ce:
                    log.debug(f"[{conn_id}] Error closing WebSocket after handler error: {ce}")

        elif isinstance(message, bytes):
            if not handshake_done:
                self.governance.record_protocol_violation(ip)
                await websocket.close(code=1008, reason="Handshake required")
                return
            
            connection_data["last_audio_received"] = time.time()
            buffer = connection_data["buffer"]
            if len(buffer) < MAX_BUFFER_SIZE:
                buffer.extend(message)
                self.bytes_received[websocket] += len(message)
            else:
                log.warning(f"[{conn_id}] Resource Exhaustion: Buffer limit reached.")
                await websocket.close(code=1009, reason="Buffer limit exceeded")
                self.disconnect(websocket)

    async def _warmup_model(self):
        """Background task to ensure model is loaded into GPU."""
        try:
            log.info("BACKGROUND: Triggering model warmup...")
            # to_thread prevents blocking the event loop during the 2-5s load
            await asyncio.to_thread(self.engine.warmup)
            log.debug("BACKGROUND: Model warmup attempt completed.")
        except Exception as e:
            log.error(f"BACKGROUND: Model warmup failed: {e}")

    async def transcribe_and_send(self, websocket: WebSocket):
        data = self.active_connections.get(websocket)
        if not data: return
        
        buffer = data["buffer"]
        conn_id = data.get("id", "????")
        is_incognito = data.get("incognito", False)
        
        if not buffer:
            log.warning(f"[{conn_id}] Transcription requested but buffer is empty.")
            await websocket.send_json({"event": "error", "code": "NO_AUDIO", "message": "No audio data received"})
            return

        tmp_path = None
        try:
            user_id = data.get("user_id", "anonymous")

            # IPC GUARD: Per-Identity Concurrency Lock
            # Ensures User A cannot bomb the GPU while User B remains unblocked.
            async with self.user_semaphores[user_id]:
                log.debug(f"[{conn_id}] IPC-LOCK ACQUIRED. Running transcription...")

                # Wrap the raw PCM buffer in a proper WAV header
                with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
                    with wave.open(tmp, 'wb') as wf:
                        wf.setnchannels(1)
                        wf.setsampwidth(2) # 16-bit
                        wf.setframerate(16000)
                        wf.writeframes(buffer)
                    tmp_path = tmp.name

                # engine.transcribe() is synchronous and handles load-on-demand
                # internally. Run in a thread to keep the WebSocket loop alive.
                result = await asyncio.to_thread(self.engine.transcribe, tmp_path)

            # 1. Backend Sanitization (Zero-Latency Security Gate)
            full_text = Sanitizer.sanitize(result.text)
            safe_segments = [
                {
                    "start": s.start,
                    "end": s.end,
                    "text": Sanitizer.sanitize(s.text),
                }
                for s in result.segments
            ]
            
            # 2. Security: Wipe buffer immediately
            data["buffer"] = bytearray()

            if not is_incognito:
                log.success(f"[{conn_id}] Transcription complete: {full_text[:50]}...")
            else:
                log.log("PRIVACY", f"[{conn_id}] Transcription complete [REDACTED]")

            await websocket.send_json({
                "event": "transcription",
                "text": full_text,
                "segments": safe_segments,
                "processing_time": result.processing_time
            })
            
        except Exception as e:
            log.error(f"[{conn_id}] Transcription failed: {e}")
            await websocket.send_json({"event": "error", "message": "Transcription failed"})
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except Exception as e:
                    log.debug(f"[{conn_id}] Failed to delete temp file {tmp_path}: {e}")
