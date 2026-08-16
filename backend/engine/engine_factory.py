"""
Engine Factory: single point of ASR engine selection.

Reads ASR_ENGINE from the environment at call time (not import time) so that
patch.dict(os.environ) in tests applies correctly without reimport tricks.

Both concrete engine imports are deferred inside their respective branches so
that importing this module never pulls in NeMo — the Whisper service image
does not need NeMo installed.
"""

import os

from engine.base_engine import BaseEngine
from logging_config import log


def create_engine() -> BaseEngine:
    """
    Instantiate and return the configured ASR engine.

    Reads ASR_ENGINE from the environment:
      'whisper'  -> WhisperEngine backed by faster-whisper + ModelManager
      'parakeet'     -> ParakeetEngine backed by NVIDIA NeMo (legacy)
      'parakeet_cpp' -> ParakeetCppEngine backed by an isolated native sidecar

    Raises ValueError on unrecognised engine names to ensure fast failure
    at startup rather than a silent misconfiguration fallback.
    """
    engine_name = os.getenv("ASR_ENGINE", "whisper").lower()
    log.info(f"ASR engine selection: '{engine_name}'")

    if engine_name == "whisper":
        from engine.whisper_engine import WhisperEngine

        return WhisperEngine(
            model_name=os.getenv("MODEL_NAME", "large-v3-turbo"),
            device=os.getenv("MODEL_DEVICE", "cuda"),
            compute_type=os.getenv("MODEL_COMPUTE_TYPE", "float16"),
        )

    if engine_name == "parakeet":
        from engine.parakeet_engine import ParakeetEngine

        return ParakeetEngine(
            model_name=os.getenv("PARAKEET_MODEL_NAME", "nvidia/parakeet-tdt-0.6b-v2"),
            device=os.getenv("PARAKEET_DEVICE", "cuda"),
        )

    if engine_name in {"parakeet_cpp", "parakeet-cpp"}:
        from engine.parakeet_cpp_engine import ParakeetCppEngine

        return ParakeetCppEngine(
            base_url=os.getenv("PARAKEET_CPP_BASE_URL", "http://parakeet-cpp:8080"),
            connect_timeout_seconds=float(
                os.getenv("PARAKEET_CPP_CONNECT_TIMEOUT_SECONDS", "2")
            ),
            request_timeout_seconds=float(
                os.getenv("PARAKEET_CPP_REQUEST_TIMEOUT_SECONDS", "30")
            ),
            startup_timeout_seconds=float(
                os.getenv("PARAKEET_CPP_STARTUP_TIMEOUT_SECONDS", "120")
            ),
            warmup_seconds=float(os.getenv("PARAKEET_CPP_WARMUP_SECONDS", "10")),
            max_audio_seconds=float(os.getenv("PARAKEET_CPP_MAX_AUDIO_SECONDS", "30")),
        )

    raise ValueError(
        f"Unknown ASR_ENGINE: '{engine_name}'. "
        "Valid options are: 'whisper', 'parakeet', 'parakeet_cpp'."
    )
