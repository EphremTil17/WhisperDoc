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

def get_gpu_available():
    return torch.cuda.is_available()

def test_whisper_cpu_basic():
    """Verify Whisper can run on CPU (baseline test)."""
    print("\n--- Testing CPU Fallback (tiny.en) ---")
    try:
        model = WhisperModel("tiny.en", device="cpu", compute_type="int8")
        # 1 second of silence
        audio = np.zeros(16000, dtype=np.float32)
        segments, info = model.transcribe(audio)
        list(segments) # Trigger execution
        assert info is not None
        print("✅ CPU Basic test passed.")
    except Exception as e:
        pytest.fail(f"CPU transcription failed: {e}")

@pytest.mark.skipif(not get_gpu_available(), reason="GPU/CUDA not available on this machine")
def test_whisper_gpu_full():
    """Verify Whisper can run on GPU (performance test)."""
    print("\n--- Testing GPU Execution (medium.en) ---")
    try:
        model = WhisperModel("medium.en", device="cuda", compute_type="float16")
        # 1 second of silence
        audio = np.zeros(16000, dtype=np.float32)
        segments, info = model.transcribe(audio)
        list(segments) # Trigger execution
        assert model.model.device == "cuda"
        print("✅ GPU Full test passed.")
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