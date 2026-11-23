import asyncio
import json
import random
import ssl
import time
from typing import cast
from urllib.parse import urlparse

import requests
import websockets
from loguru import logger

from ..logic.handshake import HandshakeState, HandshakeStateMachine
from ..logic.messages import JSONValue, MessageListener, ServerMessage
from ..logic.payload import PayloadBuilder
from ..services.config_service import cfg, sec_cfg

# Cloudflare Tunnel drops idle WebSocket connections after ~100s.
# Ping interval must sit well below that threshold.
KEEPALIVE_INTERVAL_S = 45

# Reconnection backoff parameters
BACKOFF_BASE_S = 1.0
BACKOFF_MAX_S = 60.0
BACKOFF_FACTOR = 2.0
MAX_RECONNECT_ATTEMPTS = 10

# Server close codes for idle eviction (backend: inactivity, no audio). The
# server closed an unused connection on purpose; reconnecting immediately would
# just be evicted again. The next recording reconnects on demand.
IDLE_EVICTION_CLOSE_CODES = frozenset({4000, 4001})

# Error codes that end the session; listeners report them via handshake state.
_SESSION_ERRORS: dict[str, HandshakeState] = {
    "IP_BANNED": HandshakeState.BANNED,
    "VERSION_OUTDATED": HandshakeState.VERSION_OUTDATED,
    "AUTH_FAILED": HandshakeState.FAILED,
    "MAX_CONNECTIONS": HandshakeState.FAILED,
    "HANDSHAKE_REQUIRED": HandshakeState.FAILED,
    "MALFORMED_JSON": HandshakeState.FAILED,
    "INVALID_EVENT": HandshakeState.FAILED,
    "DUPLICATE_HANDSHAKE": HandshakeState.FAILED,
}

# Handshake states that carry an error worth preserving across teardown.
_ERROR_STATES = frozenset(
    {HandshakeState.FAILED, HandshakeState.BANNED, HandshakeState.VERSION_OUTDATED}
)


class TransportService:
    """
    Service managing WebSocket connectivity, the application-level handshake,
    keepalive pings, idle disconnects, and reconnection with exponential backoff.
    """

    def __init__(self):
        self._ws = None
        self._uri = cfg.WS_URI
        self.hostname = urlparse(self._uri).hostname or "localhost"
        self._final_uri = self._prepare_uri(self._uri)

        self.handshake = HandshakeStateMachine()
        self._message_listeners: list[MessageListener] = []
        self._receive_task: asyncio.Task | None = None
        self._keepalive_task: asyncio.Task | None = None
        self._idle_task: asyncio.Task | None = None
        self._last_activity = time.monotonic()
        self._reconnect_attempt = 0
        self._reconnect_task: asyncio.Task | None = None
        self._intentional_disconnect = False
        # Serializes connect(): the launch-time connect and a hotkey press can
        # race, and each would otherwise open its own socket.
        self._connect_lock = asyncio.Lock()

    # ------------------------------------------------------------------
    # URI preparation
    # ------------------------------------------------------------------

    def _prepare_uri(self, uri: str) -> str:
        parsed = urlparse(uri)
        hostname = parsed.hostname or "localhost"
        scheme = parsed.scheme.lower() if parsed.scheme else "ws"

        if scheme == "https":
            scheme = "wss"
        elif scheme == "http":
            scheme = "ws"

        if hostname not in ("localhost", "127.0.0.1", "0.0.0.0") and scheme == "ws":
            logger.warning("Remote connection detected. Enforcing WSS (TLS/SSL)...")
            scheme = "wss"

        path = parsed.path or "/ws"
        final = f"{scheme}://{parsed.netloc}{path}"
        if parsed.query:
            final += f"?{parsed.query}"
        return final

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    @property
    def is_ready(self) -> bool:
        """True when audio can be streamed: socket open and authenticated."""
        return self._ws is not None and self.handshake.can_send_audio()

    async def connect(self) -> bool:
        """Establishes connection and initiates the application-level handshake."""
        async with self._connect_lock:
            if self._ws:
                return True
            return await self._open_connection()

    async def _open_connection(self) -> bool:
        self._intentional_disconnect = False
        self._cancel_reconnect()
        logger.info(f"Connecting to {self.hostname}...")
        self.handshake.reset()

        try:
            ssl_context = None
            if urlparse(self._final_uri).scheme == "wss":
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = True
                ssl_context.verify_mode = ssl.CERT_REQUIRED
                logger.debug(f"TLS Verification Enabled for {self.hostname}")

            self._ws = await websockets.connect(self._final_uri, ssl=ssl_context)
            self._touch()
            self._receive_task = asyncio.create_task(self._listen_loop())
            self._keepalive_task = asyncio.create_task(self._keepalive_loop())
            self._idle_task = asyncio.create_task(self._idle_watchdog())

            # Keyring access (and a first-run prompt) is blocking IO.
            api_key = await asyncio.to_thread(sec_cfg.get_api_key, self.hostname)
            if not api_key:
                raise ValueError("No API Key available for authentication.")

            await self.send_json(
                PayloadBuilder.build_hello(
                    token=api_key,
                    version=cfg.VERSION,
                    incognito=cfg.args.incognito,
                )
            )
            self.handshake.transition_to(HandshakeState.AUTHENTICATING)
            return True

        except websockets.exceptions.InvalidStatus as e:
            body = (
                e.response.body.decode(errors="replace")
                if hasattr(e.response, "body") and e.response.body
                else "(no body)"
            )
            logger.error(f"Connection failed: HTTP {e.response.status_code}")
            logger.error(f"Response body: {body}")
            await self._handle_connection_failure()
            return False
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            await self._handle_connection_failure()
            return False

    async def ensure_connected(self) -> bool:
        """Background auto-wake pattern with reconnection guard."""
        if self.is_ready:
            return True
        if self.handshake.state in (
            HandshakeState.BANNED,
            HandshakeState.VERSION_OUTDATED,
        ):
            return False
        return await self.connect()

    async def disconnect(self, reason: str = "Client closed"):
        """Intentional disconnect — cancels all background tasks and resets state."""
        self._intentional_disconnect = True
        self._cancel_reconnect()
        await self._teardown(reason)

    # ------------------------------------------------------------------
    # Message receive loop
    # ------------------------------------------------------------------

    async def _listen_loop(self):
        close_code: int | None = None
        try:
            ws = self._ws
            if ws is None:
                return
            async for message in ws:
                await self._handle_raw_message(message)
        except websockets.exceptions.ConnectionClosed as e:
            close_code = e.rcvd.code if e.rcvd else None
            reason = e.rcvd.reason if e.rcvd else ""
            logger.warning(f"WebSocket closed: {close_code} - {reason}")
        except Exception as e:
            logger.error(f"Transport receiver error: {e}")
        await self._handle_unexpected_close(close_code)

    async def _handle_raw_message(self, data: object) -> None:
        if not isinstance(data, str):
            return

        try:
            msg = cast(ServerMessage, json.loads(data))
        except json.JSONDecodeError as e:
            logger.error(f"Message parsing error: {e}")
            return

        event = msg.get("event")
        if event == "pong":
            # Keepalive traffic is not user activity; it must not defer idle.
            logger.debug("Keepalive pong received")
            return

        self._touch()
        if event == "hello":
            logger.debug("Server hello acknowledged")
        elif event == "authenticated":
            self._reconnect_attempt = 0  # backoff resets only on real success
            self.handshake.transition_to(HandshakeState.AUTHENTICATED)
            logger.success(f"Authenticated CID: {msg.get('cid', 'unknown')}")
        elif event == "error":
            await self._handle_error_message(msg)
        else:
            self._notify_listeners(msg)

    async def _handle_error_message(self, msg: ServerMessage) -> None:
        """Session errors become handshake state; operational errors go to listeners.

        Transport does not log these: the controller reports each error once
        (handshake listener for session errors, message listener otherwise).
        """
        error_code = msg.get("error_code", "")
        session_state = _SESSION_ERRORS.get(error_code)
        if session_state is None:
            # NO_AUDIO, TRANSCRIPTION_FAILED, BUFFER_EXCEEDED, SERVER_ERROR, ...
            self._notify_listeners(msg)
            return

        if error_code == "AUTH_FAILED":
            await asyncio.to_thread(sec_cfg.clear_key, self.hostname)
        self.handshake.set_error_context(
            error_code, msg.get("message", "Unknown error")
        )
        self.handshake.transition_to(session_state)

    def _notify_listeners(self, msg: ServerMessage) -> None:
        for cb in self._message_listeners:
            cb(msg)

    # ------------------------------------------------------------------
    # Send methods
    # ------------------------------------------------------------------

    async def send_audio(self, chunk: bytes):
        """Sends raw PCM chunks ONLY if authenticated."""
        if self.is_ready and self._ws:
            self._touch()
            await self._ws.send(chunk)

    async def send_json(self, data: dict[str, JSONValue]) -> None:
        if self._ws:
            self._touch()
            await self._ws.send(json.dumps(data))

    # ------------------------------------------------------------------
    # Keepalive & idle
    # ------------------------------------------------------------------

    def _touch(self) -> None:
        """Record user-driven activity (audio, transcripts, control messages)."""
        self._last_activity = time.monotonic()

    async def _keepalive_loop(self):
        while self._ws:
            await asyncio.sleep(KEEPALIVE_INTERVAL_S)
            ws = self._ws
            if ws and self.handshake.state == HandshakeState.AUTHENTICATED:
                try:
                    # Sent directly: a ping must not count as activity.
                    await ws.send(json.dumps({"event": "ping"}))
                    logger.debug("Keepalive ping sent")
                except Exception:
                    break

    async def _idle_watchdog(self):
        """Disconnect after IDLE_TIMEOUT without user activity.

        One task per connection that sleeps until the idle deadline, rather
        than a timer recreated on every audio chunk.
        """
        while self._ws:
            remaining = cfg.IDLE_TIMEOUT - (time.monotonic() - self._last_activity)
            if remaining <= 0:
                logger.info(
                    f"Idle for {cfg.IDLE_TIMEOUT}s. Disconnecting to save server resources."
                )
                await self.disconnect(reason="Idle Timeout")
                return
            await asyncio.sleep(remaining)

    # ------------------------------------------------------------------
    # Reconnection with exponential backoff + jitter
    # ------------------------------------------------------------------

    async def _handle_connection_failure(self):
        """Called after a failed connect() — tears down partial state and schedules retry."""
        await self._teardown("Connection failed", reset_handshake=False)
        self._schedule_reconnect()

    async def _handle_unexpected_close(self, close_code: int | None = None):
        """Called when the connection ends without a local disconnect()."""
        if self._intentional_disconnect:
            return

        # Keep error states (and their context) for listeners and
        # ensure_connected; a plain drop returns to LOCKED.
        keep_state = self.handshake.state in _ERROR_STATES
        await self._teardown("Closed by server", reset_handshake=not keep_state)

        if self._should_auto_reconnect(close_code):
            self._schedule_reconnect()

    def _should_auto_reconnect(self, close_code: int | None) -> bool:
        state = self.handshake.state
        if state in (HandshakeState.BANNED, HandshakeState.VERSION_OUTDATED):
            return False
        if state == HandshakeState.FAILED and (
            self.handshake.last_error_code == "AUTH_FAILED"
        ):
            # The key was rejected and cleared; retrying would only prompt for
            # a key in the background. The next recording asks interactively.
            return False
        if close_code in IDLE_EVICTION_CLOSE_CODES:
            logger.info("Server closed the idle connection; reconnecting on demand.")
            return False
        return True

    def _schedule_reconnect(self):
        if self._reconnect_attempt >= MAX_RECONNECT_ATTEMPTS:
            logger.error(
                f"Max reconnection attempts ({MAX_RECONNECT_ATTEMPTS}) reached. "
                "Use hotkey to retry manually."
            )
            self._reconnect_attempt = 0
            return

        delay = min(
            BACKOFF_BASE_S * (BACKOFF_FACTOR**self._reconnect_attempt), BACKOFF_MAX_S
        )
        wait = delay + random.uniform(0, delay * 0.3)
        self._reconnect_attempt += 1

        logger.info(
            f"Reconnecting in {wait:.1f}s (attempt {self._reconnect_attempt}/{MAX_RECONNECT_ATTEMPTS})..."
        )

        async def _reconnect():
            await asyncio.sleep(wait)
            await self.connect()

        self._reconnect_task = asyncio.create_task(_reconnect())

    def _cancel_reconnect(self):
        if self._reconnect_task and self._reconnect_task is not asyncio.current_task():
            self._reconnect_task.cancel()
        self._reconnect_task = None

    # ------------------------------------------------------------------
    # Teardown / cleanup
    # ------------------------------------------------------------------

    async def _teardown(self, reason: str, reset_handshake: bool = True):
        """Cancels background tasks and closes the socket.

        Teardown is often reached from one of these tasks (the idle watchdog,
        the receive loop); cancelling the current task would abort teardown at
        its next await and leave the socket and handshake half-reset.
        """
        current = asyncio.current_task()
        for task in (self._keepalive_task, self._idle_task, self._receive_task):
            if task is not None and task is not current:
                task.cancel()
        self._keepalive_task = self._idle_task = self._receive_task = None

        ws, self._ws = self._ws, None
        if ws is not None:
            try:
                await ws.close(1000, reason)
            except Exception as e:
                logger.debug(f"Ignoring socket-close error during teardown: {e}")

        if reset_handshake:
            self.handshake.reset()

        logger.info(f"Disconnected: {reason}")

    # ------------------------------------------------------------------
    # Listeners & health check
    # ------------------------------------------------------------------

    def add_message_listener(self, callback: MessageListener) -> None:
        self._message_listeners.append(callback)

    def check_health(self) -> bool:
        """Pre-flight health check (HTTP)."""
        parsed = urlparse(self._final_uri)
        scheme = "https" if parsed.scheme == "wss" else "http"
        health_url = f"{scheme}://{parsed.netloc}/health"

        logger.info(f"Health Check: {health_url}...")
        try:
            resp = requests.get(health_url, timeout=5)
            if resp.status_code == 200:
                logger.success("Server is healthy.")
                return True
        except Exception as e:
            logger.error(f"Health check failed: {e}")
        return False
