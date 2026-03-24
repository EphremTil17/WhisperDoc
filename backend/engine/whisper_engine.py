"""
WhisperEngine: faster-whisper backend via ModelManager.

Wraps the existing ModelManager without modifying it. Transcription
parameters are read from environment variables at construction time
and baked in — every transcribe() call uses a consistent config
without per-call overhead or handler-level parameter scatter.
"""

import os
import time

from engine.base_engine import BaseEngine, SegmentResult, TranscriptionResult
from engine.model_manager import ModelManager
from logging_config import log

# Transcription hyperparameters — baked in at engine construction.
# Changing these requires a service restart (by design: config via env).
_DEFAULT_BEAM_SIZE = int(os.getenv("WHISPER_BEAM_SIZE", "5"))
_DEFAULT_NO_SPEECH = float(os.getenv("WHISPER_NO_SPEECH_THRESHOLD", "0.6"))
_DEFAULT_LOG_PROB = float(os.getenv("WHISPER_LOG_PROB_THRESHOLD", "-1.0"))
_DEFAULT_CONDITION = (
    os.getenv("WHISPER_CONDITION_ON_PREVIOUS", "True").lower() == "true"
)


class WhisperEngine(BaseEngine):
    """
    ASR engine backed by faster-whisper (CTranslate2) via ModelManager.

    ModelManager owns the WhisperModel lifecycle (load, unload, idle-timeout).
    WhisperEngine owns the transcription contract: parameter baking,
    generator materialization, and TranscriptionResult normalization.
    """

    def __init__(
        self,
        model_name: str,
        device: str,
        compute_type: str,
        beam_size: int = _DEFAULT_BEAM_SIZE,
        language: str = "en",
        no_speech_threshold: float = _DEFAULT_NO_SPEECH,
        log_prob_threshold: float = _DEFAULT_LOG_PROB,
        condition_on_previous_text: bool = _DEFAULT_CONDITION,
    ):
        self._model_manager = ModelManager(
            model_name=model_name,
            device=device,
            compute_type=compute_type,
        )
        self._beam_size = beam_size
        self._language = language
        self._no_speech_threshold = no_speech_threshold
        self._log_prob_threshold = log_prob_threshold
        self._condition_on_previous_text = condition_on_previous_text
        log.info(
            f"WhisperEngine ready: model={model_name}, device={device}, "
            f"compute={compute_type}, beam={beam_size}, lang={language}"
        )

    def transcribe(self, audio_path: str) -> TranscriptionResult:
        """
        Transcribe a 16kHz/16-bit/mono WAV file using faster-whisper.

        IMPORTANT: faster-whisper.transcribe() returns a lazy C++ generator.
        list(segments_iter) must be called INSIDE this method (i.e., inside
        asyncio.to_thread) before the function returns. Iterating the generator
        outside the thread causes undefined behaviour due to the underlying
        CTranslate2 context not being thread-safe across boundaries.
        """
        start = time.time()
        model, _ = self._model_manager.get_model()
        if model is None:
            raise RuntimeError("Whisper model is not loaded.")

        segments_iter, info = model.transcribe(
            audio_path,
            language=self._language,
            beam_size=self._beam_size,
            no_speech_threshold=self._no_speech_threshold,
            log_prob_threshold=self._log_prob_threshold,
            condition_on_previous_text=self._condition_on_previous_text,
        )
        # Materialize the lazy generator here, inside the thread
        segments_list = list(segments_iter)
        processing_time = time.time() - start

        return TranscriptionResult(
            text=" ".join(s.text.strip() for s in segments_list),
            segments=[
                SegmentResult(start=s.start, end=s.end, text=s.text.strip())
                for s in segments_list
            ],
            language=info.language,
            processing_time=processing_time,
        )

    def warmup(self) -> None:
        """Ensure model is loaded; called in a background thread post-auth."""
        self._model_manager.get_model()

    def is_loaded(self) -> bool:
        """True when the WhisperModel is resident in memory."""
        return self._model_manager.model is not None

    def unload(self) -> None:
        """Delegate VRAM release and memory reclamation to ModelManager."""
        self._model_manager.unload_model()
