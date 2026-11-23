"""Background eviction of stale WebSocket connections.

ConnectionManager is driven the way the /ws endpoint drives it (connect,
then text/binary messages) over a fake socket, with a fake clock standing in
for wall time so timeouts can be crossed without sleeping.
"""

import asyncio
import json
from unittest.mock import patch

import pytest

from protocol import websocket_handler
from protocol.websocket_handler import ConnectionManager
from security import governance
from tests.fakes import API_KEY, FakeClock, FakeEngine, FakeSocket

HANDSHAKE_TIMEOUT = 15
IDLE_TIMEOUT = 375
NO_AUDIO_GRACE = 360


@pytest.fixture
def clock(monkeypatch):
    clock = FakeClock()
    monkeypatch.setattr(websocket_handler, "time", clock)
    monkeypatch.setattr(governance, "time", clock)
    monkeypatch.setattr(
        websocket_handler, "HANDSHAKE_TIMEOUT_SECONDS", HANDSHAKE_TIMEOUT
    )
    monkeypatch.setattr(websocket_handler, "IDLE_TIMEOUT_SECONDS", IDLE_TIMEOUT)
    monkeypatch.setattr(websocket_handler, "NO_AUDIO_GRACE_SECONDS", NO_AUDIO_GRACE)
    monkeypatch.setattr(websocket_handler, "MAX_CONNECTIONS", 10)
    monkeypatch.setattr(governance, "BAN_FAILURE_THRESHOLD", 2)
    monkeypatch.setattr(governance, "BAN_FAILURE_WINDOW_SECONDS", 60)
    monkeypatch.setattr(governance, "BAN_DURATION_SECONDS", 300)
    monkeypatch.setattr(governance, "FLOOD_ATTEMPT_THRESHOLD", 1000)
    monkeypatch.setenv("WHISPER_DOC_API_KEY", API_KEY)
    return clock


@pytest.fixture
async def manager(clock):
    manager = ConnectionManager(FakeEngine(loaded=True), "3.2.0")
    yield manager
    await manager.stop()


async def connect(
    manager, host="203.0.113.7", authenticate=True, fail_close=False, **hello
):
    ws = FakeSocket(host=host, fail_close=fail_close)
    await manager.connect(ws)
    if authenticate:
        message = {"event": "hello", "version": "3.2.0", "token": API_KEY, **hello}
        await manager.handle_message(ws, json.dumps(message))
        assert ws.sent[-1]["event"] == "authenticated"
    return ws


async def sweep(manager, clock):
    """One pass of the cleanup task at the current fake time."""
    stale = manager._identify_stale_connections(clock.now)
    await manager._execute_disconnections(stale)


# ---------------------------------------------------------------------------
# Eviction rules
# ---------------------------------------------------------------------------


async def test_unauthenticated_socket_is_closed_after_the_handshake_timeout(
    manager, clock
):
    ws = await connect(manager, authenticate=False)

    clock.advance(HANDSHAKE_TIMEOUT)
    await sweep(manager, clock)
    assert ws.closed is None

    clock.advance(1)
    await sweep(manager, clock)
    assert ws.closed == (1008, "Handshake timeout")
    assert ws not in manager.active_connections


async def test_handshake_timeouts_count_towards_a_ban(manager, clock):
    for _ in range(2):
        await connect(manager, authenticate=False)
    clock.advance(HANDSHAKE_TIMEOUT + 1)
    await sweep(manager, clock)

    refused = FakeSocket()
    await manager.connect(refused)
    assert refused.sent[0]["error_code"] == "IP_BANNED"
    assert refused.closed == (1008, "IP Banned. Cooldown: 300s")
    # A different address is unaffected.
    other = await connect(manager, host="198.51.100.1", authenticate=False)
    assert other.sent[0]["event"] == "hello"


async def test_silent_authenticated_socket_is_closed_for_inactivity(manager, clock):
    ws = await connect(manager)
    await manager.handle_message(ws, b"\x00\x00")

    clock.advance(IDLE_TIMEOUT)
    await sweep(manager, clock)
    assert ws.closed is None

    clock.advance(1)
    await sweep(manager, clock)
    assert ws.closed == (4000, "Inactivity timeout")
    assert manager.active_connections == {}


async def test_inactivity_close_is_not_a_protocol_violation(manager, clock):
    for _ in range(3):
        ws = await connect(manager)
        clock.advance(IDLE_TIMEOUT + 1)
        await sweep(manager, clock)
        assert ws.closed == (4000, "Inactivity timeout")

    ws = await connect(manager)
    assert ws.sent[0]["event"] == "hello"


async def test_pinging_without_ever_sending_audio_is_evicted_after_the_grace(
    manager, clock
):
    ws = await connect(manager)

    for _ in range(NO_AUDIO_GRACE // 60):
        clock.advance(60)
        await manager.handle_message(ws, json.dumps({"event": "ping"}))
    await sweep(manager, clock)
    assert ws.closed is None, "still inside the grace period"

    clock.advance(1)
    await manager.handle_message(ws, json.dumps({"event": "ping"}))
    await sweep(manager, clock)
    assert ws.closed == (4001, "No audio activity")


async def test_pinging_after_audio_went_stale_is_evicted(manager, clock):
    ws = await connect(manager)
    await manager.handle_message(ws, b"\x01\x00" * 10)

    for _ in range(IDLE_TIMEOUT // 25):
        clock.advance(25)
        await manager.handle_message(ws, json.dumps({"event": "ping"}))
    await sweep(manager, clock)
    assert ws.closed is None, "audio is exactly at the idle limit"

    clock.advance(1)
    await manager.handle_message(ws, json.dumps({"event": "ping"}))
    await sweep(manager, clock)
    assert ws.closed == (4001, "No audio activity")


async def test_regular_dictation_keeps_a_connection_alive_indefinitely(manager, clock):
    ws = await connect(manager)

    for _ in range(20):
        clock.advance(300)
        await manager.handle_message(ws, b"\x01\x00" * 160)
        await manager.handle_message(ws, json.dumps({"event": "end-of-stream"}))
        assert ws.sent[-1]["event"] == "transcription"
        await sweep(manager, clock)

    assert ws.closed is None
    assert ws in manager.active_connections


async def test_eviction_proceeds_when_the_socket_is_already_gone(manager, clock):
    ws = await connect(manager, authenticate=False, fail_close=True)
    healthy = await connect(manager, host="198.51.100.2")
    await manager.handle_message(healthy, b"\x00\x00")

    clock.advance(HANDSHAKE_TIMEOUT + 1)
    await manager.handle_message(healthy, b"\x00\x00")
    await sweep(manager, clock)

    assert ws not in manager.active_connections
    assert healthy in manager.active_connections


async def test_freed_slot_admits_a_new_client(manager, clock, monkeypatch):
    monkeypatch.setattr(websocket_handler, "MAX_CONNECTIONS", 1)
    ws = await connect(manager)

    refused = FakeSocket(host="198.51.100.3")
    await manager.connect(refused)
    assert refused.sent == [
        {
            "event": "error",
            "code": 1008,
            "error_code": "MAX_CONNECTIONS",
            "message": "Max concurrent connections reached",
        }
    ]

    manager.disconnect(ws)
    admitted = await connect(manager, host="198.51.100.3")
    assert admitted.sent[0]["event"] == "hello"


async def test_messages_from_unknown_sockets_are_ignored(manager):
    stranger = FakeSocket()
    await manager.handle_message(stranger, json.dumps({"event": "hello"}))
    await manager.handle_message(stranger, b"\x00\x00")
    await manager.transcribe_and_send(stranger)
    assert stranger.sent == [] and stranger.closed is None


async def test_handler_error_on_a_dead_socket_does_not_escape(manager):
    ws = await connect(manager, fail_close=True)

    await manager.handle_message(ws, "[1]")  # valid JSON, not an object

    assert ws.sent[-1]["error_code"] == "SERVER_ERROR"
    assert ws.sent[-1]["code"] == 1011


# ---------------------------------------------------------------------------
# The cleanup task itself
# ---------------------------------------------------------------------------


async def test_cleanup_task_evicts_on_its_ten_second_tick(manager, clock):
    ws = await connect(manager, authenticate=False)
    ticks = []

    async def fake_sleep(seconds):
        ticks.append(seconds)
        clock.advance(seconds)
        if len(ticks) > 2:
            raise asyncio.CancelledError

    with (
        patch.object(asyncio, "sleep", fake_sleep),
        pytest.raises(asyncio.CancelledError),
    ):
        await manager._cleanup_inactive_connections()

    assert ticks == [10, 10, 10]
    assert ws.closed == (1008, "Handshake timeout")


async def test_cleanup_task_survives_an_error_in_one_pass(manager, clock, monkeypatch):
    ws = await connect(manager, authenticate=False)
    passes = []
    real_identify = manager._identify_stale_connections

    def flaky_identify(now):
        passes.append(now)
        if len(passes) == 1:
            raise RuntimeError("transient")
        return real_identify(now)

    async def fake_sleep(seconds):
        clock.advance(seconds)
        if len(passes) >= 2:
            raise asyncio.CancelledError

    monkeypatch.setattr(manager, "_identify_stale_connections", flaky_identify)
    with (
        patch.object(asyncio, "sleep", fake_sleep),
        pytest.raises(asyncio.CancelledError),
    ):
        await manager._cleanup_inactive_connections()

    assert len(passes) == 2
    assert ws.closed == (1008, "Handshake timeout")


# ---------------------------------------------------------------------------
# Hourly maintenance
# ---------------------------------------------------------------------------


async def test_hourly_maintenance_prunes_departed_users_and_expired_bans(
    manager, clock, monkeypatch
):
    # The IdP edge: every OIDC token names its own subject.
    monkeypatch.setattr("auth.oidc.validate_oidc_token", lambda token: {"sub": token})

    async def dictate(ws):
        await manager.handle_message(ws, b"\x00\x00")
        await manager.handle_message(ws, json.dumps({"event": "end-of-stream"}))
        assert ws.sent[-1]["event"] == "transcription"

    departed = await connect(manager, auth_type="oidc", token="departed-user")
    await dictate(departed)
    manager.disconnect(departed)

    staying = await connect(
        manager, host="198.51.100.4", auth_type="oidc", token="staying-user"
    )
    await dictate(staying)
    api_key_user = await connect(manager, host="198.51.100.5")
    await dictate(api_key_user)
    assert set(manager.user_semaphores) == {
        "departed-user",
        "staying-user",
        "static_apiKey",
    }

    # Ban an address, then let the ban lapse without that address returning.
    for _ in range(2):
        bad = FakeSocket(host="192.0.2.66")
        await manager.connect(bad)
        await manager.handle_message(bad, "{bad json")
    assert manager.governance.is_ip_banned("192.0.2.66")[0]

    clock.advance(3600)
    manager._run_hourly_maintenance(clock.now)
    assert "departed-user" in manager.user_semaphores, "maintenance runs hourly"
    assert "192.0.2.66" in manager.governance.ban_tracker

    clock.advance(1)
    manager._run_hourly_maintenance(clock.now)
    assert set(manager.user_semaphores) == {"staying-user", "static_apiKey"}
    assert manager.governance.ban_tracker == {}
    assert manager.governance.failure_tracker == {}

    # The next run is an hour after this one, not after construction.
    manager.user_semaphores["ghost"]  # an entry left behind by a departed user
    clock.advance(3600)
    manager._run_hourly_maintenance(clock.now)
    assert "ghost" in manager.user_semaphores
