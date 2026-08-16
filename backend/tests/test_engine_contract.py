"""
Engine contract tests.

Verifies that every BaseEngine implementation produces a valid
TranscriptionResult. Uses parametrised fixtures so adding a new engine
in future only requires adding a fixture here — the contract tests apply
automatically.

Heavy Whisper dependencies are stubbed by conftest.py. Parakeet's HTTP
transport is mocked at the process boundary.
"""

import wave
from unittest.mock import MagicMock, patch

import pytest

from engine.base_engine import BaseEngine, SegmentResult, TranscriptionResult
from engine.parakeet_engine import ParakeetEngine
from engine.whisper_engine import WhisperEngine

# ---------------------------------------------------------------------------
# Shared engine fixture parametrisation
# ---------------------------------------------------------------------------


@pytest.fixture(params=["whisper", "parakeet"])
def engine(request, tmp_path):
    """Return ``(engine, audio_path)`` for each backend."""
    if request.param == "whisper":
        with (
            patch("engine.model_manager.WhisperModel") as MockWhisper,
            patch(
                "engine.model_manager.asyncio.create_task",
                side_effect=lambda c: c.close(),
            ),
        ):
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
            yield eng, "/fake/audio.wav"

    elif request.param == "parakeet":
        health = MagicMock()
        health.json.return_value = {"status": "ok"}
        transcript = MagicMock()
        transcript.json.return_value = {"text": "Hello"}
        audio_path = tmp_path / "contract.wav"
        with wave.open(str(audio_path), "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(16000)
            wav_file.writeframes(b"\x00\x00" * 16000)

        with (
            patch("engine.parakeet_engine.requests.get", return_value=health),
            patch("engine.parakeet_engine.requests.post", return_value=transcript),
        ):
            yield (
                ParakeetEngine(
                    base_url="http://parakeet:8080",
                    startup_timeout_seconds=0.01,
                    warmup_seconds=0.01,
                ),
                str(audio_path),
            )


# ---------------------------------------------------------------------------
# Contract assertions (run against every engine)
# ---------------------------------------------------------------------------


class TestEngineContract:
    def test_is_base_engine_subclass(self, engine):
        engine_impl, _ = engine
        assert isinstance(engine_impl, BaseEngine)

    def test_is_loaded_returns_bool(self, engine):
        engine_impl, _ = engine
        result = engine_impl.is_loaded()
        assert isinstance(result, bool)

    def test_transcribe_returns_transcription_result(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        assert isinstance(result, TranscriptionResult)

    def test_transcription_result_text_is_string(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        assert isinstance(result.text, str)

    def test_transcription_result_language_is_string(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        assert isinstance(result.language, str)

    def test_transcription_result_segments_is_list(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        assert isinstance(result.segments, list)

    def test_transcription_result_processing_time_is_float(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        assert isinstance(result.processing_time, float)
        assert result.processing_time >= 0.0

    def test_all_segments_are_segment_results(self, engine):
        engine_impl, audio_path = engine
        result = engine_impl.transcribe(audio_path)
        for seg in result.segments:
            assert isinstance(seg, SegmentResult)
            assert isinstance(seg.start, float)
            assert isinstance(seg.end, float)
            assert isinstance(seg.text, str)

    def test_warmup_is_idempotent(self, engine):
        engine_impl, _ = engine
        engine_impl.warmup()
        engine_impl.warmup()  # Second call must not raise

    def test_unload_then_is_loaded_false(self, engine):
        engine_impl, _ = engine
        engine_impl.unload()
        assert engine_impl.is_loaded() is False
