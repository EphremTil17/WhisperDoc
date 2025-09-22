#!/usr/bin/env python3
"""
Simple test to verify faster-whisper works with GPU
"""

import time
import numpy as np
from faster_whisper import WhisperModel

print("=== faster-whisper GPU Test ===")

# Test GPU availability
try:
    import torch
    print(f"PyTorch CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"CUDA device count: {torch.cuda.device_count()}")
        print(f"Current CUDA device: {torch.cuda.current_device()}")
        print(f"Device name: {torch.cuda.get_device_name()}")
except ImportError:
    print("PyTorch not available, checking CUDA directly...")

# Test faster-whisper model loading
print("\n=== Loading Whisper Model ===")
start_time = time.time()

try:
    # Load medium.en model on GPU
    model = WhisperModel("medium.en", device="cuda", compute_type="float16")
    load_time = time.time() - start_time
    print(f"✅ Model loaded successfully in {load_time:.2f}s")
    print(f"Model device: {model.model.device}")
    print(f"Model is multilingual: {model.model.is_multilingual}")
    
    # Create test audio (5 seconds of silence + simple tone)
    print("\n=== Testing Transcription ===")
    sample_rate = 16000
    duration = 3
    
    # Generate simple test audio - silence with a beep
    audio = np.zeros(sample_rate * duration, dtype=np.float32)
    # Add a simple tone for the last second
    t = np.linspace(0, 1, sample_rate)
    tone = 0.1 * np.sin(2 * np.pi * 440 * t)  # 440Hz tone
    audio[-sample_rate:] = tone
    
    print(f"Generated test audio: {duration}s, {sample_rate}Hz")
    
    # Transcribe
    transcribe_start = time.time()
    segments, info = model.transcribe(audio, language="en")
    transcribe_time = time.time() - transcribe_start
    
    print(f"✅ Transcription completed in {transcribe_time:.2f}s")
    print(f"Detected language: {info.language} (confidence: {info.language_probability:.2f})")
    
    # Print segments
    segments_list = list(segments)
    print(f"Number of segments: {len(segments_list)}")
    
    for segment in segments_list:
        print(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")
    
    print("\n SUCCESS: faster-whisper working correctly with GPU!")
    
except Exception as e:
    print(f"❌ ERROR: {e}")
    print("This might indicate GPU/CUDA setup issues")
    
    # Try CPU fallback
    print("\n=== Trying CPU fallback ===")
    try:
        model_cpu = WhisperModel("tiny.en", device="cpu")
        print("✅ CPU model loaded successfully")
        
        # Quick test with CPU
        audio = np.zeros(16000, dtype=np.float32)  # 1 second silence
        segments, info = model_cpu.transcribe(audio)
        print("✅ CPU transcription works")
        
    except Exception as cpu_error:
        print(f"❌ CPU also failed: {cpu_error}")

print("\n=== Test Complete ===")
print("If you see SUCCESS above, your Docker + GPU setup is working!")
print("If you see errors, we need to fix CUDA/GPU access first.")