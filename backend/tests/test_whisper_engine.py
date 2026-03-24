"""
Tests for WhisperEngine.

Patches WhisperModel and ModelManager internals to avoid GPU/model-file
dependencies. Verifies:
  - TranscriptionResult shape and field values
  - Lazy generator materialisation inside the thread
  - is_loaded() delegates to ModelManager.model
  - warmup() triggers get_model()
  - unload() triggers unload_model()
"""

from unittest.mock import MagicMock, patch

import pytest
from engine.base_engine import SegmentResult, TranscriptionResult
from engine.whisper_engine import WhisperEngine


@pytest.fixture
def mock_whisper_model():
    """Patch WhisperModel and asyncio.create_task so no GPU or event loop is needed."""
    with (
        patch("engine.model_manager.WhisperModel") as MockClass,
        patch(
            "engine.model_manager.asyncio.create_task", side_effect=lambda c: c.close()
        ),
    ):
        instance = MagicMock()
        MockClass.return_value = instance
        yield MockClass, instance


def _make_segment(start, end, text):
    seg = MagicMock()
    seg.start = start
    seg.end = end
    seg.text = text
    return seg


def _make_info(language="en"):
    info = MagicMock()
    info.language = language
    return info


def _build_engine(mock_whisper_model):
    """Construct a WhisperEngine with CPU/int8 for unit tests."""
    return WhisperEngine(
        model_name="tiny.en",
        device="cpu",
        compute_type="int8",
    )


class TestTranscribeReturnShape:
    def test_returns_transcription_result(self, mock_whisper_model):
        _, instance = mock_whisper_model
        segments = [
            _make_segment(0.0, 1.0, " Hello"),
            _make_segment(1.0, 2.0, " world"),
        ]
        instance.transcribe.return_value = (iter(segments), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert isinstance(result, TranscriptionResult)

    def test_text_joins_stripped_segments(self, mock_whisper_model):
        _, instance = mock_whisper_model
        segments = [
            _make_segment(0.0, 1.0, " Hello"),
            _make_segment(1.0, 2.0, " world"),
        ]
        instance.transcribe.return_value = (iter(segments), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert result.text == "Hello world"

    def test_segments_list_matches_input(self, mock_whisper_model):
        _, instance = mock_whisper_model
        raw = [_make_segment(0.0, 0.5, " Hi"), _make_segment(0.5, 1.2, " there")]
        instance.transcribe.return_value = (iter(raw), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert len(result.segments) == 2
        assert result.segments[0] == SegmentResult(start=0.0, end=0.5, text="Hi")
        assert result.segments[1] == SegmentResult(start=0.5, end=1.2, text="there")

    def test_language_comes_from_info(self, mock_whisper_model):
        _, instance = mock_whisper_model
        instance.transcribe.return_value = (iter([]), _make_info(language="fr"))

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert result.language == "fr"

    def test_processing_time_is_positive(self, mock_whisper_model):
        _, instance = mock_whisper_model
        instance.transcribe.return_value = (iter([]), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert result.processing_time >= 0.0

    def test_empty_audio_returns_empty_text(self, mock_whisper_model):
        _, instance = mock_whisper_model
        instance.transcribe.return_value = (iter([]), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        assert result.text == ""
        assert result.segments == []


class TestGeneratorMaterialisation:
    def test_lazy_generator_is_consumed(self, mock_whisper_model):
        """Verify list() is called on the generator (not returned raw)."""
        _, instance = mock_whisper_model
        consumed = []

        def tracking_gen():
            for seg in [_make_segment(0, 1, " test")]:
                consumed.append(seg)
                yield seg

        instance.transcribe.return_value = (tracking_gen(), _make_info())

        engine = _build_engine(mock_whisper_model)
        result = engine.transcribe("/fake/audio.wav")

        # Generator must be fully consumed by transcribe()
        assert len(consumed) == 1
        assert isinstance(result, TranscriptionResult)


class TestLifecycleDelegation:
    def test_is_loaded_true_when_model_set(self, mock_whisper_model):
        engine = _build_engine(mock_whisper_model)
        assert engine.is_loaded() is True  # ModelManager loads on __init__

    def test_is_loaded_false_after_unload(self, mock_whisper_model):
        engine = _build_engine(mock_whisper_model)
        engine.unload()
        assert engine.is_loaded() is False

    def test_warmup_calls_get_model(self, mock_whisper_model):
        engine = _build_engine(mock_whisper_model)
        with patch.object(engine._model_manager, "get_model") as mock_get:
            engine.warmup()
        mock_get.assert_called_once()

    def test_unload_calls_unload_model(self, mock_whisper_model):
        engine = _build_engine(mock_whisper_model)
        with patch.object(engine._model_manager, "unload_model") as mock_unload:
            engine.unload()
        mock_unload.assert_called_once()
