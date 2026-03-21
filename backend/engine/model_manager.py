import os
import time
import gc
import torch
import asyncio
import ctypes
import platform
import threading
from faster_whisper import WhisperModel
from logging_config import log

# Load config from env
MODEL_TIMEOUT_SECONDS = int(os.getenv("MODEL_TIMEOUT_SECONDS", "1800"))

class ModelManager:
    """Manages the lifecycle of the WhisperModel for dynamic GPU loading."""
    def __init__(self, model_name, device, compute_type):
        self.model_name = model_name
        self.device = device
        self.compute_type = compute_type
        self.model = None
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
            if self.model: return
            log.info(f"Loading Whisper model ({self.model_name}) into {self.device}...")
            try:
                start = time.time()
                try:
                    # Prefer cache-only load to skip the HuggingFace revision check
                    self.model = WhisperModel(
                        self.model_name,
                        device=self.device,
                        compute_type=self.compute_type,
                        download_root="/app/model-cache",
                        local_files_only=True,
                    )
                except Exception:
                    # Cache miss — download and cache the model
                    self.model = WhisperModel(
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
            if not self.model: return
            log.info("Unloading IDLE model from GPU...")
            del self.model
            self.model = None
            gc.collect()
        
        # Clear Torch CUDA cache if available
        if torch.cuda.is_available():
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
            return self.model, True # Tuple: (model, was_reloaded)
        return self.model, False

    async def _monitor_usage(self):
        while True:
            await asyncio.sleep(60) # Check every minute
            if self.model and (time.time() - self.last_used > MODEL_TIMEOUT_SECONDS):
                self.unload_model()
