"""
Tests for TransportService connection lifecycle, teardown, idle and keepalive.

Complements test_transport.py by covering the connect/disconnect flows
and the full reconnection state machine.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from whisper_shell.logic.handshake import HandshakeState
from whisper_shell.services.transport_service import TransportService

# ---------------------------------------------------------------------------
# Connect flow
# ---------------------------------------------------------------------------


class TestConnectFlow:
    @pytest.mark.asyncio
    async def test_connect_when_already_connected_returns_true(self):
        svc = TransportService()
        svc._ws = MagicMock()  # pretend already connected
        result = await svc.connect()
        assert result is True

    @pytest.mark.asyncio
    async def test_connect_failure_schedules_reconnect(self):
        svc = TransportService()
        with patch(
            "whisper_shell.services.transport_service.websockets.connect",
            new_callable=AsyncMock,
            side_effect=OSError("refused"),
        ):
            result = await svc.connect()
        assert result is False
        assert svc._reconnect_task is not None
        svc._cancel_reconnect()

    @pytest.mark.asyncio
    async def test_connect_resets_intentional_disconnect_flag(self):
        svc = TransportService()
        svc._intentional_disconnect = True
        with patch(
            "whisper_shell.services.transport_service.websockets.connect",
            new_callable=AsyncMock,
            side_effect=OSError("refused"),
        ):
            await svc.connect()
        assert svc._intentional_disconnect is False
        svc._cancel_reconnect()

    @pytest.mark.asyncio
    async def test_concurrent_connects_open_one_socket(self):
        """Regression: launch-time connect and a hotkey press opened two sockets."""
        svc = TransportService()

        async def slow_open():
            await asyncio.sleep(0.01)
            svc._ws = MagicMock()
            return True

        with patch.object(
            svc, "_open_connection", AsyncMock(side_effect=slow_open)
        ) as open_connection:
            results = await asyncio.gather(svc.connect(), svc.connect())

        assert results == [True, True]
        assert open_connection.await_count == 1


# ---------------------------------------------------------------------------
# Disconnect
# ---------------------------------------------------------------------------


class TestDisconnect:
    @pytest.mark.asyncio
    async def test_disconnect_sets_intentional_flag(self):
        svc = TransportService()
        await svc.disconnect(reason="user action")
        assert svc._intentional_disconnect is True

    @pytest.mark.asyncio
    async def test_disconnect_resets_handshake(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        await svc.disconnect()
        assert svc.handshake.state == HandshakeState.LOCKED


# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------


class TestTeardown:
    @pytest.mark.asyncio
    async def test_teardown_cancels_background_tasks(self):
        svc = TransportService()
        tasks = [asyncio.create_task(asyncio.sleep(999)) for _ in range(3)]
        svc._keepalive_task, svc._idle_task, svc._receive_task = tasks
        await svc._teardown("test")
        await asyncio.sleep(0)
        assert all(task.cancelled() for task in tasks)
        assert svc._keepalive_task is None
        assert svc._idle_task is None
        assert svc._receive_task is None

    @pytest.mark.asyncio
    async def test_teardown_from_its_own_task_completes(self):
        """Regression: the idle watchdog and receive loop run teardown
        themselves; cancelling the current task aborted it half-way."""
        svc = TransportService()
        svc._ws = AsyncMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)

        async def watchdog_like():
            await svc._teardown("from inside")

        svc._idle_task = asyncio.create_task(watchdog_like())
        await svc._idle_task

        assert svc._ws is None
        assert svc.handshake.state == HandshakeState.LOCKED

    @pytest.mark.asyncio
    async def test_teardown_closes_websocket(self):
        svc = TransportService()
        mock_ws = AsyncMock()
        svc._ws = mock_ws
        await svc._teardown("test")
        mock_ws.close.assert_called_once()
        assert svc._ws is None

    @pytest.mark.asyncio
    async def test_teardown_handles_ws_close_exception(self):
        svc = TransportService()
        mock_ws = AsyncMock()
        mock_ws.close.side_effect = Exception("already closed")
        svc._ws = mock_ws
        await svc._teardown("test")
        assert svc._ws is None  # Still cleaned up

    @pytest.mark.asyncio
    async def test_teardown_skips_handshake_reset_when_requested(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.FAILED)
        await svc._teardown("test", reset_handshake=False)
        assert svc.handshake.state == HandshakeState.FAILED


# ---------------------------------------------------------------------------
# Handle unexpected close
# ---------------------------------------------------------------------------


def _failed_with(svc: TransportService, error_code: str) -> None:
    svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
    svc.handshake.set_error_context(error_code, "reason")
    svc.handshake.transition_to(HandshakeState.FAILED)


class TestHandleUnexpectedClose:
    @pytest.mark.asyncio
    async def test_unexpected_close_schedules_reconnect(self):
        svc = TransportService()
        await svc._handle_unexpected_close()
        assert svc._reconnect_task is not None
        svc._cancel_reconnect()

    @pytest.mark.asyncio
    async def test_plain_drop_returns_to_locked(self):
        svc = TransportService()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc.handshake.transition_to(HandshakeState.AUTHENTICATED)
        await svc._handle_unexpected_close()
        assert svc.handshake.state == HandshakeState.LOCKED
        svc._cancel_reconnect()

    @pytest.mark.asyncio
    async def test_intentional_disconnect_skips_reconnect(self):
        svc = TransportService()
        svc._intentional_disconnect = True
        await svc._handle_unexpected_close()
        assert svc._reconnect_task is None

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        "state", [HandshakeState.BANNED, HandshakeState.VERSION_OUTDATED]
    )
    async def test_terminal_states_skip_reconnect(self, state):
        svc = TransportService()
        svc.handshake.transition_to(state)
        await svc._handle_unexpected_close()
        assert svc._reconnect_task is None
        assert svc.handshake.state == state

    @pytest.mark.asyncio
    @pytest.mark.parametrize("close_code", [4000, 4001])
    async def test_idle_eviction_does_not_reconnect(self, close_code):
        """Regression: server idle evictions caused an endless reconnect loop."""
        svc = TransportService()
        await svc._handle_unexpected_close(close_code)
        assert svc._reconnect_task is None

    @pytest.mark.asyncio
    async def test_auth_failure_does_not_reconnect(self):
        svc = TransportService()
        _failed_with(svc, "AUTH_FAILED")
        await svc._handle_unexpected_close(1008)
        assert svc._reconnect_task is None
        assert svc.handshake.state == HandshakeState.FAILED

    @pytest.mark.asyncio
    async def test_capacity_rejection_retries_with_backoff(self):
        svc = TransportService()
        _failed_with(svc, "MAX_CONNECTIONS")
        await svc._handle_unexpected_close(1008)
        assert svc._reconnect_task is not None
        assert svc._reconnect_attempt == 1
        svc._cancel_reconnect()


# ---------------------------------------------------------------------------
# Idle watchdog & keepalive
# ---------------------------------------------------------------------------


def _authenticated(svc: TransportService) -> None:
    svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
    svc.handshake.transition_to(HandshakeState.AUTHENTICATED)


class TestIdleAndKeepalive:
    @pytest.mark.asyncio
    async def test_pong_does_not_count_as_activity(self):
        svc = TransportService()
        svc._last_activity = 0.0
        await svc._handle_raw_message('{"event": "pong"}')
        assert svc._last_activity == 0.0

    @pytest.mark.asyncio
    async def test_audio_counts_as_activity(self):
        svc = TransportService()
        svc._ws = AsyncMock()
        _authenticated(svc)
        svc._last_activity = 0.0
        await svc.send_audio(b"\x00\x01")
        assert svc._last_activity > 0.0

    @pytest.mark.asyncio
    async def test_keepalive_ping_does_not_defer_idle(self):
        """Regression: pings reset the idle timer, so idle disconnect never fired."""
        svc = TransportService()
        ws = AsyncMock()
        svc._ws = ws
        _authenticated(svc)
        svc._last_activity = 0.0
        with patch(
            "whisper_shell.services.transport_service.KEEPALIVE_INTERVAL_S", 0.001
        ):
            task = asyncio.create_task(svc._keepalive_loop())
            await asyncio.sleep(0.02)
            task.cancel()
        assert ws.send.await_count >= 1
        assert svc._last_activity == 0.0

    @pytest.mark.asyncio
    async def test_idle_watchdog_disconnects_cleanly(self):
        svc = TransportService()
        svc._ws = AsyncMock()
        svc.handshake.transition_to(HandshakeState.AUTHENTICATING)
        svc._last_activity = 0.0  # long ago
        with patch("whisper_shell.services.transport_service.cfg") as cfg:
            cfg.IDLE_TIMEOUT = 1
            svc._idle_task = asyncio.create_task(svc._idle_watchdog())
            await svc._idle_task
        assert svc._ws is None
        assert svc._intentional_disconnect is True
        assert svc.handshake.state == HandshakeState.LOCKED
