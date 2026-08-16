"""Unit tests for the isolated parakeet.cpp sidecar adapter."""

from __future__ import annotations

import wave
from unittest.mock import MagicMock, call, patch

import pytest
import requests

from engine.base_engine import SegmentResult, TranscriptionResult
from engine.parakeet_cpp_engine import ParakeetCppEngine


def _response(payload: object) -> MagicMock:
    response = MagicMock()
    response.json.return_value = payload
    response.raise_for_status.return_value = None
    return response


def _write_wav(path, seconds: float = 1.0) -> None:
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(16000)
        wav_file.writeframes(b"\x00\x00" * int(16000 * seconds))


@pytest.fixture
def mocked_transport():
    with (
        patch(
            "engine.parakeet_cpp_engine.requests.get",
            return_value=_response({"status": "ok"}),
        ) as get,
        patch(
            "engine.parakeet_cpp_engine.requests.post",
            return_value=_response({"text": ""}),
        ) as post,
    ):
        yield get, post


def _engine() -> ParakeetCppEngine:
    return ParakeetCppEngine(
        "http://parakeet-cpp:8080/",
        startup_timeout_seconds=0.01,
        warmup_seconds=0.01,
        max_audio_seconds=2,
    )


def test_constructor_checks_health_and_runs_cuda_warmup(mocked_transport):
    get, post = mocked_transport

    engine = _engine()

    assert engine.is_loaded() is True
    get.assert_called_once()
    post.assert_called_once()
    assert get.call_args.kwargs["headers"] == {"Connection": "close"}
    assert post.call_args.kwargs["headers"] == {"Connection": "close"}
    assert post.call_args.kwargs["data"] == {"response_format": "json"}


def test_transcribe_maps_single_segment_and_duration(mocked_transport, tmp_path):
    _, post = mocked_transport
    engine = _engine()
    post.return_value = _response({"text": "  Hello, world.  "})
    audio = tmp_path / "speech.wav"
    _write_wav(audio, 1.25)

    result = engine.transcribe(str(audio))

    assert isinstance(result, TranscriptionResult)
    assert result.text == "Hello, world."
    assert result.language == "en"
    assert result.processing_time >= 0.0
    assert result.segments == [SegmentResult(start=0.0, end=1.25, text="Hello, world.")]
    assert post.call_count == 2  # startup warmup + transcription


def test_transcribe_rejects_audio_above_safe_limit(mocked_transport, tmp_path):
    _, post = mocked_transport
    engine = _engine()
    audio = tmp_path / "too-long.wav"
    _write_wav(audio, 2.1)

    with pytest.raises(ValueError, match="safe maximum"):
        engine.transcribe(str(audio))

    post.assert_called_once()  # startup warmup only


def test_transcribe_rejects_wrong_wav_contract(mocked_transport, tmp_path):
    engine = _engine()
    audio = tmp_path / "stereo.wav"
    with wave.open(str(audio), "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(16000)
        wav_file.writeframes(b"\x00\x00\x00\x00" * 100)

    with pytest.raises(ValueError, match="16-kHz, 16-bit, mono"):
        engine.transcribe(str(audio))


def test_invalid_sidecar_payload_marks_engine_unready(mocked_transport, tmp_path):
    _, post = mocked_transport
    engine = _engine()
    post.return_value = _response({"unexpected": "value"})
    audio = tmp_path / "speech.wav"
    _write_wav(audio)

    with pytest.raises(RuntimeError, match="invalid transcription payload"):
        engine.transcribe(str(audio))

    assert engine.is_loaded() is False


def test_transport_error_is_masked_and_marks_engine_unready(mocked_transport, tmp_path):
    _, post = mocked_transport
    engine = _engine()
    post.side_effect = requests.ConnectionError("internal address details")
    audio = tmp_path / "speech.wav"
    _write_wav(audio)

    with pytest.raises(RuntimeError, match="transcription request failed"):
        engine.transcribe(str(audio))

    assert engine.is_loaded() is False


def test_unload_detaches_and_warmup_restores_readiness(mocked_transport):
    get, post = mocked_transport
    engine = _engine()

    engine.unload()
    assert engine.is_loaded() is False
    engine.warmup()

    assert engine.is_loaded() is True
    assert get.call_count == 2
    assert post.call_count == 2


def test_warmup_is_idempotent(mocked_transport):
    get, post = mocked_transport
    engine = _engine()

    engine.warmup()
    engine.warmup()

    assert get.mock_calls == [
        call(
            "http://parakeet-cpp:8080/health",
            headers={"Connection": "close"},
            timeout=(2.0, 30.0),
        )
    ]
    assert post.call_count == 1


@pytest.mark.parametrize(
    "url",
    [
        "parakeet-cpp:8080",
        "ftp://parakeet-cpp/model",
        "http://user:password@parakeet-cpp:8080",
        "http://parakeet-cpp:8080?debug=true",
    ],
)
def test_base_url_validation_rejects_unsafe_or_ambiguous_values(url):
    with pytest.raises(ValueError, match="PARAKEET_CPP_BASE_URL"):
        ParakeetCppEngine(url)
