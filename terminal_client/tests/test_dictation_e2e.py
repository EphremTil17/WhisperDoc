"""
End-to-end tests over a real WebSocket connection.

A small in-process server (the `websockets` library, bound to 127.0.0.1 on a
free port) plays the backend. TransportService, AudioService and
RecordingController are the real ones; only the OS edges are faked: the
keyring, the clipboard and the keyboard. Audio enters exactly where PortAudio
would deliver it, through AudioService.audio_callback.
"""

import asyncio
import contextlib
import json
from http import HTTPStatus
from typing import Any, cast
from unittest.mock import MagicMock

import numpy as np
import pytest
from loguru import logger
from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed

from whisper_shell.controllers import recording_controller
from whisper_shell.logic.handshake import HandshakeState
from whisper_shell.logic.payload import PayloadBuilder
from whisper_shell.services import transport_service
from whisper_shell.services.config_service import cfg
from whisper_shell.services.transport_service import TransportService

API_KEY = "e2e-api-key"
AUTHENTICATED = json.dumps({"event": "authenticated", "cid": "cid-e2e"})
EOS = "<end-of-stream>"


async def eventually(predicate, timeout: float = 3.0) -> None:
    """Wait until predicate() holds, failing after `timeout` seconds."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while not predicate():
        if loop.time() > deadline:
            raise AssertionError("condition not reached in time")
        await asyncio.sleep(0.005)


@contextlib.asynccontextmanager
async def backend(handler, **options):
    """Serve `handler` on a free local port; yields the client's server URI."""
    async with serve(handler, "127.0.0.1", 0, **options) as server:
        port = next(iter(server.sockets)).getsockname()[1]
        yield f"ws://127.0.0.1:{port}"


async def read_stream(ws: ServerConnection, received: list) -> None:
    """Record binary audio frames and end-of-stream markers, in arrival order."""
    async for message in ws:
        if isinstance(message, bytes):
            received.append(message)
        elif json.loads(message).get("event") == "end-of-stream":
            received.append(EOS)
            return


@pytest.fixture
def keyring(monkeypatch) -> MagicMock:
    sec = MagicMock()
    sec.get_api_key.return_value = API_KEY
    monkeypatch.setattr(transport_service, "sec_cfg", sec)
    return sec


@pytest.fixture
async def client_for(monkeypatch, keyring):
    """Build a TransportService pointed at a fake backend URI."""
    services: list[TransportService] = []

    def build(uri: str) -> TransportService:
        monkeypatch.setattr(cfg, "WS_URI", uri)
        svc = TransportService()
        services.append(svc)
        return svc

    yield build
    for svc in services:  # also cancels any pending retry
        await svc.disconnect()


async def _closed(svc: TransportService) -> None:
    await eventually(lambda: svc._ws is None and svc._receive_task is None)


# ---------------------------------------------------------------------------
# Transport against the fake backend
# ---------------------------------------------------------------------------


class TestHandshakeOverTheWire:
    async def test_hello_carries_key_and_version_then_audio_flows(self, client_for):
        hellos, paths, received = [], [], []

        async def handler(ws: ServerConnection):
            paths.append(ws.request.path if ws.request else None)
            hellos.append(json.loads(await ws.recv()))
            await ws.send(AUTHENTICATED)
            await read_stream(ws, received)

        async with backend(handler) as uri:
            svc = client_for(uri)
            assert await svc.connect() is True
            await eventually(lambda: svc.is_ready)

            await svc.send_audio(b"\x01\x02")
            await svc.send_audio(b"\x03\x04")
            await svc.send_json(PayloadBuilder.build_end_of_stream())
            await eventually(lambda: EOS in received)
            await svc.disconnect()

        assert paths == ["/ws"]
        assert hellos == [
            {
                "event": "hello",
                "client": "whisper.client.terminal",
                "version": cfg.VERSION,
                "auth_type": "api_key",
                "token": API_KEY,
                "incognito": False,
            }
        ]
        assert received == [b"\x01\x02", b"\x03\x04", EOS]

    async def test_audio_is_withheld_until_authenticated(self, client_for):
        received = []
        release_auth = asyncio.Event()

        async def handler(ws: ServerConnection):
            await ws.recv()
            await release_auth.wait()
            await ws.send(AUTHENTICATED)
            await read_stream(ws, received)

        async with backend(handler) as uri:
            svc = client_for(uri)
            await svc.connect()
            await svc.send_audio(b"too-early")  # still AUTHENTICATING
            release_auth.set()
            await eventually(lambda: svc.is_ready)
            await svc.send_audio(b"on-time")
            await svc.send_json(PayloadBuilder.build_end_of_stream())
            await eventually(lambda: EOS in received)
            await svc.disconnect()

        assert received == [b"on-time", EOS]

    async def test_operational_messages_reach_listeners_in_order(self, client_for):
        async def handler(ws: ServerConnection):
            await ws.recv()
            await ws.send(AUTHENTICATED)
            await ws.send(json.dumps({"event": "hello"}))
            await ws.send(json.dumps({"event": "pong"}))
            await ws.send("not json")
            await ws.send(json.dumps({"event": "error", "error_code": "NO_AUDIO"}))
            await ws.send(json.dumps({"event": "transcription", "text": "done"}))
            await ws.wait_closed()

        async with backend(handler) as uri:
            svc = client_for(uri)
            seen: list[dict] = []

            async def listener(msg):
                seen.append(dict(msg))

            svc.add_message_listener(listener)
            await svc.connect()
            await eventually(lambda: len(seen) == 2)
            await svc.disconnect()

        assert seen == [
            {"event": "error", "error_code": "NO_AUDIO"},
            {"event": "transcription", "text": "done"},
        ]
        assert svc.handshake.state == HandshakeState.LOCKED  # after disconnect


class TestServerEndedSessions:
    async def test_rejected_key_is_cleared_and_not_retried(self, client_for, keyring):
        async def handler(ws: ServerConnection):
            await ws.recv()
            await ws.send(
                json.dumps(
                    {
                        "event": "error",
                        "error_code": "AUTH_FAILED",
                        "message": "Invalid API key",
                    }
                )
            )
            await ws.close(1008, "auth failed")

        async with backend(handler) as uri:
            svc = client_for(uri)
            await svc.connect()
            await eventually(lambda: svc.handshake.state == HandshakeState.FAILED)
            await _closed(svc)

        keyring.clear_key.assert_called_once_with("127.0.0.1")
        assert svc.handshake.last_error_code == "AUTH_FAILED"
        assert svc.handshake.last_message == "Invalid API key"
        assert svc._reconnect_task is None

    async def test_banned_client_stays_banned(self, client_for, keyring):
        async def handler(ws: ServerConnection):
            await ws.recv()
            await ws.send(json.dumps({"event": "error", "error_code": "IP_BANNED"}))
            await ws.close(1008, "banned")

        async with backend(handler) as uri:
            svc = client_for(uri)
            await svc.connect()
            await _closed(svc)
            assert await svc.ensure_connected() is False

        assert svc.handshake.state == HandshakeState.BANNED
        assert svc._reconnect_task is None
        keyring.clear_key.assert_not_called()

    @pytest.mark.parametrize("close_code", [4000, 4001])
    async def test_idle_eviction_waits_for_the_next_recording(
        self, client_for, close_code
    ):
        async def handler(ws: ServerConnection):
            await ws.recv()
            await ws.send(AUTHENTICATED)
            await ws.close(close_code, "idle")

        async with backend(handler) as uri:
            svc = client_for(uri)
            await svc.connect()
            await eventually(lambda: svc.is_ready)
            await _closed(svc)

        assert svc.handshake.state == HandshakeState.LOCKED
        assert svc._reconnect_task is None

    async def test_server_crash_reconnects_and_reauthenticates(
        self, client_for, monkeypatch
    ):
        monkeypatch.setattr(transport_service, "BACKOFF_BASE_S", 0.01)
        connections = []

        async def handler(ws: ServerConnection):
            connections.append(json.loads(await ws.recv())["token"])
            await ws.send(AUTHENTICATED)
            if len(connections) == 1:
                await ws.close(1011, "internal error")
            else:
                await ws.wait_closed()

        async with backend(handler) as uri:
            svc = client_for(uri)
            await svc.connect()
            await eventually(lambda: len(connections) == 2 and svc.is_ready)
            attempts_after_success = svc._reconnect_attempt
            await svc.disconnect()

        assert connections == [API_KEY, API_KEY]
        assert attempts_after_success == 0  # backoff reset by authentication


class TestRefusedUpgrade:
    async def test_http_rejection_is_reported_and_retried(self, client_for):
        errors: list[str] = []
        sink = logger.add(lambda m: errors.append(m.record["message"]), level="ERROR")

        def reject(connection, request):
            return connection.respond(HTTPStatus.FORBIDDEN, "blocked by policy\n")

        try:
            async with backend(
                lambda ws: ws.wait_closed(), process_request=reject
            ) as uri:
                svc = client_for(uri)
                assert await svc.connect() is False
        finally:
            logger.remove(sink)

        assert "Connection failed: HTTP 403" in errors
        assert any("blocked by policy" in e for e in errors)
        assert svc._ws is None
        assert svc._reconnect_attempt == 1
        assert svc._reconnect_task is not None


# ---------------------------------------------------------------------------
# Full dictation: hotkey toggle -> audio -> server -> clipboard paste
# ---------------------------------------------------------------------------


def _pcm(level: float, frames: int = 160) -> tuple[np.ndarray, bytes]:
    """A block of float32 frames as PortAudio delivers it, and its PCM bytes."""
    block = np.full((frames, 1), level, dtype=np.float32)
    return block, (block.flatten() * 32767).astype(np.int16).tobytes()


@pytest.fixture
def desktop(monkeypatch):
    """Fake clipboard and keyboard; returns them as (clipboard, keyboard)."""
    clipboard = MagicMock()
    keyboard = MagicMock()
    monkeypatch.setattr(recording_controller, "pyperclip", clipboard)
    monkeypatch.setattr(recording_controller, "keyboard", keyboard)
    return clipboard, keyboard


@pytest.fixture
async def dictation(monkeypatch, keyring, desktop):
    """Build a real RecordingController against a fake backend URI."""
    controllers = []

    def build(uri: str):
        monkeypatch.setattr(cfg, "WS_URI", uri)
        ctrl = recording_controller.RecordingController(asyncio.get_running_loop())
        controllers.append(ctrl)
        return ctrl

    yield build
    for ctrl in controllers:
        await ctrl.shutdown()


def _backend_transcribing(received: list, transcript: str, release_auth=None):
    async def handler(ws: ServerConnection):
        await ws.recv()
        if release_auth is not None:
            await release_auth.wait()
        await ws.send(AUTHENTICATED)
        await read_stream(ws, received)
        await ws.send(json.dumps({"event": "transcription", "text": transcript}))
        await ws.wait_closed()

    return handler


class TestDictationEndToEnd:
    async def test_speech_during_connect_is_delivered_before_end_of_stream(
        self, dictation, desktop
    ):
        clipboard, keyboard = desktop
        received: list = []
        release_auth = asyncio.Event()
        first, first_pcm = _pcm(0.25)
        second, second_pcm = _pcm(-0.5)
        transcript = "\x1b[31mHello world\x1b[0m\x07"

        handler = _backend_transcribing(received, transcript, release_auth)
        async with backend(handler) as uri:
            ctrl = dictation(uri)
            ctrl.toggle_recording()  # hotkey down: capture + auto-connect
            ctrl.audio.audio_callback(first, len(first), None, None)
            ctrl.audio.audio_callback(second, len(second), None, None)
            await asyncio.sleep(0.02)  # both chunks buffered while connecting
            ctrl.toggle_recording()  # hotkey again: stop before auth finishes
            release_auth.set()
            await eventually(lambda: clipboard.copy.called)

        assert received == [first_pcm, second_pcm, EOS]
        clipboard.copy.assert_called_once_with("Hello world")
        keyboard_ctl = cast(Any, ctrl.kb)
        keyboard_ctl.pressed.assert_called_once_with(keyboard.Key.ctrl)
        keyboard_ctl.press.assert_called_once_with("v")
        keyboard_ctl.release.assert_called_once_with("v")

    async def test_live_session_streams_in_capture_order(self, dictation, desktop):
        clipboard, _ = desktop
        received: list = []
        blocks = [_pcm(level) for level in (0.1, 0.2, 0.3)]

        handler = _backend_transcribing(received, "Second note.")
        async with backend(handler) as uri:
            ctrl = dictation(uri)
            await ctrl.transport.connect()
            await eventually(lambda: ctrl.transport.is_ready)

            ctrl.toggle_recording()
            for block, _ in blocks:
                ctrl.audio.audio_callback(block, len(block), None, None)
            ctrl.toggle_recording()
            late, _ = _pcm(0.9)
            ctrl.audio.audio_callback(late, len(late), None, None)  # after stop
            await eventually(lambda: clipboard.copy.called)

        assert received == [pcm for _, pcm in blocks] + [EOS]
        clipboard.copy.assert_called_once_with("Second note.")

    async def test_rejected_key_discards_the_recording(self, dictation, desktop):
        clipboard, _ = desktop
        frames_seen: list = []

        async def handler(ws: ServerConnection):
            await ws.recv()
            await ws.send(json.dumps({"event": "error", "error_code": "AUTH_FAILED"}))
            with contextlib.suppress(ConnectionClosed):
                async for message in ws:
                    frames_seen.append(message)

        async with backend(handler) as uri:
            ctrl = dictation(uri)
            ctrl.toggle_recording()
            block, _ = _pcm(0.4)
            ctrl.audio.audio_callback(block, len(block), None, None)
            ctrl.toggle_recording()
            await eventually(
                lambda: ctrl.transport.handshake.state == HandshakeState.FAILED
            )
            await asyncio.sleep(0.05)  # give a buggy pipe time to send anyway

        assert frames_seen == []
        clipboard.copy.assert_not_called()
