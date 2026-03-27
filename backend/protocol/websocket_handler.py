import asyncio
import json
import os
import tempfile
import time
import wave
from collections import defaultdict
from typing import Any, Dict

from auth import validate_token
from engine.base_engine import BaseEngine
from fastapi import WebSocket
from logging_config import log
from security.governance import (
    HANDSHAKE_TIMEOUT_SECONDS,
    IDLE_TIMEOUT_SECONDS,
    MAX_CONNECTIONS,
    NO_AUDIO_GRACE_SECONDS,
    SecurityGovernance,
)
from security.sanitizer import Sanitizer

# Max buffer size (in bytes) for 5 minutes of 16kHz, 16-bit mono audio
MAX_BUFFER_SIZE = int(os.getenv("MAX_BUFFER_SIZE", "9600000"))


def get_client_host(websocket: WebSocket) -> str:
    client = websocket.client
    return client.host if client else "unknown"


def describe_client(websocket: WebSocket) -> str:
    client = websocket.client
    return str(client) if client else "unknown"


def is_lower(v1: str, v2: str) -> bool:
    """Return True if semver v1 < v2.  Fail-secure: unparseable → True."""
    try:
        v1_parts = [int(p) for p in v1.split("+")[0].split("-")[0].split(".")]
        v2_parts = [int(p) for p in v2.split("+")[0].split("-")[0].split(".")]
        for i in range(3):
            p1 = v1_parts[i] if i < len(v1_parts) else 0
            p2 = v2_parts[i] if i < len(v2_parts) else 0
            if p1 < p2:
                return True
            if p1 > p2:
                return False
        return False
    except Exception:
        return True


# --- Structured Error Codes (string enums for JSON "error_code" field) ---
class ErrorCode:
    AUTH_FAILED = "AUTH_FAILED"
    HANDSHAKE_REQUIRED = "HANDSHAKE_REQUIRED"
    VERSION_OUTDATED = "VERSION_OUTDATED"
    IP_BANNED = "IP_BANNED"
    MAX_CONNECTIONS = "MAX_CONNECTIONS"
    MALFORMED_JSON = "MALFORMED_JSON"
    INVALID_EVENT = "INVALID_EVENT"
    DUPLICATE_HANDSHAKE = "DUPLICATE_HANDSHAKE"
    NO_AUDIO = "NO_AUDIO"
    BUFFER_EXCEEDED = "BUFFER_EXCEEDED"
    TRANSCRIPTION_FAILED = "TRANSCRIPTION_FAILED"
    SERVER_ERROR = "SERVER_ERROR"


class _Sentinel:
    """Marker for unset default arguments."""


_SENTINEL: _Sentinel = _Sentinel()


class ConnectionManager:
    """Manages WebSocket connection lifecycle, protocol state, and audio processing."""

    def __init__(
        self,
        engine: BaseEngine,
        app_version: str,
        min_client_version: str = "0.0.0",
        sec_client_version: str = "0.0.0",
    ):
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

        # Background task references
        self._warmup_task: asyncio.Task | None = None

        # Start background cleanup — guard against sync contexts (tests, scripts)
        _coro = self._cleanup_inactive_connections()
        try:
            self.cleanup_task = asyncio.create_task(_coro)
        except RuntimeError:
            _coro.close()
            self.cleanup_task = None
        log.info(
            f"ConnectionManager initialized. Proxy-Ready. Max Connections: {MAX_CONNECTIONS}"
        )

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    async def connect(self, websocket: WebSocket):
        ip = get_client_host(websocket)

        # 1. Check for Active Bans
        is_banned, remaining = self.governance.is_ip_banned(ip)
        if is_banned:
            log.warning(
                f"BANNED CLIENT: {ip} rejected. Active ban in effect. Retry in {remaining}s."
            )
            await websocket.accept()
            await websocket.send_json(
                {
                    "event": "error",
                    "code": 1008,
                    "error_code": ErrorCode.IP_BANNED,
                    "message": f"IP Banned. Cooldown: {remaining}s",
                }
            )
            await websocket.close(
                code=1008, reason=f"IP Banned. Cooldown: {remaining}s"
            )
            return

        # 2. Max Connections Check
        if len(self.active_connections) >= MAX_CONNECTIONS:
            log.warning(
                f"Connection rejected for {describe_client(websocket)}: Max connections reached."
            )
            await websocket.accept()
            await websocket.send_json(
                {
                    "event": "error",
                    "code": 1008,
                    "error_code": ErrorCode.MAX_CONNECTIONS,
                    "message": "Max concurrent connections reached",
                }
            )
            await websocket.close(
                code=1008, reason="Max concurrent connections reached"
            )
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
            "incognito": False,
        }
        log.info(f"[{conn_id}] WebSocket client connected from {ip}")

        await websocket.send_json(
            {
                "event": "hello",
                "server": "WhisperDoc Backend",
                "version": self.app_version,
                "min_version": self.min_client_version,
                "sec_version": self.sec_client_version,
                "status": "ready" if self.engine.is_loaded() else "idle",
                "cid": conn_id,
            }
        )

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            conn_id = self.active_connections[websocket].get("id", "????")
            del self.active_connections[websocket]
            if websocket in self.bytes_received:
                del self.bytes_received[websocket]
            log.info(
                f"[{conn_id}] WebSocket client disconnected: {describe_client(websocket)}"
            )

    # ------------------------------------------------------------------
    # Error rejection helper
    # ------------------------------------------------------------------

    async def _reject(
        self,
        websocket: WebSocket,
        *,
        code: int,
        close_code: int,
        error_code: str,
        message: str,
        close_reason: str | None | _Sentinel = _SENTINEL,
        record_violation: bool = False,
        do_disconnect: bool = False,
    ) -> None:
        """Send a structured error JSON and close the WebSocket.

        ``close_reason`` controls the WebSocket close-frame reason string.
        Pass an explicit string (including ``""``) to override, or omit to
        reuse *message*.  Pass ``None`` to close without a reason keyword
        (preserves the legacy contract for paths that never sent one).
        """
        ip = get_client_host(websocket)
        if record_violation:
            self.governance.record_protocol_violation(ip)
        await websocket.send_json(
            {
                "event": "error",
                "code": code,
                "error_code": error_code,
                "message": message,
            }
        )
        if isinstance(close_reason, _Sentinel):
            await websocket.close(code=close_code, reason=message)
        elif close_reason is None:
            await websocket.close(code=close_code)
        else:
            await websocket.close(code=close_code, reason=close_reason)
        if do_disconnect:
            self.disconnect(websocket)

    # ------------------------------------------------------------------
    # Background cleanup (decomposed)
    # ------------------------------------------------------------------

    async def _cleanup_inactive_connections(self):
        while True:
            try:
                await asyncio.sleep(10)
                now = time.time()
                stale = self._identify_stale_connections(now)
                await self._execute_disconnections(stale)
                self._run_hourly_maintenance(now)
            except Exception as e:
                log.error(f"Error in cleanup task: {e}")

    def _identify_stale_connections(self, now: float) -> list:
        """Return list of (websocket, close_code, reason) for stale connections."""
        to_disconnect = []
        for websocket, data in self.active_connections.items():
            idle_time = now - data["last_activity"]

            if (
                not data["handshake_completed"]
                and idle_time > HANDSHAKE_TIMEOUT_SECONDS
            ):
                log.warning(
                    f"Closing un-handshaked connection from {describe_client(websocket)} (Timeout)"
                )
                to_disconnect.append((websocket, 1008, "Handshake timeout"))
                self.governance.record_protocol_violation(get_client_host(websocket))
                continue

            if idle_time > IDLE_TIMEOUT_SECONDS:
                log.warning(
                    f"Closing inactive connection for client {describe_client(websocket)}"
                )
                to_disconnect.append((websocket, 4000, "Inactivity timeout"))
                continue

            # Anti-slot-hogging: kick authenticated connections with no audio activity.
            # Catches clients that hold a slot via keep-alive pings without ever transcribing.
            # Uses last_audio_received (set only on binary audio chunks) rather than a
            # lifetime throughput average, which false-positives on short push-to-talk clips.
            if data["handshake_completed"]:
                connection_age = now - data["connected_at"]
                last_audio = data.get("last_audio_received")
                no_audio_ever = (
                    last_audio is None and connection_age > NO_AUDIO_GRACE_SECONDS
                )
                audio_stale = (
                    last_audio is not None and (now - last_audio) > IDLE_TIMEOUT_SECONDS
                )
                if no_audio_ever or audio_stale:
                    log.warning(
                        f"Closing slot-hogging connection from {describe_client(websocket)} (no audio activity)"
                    )
                    to_disconnect.append((websocket, 4001, "No audio activity"))

        return to_disconnect

    async def _execute_disconnections(self, to_disconnect: list) -> None:
        """Close and remove stale connections."""
        for websocket, code, reason in to_disconnect:
            try:
                await websocket.close(code=code, reason=reason)
            except Exception as e:
                log.debug(f"Error closing WebSocket ({reason}): {e}")
            self.disconnect(websocket)

    def _run_hourly_maintenance(self, now: float) -> None:
        """Prune security trackers and stale IPC semaphores (every ~1 hour)."""
        if now - self.last_tracker_cleanup <= 3600:
            return
        self.governance.clear_old_trackers()
        active_user_ids = {
            d.get("user_id")
            for d in self.active_connections.values()
            if d.get("user_id")
        }
        stale_ids = [uid for uid in self.user_semaphores if uid not in active_user_ids]
        for uid in stale_ids:
            del self.user_semaphores[uid]
        if stale_ids:
            log.debug(f"Maintenance: Pruned {len(stale_ids)} stale IPC semaphore(s).")
        self.last_tracker_cleanup = now
        log.debug("Maintenance: Security trackers cleared.")

    # ------------------------------------------------------------------
    # Message handling (decomposed)
    # ------------------------------------------------------------------

    async def handle_message(self, websocket: WebSocket, message):
        connection_data = self.active_connections.get(websocket)
        if not connection_data:
            return

        connection_data["last_activity"] = time.time()

        if isinstance(message, str):
            await self._handle_text_message(websocket, message, connection_data)
        elif isinstance(message, bytes):
            await self._handle_binary_message(websocket, message, connection_data)

    async def _handle_text_message(
        self,
        websocket: WebSocket,
        message: str,
        connection_data: Dict[str, Any],
    ) -> None:
        conn_id = connection_data.get("id", "????")

        try:
            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                log.warning(f"[{conn_id}] Protocol Violation: Malformed JSON.")
                await self._reject(
                    websocket,
                    code=1008,
                    close_code=1008,
                    error_code=ErrorCode.MALFORMED_JSON,
                    message="Malformed JSON",
                    record_violation=True,
                )
                return

            event = data.get("event")
            handshake_done = connection_data.get("handshake_completed", False)

            if not handshake_done:
                await self._handle_handshake(
                    websocket, data, event, connection_data, conn_id
                )
                return

            # Post-handshake event routing
            if event == "hello":
                await self._reject(
                    websocket,
                    code=1008,
                    close_code=1008,
                    error_code=ErrorCode.DUPLICATE_HANDSHAKE,
                    message="Handshake already completed",
                )
                return

            if event == "end-of-stream":
                log.info(f"[{conn_id}] Received EOS.")
                await self.transcribe_and_send(websocket)
            elif event == "ping":
                await websocket.send_json({"event": "pong"})
            else:
                await self._reject(
                    websocket,
                    code=1008,
                    close_code=1008,
                    error_code=ErrorCode.INVALID_EVENT,
                    message=f"Invalid event: {event}",
                )

        except Exception as e:
            log.error(f"[{conn_id}] Error in text handler: {e}")
            try:
                await websocket.send_json(
                    {
                        "event": "error",
                        "code": 1011,
                        "error_code": ErrorCode.SERVER_ERROR,
                        "message": "Internal server error",
                    }
                )
                await websocket.close(code=1011)
            except Exception as ce:
                log.debug(
                    f"[{conn_id}] Error closing WebSocket after handler error: {ce}"
                )

    async def _handle_handshake(
        self,
        websocket: WebSocket,
        data: dict,
        event: str | None,
        connection_data: Dict[str, Any],
        conn_id: str,
    ) -> None:
        if event != "hello":
            log.warning(
                f"[{conn_id}] Protocol Violation: Expected 'hello', got '{event}'."
            )
            await self._reject(
                websocket,
                code=1008,
                close_code=1008,
                error_code=ErrorCode.HANDSHAKE_REQUIRED,
                message="Handshake required",
                record_violation=True,
            )
            return

        token = data.get("token", "")
        auth_type = data.get("auth_type", "api_key")
        client_version = data.get("version", "0.0.0")
        client_type = data.get("client", "unknown")

        # 1. Version Validation (Hardened Gate)
        if is_lower(client_version, self.min_client_version):
            log.warning(
                f"[{conn_id}] BLOCKED: Outdated client ({client_version}) < MIN ({self.min_client_version})"
            )
            await self._reject(
                websocket,
                code=1008,
                close_code=1008,
                error_code=ErrorCode.VERSION_OUTDATED,
                message=f"Update required: v{self.min_client_version} (Client: {client_version})",
                close_reason=None,
                record_violation=True,
            )
            return

        if is_lower(client_version, self.sec_client_version):
            log.info(
                f"[{conn_id}] ADVISORY: Outdated client ({client_version}) < SEC ({self.sec_client_version})"
            )
        else:
            log.debug(
                f"[{conn_id}] HANDSHAKE: Client version {client_version} verified."
            )

        # 2. Authentication
        user_id = await self._authenticate(
            websocket, token, auth_type, connection_data, conn_id
        )
        if user_id is None:
            return  # _authenticate already rejected

        connection_data["handshake_completed"] = True
        connection_data["auth_type"] = auth_type
        connection_data["incognito"] = data.get("incognito", False)
        log.info(
            f"[{conn_id}] Handshake Verified ({auth_type}) | {client_type} (v{client_version}) | Incognito: {connection_data['incognito']}"
        )

        await websocket.send_json(
            {"event": "authenticated", "status": "success", "cid": conn_id}
        )

        # TRIGGER WARMUP: Load model in background if not already loaded.
        # Guard skips the task entirely for reconnecting clients whose model is still hot,
        # avoiding a pointless thread spawn and last_used timestamp churn.
        if not self.engine.is_loaded():
            self._warmup_task = asyncio.create_task(self._warmup_model())

    async def _authenticate(
        self,
        websocket: WebSocket,
        token: str,
        auth_type: str,
        connection_data: Dict[str, Any],
        conn_id: str,
    ) -> str | None:
        """Validate credentials and return user_id, or reject and return None."""
        if auth_type == "oidc":
            from auth.oidc import validate_oidc_token

            payload = validate_oidc_token(token)
            if not payload:
                log.warning(f"[{conn_id}] OIDC Authentication Failed.")
                await self._reject(
                    websocket,
                    code=403,
                    close_code=1008,
                    error_code=ErrorCode.AUTH_FAILED,
                    message="OIDC Authentication failed",
                    close_reason=None,
                    record_violation=True,
                )
                return None

            # Keep the stable OIDC subject as the canonical identity.
            # Email is useful for development-time observability, but it
            # is not authoritative enough to store as connection state.
            user_sub = payload.get("sub", "unknown")
            user_email = payload.get("email") or payload.get("preferred_username")
            connection_data["user_id"] = user_sub
            if user_email:
                log.info(
                    f"[{conn_id}] OIDC verified for sub={user_sub} email={user_email}"
                )
            else:
                log.info(f"[{conn_id}] OIDC verified for sub={user_sub}")
            return user_sub

        # Fallback to static API key validation
        if not validate_token(token):
            log.warning(f"[{conn_id}] API Key Authentication Failed.")
            await self._reject(
                websocket,
                code=403,
                close_code=1008,
                error_code=ErrorCode.AUTH_FAILED,
                message="API Key Authentication failed",
                close_reason=None,
                record_violation=True,
            )
            return None
        connection_data["user_id"] = "static_apiKey"
        return "static_apiKey"

    async def _handle_binary_message(
        self,
        websocket: WebSocket,
        message: bytes,
        connection_data: Dict[str, Any],
    ) -> None:
        conn_id = connection_data.get("id", "????")
        handshake_done = connection_data.get("handshake_completed", False)

        if not handshake_done:
            await self._reject(
                websocket,
                code=1008,
                close_code=1008,
                error_code=ErrorCode.HANDSHAKE_REQUIRED,
                message="Handshake required",
                record_violation=True,
            )
            return

        connection_data["last_audio_received"] = time.time()
        buffer = connection_data["buffer"]
        if len(buffer) < MAX_BUFFER_SIZE:
            buffer.extend(message)
            self.bytes_received[websocket] += len(message)
        else:
            log.warning(f"[{conn_id}] Resource Exhaustion: Buffer limit reached.")
            await self._reject(
                websocket,
                code=1009,
                close_code=1009,
                error_code=ErrorCode.BUFFER_EXCEEDED,
                message="Buffer limit exceeded",
                do_disconnect=True,
            )

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    async def _warmup_model(self):
        """Background task to ensure model is loaded into GPU."""
        try:
            log.info("BACKGROUND: Triggering model warmup...")
            # to_thread prevents blocking the event loop during the 2-5s load
            await asyncio.to_thread(self.engine.warmup)
            log.debug("BACKGROUND: Model warmup attempt completed.")
        except Exception as e:
            log.error(f"BACKGROUND: Model warmup failed: {e}")

    @staticmethod
    def _write_wav_temp(buffer: bytearray) -> str:
        """Write raw PCM buffer to a temporary WAV file (sync, for use with to_thread)."""
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
            with wave.open(tmp, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)  # 16-bit
                wf.setframerate(16000)
                wf.writeframes(buffer)
            return tmp.name

    async def transcribe_and_send(self, websocket: WebSocket):
        data = self.active_connections.get(websocket)
        if not data:
            return

        buffer = data["buffer"]
        conn_id = data.get("id", "????")
        is_incognito = data.get("incognito", False)

        if not buffer:
            log.warning(f"[{conn_id}] Transcription requested but buffer is empty.")
            await websocket.send_json(
                {
                    "event": "error",
                    "code": 422,
                    "error_code": ErrorCode.NO_AUDIO,
                    "message": "No audio data received",
                }
            )
            return

        tmp_path = None
        try:
            user_id = data.get("user_id", "anonymous")

            # Write WAV outside the GPU semaphore — this is pure IO and does
            # not need to block other users' transcriptions.
            tmp_path = await asyncio.to_thread(self._write_wav_temp, buffer)

            # IPC GUARD: Per-Identity Concurrency Lock
            # Ensures User A cannot bomb the GPU while User B remains unblocked.
            async with self.user_semaphores[user_id]:
                log.debug(f"[{conn_id}] IPC-LOCK ACQUIRED. Running transcription...")

                # engine.transcribe() is synchronous and handles load-on-demand
                # internally. Run in a thread to keep the WebSocket loop alive.
                result = await asyncio.to_thread(self.engine.transcribe, tmp_path)

            # 1. Backend Sanitization (Zero-Latency Security Gate)
            # Sanitize each segment once and derive full_text from the results.
            # This avoids a redundant second sanitization pass on the joined text
            # and guarantees full_text is consistent with the segment texts.
            safe_segments = [
                {
                    "start": s.start,
                    "end": s.end,
                    "text": Sanitizer.sanitize(s.text),
                }
                for s in result.segments
            ]
            full_text = " ".join(seg["text"] for seg in safe_segments)

            # 2. Security: Wipe buffer immediately
            data["buffer"] = bytearray()

            if not is_incognito:
                log.success(f"[{conn_id}] Transcription complete: {full_text[:50]}...")
            else:
                log.log("PRIVACY", f"[{conn_id}] Transcription complete [REDACTED]")

            await websocket.send_json(
                {
                    "event": "transcription",
                    "text": full_text,
                    "segments": safe_segments,
                    "processing_time": result.processing_time,
                }
            )

        except Exception as e:
            log.error(f"[{conn_id}] Transcription failed: {e}")
            await websocket.send_json(
                {
                    "event": "error",
                    "code": 1011,
                    "error_code": ErrorCode.TRANSCRIPTION_FAILED,
                    "message": "Transcription failed",
                }
            )
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except Exception as e:
                    log.debug(f"[{conn_id}] Failed to delete temp file {tmp_path}: {e}")
