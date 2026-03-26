import asyncio
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
WhisperModel: Any | None = None


def _load_torch_module() -> Any:
    """Import torch lazily so non-Whisper environments can still import this module."""
    return importlib.import_module("torch")


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

        # Start cleanup task — guard against sync contexts (tests, scripts)
        _coro = self._monitor_usage()
        try:
            self._monitor_task = asyncio.create_task(_coro)
        except RuntimeError:
            _coro.close()
            self._monitor_task = None

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

        # Clear Torch CUDA cache if available
        try:
            torch = _load_torch_module()
        except ImportError:
            torch = None

        if torch is not None and torch.cuda.is_available():
            torch.cuda.empty_cache()

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

    def get_model(self):
        self.last_used = time.time()
        if not self.model:
            self.load_model()
            if self.model is None:
                raise RuntimeError("Whisper model failed to initialize.")
            return self.model, True  # Tuple: (model, was_reloaded)
        return self.model, False

    async def _monitor_usage(self):
        while True:
            await asyncio.sleep(60)  # Check every minute
            if self.model and (time.time() - self.last_used > MODEL_TIMEOUT_SECONDS):
                self.unload_model()
