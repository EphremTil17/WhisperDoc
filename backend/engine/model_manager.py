import ctypes
import gc
import importlib
import os
import platform
import threading
import time
from typing import Any, cast

from logging_config import log

# Load config from env
MODEL_TIMEOUT_SECONDS = int(os.getenv("MODEL_TIMEOUT_SECONDS", "1800"))
_MONITOR_INTERVAL_SECONDS = 60
WhisperModel: Any | None = None


def _load_whisper_model_class() -> type[Any]:
    """Import faster-whisper lazily to scope dependency errors to actual usage."""
    global WhisperModel

    if WhisperModel is not None:
        return cast(type[Any], WhisperModel)

    module = importlib.import_module("faster_whisper")
    WhisperModel = getattr(module, "WhisperModel")
    return cast(type[Any], WhisperModel)


class ModelManager:
    """Manages the lifecycle of the WhisperModel for dynamic GPU loading."""

    def __init__(self, model_name, device, compute_type):
        self.model_name = model_name
        self.device = device
        self.compute_type = compute_type
        self.model: Any | None = None
        self.last_used = time.time()
        self._lock = threading.Lock()

        # Initial load
        self.load_model()

        # Idle unloading runs on a daemon thread rather than an event-loop task:
        # unload_model() does gc, CUDA teardown and malloc_trim, which would
        # stall every connection if run on the loop.
        threading.Thread(
            target=self._monitor_usage, name="whisper-idle-monitor", daemon=True
        ).start()

    def load_model(self):
        with self._lock:
            if self.model:
                return
            log.info(f"Loading Whisper model ({self.model_name}) into {self.device}...")
            try:
                start = time.time()
                whisper_model_class = _load_whisper_model_class()
                try:
                    # Prefer cache-only load to skip the HuggingFace revision check
                    self.model = whisper_model_class(
                        self.model_name,
                        device=self.device,
                        compute_type=self.compute_type,
                        download_root="/app/model-cache",
                        local_files_only=True,
                    )
                except (OSError, ValueError):
                    # Cache miss or corrupt local state — fall back to network download
                    self.model = whisper_model_class(
                        self.model_name,
                        device=self.device,
                        compute_type=self.compute_type,
                        download_root="/app/model-cache",
                    )
                log.success(f"Model loaded in {time.time() - start:.2f}s")
            except Exception as e:
                log.error(f"Failed to load model: {e}")
                raise

    def unload_model(self):
        with self._lock:
            if not self.model:
                return
            log.info("Unloading IDLE model from GPU...")
            del self.model
            self.model = None
            gc.collect()

        # CTranslate2 frees its CUDA allocations when the model object is
        # released above; torch is not involved in Whisper inference.

        # AGGRESSIVE: Release memory back to the OS (Linux only)
        # Python's GC often keeps free memory in its own heap.
        # malloc_trim(0) forces the glibc allocator to return it to the system.
        if platform.system() == "Linux":
            try:
                libc = ctypes.CDLL("libc.so.6")
                libc.malloc_trim(0)
                log.debug("Memory trimmed via malloc_trim(0)")
            except Exception as e:
                log.warning(f"Could not perform malloc_trim: {e}")

        log.success("Model unloaded. Memory reclamation complete.")

    def get_model(self) -> Any:
        """Return the resident model, loading it on demand.

        load_model() either sets self.model or raises, so the result is
        never None.
        """
        self.last_used = time.time()
        if not self.model:
            self.load_model()
        return self.model

    def _monitor_usage(self) -> None:
        while True:
            time.sleep(_MONITOR_INTERVAL_SECONDS)
            if self.model and (time.time() - self.last_used > MODEL_TIMEOUT_SECONDS):
                self.unload_model()
