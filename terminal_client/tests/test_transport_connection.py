"""
Tests for TransportService connection setup, reconnect backoff, keepalive,
idle disconnect and the receive loop's failure handling.

The socket is faked at the websockets edge; the end-to-end wire behaviour
against a real (in-process) WebSocket server lives in test_dictation_e2e.py.
"""

import asyncio
import json
import ssl
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock

import pytest
from loguru import logger

from whisper_shell.logic.handshake import HandshakeState
from whisper_shell.services import transport_service
from whisper_shell.services.config_service import cfg
from whisper_shell.services.transport_service import (
    MAX_RECONNECT_ATTEMPTS,
    TransportService,
)


@pytest.fixture
def log_messages():
    """Messages logged at INFO and above while the test runs."""
    messages: list[str] = []
    sink = logger.add(
        lambda m: messages.append(m.record["message"]), level="INFO", format="{message}"
    )
    yield messages
    logger.remove(sink)


@pytest.fixture
def refused_connect(monkeypatch) -> AsyncMock:
    """websockets.connect that records its arguments and refuses the socket."""
    connect = AsyncMock(side_effect=OSError("connection refused"))
    monkeypatch.setattr(transport_service.websockets, "connect", connect)
    return connect


def _service_for(monkeypatch, uri: str) -> TransportService:
    monkeypatch.setattr(cfg, "WS_URI", uri)
    return TransportService()


def _authenticated(svc: TransportService) -> None:
    svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
    svc.handshake.transition_to(HandshakeState.AUTHENTICATED)


# ---------------------------------------------------------------------------
# Connection setup
# ---------------------------------------------------------------------------


class TestConnectTls:
    async def test_remote_server_is_dialled_over_verified_tls(
        self, monkeypatch, refused_connect
    ):
        svc = _service_for(monkeypatch, "ws://dictation.example.com/api/ws?team=7")

        assert await svc.connect() is False
        svc._cancel_reconnect()

        (uri,), kwargs = refused_connect.call_args
        assert uri == "wss://dictation.example.com/api/ws?team=7"
        context = kwargs["ssl"]
        assert isinstance(context, ssl.SSLContext)
        assert context.check_hostname is True
        assert context.verify_mode == ssl.CERT_REQUIRED

    async def test_local_server_is_dialled_without_tls(
        self, monkeypatch, refused_connect
    ):
        svc = _service_for(monkeypatch, "ws://localhost:9989")

        await svc.connect()
        svc._cancel_reconnect()

        refused_connect.assert_awaited_once_with("ws://localhost:9989/ws", ssl=None)

    async def test_missing_api_key_closes_the_socket_unauthenticated(self, monkeypatch):
        ws = AsyncMock()
        monkeypatch.setattr(
            transport_service.websockets, "connect", AsyncMock(return_value=ws)
        )
        monkeypatch.setattr(
            transport_service, "sec_cfg", MagicMock(get_api_key=lambda host: "")
        )
        svc = _service_for(monkeypatch, "ws://localhost:9989/ws")

        assert await svc.connect() is False
        svc._cancel_reconnect()

        ws.send.assert_not_called()  # no hello without a key
        ws.close.assert_awaited_once()
        assert svc._ws is None
        assert svc.handshake.state == HandshakeState.LOCKED


# ---------------------------------------------------------------------------
# Reconnect backoff
# ---------------------------------------------------------------------------


def _reconnect_lines(messages: list[str]) -> list[str]:
    return [m for m in messages if m.startswith(("Reconnecting", "Max reconnection"))]


class TestReconnectBackoff:
    @pytest.mark.parametrize(
        ("jitter", "waits"),
        [
            ("none", ["1.0", "2.0", "4.0", "8.0", "16.0", "32.0", "60.0", "60.0"]),
            ("max", ["1.3", "2.6", "5.2", "10.4", "20.8", "41.6", "78.0", "78.0"]),
        ],
    )
    async def test_waits_double_up_to_the_cap_plus_jitter(
        self, monkeypatch, log_messages, jitter, waits
    ):
        uniform = (lambda lo, hi: lo) if jitter == "none" else (lambda lo, hi: hi)
        monkeypatch.setattr(
            transport_service, "random", SimpleNamespace(uniform=uniform)
        )
        svc = TransportService()

        for _ in waits:
            svc._schedule_reconnect()
            svc._cancel_reconnect()

        assert _reconnect_lines(log_messages) == [
            f"Reconnecting in {wait}s (attempt {n}/{MAX_RECONNECT_ATTEMPTS})..."
            for n, wait in enumerate(waits, start=1)
        ]

    async def test_gives_up_after_max_attempts_then_starts_over(
        self, monkeypatch, log_messages
    ):
        monkeypatch.setattr(
            transport_service, "random", SimpleNamespace(uniform=lambda lo, hi: lo)
        )
        svc = TransportService()

        for _ in range(MAX_RECONNECT_ATTEMPTS):
            svc._schedule_reconnect()
            svc._cancel_reconnect()
        svc._schedule_reconnect()  # one too many
        assert svc._reconnect_task is None

        svc._schedule_reconnect()  # a later failure starts a fresh series
        svc._cancel_reconnect()

        lines = _reconnect_lines(log_messages)
        assert len(lines) == MAX_RECONNECT_ATTEMPTS + 2
        assert lines[-2].startswith("Max reconnection attempts (10) reached")
        assert lines[-1] == "Reconnecting in 1.0s (attempt 1/10)..."

    async def test_scheduled_retry_reconnects_after_the_wait(self, monkeypatch):
        monkeypatch.setattr(transport_service, "BACKOFF_BASE_S", 0.001)
        svc = TransportService()
        connect = AsyncMock(return_value=True)
        monkeypatch.setattr(svc, "connect", connect)

        svc._schedule_reconnect()
        task = svc._reconnect_task
        assert task is not None
        await asyncio.wait_for(task, timeout=1)

        connect.assert_awaited_once_with()

    async def test_connecting_cancels_a_pending_retry(self, refused_connect):
        svc = TransportService()
        svc._schedule_reconnect()
        pending = svc._reconnect_task
        assert pending is not None

        await svc.connect()  # fails again and schedules its own retry
        await asyncio.sleep(0)

        assert pending.cancelled()
        assert svc._reconnect_task is not pending
        svc._cancel_reconnect()


# ---------------------------------------------------------------------------
# Sending, keepalive and idle
# ---------------------------------------------------------------------------


class TestSendJson:
    async def test_serializes_and_counts_as_activity(self):
        svc = TransportService()
        svc._ws = AsyncMock()
        svc._last_activity = 0.0

        await svc.send_json({"event": "end-of-stream"})

        svc._ws.send.assert_awaited_once_with('{"event": "end-of-stream"}')
        assert svc._last_activity > 0.0


class TestKeepalive:
    async def test_failed_ping_stops_the_keepalive(self, monkeypatch):
        monkeypatch.setattr(transport_service, "KEEPALIVE_INTERVAL_S", 0.001)
        svc = TransportService()
        svc._ws = AsyncMock()
        svc._ws.send.side_effect = ConnectionResetError("gone")
        _authenticated(svc)

        await asyncio.wait_for(svc._keepalive_loop(), timeout=1)

        svc._ws.send.assert_awaited_once_with(json.dumps({"event": "ping"}))

    async def test_no_pings_before_authentication(self, monkeypatch):
        monkeypatch.setattr(transport_service, "KEEPALIVE_INTERVAL_S", 0.001)
        svc = TransportService()
        ws = AsyncMock()
        svc._ws = ws
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)

        task = asyncio.create_task(svc._keepalive_loop())
        await asyncio.sleep(0.02)
        svc._ws = None  # socket gone: the loop exits on its own
        await asyncio.wait_for(task, timeout=1)

        ws.send.assert_not_called()


class TestIdleWatchdog:
    async def test_recent_activity_defers_the_disconnect(self, monkeypatch):
        monkeypatch.setattr(cfg, "IDLE_TIMEOUT", 0.2)
        svc = TransportService()
        ws = AsyncMock()
        svc._ws = ws
        svc._touch()

        watchdog = asyncio.create_task(svc._idle_watchdog())
        await asyncio.sleep(0.05)
        assert svc._ws is ws  # not idle long enough yet

        await asyncio.wait_for(watchdog, timeout=2)
        assert svc._ws is None
        ws.close.assert_awaited_once_with(1000, "Idle Timeout")


# ---------------------------------------------------------------------------
# Receive loop failure handling
# ---------------------------------------------------------------------------


class _BrokenSocket:
    """A socket whose message stream fails with a non-close error."""

    def __init__(self):
        self.close = AsyncMock()

    def __aiter__(self):
        return self

    async def __anext__(self):
        raise RuntimeError("TLS record corrupted")


class TestListenLoop:
    async def test_without_a_socket_does_nothing(self):
        svc = TransportService()

        await svc._listen_loop()

        assert svc._reconnect_task is None

    async def test_receiver_error_tears_down_and_retries(self, log_messages):
        svc = TransportService()
        socket = _BrokenSocket()
        svc._ws = cast(Any, socket)
        _authenticated(svc)

        await svc._listen_loop()

        socket.close.assert_awaited_once()
        assert svc._ws is None
        assert svc.handshake.state == HandshakeState.LOCKED
        assert svc._reconnect_task is not None
        assert "Transport receiver error: TLS record corrupted" in log_messages
        svc._cancel_reconnect()

    async def test_session_error_on_the_wire_reaches_handshake_state(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        listener = AsyncMock()
        svc.add_message_listener(listener)

        await svc._handle_raw_message(
            json.dumps(
                {"event": "error", "error_code": "IP_BANNED", "message": "abuse"}
            )
        )

        assert svc.handshake.state == HandshakeState.BANNED
        listener.assert_not_awaited()
