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
from engine.model_manager import ModelManager
from security.governance import SecurityGovernance, MAX_CONNECTIONS, IDLE_TIMEOUT_SECONDS, HANDSHAKE_TIMEOUT_SECONDS

# Max buffer size (in bytes) for 5 minutes of 16kHz, 16-bit mono audio
MAX_BUFFER_SIZE = int(os.getenv("MAX_BUFFER_SIZE", "9600000"))

class ConnectionManager:
    """Manages WebSocket connection lifecycle, protocol state, and audio processing."""
    def __init__(self, model_manager: ModelManager, app_version: str):
        self.active_connections: Dict[WebSocket, Dict[str, Any]] = {}
        self.model_manager = model_manager
        self.app_version = app_version
        self.governance = SecurityGovernance()
        
        # Start background cleanup
        self.cleanup_task = asyncio.create_task(self._cleanup_inactive_connections())
        log.info(f"ConnectionManager initialized. Proxy-Ready. Max Connections: {MAX_CONNECTIONS}")

    async def connect(self, websocket: WebSocket):
        ip = websocket.client.host
        
        # 1. Check for Active Bans
        is_banned, remaining = self.governance.is_ip_banned(ip)
        if is_banned:
            log.warning(f"BANNED CLIENT: {ip} rejected. Active ban in effect. Retry in {remaining}s.")
            await websocket.accept()
            await websocket.close(code=1008, reason=f"IP Banned. Cooldown: {remaining}s")
            return

        # 2. Max Connections Check
        if len(self.active_connections) >= MAX_CONNECTIONS:
            log.warning(f"Connection rejected for {websocket.client}: Max connections reached.")
            await websocket.accept()
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
            "handshake_completed": False,
            "id": conn_id,
            "incognito": False
        }
        log.info(f"[{conn_id}] WebSocket client connected from {ip}")
        
        await websocket.send_json({
            "event": "hello",
            "server": "WhisperDoc Backend",
            "version": self.app_version,
            "status": "ready" if self.model_manager.model else "idle",
            "cid": conn_id
        })

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            conn_id = self.active_connections[websocket].get("id", "????")
            del self.active_connections[websocket]
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

                for websocket, code, reason in to_disconnect:
                    try: await websocket.close(code=code, reason=reason)
                    except: pass
                    self.disconnect(websocket)
                    
                if int(now) % 3600 == 0:
                    self.governance.clear_old_trackers()

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
                    await websocket.close(code=1008, reason="Malformed JSON")
                    return

                event = data.get("event")

                if not handshake_done:
                    if event != "hello":
                        log.warning(f"[{conn_id}] Protocol Violation: Expected 'hello', got '{event}'.")
                        self.governance.record_protocol_violation(ip)
                        await websocket.close(code=1008, reason="Handshake required")
                        return

                    token = data.get("token")
                    auth_type = data.get("auth_type", "api_key")

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
                    log.info(f"[{conn_id}] Handshake Verified ({auth_type}). Incognito: {connection_data['incognito']}")

                    await websocket.send_json({"event": "authenticated", "status": "success", "cid": conn_id})
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
                try: await websocket.close(code=1011)
                except: pass

        elif isinstance(message, bytes):
            if not handshake_done:
                self.governance.record_protocol_violation(ip)
                await websocket.close(code=1008, reason="Handshake required")
                return
            
            buffer = connection_data["buffer"]
            if len(buffer) < MAX_BUFFER_SIZE:
                buffer.extend(message)
            else:
                log.warning(f"[{conn_id}] Resource Exhaustion: Buffer limit reached.")
                await websocket.close(code=1009, reason="Buffer limit exceeded")
                self.disconnect(websocket)

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
            model, _ = self.model_manager.get_model()
            
            # Wrap the raw PCM buffer in a proper WAV header before writing to file
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
                with wave.open(tmp, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2) # 16-bit
                    wf.setframerate(16000)
                    wf.writeframes(buffer)
                tmp_path = tmp.name
            
            start_time = time.time()
            # Run transcription in a thread to keep WebSocket loop alive
            def run_transcription():
                segments, info = model.transcribe(tmp_path, language="en")
                return list(segments), info

            segments_list, info = await asyncio.to_thread(run_transcription)
            duration = time.time() - start_time
            
            full_text = " ".join([s.text.strip() for s in segments_list])
            
            # Security: Wipe buffer immediately
            data["buffer"] = bytearray()

            if not is_incognito:
                log.success(f"[{conn_id}] Transcription complete: {full_text[:50]}...")
            else:
                log.log("PRIVACY", f"[{conn_id}] Transcription complete [REDACTED]")

            await websocket.send_json({
                "event": "transcription",
                "text": full_text,
                "segments": [{"start": s.start, "end": s.end, "text": s.text.strip()} for s in segments_list],
                "processing_time": duration
            })
            
        except Exception as e:
            log.error(f"[{conn_id}] Transcription failed: {e}")
            await websocket.send_json({"event": "error", "message": "Transcription failed"})
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try: os.unlink(tmp_path)
                except: pass
