"""
Abstract base class for all ASR engine implementations.

The engine contract decouples the orchestration layer (ConnectionManager,
api_server) from any specific model backend. Engines own their full lifecycle:
loading, transcription, idle-timeout unloading, and graceful shutdown.
"""

from __future__ import annotations

import abc
from dataclasses import dataclass
from typing import List


@dataclass
class SegmentResult:
    """A single time-aligned transcript segment."""

    start: float
    end: float
    text: str


@dataclass
class TranscriptionResult:
    """Canonical output of any ASR engine. All engines must produce this shape."""

    text: str
    segments: List[SegmentResult]
    language: str
    processing_time: float


class BaseEngine(abc.ABC):
    """
    Abstract interface every ASR engine must implement.

    Engines are synchronous — callers are responsible for dispatching via
    asyncio.to_thread(). This keeps engines independently testable without
    an event loop and keeps the async boundary in one place (websocket_handler).

    Lifecycle contract:
      - __init__ triggers an initial load (same as ModelManager behaviour).
      - warmup() is idempotent; safe to call when already loaded.
      - unload() releases locally managed model resources. For an isolated
        sidecar, the process supervisor owns model/VRAM teardown.
      - is_loaded() is used by the hello-packet status field only.
    """

    @abc.abstractmethod
    def transcribe(self, audio_path: str) -> TranscriptionResult:
        """
        Transcribe the WAV file at audio_path.

        The file is always 16kHz / 16-bit / mono PCM, written by
        websocket_handler before this call.

        This method is SYNCHRONOUS. The caller wraps it with asyncio.to_thread.
        Both batch mode (full utterance) and the internal model load-on-demand
        path are handled here — the caller does not manage model state.

        # TODO(streaming): add optional on_segment callback for future
        # per-chunk streaming mode:
        #   def transcribe(self, audio_path: str,
        #                  on_segment=None) -> TranscriptionResult
        # When on_segment is provided, the engine should emit partial results
        # as they are produced rather than waiting for the full utterance.
        """
        ...

    @abc.abstractmethod
    def warmup(self) -> None:
        """
        Ensure the model is resident in memory/VRAM.

        Called in a background thread immediately after client authentication,
        using the client's "thinking time" before they start recording.
        Must be idempotent: safe to call when the model is already loaded.
        """
        ...

    @abc.abstractmethod
    def is_loaded(self) -> bool:
        """
        Returns True if the model is currently resident in memory.

        Used only to populate the 'status' field in the WebSocket hello packet
        ('ready' vs 'idle'). Not used as a guard for transcription calls —
        transcribe() handles load-on-demand internally.
        """
        ...

    @abc.abstractmethod
    def unload(self) -> None:
        """
        Release locally managed model weights and perform VRAM/RAM cleanup.

        Called during server shutdown and by the engine's own idle-timeout
        monitor. After unload(), transcribe() and warmup() must be able to
        restore readiness transparently. Externally supervised engines detach
        here; their process supervisor performs the actual model teardown.
        """
        ...
