"""
WhisperDoc Model Hardware Test
------------------------------
Verifies that faster-whisper can actually load and execute transcriptions.
Automatically detects CPU vs GPU and runs appropriate tests.

Usage:
  - pytest tests/test_whisper.py
  - python tests/test_whisper.py
"""
import pytest
import time
import numpy as np
import os
import torch
from faster_whisper import WhisperModel

# Determine the model cache directory relative to this file
# This allows local tests to share the same cache as Docker
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# In Docker, we use /app/model-cache via ENV. Locally, we use the root model-cache.
CACHE_DIR = os.getenv("HF_HOME", os.path.join(os.path.dirname(BASE_DIR), "model-cache"))

def get_gpu_available():
    return torch.cuda.is_available()

@pytest.mark.skipif(
    not os.path.exists("/.dockerenv"),
    reason="Hardware model test only runs inside Docker container"
)
def test_whisper_cpu_basic():
    """Verify Whisper can run on CPU (baseline test)."""
    print(f"\n--- Testing CPU Fallback (tiny.en) [Cache: {CACHE_DIR}] ---")
    try:
        model = WhisperModel("tiny.en", device="cpu", compute_type="int8", download_root=CACHE_DIR)
        # 1 second of silence
        audio = np.zeros(16000, dtype=np.float32)
        result = model.transcribe(audio)
        
        # Diagnostic check
        if not isinstance(result, tuple) or len(result) != 2:
             pytest.fail(f"Unexpected return from model.transcribe: type={type(result)}, value={result}")

        segments, info = result
        list(segments) # Trigger execution
        assert info is not None
        print("✅ CPU Basic test passed.")
    except Exception as e:
        pytest.fail(f"CPU transcription failed: {e}")

@pytest.mark.skipif(
    not get_gpu_available() or (not os.path.exists('/.dockerenv') and not os.getenv("WHISPER_ALLOW_LOCAL_GPU")), 
    reason="GPU test skipped locally to avoid SIGABRT. Run inside Docker or set WHISPER_ALLOW_LOCAL_GPU=1 to override."
)
def test_whisper_gpu_full():
    """Verify Whisper can run on GPU (smoke test)."""
    print(f"\n--- Testing GPU Execution (tiny.en) [Cache: {CACHE_DIR}] ---")

    try:
        model = WhisperModel("tiny.en", device="cuda", compute_type="float16", download_root=CACHE_DIR)
        # 1 second of silence
        audio = np.zeros(16000, dtype=np.float32)
        result = model.transcribe(audio)
        
        # Diagnostic check
        if not isinstance(result, tuple) or len(result) != 2:
             pytest.fail(f"Unexpected return from model.transcribe: type={type(result)}, value={result}")

        segments, info = result
        list(segments) # Trigger execution
        # Verify it actually used the GPU
        assert model.model.device == "cuda"
        print("✅ GPU Smoke test passed.")
    except Exception as e:
        pytest.fail(f"GPU transcription failed: {e}")

if __name__ == "__main__":
    # Manual execution logic
    print("=== Manual Whisper Hardware Discovery ===")
    print(f"CUDA Available: {get_gpu_available()}")
    if get_gpu_available():
        print(f"Device: {torch.cuda.get_device_name(0)}")
    
    test_whisper_cpu_basic()
    if get_gpu_available():
        test_whisper_gpu_full()
    else:
        print("⚠️ Skipping GPU test (Not detected)")