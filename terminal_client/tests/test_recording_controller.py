"""
Tests for RecordingController.

Mocks Transport, Audio, and keyboard to isolate orchestration logic.
"""

import asyncio
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from whisper_shell.logic.audio_buffer import AudioBufferManager
from whisper_shell.logic.handshake import HandshakeState, HandshakeStateMachine
from whisper_shell.logic.payload import PayloadBuilder

EOS = PayloadBuilder.build_end_of_stream()


def _as_mock(value: object) -> MagicMock:
    return cast(MagicMock, value)


# ---------------------------------------------------------------------------
# Helpers — build a controller with fully mocked dependencies
# ---------------------------------------------------------------------------


def _make_controller():
    """
    Constructs a RecordingController with mocked Audio, Transport,
    and keyboard so no hardware or network is touched. `transport.is_ready`
    is a plain attribute tests flip to model the connection.
    """
    with (
        patch(
            "whisper_shell.controllers.recording_controller.AudioService"
        ) as MockAudio,
        patch(
            "whisper_shell.controllers.recording_controller.TransportService"
        ) as MockTransport,
        patch("whisper_shell.controllers.recording_controller.keyboard"),
    ):
        mock_transport = MockTransport.return_value
        mock_transport.handshake = HandshakeStateMachine()
        mock_transport.is_ready = False
        mock_transport.send_audio = AsyncMock()
        mock_transport.send_json = AsyncMock()
        mock_transport.ensure_connected = AsyncMock(return_value=True)
        mock_transport.disconnect = AsyncMock()
        mock_transport.add_message_listener = MagicMock()

        mock_audio = MockAudio.return_value
        mock_audio.start_capture = MagicMock(side_effect=lambda: asyncio.Queue())
        mock_audio.stop_capture = MagicMock()
        mock_audio.stop_stream = MagicMock()

        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            # Synchronous tests never schedule work on the loop (AudioService is
            # mocked), and since pytest-asyncio 1.5 no loop outlives an async test.
            loop = MagicMock(spec=asyncio.AbstractEventLoop)
        from whisper_shell.controllers.recording_controller import RecordingController

        return RecordingController(loop)


def _transport(ctrl) -> MagicMock:
    """The mocked transport, typed as a mock so tests can set attributes."""
    return cast(MagicMock, ctrl.transport)


def _capture(*chunks: bytes) -> asyncio.Queue:
    """A finished capture session: chunks followed by the None sentinel."""
    queue: asyncio.Queue = asyncio.Queue()
    for chunk in (*chunks, None):
        queue.put_nowait(chunk)
    return queue


def _record_wire(ctrl) -> list:
    """Capture the order of everything sent over the transport."""
    wire: list = []
    _transport(ctrl).send_audio.side_effect = lambda chunk: wire.append(chunk)
    _transport(ctrl).send_json.side_effect = lambda data: wire.append(data)
    return wire


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------


class TestInit:
    def test_initial_state(self):
        ctrl = _make_controller()
        assert ctrl.is_recording is False

    def test_wires_up_handshake_listener(self):
        ctrl = _make_controller()
        assert len(ctrl.transport.handshake._listeners) >= 1


# ---------------------------------------------------------------------------
# Toggle recording
# ---------------------------------------------------------------------------


class TestToggleRecording:
    @pytest.mark.asyncio
    async def test_toggle_starts_then_stops(self):
        ctrl = _make_controller()

        await ctrl.toggle_recording()
        assert ctrl.is_recording is True
        _as_mock(ctrl.audio.start_capture).assert_called_once()

        await ctrl.toggle_recording()
        assert ctrl.is_recording is False
        _as_mock(ctrl.audio.stop_capture).assert_called_once()
        await ctrl.shutdown()

    @pytest.mark.asyncio
    async def test_double_start_is_noop(self):
        ctrl = _make_controller()
        await ctrl.toggle_recording()
        ctrl._start_recording_session()
        _as_mock(ctrl.audio.start_capture).assert_called_once()
        await ctrl.shutdown()

    def test_stop_when_idle_is_noop(self):
        ctrl = _make_controller()
        ctrl._stop_recording_session()
        _as_mock(ctrl.audio.stop_capture).assert_not_called()

    def test_stop_does_not_send_end_of_stream_directly(self):
        """End-of-stream is sent by the pipe after the tail, never by stop."""
        ctrl = _make_controller()
        ctrl.is_recording = True
        _transport(ctrl).is_ready = True
        ctrl._stop_recording_session()
        _as_mock(ctrl.transport.send_json).assert_not_called()
        _as_mock(ctrl.audio.stop_capture).assert_called_once()


# ---------------------------------------------------------------------------
# Audio pipe & utterance completion
# ---------------------------------------------------------------------------


class TestAudioPipe:
    @pytest.mark.asyncio
    async def test_streams_session_then_ends_it(self):
        ctrl = _make_controller()
        _transport(ctrl).is_ready = True
        wire = _record_wire(ctrl)

        await ctrl._process_audio_pipe(_capture(b"\x01", b"\x02"))

        assert wire == [b"\x01", b"\x02", EOS]

    @pytest.mark.asyncio
    async def test_audio_recorded_while_connecting_is_sent_before_eos(self):
        """Regression: stopping before auth silently dropped the utterance."""
        ctrl = _make_controller()
        wire = _record_wire(ctrl)

        async def authenticate_soon():
            await asyncio.sleep(0.01)
            _transport(ctrl).is_ready = True
            ctrl._on_handshake_state_changed(HandshakeState.AUTHENTICATED)

        asyncio.create_task(authenticate_soon())
        await ctrl._process_audio_pipe(_capture(b"\xaa", b"\xbb"))

        assert wire == [b"\xaa", b"\xbb", EOS]

    @pytest.mark.asyncio
    async def test_buffered_audio_flushes_ahead_of_live_audio(self):
        ctrl = _make_controller()
        wire = _record_wire(ctrl)
        capture: asyncio.Queue = asyncio.Queue()

        async def feed():
            capture.put_nowait(b"early")  # buffered: not ready yet
            await asyncio.sleep(0.01)
            _transport(ctrl).is_ready = True
            capture.put_nowait(b"live")
            capture.put_nowait(None)

        asyncio.create_task(feed())
        await ctrl._process_audio_pipe(capture)

        assert wire == [b"early", b"live", EOS]

    @pytest.mark.asyncio
    async def test_discards_when_connection_never_settles(self):
        ctrl = _make_controller()
        with patch(
            "whisper_shell.controllers.recording_controller.HANDSHAKE_WAIT_S", 0.01
        ):
            await ctrl._process_audio_pipe(_capture(b"\x01"))

        _as_mock(ctrl.transport.send_audio).assert_not_called()
        _as_mock(ctrl.transport.send_json).assert_not_called()

    @pytest.mark.asyncio
    async def test_discards_immediately_when_handshake_failed(self):
        ctrl = _make_controller()
        ctrl._on_handshake_state_changed(HandshakeState.FAILED)
        buffer = AudioBufferManager()
        buffer.add(b"\x01")

        await asyncio.wait_for(ctrl._finish_utterance(buffer), timeout=1)

        _as_mock(ctrl.transport.send_json).assert_not_called()


# ---------------------------------------------------------------------------
# Handshake state change callbacks
# ---------------------------------------------------------------------------


class TestHandshakeCallbacks:
    @pytest.mark.parametrize(
        "state",
        [
            HandshakeState.AUTHENTICATED,
            HandshakeState.FAILED,
            HandshakeState.BANNED,
            HandshakeState.VERSION_OUTDATED,
        ],
    )
    def test_settled_states_release_waiters(self, state):
        ctrl = _make_controller()
        ctrl._on_handshake_state_changed(state)
        assert ctrl._handshake_settled.is_set()

    @pytest.mark.parametrize(
        "state", [HandshakeState.LOCKED, HandshakeState.AUTHENTICATING]
    )
    def test_pending_states_block_waiters(self, state):
        ctrl = _make_controller()
        ctrl._handshake_settled.set()
        ctrl._on_handshake_state_changed(state)
        assert not ctrl._handshake_settled.is_set()

    def test_auth_failed_shows_key_guidance(self):
        ctrl = _make_controller()
        ctrl.transport.handshake.set_error_context("AUTH_FAILED", "Invalid token")
        ctrl._on_handshake_state_changed(HandshakeState.FAILED)

    def test_max_connections_shows_capacity_warning(self):
        ctrl = _make_controller()
        ctrl.transport.handshake.set_error_context(
            "MAX_CONNECTIONS", "10/10 slots full"
        )
        ctrl._on_handshake_state_changed(HandshakeState.FAILED)


# ---------------------------------------------------------------------------
# Server message handling
# ---------------------------------------------------------------------------


class TestServerMessageHandling:
    @pytest.mark.asyncio
    async def test_transcription_triggers_paste(self):
        ctrl = _make_controller()
        with patch.object(ctrl, "_paste_text") as mock_paste:
            await ctrl._handle_server_message(
                {"event": "transcription", "text": "hello world"}
            )
            mock_paste.assert_called_once_with("hello world")

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        "error_code",
        ["NO_AUDIO", "TRANSCRIPTION_FAILED", "BUFFER_EXCEEDED", "SERVER_ERROR", ""],
    )
    async def test_operational_errors_are_reported(self, error_code):
        ctrl = _make_controller()
        await ctrl._handle_server_message(
            {"event": "error", "error_code": error_code, "message": "why"}
        )

    @pytest.mark.asyncio
    async def test_status_event(self):
        ctrl = _make_controller()
        await ctrl._handle_server_message(
            {"event": "status", "message": "Model loaded"}
        )


# ---------------------------------------------------------------------------
# Paste text
# ---------------------------------------------------------------------------


class TestPasteText:
    def test_empty_text_is_noop(self):
        ctrl = _make_controller()
        with patch(
            "whisper_shell.controllers.recording_controller.pyperclip"
        ) as mock_clip:
            ctrl._paste_text("")
            mock_clip.copy.assert_not_called()

    def test_whitespace_only_is_noop(self):
        ctrl = _make_controller()
        with patch(
            "whisper_shell.controllers.recording_controller.pyperclip"
        ) as mock_clip:
            ctrl._paste_text("   ")
            mock_clip.copy.assert_not_called()

    def test_valid_text_copies_to_clipboard(self):
        ctrl = _make_controller()
        with patch(
            "whisper_shell.controllers.recording_controller.pyperclip"
        ) as mock_clip:
            ctrl._paste_text("hello world")
            mock_clip.copy.assert_called_once_with("hello world")


# ---------------------------------------------------------------------------
# Shutdown
# ---------------------------------------------------------------------------


class TestShutdown:
    @pytest.mark.asyncio
    async def test_shutdown_disconnects_and_stops_audio(self):
        ctrl = _make_controller()
        await ctrl.shutdown()
        _as_mock(ctrl.transport.disconnect).assert_called_once_with(
            reason="App shutdown"
        )
        _as_mock(ctrl.audio.stop_stream).assert_called_once()
