"""
Tests for EngineFactory.

Verifies ASR_ENGINE env var routing without touching real model weights.
Both concrete engine constructors are patched at the class level.
"""
import pytest
import os
from unittest.mock import MagicMock, patch

from engine.engine_factory import create_engine
from engine.base_engine import BaseEngine


@pytest.fixture(autouse=True)
def _patch_whisper_model():
    """Prevent WhisperModel from loading and suppress asyncio.create_task."""
    with patch("engine.model_manager.WhisperModel") as mock, \
         patch("engine.model_manager.asyncio.create_task", side_effect=lambda c: c.close()):
        mock.return_value = MagicMock()
        yield mock


class TestWhisperSelection:
    def test_default_creates_whisper_engine(self, monkeypatch):
        monkeypatch.delenv("ASR_ENGINE", raising=False)
        from engine.whisper_engine import WhisperEngine
        engine = create_engine()
        assert isinstance(engine, WhisperEngine)

    def test_explicit_whisper_creates_whisper_engine(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "whisper")
        from engine.whisper_engine import WhisperEngine
        engine = create_engine()
        assert isinstance(engine, WhisperEngine)

    def test_whisper_uppercase_creates_whisper_engine(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "WHISPER")
        from engine.whisper_engine import WhisperEngine
        engine = create_engine()
        assert isinstance(engine, WhisperEngine)

    def test_whisper_engine_is_base_engine(self, monkeypatch):
        monkeypatch.delenv("ASR_ENGINE", raising=False)
        engine = create_engine()
        assert isinstance(engine, BaseEngine)

    def test_model_name_env_forwarded(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "whisper")
        monkeypatch.setenv("MODEL_NAME", "large-v3-turbo")
        from engine.whisper_engine import WhisperEngine
        engine = create_engine()
        assert isinstance(engine, WhisperEngine)
        assert engine._model_manager.model_name == "large-v3-turbo"


class TestParakeetSelection:
    def test_parakeet_creates_parakeet_engine(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "parakeet")
        # ParakeetEngine is imported inside the if-branch; patch at its own module
        with patch("engine.parakeet_engine.ParakeetEngine") as MockParakeet:
            mock_instance = MagicMock(spec=BaseEngine)
            MockParakeet.return_value = mock_instance
            engine = create_engine()
        assert engine is mock_instance

    def test_parakeet_uppercase(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "PARAKEET")
        with patch("engine.parakeet_engine.ParakeetEngine") as MockParakeet:
            mock_instance = MagicMock(spec=BaseEngine)
            MockParakeet.return_value = mock_instance
            engine = create_engine()
        assert engine is mock_instance


class TestUnknownEngine:
    def test_unknown_value_raises_value_error(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "unknown_engine")
        with pytest.raises(ValueError, match="Unknown ASR_ENGINE"):
            create_engine()

    def test_error_message_includes_engine_name(self, monkeypatch):
        monkeypatch.setenv("ASR_ENGINE", "deepgram")
        with pytest.raises(ValueError, match="deepgram"):
            create_engine()
