"""Parakeet sidecar adapter powered by parakeet.cpp.

The native ggml/CUDA runtime lives in a separate container. This adapter keeps
native model code outside WhisperDoc's Python process while preserving the
synchronous :class:`BaseEngine` contract used by the WebSocket orchestration
layer.
"""

from __future__ import annotations

import io
import math
import threading
import time
import wave
from dataclasses import dataclass
from numbers import Real
from pathlib import Path
from urllib.parse import urlparse

import requests

from engine.base_engine import BaseEngine, SegmentResult, TranscriptionResult
from engine.silence_chunker import PCM_SAMPLE_WIDTH_BYTES, plan_silence_aware_chunks
from logging_config import log

_SAMPLE_RATE = 16000
_CHUNK_OVERLAP_SECONDS = 0.8


@dataclass(frozen=True, slots=True)
class _TimedWord:
    text: str
    start: float
    end: float


@dataclass(frozen=True, slots=True)
class _SidecarTranscript:
    text: str
    words: tuple[_TimedWord, ...]


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
        frame_count = max(1, int(_SAMPLE_RATE * duration_seconds))
        return ParakeetEngine._pcm_wav(
            b"\x00\x00" * frame_count,
        )

    @staticmethod
    def _pcm_wav(pcm: bytes) -> bytes:
        output = io.BytesIO()
        with wave.open(output, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(PCM_SAMPLE_WIDTH_BYTES)
            wav_file.setframerate(_SAMPLE_RATE)
            wav_file.writeframes(pcm)
        return output.getvalue()

    @staticmethod
    def _parse_transcript_payload(
        payload: object, *, require_words: bool
    ) -> _SidecarTranscript:
        if not isinstance(payload, dict):
            raise ValueError("payload must be a JSON object")

        text = payload.get("text")
        if not isinstance(text, str):
            raise ValueError("payload text must be a string")

        if not require_words:
            return _SidecarTranscript(text=text.strip(), words=())

        raw_words = payload.get("words")
        if not isinstance(raw_words, list):
            raise ValueError("verbose payload words must be a list")

        words: list[_TimedWord] = []
        for raw_word in raw_words:
            if not isinstance(raw_word, dict):
                raise ValueError("word entries must be JSON objects")
            word = raw_word.get("word", raw_word.get("w"))
            start = raw_word.get("start")
            end = raw_word.get("end")
            if (
                not isinstance(word, str)
                or not word.strip()
                or not isinstance(start, Real)
                or isinstance(start, bool)
                or not isinstance(end, Real)
                or isinstance(end, bool)
            ):
                raise ValueError(
                    "word entries must contain text and numeric timestamps"
                )

            parsed_start = float(start)
            parsed_end = float(end)
            if (
                not math.isfinite(parsed_start)
                or not math.isfinite(parsed_end)
                or parsed_start < 0
                or parsed_end < parsed_start
            ):
                raise ValueError("word timestamps must be finite and ordered")
            words.append(
                _TimedWord(
                    text=word.strip(),
                    start=parsed_start,
                    end=parsed_end,
                )
            )

        if text.strip() and not words:
            raise ValueError(
                "non-empty verbose transcript must contain word timestamps"
            )
        return _SidecarTranscript(text=text.strip(), words=tuple(words))

    def _post_wav(
        self,
        wav_bytes: bytes,
        filename: str,
        *,
        require_words: bool = False,
    ) -> _SidecarTranscript:
        form_data = {"response_format": "json"}
        if require_words:
            form_data = {
                "response_format": "verbose_json",
                "timestamp_granularities[]": "word",
            }

        try:
            response = requests.post(
                self._transcription_url,
                files={"file": (filename, wav_bytes, "audio/wav")},
                data=form_data,
                headers=self._connection_headers(),
                timeout=self._timeouts,
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError) as error:
            with self._state_lock:
                self._ready = False
            raise RuntimeError("Parakeet.cpp transcription request failed.") from error

        try:
            return self._parse_transcript_payload(payload, require_words=require_words)
        except ValueError as error:
            with self._state_lock:
                self._ready = False
            raise RuntimeError(
                "Parakeet.cpp returned an invalid transcription payload."
            ) from error

    @staticmethod
    def _read_wav(path: Path) -> tuple[bytes, float]:
        try:
            with wave.open(str(path), "rb") as wav_file:
                if (
                    wav_file.getnchannels() != 1
                    or wav_file.getsampwidth() != PCM_SAMPLE_WIDTH_BYTES
                    or wav_file.getframerate() != _SAMPLE_RATE
                    or wav_file.getcomptype() != "NONE"
                ):
                    raise ValueError(
                        "Parakeet.cpp input must be 16-kHz, 16-bit, mono PCM WAV."
                    )
                frame_count = wav_file.getnframes()
                pcm = wav_file.readframes(frame_count)
                return pcm, frame_count / wav_file.getframerate()
        except (EOFError, wave.Error) as error:
            raise ValueError("Parakeet.cpp input is not a valid WAV file.") from error

    def transcribe(self, audio_path: str) -> TranscriptionResult:
        if not self.is_loaded():
            self.warmup()

        path = Path(audio_path)
        pcm, duration = self._read_wav(path)
        windows = plan_silence_aware_chunks(
            pcm,
            sample_rate=_SAMPLE_RATE,
            max_audio_seconds=self._max_audio_seconds,
            overlap_seconds=min(
                _CHUNK_OVERLAP_SECONDS,
                self._max_audio_seconds / 10,
            ),
        )
        is_chunked = len(windows) > 1
        if is_chunked:
            silence_cuts = sum(window.cut_at_silence for window in windows[:-1])
            log.info(
                "ParakeetEngine: split {:.1f}s input into {} bounded chunks "
                "({} silence-aware cuts)",
                duration,
                len(windows),
                silence_cuts,
            )

        started = time.perf_counter()
        segment_results: list[SegmentResult] = []
        transcript_parts: list[str] = []
        for index, window in enumerate(windows, start=1):
            chunk_pcm = pcm[
                window.audio_start_sample
                * PCM_SAMPLE_WIDTH_BYTES : window.audio_end_sample
                * PCM_SAMPLE_WIDTH_BYTES
            ]
            transcript = self._post_wav(
                self._pcm_wav(chunk_pcm),
                f"whisperdoc-chunk-{index:03d}.wav",
                require_words=is_chunked,
            )

            if not is_chunked:
                transcript_parts.append(transcript.text)
                segment_results.append(
                    SegmentResult(start=0.0, end=duration, text=transcript.text)
                )
                continue

            audio_start = window.audio_start_sample / _SAMPLE_RATE
            keep_start = window.keep_start_sample / _SAMPLE_RATE
            keep_end = window.keep_end_sample / _SAMPLE_RATE
            is_final_window = (
                window.keep_end_sample == len(pcm) // PCM_SAMPLE_WIDTH_BYTES
            )
            owned_words: list[tuple[_TimedWord, float, float]] = []
            for word in transcript.words:
                global_start = audio_start + word.start
                global_end = audio_start + word.end
                midpoint = (global_start + global_end) / 2
                if midpoint < keep_start:
                    continue
                if not is_final_window and midpoint >= keep_end:
                    continue
                owned_words.append((word, global_start, global_end))

            if not owned_words:
                continue
            chunk_text = " ".join(word.text for word, _, _ in owned_words)
            transcript_parts.append(chunk_text)
            segment_results.append(
                SegmentResult(
                    start=max(keep_start, owned_words[0][1]),
                    end=min(keep_end, owned_words[-1][2]),
                    text=chunk_text,
                )
            )

        processing_time = time.perf_counter() - started
        text = " ".join(transcript_parts)
        return TranscriptionResult(
            text=text,
            segments=segment_results,
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
