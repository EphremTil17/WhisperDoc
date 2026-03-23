"""
Tests for ParakeetEngine.

NeMo is not installed in the Whisper image (or on the Windows host).
conftest.py registers a MagicMock stub for nemo.collections.asr before any
module is imported. We retrieve that stub via sys.modules here instead of
registering a second one (setdefault is a no-op after conftest runs).
"""
import sys
import pytest
from unittest.mock import MagicMock

from engine.parakeet_engine import ParakeetEngine
from engine.base_engine import TranscriptionResult, SegmentResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _nemo_asr_stub():
    """Return the MagicMock that conftest registered for nemo.collections.asr."""
    return sys.modules["nemo.collections.asr"]


def _make_hyp(text: str, segments=None):
    """Build a mock NeMo Hypothesis.

    NeMo stores timestamp data in ``hyp.timestep`` (not ``hyp.timestamp``).
    When timestamps=True, ``transcribe()`` returns list[list[Hypothesis]].
    """
    hyp = MagicMock()
    hyp.text = text
    if segments is not None:
        hyp.timestep = {"segment": segments}
    else:
        hyp.timestep = None
    return hyp


def _build_engine(mock_model) -> ParakeetEngine:
    """Construct a ParakeetEngine whose NeMo from_pretrained returns mock_model.

    mock_model.to() must return mock_model itself so that the .to(device) chain
    in _load_model does not produce a different MagicMock as self._model.
    """
    mock_model.to.return_value = mock_model
    mock_model.cuda.return_value = mock_model
    mock_model.half.return_value = mock_model
    _nemo_asr_stub().models.ASRModel.from_pretrained.return_value = mock_model
    return ParakeetEngine(model_name="nvidia/parakeet-tdt-0.6b-v3", device="cpu")


# ---------------------------------------------------------------------------
# Transcription shape
# ---------------------------------------------------------------------------

class TestTranscribeReturnShape:
    def test_returns_transcription_result(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Hello world")]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert isinstance(result, TranscriptionResult)

    def test_text_from_hypothesis(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Test transcription")]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert result.text == "Test transcription"

    def test_language_is_always_en(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Hi")]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert result.language == "en"

    def test_processing_time_is_non_negative(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Hi")]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert result.processing_time >= 0.0


class TestSegmentNormalisation:
    def test_segment_timestamps_extracted(self):
        segs = [
            {"start": 0.0, "end": 0.8, "segment": "Hello"},
            {"start": 0.8, "end": 1.5, "segment": "world"},
        ]
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Hello world", segments=segs)]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert len(result.segments) == 2
        assert result.segments[0] == SegmentResult(start=0.0, end=0.8, text="Hello")
        assert result.segments[1] == SegmentResult(start=0.8, end=1.5, text="world")

    def test_fallback_single_segment_when_no_timestamps(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("No timestamps here", segments=None)]]
        engine = _build_engine(mock_model)

        result = engine.transcribe("/fake/audio.wav")

        assert len(result.segments) == 1
        assert result.segments[0].text == "No timestamps here"
        assert result.segments[0].start == 0.0
        assert result.segments[0].end == 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

class TestLifecycle:
    def test_is_loaded_true_after_init(self):
        mock_model = MagicMock()
        engine = _build_engine(mock_model)
        assert engine.is_loaded() is True

    def test_is_loaded_false_after_unload(self):
        mock_model = MagicMock()
        engine = _build_engine(mock_model)
        engine.unload()
        assert engine.is_loaded() is False

    def test_warmup_is_idempotent_when_loaded(self):
        mock_model = MagicMock()
        engine = _build_engine(mock_model)
        call_count_before = _nemo_asr_stub().models.ASRModel.from_pretrained.call_count
        engine.warmup()  # Already loaded — should NOT call from_pretrained again
        assert _nemo_asr_stub().models.ASRModel.from_pretrained.call_count == call_count_before

    def test_transcribe_after_unload_reloads(self):
        mock_model = MagicMock()
        mock_model.transcribe.return_value = [[_make_hyp("Reloaded")]]
        engine = _build_engine(mock_model)

        engine.unload()
        assert engine.is_loaded() is False

        # from_pretrained will be called again on transcribe → _load_model
        _nemo_asr_stub().models.ASRModel.from_pretrained.return_value = mock_model
        result = engine.transcribe("/fake/audio.wav")

        assert engine.is_loaded() is True
        assert result.text == "Reloaded"
