"""
Tests for TransportService.

Covers: URI preparation, error routing, keepalive lifecycle,
reconnection backoff, and the send guard.
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from whisper_shell.logic.handshake import HandshakeState
from whisper_shell.logic.messages import ServerMessage
from whisper_shell.services.transport_service import (
    MAX_RECONNECT_ATTEMPTS,
    TransportService,
)

# ---------------------------------------------------------------------------
# URI preparation
# ---------------------------------------------------------------------------


class TestPrepareUri:
    def test_localhost_stays_ws(self):
        svc = TransportService()
        assert svc._prepare_uri("ws://localhost:9989/ws").startswith("ws://")

    def test_remote_host_upgraded_to_wss(self):
        svc = TransportService()
        result = svc._prepare_uri("ws://api.example.com/ws")
        assert result.startswith("wss://")

    def test_https_becomes_wss(self):
        svc = TransportService()
        result = svc._prepare_uri("https://api.example.com/ws")
        assert result.startswith("wss://")

    def test_http_localhost_stays_ws(self):
        svc = TransportService()
        result = svc._prepare_uri("http://localhost:9989/ws")
        assert result.startswith("ws://")

    def test_default_path_is_ws(self):
        svc = TransportService()
        result = svc._prepare_uri("ws://localhost:9989")
        assert result.endswith("/ws")

    def test_query_string_preserved(self):
        svc = TransportService()
        result = svc._prepare_uri("ws://localhost:9989/ws?token=abc")
        assert "?token=abc" in result

    def test_127_0_0_1_stays_ws(self):
        svc = TransportService()
        result = svc._prepare_uri("ws://127.0.0.1:9989/ws")
        assert result.startswith("ws://")


# ---------------------------------------------------------------------------
# Error routing (_handle_error_message)
# ---------------------------------------------------------------------------


class TestErrorRouting:
    """Session errors become handshake state; operational errors go to listeners."""

    def _make_svc(self) -> TransportService:
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        return svc

    @staticmethod
    def _error(error_code: str, message: str = "msg") -> ServerMessage:
        return {"event": "error", "error_code": error_code, "message": message}

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        ("error_code", "expected"),
        [
            ("IP_BANNED", HandshakeState.BANNED),
            ("VERSION_OUTDATED", HandshakeState.VERSION_OUTDATED),
            ("MAX_CONNECTIONS", HandshakeState.FAILED),
            ("HANDSHAKE_REQUIRED", HandshakeState.FAILED),
            ("MALFORMED_JSON", HandshakeState.FAILED),
            ("INVALID_EVENT", HandshakeState.FAILED),
            ("DUPLICATE_HANDSHAKE", HandshakeState.FAILED),
        ],
    )
    async def test_session_errors_set_state_without_notifying(
        self, error_code, expected
    ):
        svc = self._make_svc()
        listener = MagicMock()
        svc.add_message_listener(listener)

        await svc._handle_error_message(self._error(error_code, "why"))

        assert svc.handshake.state == expected
        assert svc.handshake.last_error_code == error_code
        assert svc.handshake.last_message == "why"
        listener.assert_not_called()  # reported once, via handshake state

    @pytest.mark.asyncio
    async def test_auth_failed_clears_key(self):
        svc = self._make_svc()
        with patch("whisper_shell.services.transport_service.sec_cfg") as mock_sec:
            await svc._handle_error_message(self._error("AUTH_FAILED"))
            mock_sec.clear_key.assert_called_once_with(svc.hostname)
        assert svc.handshake.state == HandshakeState.FAILED

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        "error_code",
        [
            "NO_AUDIO",
            "TRANSCRIPTION_FAILED",
            "BUFFER_EXCEEDED",
            "SERVER_ERROR",
            "UNKNOWN_FUTURE_CODE",
            "",
        ],
    )
    async def test_operational_errors_notify_and_keep_session(self, error_code):
        svc = self._make_svc()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        listener = MagicMock()
        svc.add_message_listener(listener)
        msg = self._error(error_code)

        await svc._handle_error_message(msg)

        assert svc.handshake.state == HandshakeState.AUTHENTICATED
        listener.assert_called_once_with(msg)


# ---------------------------------------------------------------------------
# Raw message handling
# ---------------------------------------------------------------------------


class TestHandleRawMessage:
    @pytest.mark.asyncio
    async def test_authenticated_event(self):
        svc = TransportService()
        svc._ws = MagicMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        await svc._handle_raw_message(
            json.dumps(
                {
                    "event": "authenticated",
                    "cid": "abc123",
                }
            )
        )
        assert svc.handshake.state == HandshakeState.AUTHENTICATED

    @pytest.mark.asyncio
    async def test_hello_event_is_noop(self):
        svc = TransportService()
        svc._ws = MagicMock()
        await svc._handle_raw_message(json.dumps({"event": "hello"}))
        assert svc.handshake.state == HandshakeState.LOCKED

    @pytest.mark.asyncio
    async def test_pong_event_is_noop(self):
        svc = TransportService()
        svc._ws = MagicMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        await svc._handle_raw_message(json.dumps({"event": "pong"}))
        assert svc.handshake.state == HandshakeState.AUTHENTICATED

    @pytest.mark.asyncio
    async def test_transcription_forwarded_to_listeners(self):
        svc = TransportService()
        svc._ws = MagicMock()
        received = []
        svc.add_message_listener(received.append)
        await svc._handle_raw_message(
            json.dumps(
                {
                    "event": "transcription",
                    "text": "hello world",
                }
            )
        )
        assert len(received) == 1
        assert received[0]["text"] == "hello world"

    @pytest.mark.asyncio
    async def test_binary_message_ignored(self):
        svc = TransportService()
        svc._ws = MagicMock()
        await svc._handle_raw_message(b"\x00\x01\x02")
        # Should not raise

    @pytest.mark.asyncio
    async def test_malformed_json_does_not_raise(self):
        svc = TransportService()
        svc._ws = MagicMock()
        await svc._handle_raw_message("{bad json")
        # Should log error but not raise


# ---------------------------------------------------------------------------
# Send guard
# ---------------------------------------------------------------------------


class TestSendGuard:
    @pytest.mark.asyncio
    async def test_send_audio_requires_authenticated(self):
        svc = TransportService()
        svc._ws = AsyncMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        await svc.send_audio(b"\x00\x01")
        svc._ws.send.assert_not_called()

    @pytest.mark.asyncio
    async def test_send_audio_works_when_authenticated(self):
        svc = TransportService()
        svc._ws = AsyncMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        await svc.send_audio(b"\x00\x01")
        svc._ws.send.assert_called_once_with(b"\x00\x01")

    @pytest.mark.asyncio
    async def test_send_audio_noop_without_socket(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        await svc.send_audio(b"\x00\x01")
        # No socket — should not raise

    @pytest.mark.asyncio
    async def test_send_json_noop_without_socket(self):
        svc = TransportService()
        await svc.send_json({"event": "ping"})
        # No socket — should not raise


# ---------------------------------------------------------------------------
# ensure_connected guards terminal states
# ---------------------------------------------------------------------------


class TestEnsureConnected:
    @pytest.mark.asyncio
    async def test_returns_false_when_banned(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.BANNED)
        assert await svc.ensure_connected() is False

    @pytest.mark.asyncio
    async def test_returns_false_when_version_outdated(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.VERSION_OUTDATED)
        assert await svc.ensure_connected() is False

    @pytest.mark.asyncio
    async def test_returns_true_when_already_authenticated(self):
        svc = TransportService()
        svc._ws = MagicMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        assert await svc.ensure_connected() is True

    @pytest.mark.asyncio
    async def test_reconnects_when_authenticated_state_has_no_socket(self):
        """A dropped socket must not pass for a live session."""
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        with patch.object(svc, "connect", AsyncMock(return_value=True)) as connect:
            assert await svc.ensure_connected() is True
            connect.assert_awaited_once()


# ---------------------------------------------------------------------------
# Reconnection backoff
# ---------------------------------------------------------------------------


class TestReconnectionBackoff:
    @pytest.mark.asyncio
    async def test_schedule_reconnect_increments_attempt(self):
        svc = TransportService()
        svc._schedule_reconnect()
        assert svc._reconnect_attempt == 1
        assert svc._reconnect_task is not None
        svc._cancel_reconnect()

    def test_max_attempts_resets_counter(self):
        svc = TransportService()
        svc._reconnect_attempt = MAX_RECONNECT_ATTEMPTS
        svc._schedule_reconnect()
        assert svc._reconnect_attempt == 0
        assert svc._reconnect_task is None

    @pytest.mark.asyncio
    async def test_cancel_reconnect(self):
        svc = TransportService()
        svc._schedule_reconnect()
        svc._cancel_reconnect()
        assert svc._reconnect_task is None

    @pytest.mark.asyncio
    async def test_backoff_resets_only_on_authentication(self):
        """Regression: the counter reset when the socket opened, so a server
        rejecting before auth (e.g. at capacity) was retried every second."""
        svc = TransportService()
        svc._reconnect_attempt = 3
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        await svc._handle_raw_message('{"event": "authenticated", "cid": "x"}')
        assert svc._reconnect_attempt == 0


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------


class TestHealthCheck:
    def test_health_success(self):
        svc = TransportService()
        with patch("whisper_shell.services.transport_service.requests.get") as mock_get:
            mock_get.return_value = MagicMock(status_code=200)
            assert svc.check_health() is True

    def test_health_failure(self):
        svc = TransportService()
        with patch("whisper_shell.services.transport_service.requests.get") as mock_get:
            mock_get.return_value = MagicMock(status_code=503)
            assert svc.check_health() is False

    def test_health_exception(self):
        svc = TransportService()
        with patch("whisper_shell.services.transport_service.requests.get") as mock_get:
            mock_get.side_effect = ConnectionError("refused")
            assert svc.check_health() is False
