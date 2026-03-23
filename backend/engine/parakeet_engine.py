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

PARAKEET_SUPPRESS_STDIO = os.getenv("PARAKEET_SUPPRESS_STDIO", "true").lower() == "true"


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
    if not PARAKEET_SUPPRESS_STDIO:
        yield
        return

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


def _mute_nemo_loggers() -> None:
    """Best-effort Python-level muting of NeMo's noisy loggers.

    NeMo's singleton logger (nemo.utils.logging) attaches StreamHandlers to
    stdout.  We redirect them to a NullHandler so they don't pollute output.
    NeMo may re-attach handlers on each transcribe() call, but with propagate
    disabled and the root-level _ThirdPartyNoiseFilter in place, most noise
    is suppressed without touching file descriptors.
    """
    null = logging.NullHandler()
    for name in ("nemo", "nemo_logger", "nemo.utils.logging", "lhotse", "lhotse.cut"):
        lg = logging.getLogger(name)
        lg.handlers = [null]
        lg.propagate = False


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
        log.info(f"ParakeetEngine: fd stdio suppression {'enabled' if PARAKEET_SUPPRESS_STDIO else 'disabled'}")
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
                    model = model.half() #Fp16 for faster inference; Parakeet supports it and it reduces VRAM usage by ~50%
                    model.eval()
                self._model = model
                log.success(f"ParakeetEngine: model loaded in {time.time() - start:.2f}s")

                # Mute NeMo's stdout StreamHandlers at the Python level.
                # NeMo re-attaches these on every transcribe(), but clearing
                # the nemo_logger's handlers + setting propagate=False limits
                # most noise.  This is best-effort — some C-level stdout lines
                # will still appear, but that's preferable to the memory
                # corruption caused by fd-level suppression during inference.
                _mute_nemo_loggers()

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

        # Lock serialises concurrent transcriptions — NeMo's model.transcribe()
        # is not thread-safe on a single model instance.
        #
        # NOTE: _suppress_nemo_noise() is intentionally NOT used here.
        # After model.transcribe() runs, the b" " bytes object used in
        # uvicorn's h11 WebSocket upgrade path is observed to be corrupted
        # (0x20 → 0x00).  The exact cause is unconfirmed, but the corruption
        # correlates with NeMo inference and is absent with the Whisper engine.
        # Removing fd-level suppression from this path was tested and did NOT
        # prevent the corruption — the fix is in api_server.py (h11 patch).
        # We still remove it here as good hygiene: process-wide os.dup2()
        # during concurrent threaded inference is hazardous regardless.
        # NeMo's stdout noise during transcription is cosmetic;
        # _ThirdPartyNoiseFilter in logging_config.py catches the Python-routed
        # portion, and any remaining C-level stdout lines are harmless.
        with self._lock:
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
