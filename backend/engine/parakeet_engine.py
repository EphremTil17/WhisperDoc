"""
ParakeetEngine: NVIDIA NeMo backend using parakeet-tdt-0.6b-v2.

English-only TDT (Token and Duration Transducer) model.
NeMo is imported lazily inside this module — the Whisper service image
does not need NeMo installed; deferred import in engine_factory.py ensures
this module is never imported in the Whisper container.

Lifecycle mirrors WhisperEngine: __init__ triggers an initial load so the
first transcribe() call is not penalised by model download/init latency.
"""
import contextlib
import gc
import logging
import os
import sys
import threading
import time

from engine.base_engine import BaseEngine, TranscriptionResult, SegmentResult
from logging_config import log, SILENCED_PREFIXES


@contextlib.contextmanager
def _suppress_nemo_noise():
    """Silence all NeMo output by redirecting stdout AND stderr to /dev/null.

    NeMo's logging is exceptionally aggressive: a custom singleton
    (nemo.utils.logging) attaches StreamHandlers that write [NeMo I/W/E]
    lines to stdout, and it re-attaches them on every transcribe() call.
    Python-level patching (setLevel, handler clearing) cannot keep up.

    This context manager redirects both stdout and stderr at the OS
    file-descriptor level — the standard pattern for silencing noisy
    C/Fortran/CUDA libraries.  The redirect is process-wide, so callers
    must ensure no other threads need stdout/stderr during the block:

      - _load_model() runs at startup (single-threaded)
      - transcribe() runs inside asyncio.to_thread (event loop yields)
      - Our own loguru lines are emitted OUTSIDE the `with` block
    """
    stdout_fd = sys.stdout.fileno()
    stderr_fd = sys.stderr.fileno()
    saved_stdout = os.dup(stdout_fd)
    saved_stderr = os.dup(stderr_fd)
    try:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, stdout_fd)
        os.dup2(devnull, stderr_fd)
        os.close(devnull)
        yield
    finally:
        os.dup2(saved_stdout, stdout_fd)
        os.dup2(saved_stderr, stderr_fd)
        os.close(saved_stdout)
        os.close(saved_stderr)


class ParakeetEngine(BaseEngine):
    """
    ASR engine backed by NVIDIA NeMo parakeet-tdt-0.6b-v2.

    Parakeet is English-only. Full-utterance (batch) mode is used — the
    model receives the entire audio file and returns a single Hypothesis.
    Segment timestamps are extracted from hyp.timestep["segment"] when
    available; if the model does not return timestamps the full utterance
    is represented as one SegmentResult with start=0, end=0.
    """

    def __init__(self, model_name: str = "nvidia/parakeet-tdt-0.6b-v2", device: str = "cuda"):
        self._model_name = model_name
        self._device = device
        self._model = None
        self._lock = threading.Lock()
        log.info(f"ParakeetEngine: initialising model={model_name}, device={device}")
        self._load_model()

    def _load_model(self) -> None:
        with self._lock:
            if self._model is not None:
                return
            log.info(f"ParakeetEngine: loading {self._model_name} into GPU memory, please wait...")
            try:
                with _suppress_nemo_noise():
                    import nemo.collections.asr as nemo_asr  # type: ignore[import-untyped]
                    start = time.time()
                    model = nemo_asr.models.ASRModel.from_pretrained(self._model_name)
                    model = model.to(self._device) if self._device != "cuda" else model.cuda()
                    model.eval()
                self._model = model
                log.success(f"ParakeetEngine: model loaded in {time.time() - start:.2f}s")
            except Exception as e:
                log.error(f"ParakeetEngine: model load failed: {e}")
                raise

    def transcribe(self, audio_path: str) -> TranscriptionResult:
        """
        Transcribe a 16kHz/16-bit/mono WAV file using NeMo Parakeet TDT.

        NeMo's transcribe() accepts a list of file paths and returns a list
        of Hypothesis objects when timestamps=True, or a list of strings when
        timestamps=False.

        Segment timestamps are extracted from hyp.timestep["segment"]:
          [{"start": float, "end": float, "segment": str}, ...]

        This method is SYNCHRONOUS. The caller wraps it with asyncio.to_thread.
        """
        if self._model is None:
            self._load_model()

        start = time.time()

        # Lock serialises concurrent transcriptions.  This is required for two
        # reasons: (1) NeMo's model.transcribe() is not thread-safe on a single
        # model instance, and (2) _suppress_nemo_noise() redirects process-wide
        # file descriptors — overlapping contexts would restore them out of order.
        with self._lock, _suppress_nemo_noise():
            try:
                hypotheses = self._model.transcribe(
                    [audio_path], timestamps=True, verbose=False,
                )
            except Exception:
                # Some NeMo builds return strings when timestamps are unsupported
                hypotheses = self._model.transcribe([audio_path], verbose=False)

        # NeMo returns list[list[Hypothesis]] when timestamps=True,
        # or list[str] when timestamps=False.  Unwrap both layers.
        hyp = hypotheses[0]
        if isinstance(hyp, list):
            hyp = hyp[0]
        processing_time = time.time() - start

        # Normalise to canonical output shape
        full_text = hyp.text if hasattr(hyp, "text") else str(hyp)

        segments: list[SegmentResult] = []
        # NeMo Hypothesis stores timestamps in .timestep (not .timestamp)
        timestep = getattr(hyp, "timestep", None)
        if timestep and isinstance(timestep, dict) and "segment" in timestep:
            for seg in timestep["segment"]:
                segments.append(SegmentResult(
                    start=float(seg.get("start", 0.0)),
                    end=float(seg.get("end", 0.0)),
                    text=str(seg.get("segment", "")),
                ))
        else:
            # Fallback: single segment covering the full utterance
            segments = [SegmentResult(start=0.0, end=0.0, text=full_text)]

        return TranscriptionResult(
            text=full_text,
            segments=segments,
            language="en",  # Parakeet is English-only
            processing_time=processing_time,
        )

    def warmup(self) -> None:
        """Ensure model is resident in VRAM; idempotent."""
        if self._model is None:
            self._load_model()

    def is_loaded(self) -> bool:
        """True when the NeMo model is resident in memory."""
        return self._model is not None

    def unload(self) -> None:
        """Release model from VRAM and reclaim memory."""
        with self._lock:
            if self._model is None:
                return
            log.info("ParakeetEngine: unloading model...")
            del self._model
            self._model = None
            gc.collect()
            try:
                import torch  # type: ignore[import-untyped]  # Parakeet image only
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            except ImportError:
                pass
            log.success("ParakeetEngine: model unloaded.")
