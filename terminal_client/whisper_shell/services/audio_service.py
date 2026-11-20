import asyncio
import threading

import numpy as np
import sounddevice as sd
from loguru import logger

from ..services.config_service import cfg

TARGET_RATE = 16000

# One capture session's audio: PCM chunks, terminated by None.
CaptureQueue = asyncio.Queue[bytes | None]


class AudioService:
    """
    Service for capturing audio from the primary input device.
    Strictly outputs 16kHz, Mono, 16-bit PCM.

    Each capture session gets its own queue ending in a None sentinel, so a
    session's consumer knows exactly when its audio is complete and sessions
    never share or steal each other's chunks.
    """

    def __init__(self, loop: asyncio.AbstractEventLoop):
        self.loop = loop
        self.device_rate = TARGET_RATE
        self.stream = None
        self._session: CaptureQueue | None = None
        # Orders "check session + enqueue chunk" (PortAudio thread) against
        # "close session + enqueue sentinel" (event loop), so no chunk can land
        # behind its session's sentinel.
        self._session_lock = threading.Lock()

    @property
    def is_recording(self) -> bool:
        return self._session is not None

    def audio_callback(self, indata, frames, time, status):
        """Callback for sounddevice InputStream (runs on the PortAudio thread)."""
        if status:
            logger.warning(f"Audio Callback Status: {status}")
        if self._session is None:
            return

        if self.device_rate != TARGET_RATE:
            duration = len(indata) / self.device_rate
            new_len = int(duration * TARGET_RATE)
            # Linear interpolation for resampling (fast, decent quality for speech)
            audio = np.interp(
                np.linspace(0, duration, new_len),
                np.linspace(0, duration, len(indata)),
                indata.flatten(),
            )
        else:
            audio = indata.flatten()

        # float32 -> int16 PCM. Clip first: out-of-range samples would wrap
        # around on the integer cast and turn loud speech into distortion.
        pcm_data = (np.clip(audio, -1.0, 1.0) * 32767).astype(np.int16).tobytes()

        with self._session_lock:
            session = self._session
            if session is not None:
                self.loop.call_soon_threadsafe(session.put_nowait, pcm_data)

    def start_stream(self):
        """Starts the hardware audio input stream."""
        if self.stream:
            return

        try:
            device_id = cfg.AUDIO_DEVICE_ID
            info = sd.query_devices(device_id, "input")
            self.device_rate = int(info.get("default_samplerate", TARGET_RATE))

            self.stream = sd.InputStream(
                samplerate=self.device_rate,
                channels=1,
                callback=self.audio_callback,
                device=device_id,
            )
            self.stream.start()
            host_api_name = sd.query_hostapis(info["hostapi"])["name"]
            logger.success(
                f"Audio Stream Active: [{device_id}] {info['name']} | {host_api_name} ({self.device_rate}Hz → {TARGET_RATE}Hz)"
            )
        except Exception as e:
            logger.critical(f"Failed to start hardware audio stream: {e}")
            raise e

    def stop_stream(self):
        """Closes hardware stream."""
        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None
            logger.info("Audio Stream Shutdown.")

    def start_capture(self) -> CaptureQueue:
        """Begin a capture session and return its queue."""
        session: CaptureQueue = asyncio.Queue()
        with self._session_lock:
            self._session = session
        return session

    def stop_capture(self) -> None:
        """End the current session; its queue receives a final None."""
        with self._session_lock:
            session, self._session = self._session, None
            if session is not None:
                self.loop.call_soon_threadsafe(session.put_nowait, None)
