"""
Engine contract tests.

Verifies that every BaseEngine implementation produces a valid
TranscriptionResult. Uses parametrised fixtures so adding a new engine
in future only requires adding a fixture here — the contract tests apply
automatically.

Heavy deps (torch, faster_whisper, nemo) are stubbed by conftest.py before
this module is imported — no setdefault() calls are needed here.
"""
import sys
import pytest
from unittest.mock import MagicMock, patch

from engine.base_engine import BaseEngine, TranscriptionResult, SegmentResult
from engine.whisper_engine import WhisperEngine
from engine.parakeet_engine import ParakeetEngine


# ---------------------------------------------------------------------------
# Shared engine fixture parametrisation
# ---------------------------------------------------------------------------

@pytest.fixture(params=["whisper", "parakeet"])
def engine(request):
    """Return a fully initialised engine for each backend."""
    if request.param == "whisper":
        with patch("engine.model_manager.WhisperModel") as MockWhisper, \
             patch("engine.model_manager.asyncio.create_task", side_effect=lambda c: c.close()):
            mock_instance = MagicMock()
            seg = MagicMock()
            seg.start, seg.end, seg.text = 0.0, 1.0, " Hello"
            info = MagicMock()
            info.language = "en"
            mock_instance.transcribe.return_value = (iter([seg]), info)
            MockWhisper.return_value = mock_instance
            eng = WhisperEngine(model_name="tiny.en", device="cpu", compute_type="int8")
            # Re-bind the mock so transcribe() still works after the patch context
            eng._model_manager.model = mock_instance
            yield eng

    elif request.param == "parakeet":
        nemo_asr_stub = sys.modules["nemo.collections.asr"]
        hyp = MagicMock()
        hyp.text = "Hello"
        hyp.timestamp = {"segment": [{"start": 0.0, "end": 1.0, "segment": "Hello"}]}
        mock_nemo_model = MagicMock()
        mock_nemo_model.to.return_value = mock_nemo_model  # keep identity through .to(device) chain
        mock_nemo_model.transcribe.return_value = [hyp]
        nemo_asr_stub.models.ASRModel.from_pretrained.return_value = mock_nemo_model
        yield ParakeetEngine(model_name="nvidia/parakeet-tdt-0.6b-v3", device="cpu")


# ---------------------------------------------------------------------------
# Contract assertions (run against every engine)
# ---------------------------------------------------------------------------

class TestEngineContract:
    def test_is_base_engine_subclass(self, engine):
        assert isinstance(engine, BaseEngine)

    def test_is_loaded_returns_bool(self, engine):
        result = engine.is_loaded()
        assert isinstance(result, bool)

    def test_transcribe_returns_transcription_result(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        assert isinstance(result, TranscriptionResult)

    def test_transcription_result_text_is_string(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        assert isinstance(result.text, str)

    def test_transcription_result_language_is_string(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        assert isinstance(result.language, str)

    def test_transcription_result_segments_is_list(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        assert isinstance(result.segments, list)

    def test_transcription_result_processing_time_is_float(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        assert isinstance(result.processing_time, float)
        assert result.processing_time >= 0.0

    def test_all_segments_are_segment_results(self, engine):
        result = engine.transcribe("/fake/audio.wav")
        for seg in result.segments:
            assert isinstance(seg, SegmentResult)
            assert isinstance(seg.start, float)
            assert isinstance(seg.end, float)
            assert isinstance(seg.text, str)

    def test_warmup_is_idempotent(self, engine):
        engine.warmup()
        engine.warmup()  # Second call must not raise

    def test_unload_then_is_loaded_false(self, engine):
        engine.unload()
        assert engine.is_loaded() is False
