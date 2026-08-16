"""Parakeet sidecar adapter powered by parakeet.cpp.

The native ggml/CUDA runtime lives in a separate container. This adapter keeps
native model code outside WhisperDoc's Python process while preserving the
synchronous :class:`BaseEngine` contract used by the WebSocket orchestration
layer.
"""

from __future__ import annotations

import io
import threading
import time
import wave
from pathlib import Path
from urllib.parse import urlparse

import requests

from engine.base_engine import BaseEngine, SegmentResult, TranscriptionResult
from logging_config import log


class ParakeetEngine(BaseEngine):
    """ASR engine backed by the isolated ``parakeet-server`` process."""

    def __init__(
        self,
        base_url: str,
        *,
        connect_timeout_seconds: float = 2.0,
        request_timeout_seconds: float = 30.0,
        startup_timeout_seconds: float = 120.0,
        warmup_seconds: float = 10.0,
        max_audio_seconds: float = 30.0,
    ) -> None:
        self._base_url = self._validate_base_url(base_url)
        self._connect_timeout = self._positive(
            "connect_timeout_seconds", connect_timeout_seconds
        )
        self._request_timeout = self._positive(
            "request_timeout_seconds", request_timeout_seconds
        )
        self._startup_timeout = self._positive(
            "startup_timeout_seconds", startup_timeout_seconds
        )
        self._warmup_seconds = self._positive("warmup_seconds", warmup_seconds)
        self._max_audio_seconds = self._positive("max_audio_seconds", max_audio_seconds)
        # RLock permits the warmup request's error path to mark readiness false
        # without deadlocking while warmup() already owns the state lock.
        self._state_lock = threading.RLock()
        self._ready = False

        log.info(
            "ParakeetEngine: connecting to isolated sidecar at {}",
            self._base_url,
        )
        self.warmup()

    @staticmethod
    def _positive(name: str, value: float) -> float:
        parsed = float(value)
        if parsed <= 0:
            raise ValueError(f"{name} must be greater than zero.")
        return parsed

    @staticmethod
    def _validate_base_url(value: str) -> str:
        normalized = value.strip().rstrip("/")
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("PARAKEET_BASE_URL must be an absolute HTTP(S) URL.")
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError(
                "PARAKEET_BASE_URL cannot contain credentials, a query, or a fragment."
            )
        return normalized

    @property
    def _health_url(self) -> str:
        return f"{self._base_url}/health"

    @property
    def _transcription_url(self) -> str:
        return f"{self._base_url}/v1/audio/transcriptions"

    @property
    def _timeouts(self) -> tuple[float, float]:
        return self._connect_timeout, self._request_timeout

    @staticmethod
    def _connection_headers() -> dict[str, str]:
        # cpp-httplib's keep-alive path added ~40 ms/request on the benchmark
        # host. A fresh loopback connection measured ~1 ms and was consistently
        # faster, so make the intended transport behavior explicit.
        return {"Connection": "close"}

    def _wait_until_healthy(self) -> None:
        deadline = time.monotonic() + self._startup_timeout
        last_error: Exception | None = None
        while True:
            try:
                response = requests.get(
                    self._health_url,
                    headers=self._connection_headers(),
                    timeout=self._timeouts,
                )
                response.raise_for_status()
                payload = response.json()
                if payload == {"status": "ok"}:
                    return
                last_error = RuntimeError("sidecar returned an invalid health payload")
            except (requests.RequestException, ValueError) as error:
                last_error = error

            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "Parakeet.cpp sidecar did not become healthy before the startup timeout."
                ) from last_error
            time.sleep(0.25)

    @staticmethod
    def _silent_wav(duration_seconds: float) -> bytes:
        frame_count = max(1, int(16000 * duration_seconds))
        output = io.BytesIO()
        with wave.open(output, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(16000)
            wav_file.writeframes(b"\x00\x00" * frame_count)
        return output.getvalue()

    def _post_wav(self, wav_bytes: bytes, filename: str) -> str:
        try:
            response = requests.post(
                self._transcription_url,
                files={"file": (filename, wav_bytes, "audio/wav")},
                data={"response_format": "json"},
                headers=self._connection_headers(),
                timeout=self._timeouts,
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError) as error:
            with self._state_lock:
                self._ready = False
            raise RuntimeError("Parakeet.cpp transcription request failed.") from error

        text = payload.get("text") if isinstance(payload, dict) else None
        if not isinstance(text, str):
            with self._state_lock:
                self._ready = False
            raise RuntimeError(
                "Parakeet.cpp returned an invalid transcription payload."
            )
        return text.strip()

    @staticmethod
    def _wav_duration(path: Path) -> float:
        try:
            with wave.open(str(path), "rb") as wav_file:
                if (
                    wav_file.getnchannels() != 1
                    or wav_file.getsampwidth() != 2
                    or wav_file.getframerate() != 16000
                ):
                    raise ValueError(
                        "Parakeet.cpp input must be 16-kHz, 16-bit, mono PCM WAV."
                    )
                return wav_file.getnframes() / wav_file.getframerate()
        except (EOFError, wave.Error) as error:
            raise ValueError("Parakeet.cpp input is not a valid WAV file.") from error

    def transcribe(self, audio_path: str) -> TranscriptionResult:
        if not self.is_loaded():
            self.warmup()

        path = Path(audio_path)
        duration = self._wav_duration(path)
        if duration > self._max_audio_seconds:
            raise ValueError(
                f"Parakeet.cpp input is {duration:.1f}s; the configured safe maximum "
                f"is {self._max_audio_seconds:.1f}s. Split long recordings at silence "
                "boundaries before transcription."
            )

        started = time.perf_counter()
        text = self._post_wav(path.read_bytes(), path.name)
        processing_time = time.perf_counter() - started
        return TranscriptionResult(
            text=text,
            segments=[SegmentResult(start=0.0, end=duration, text=text)],
            language="en",
            processing_time=processing_time,
        )

    def warmup(self) -> None:
        with self._state_lock:
            if self._ready:
                return
            self._wait_until_healthy()
            # A health check proves the process is listening but does not prime
            # ggml's lazy CUDA graph setup. A representative 10-second silent
            # decode removed the first real-request spike on the RTX 3060 Ti.
            self._post_wav(
                self._silent_wav(self._warmup_seconds), "whisperdoc-warmup.wav"
            )
            self._ready = True
        log.success("ParakeetEngine: sidecar healthy and CUDA path warmed")

    def is_loaded(self) -> bool:
        with self._state_lock:
            return self._ready

    def unload(self) -> None:
        # Docker Compose owns the native process and releases its VRAM when the
        # sidecar stops. WhisperDoc must not mount the Docker socket merely to
        # make BaseEngine.unload() control another container.
        with self._state_lock:
            self._ready = False
        log.info("ParakeetEngine: detached from externally managed sidecar")
