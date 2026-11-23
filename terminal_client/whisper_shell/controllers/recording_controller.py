import asyncio

import pyperclip
from colorama import Fore, Style
from loguru import logger
from pynput import keyboard

from ..logic.audio_buffer import AudioBufferManager
from ..logic.handshake import HandshakeState
from ..logic.messages import ServerMessage
from ..logic.payload import PayloadBuilder
from ..logic.sanitizer import Sanitizer
from ..services.audio_service import AudioService, CaptureQueue
from ..services.config_service import cfg
from ..services.transport_service import TransportService

# Upper bound for finishing an utterance recorded while still connecting. The
# handshake itself times out at 15 s; this also covers the socket connect.
HANDSHAKE_WAIT_S = 20.0

# Handshake states after which waiting cannot change the outcome.
_SETTLED_STATES = frozenset(
    {
        HandshakeState.AUTHENTICATED,
        HandshakeState.FAILED,
        HandshakeState.BANNED,
        HandshakeState.VERSION_OUTDATED,
    }
)

_OPERATIONAL_ERROR_MESSAGES = {
    "NO_AUDIO": "No audio detected",
    "TRANSCRIPTION_FAILED": "Transcription failed",
    "BUFFER_EXCEEDED": "Audio buffer exceeded",
    "SERVER_ERROR": "Server error",
}


class RecordingController:
    """
    Orchestrates the recording lifecycle.
    Bridges Transport, Audio, and UI logic (paste).
    """

    def __init__(self, loop: asyncio.AbstractEventLoop):
        self.loop = loop

        # Services
        self.audio = AudioService(loop)
        self.transport = TransportService()
        self.kb = keyboard.Controller()

        # State
        self.is_recording = False
        self._handshake_settled = asyncio.Event()
        self._background_tasks: set[asyncio.Task[object]] = set()

        # Wire up transport listeners
        self.transport.add_message_listener(self._handle_server_message)
        self.transport.handshake.add_listener(self._on_handshake_state_changed)

    def _track_task(self, task: asyncio.Task[object]) -> None:
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)

    def toggle_recording(self) -> None:
        """Main entry point triggered by Hotkey.

        Runs on the event loop's thread: the hotkey thread schedules it there
        (DictationClient._on_hotkey), because the sessions it starts and stops
        create loop tasks.
        """
        if not self.is_recording:
            self._start_recording_session()
        else:
            self._stop_recording_session()

    def _start_recording_session(self):
        if self.is_recording:
            return

        self.is_recording = True
        logger.info(f"{Fore.CYAN}Recording...{Style.RESET_ALL}")

        # 1. Start capture instantly (zero-latency); the session owns its queue.
        capture = self.audio.start_capture()

        # 2. Ensure Transport is connected in background (Auto-Wake)
        self._track_task(asyncio.create_task(self.transport.ensure_connected()))

        # 3. Stream this session, then finish it in order
        self._track_task(asyncio.create_task(self._process_audio_pipe(capture)))

    def _stop_recording_session(self):
        if not self.is_recording:
            return

        self.is_recording = False
        # Ends the session's queue with a sentinel; the pipe flushes the
        # remaining audio and then sends end-of-stream, in that order.
        self.audio.stop_capture()
        logger.info(f"{Fore.CYAN}Stopped. Processing...{Style.RESET_ALL}")

    async def _process_audio_pipe(self, capture: CaptureQueue) -> None:
        """Streams one session's audio, buffering while the connection is not ready."""
        buffer = AudioBufferManager()
        try:
            while (chunk := await capture.get()) is not None:
                if self.transport.is_ready:
                    await buffer.flush(self.transport.send_audio)
                    await self.transport.send_audio(chunk)
                else:
                    buffer.add(chunk)
            await self._finish_utterance(buffer)
        except Exception as e:
            logger.error(f"Audio pipe error: {e}")

    async def _finish_utterance(self, buffer: AudioBufferManager) -> None:
        """Send any buffered tail, then end-of-stream — never the reverse."""
        if not self.transport.is_ready:
            try:
                await asyncio.wait_for(
                    self._handshake_settled.wait(), timeout=HANDSHAKE_WAIT_S
                )
            except TimeoutError:
                pass
        if not self.transport.is_ready:
            if not buffer.is_empty:
                logger.warning(
                    f"Not connected; discarded {len(buffer)} chunks of recorded audio."
                )
            return

        await buffer.flush(self.transport.send_audio)
        await self.transport.send_json(PayloadBuilder.build_end_of_stream())

    def _on_handshake_state_changed(self, state: HandshakeState):
        """Tracks handshake progress and reports session-ending errors once."""
        if state in _SETTLED_STATES:
            self._handshake_settled.set()
        else:
            self._handshake_settled.clear()

        handshake = self.transport.handshake
        message = handshake.last_message
        if state == HandshakeState.AUTHENTICATED:
            logger.debug("Handshake authenticated; buffered audio will stream.")
        elif state == HandshakeState.FAILED:
            error_code = handshake.last_error_code
            if error_code == "AUTH_FAILED":
                logger.error(
                    f"Authentication failed: {message}. The stored API key was "
                    "removed; you will be prompted for a new one on the next recording."
                )
            elif error_code == "MAX_CONNECTIONS":
                logger.warning(f"Server at capacity: {message}. Retrying shortly.")
            else:
                logger.error(f"Handshake failed: {message or 'Unknown error'}")
        elif state == HandshakeState.BANNED:
            logger.error(f"{Fore.RED}Banned: {message or 'IP banned'}{Style.RESET_ALL}")
        elif state == HandshakeState.VERSION_OUTDATED:
            logger.error(
                f"{Fore.RED}{message or 'Client version outdated'}. "
                f"Please update your client.{Style.RESET_ALL}"
            )

    async def _handle_server_message(self, msg: ServerMessage) -> None:
        """Processes transcription results and operational server errors.

        Async because TransportService awaits every message listener.
        """
        event = msg.get("event")

        if "text" in msg:
            self._paste_text(msg["text"])
        elif event == "error":
            error_code = msg.get("error_code", "")
            message = msg.get("message", "Unknown error")
            label = _OPERATIONAL_ERROR_MESSAGES.get(error_code)
            if error_code == "NO_AUDIO":
                logger.info(f"{label}: {message}")
            elif label is not None:
                logger.error(f"{label}: {message}")
            else:
                logger.error(f"Server error ({error_code or 'unknown'}): {message}")
        elif event == "status":
            logger.info(f"Server Status: {msg.get('message')}")

    def _paste_text(self, text: str) -> None:
        safe_text = Sanitizer.sanitize(text)
        if not safe_text:
            return

        if cfg.args.incognito:
            logger.log("GHOST", f"Result: {safe_text}")
        else:
            logger.success(f"Result: {safe_text}")

        pyperclip.copy(safe_text)
        with self.kb.pressed(keyboard.Key.ctrl):
            self.kb.press("v")
            self.kb.release("v")

    async def shutdown(self):
        for task in self._background_tasks:
            task.cancel()
        self._background_tasks.clear()
        await self.transport.disconnect(reason="App shutdown")
        self.audio.stop_stream()
