"""
Tests for AudioService capture sessions and PCM conversion.

audio_callback is driven with synthetic frames; the hardware stream runs
against a fake sounddevice module, so no audio device is needed.
"""

import asyncio
from unittest.mock import MagicMock

import numpy as np
import pytest
from loguru import logger

from whisper_shell.services import audio_service
from whisper_shell.services.audio_service import TARGET_RATE, AudioService
from whisper_shell.services.config_service import cfg


def _frames(*samples: float) -> np.ndarray:
    """sounddevice delivers float32 frames shaped (frames, channels)."""
    return np.array(samples, dtype=np.float32).reshape(-1, 1)


async def _drain(queue: asyncio.Queue) -> list:
    await asyncio.sleep(0)  # let call_soon_threadsafe callbacks run
    items = []
    while not queue.empty():
        items.append(queue.get_nowait())
    return items


class TestCaptureSession:
    @pytest.mark.asyncio
    async def test_initial_state(self):
        svc = AudioService(asyncio.get_running_loop())
        assert svc.is_recording is False
        assert svc.stream is None
        assert svc.device_rate == 16000

    @pytest.mark.asyncio
    async def test_session_receives_chunks_then_sentinel(self):
        svc = AudioService(asyncio.get_running_loop())
        session = svc.start_capture()
        assert svc.is_recording is True

        svc.audio_callback(_frames(0.0, 0.5), 2, None, None)
        svc.stop_capture()

        items = await _drain(session)
        assert len(items) == 2
        assert isinstance(items[0], bytes)
        assert items[-1] is None
        assert svc.is_recording is False

    @pytest.mark.asyncio
    async def test_no_audio_after_stop(self):
        """A callback racing stop must not land behind the session's sentinel."""
        svc = AudioService(asyncio.get_running_loop())
        session = svc.start_capture()
        svc.stop_capture()
        svc.audio_callback(_frames(0.25), 1, None, None)

        assert await _drain(session) == [None]

    @pytest.mark.asyncio
    async def test_sessions_get_separate_queues(self):
        svc = AudioService(asyncio.get_running_loop())
        first = svc.start_capture()
        svc.stop_capture()
        second = svc.start_capture()
        svc.audio_callback(_frames(0.1), 1, None, None)

        assert await _drain(first) == [None]
        assert len(await _drain(second)) == 1

    @pytest.mark.asyncio
    async def test_out_of_range_samples_saturate_instead_of_wrapping(self):
        svc = AudioService(asyncio.get_running_loop())
        session = svc.start_capture()
        svc.audio_callback(_frames(1.5, -1.5), 2, None, None)

        (chunk,) = await _drain(session)
        assert np.frombuffer(chunk, dtype=np.int16).tolist() == [32767, -32767]


class TestStopStream:
    @pytest.mark.asyncio
    async def test_stop_stream_when_none(self):
        svc = AudioService(asyncio.get_running_loop())
        svc.stop_stream()  # Should not raise
        assert svc.stream is None

    @pytest.mark.asyncio
    async def test_stop_stream_closes_and_clears(self):
        svc = AudioService(asyncio.get_running_loop())
        mock_stream = MagicMock()
        svc.stream = mock_stream
        svc.stop_stream()
        mock_stream.stop.assert_called_once()
        mock_stream.close.assert_called_once()
        assert svc.stream is None


# ---------------------------------------------------------------------------
# Hardware stream (sounddevice faked at the module edge)
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_sd(monkeypatch) -> MagicMock:
    """A 48 kHz WASAPI microphone behind a fake sounddevice module."""
    sd = MagicMock()
    sd.query_devices.return_value = {
        "name": "USB Mic",
        "hostapi": 1,
        "default_samplerate": 48000.0,
    }
    sd.query_hostapis.return_value = {"name": "Windows WASAPI"}
    monkeypatch.setattr(audio_service, "sd", sd)
    monkeypatch.setattr(cfg, "AUDIO_DEVICE_ID", 7)
    return sd


def _stream_callback(sd: MagicMock):
    """The callback the service handed to PortAudio."""
    return sd.InputStream.call_args.kwargs["callback"]


class TestStartStream:
    @pytest.mark.asyncio
    async def test_opens_configured_device_mono_at_its_native_rate(self, fake_sd):
        svc = AudioService(asyncio.get_running_loop())

        svc.start_stream()

        fake_sd.query_devices.assert_called_once_with(7, "input")
        fake_sd.InputStream.assert_called_once_with(
            samplerate=48000, channels=1, callback=svc.audio_callback, device=7
        )
        fake_sd.InputStream.return_value.start.assert_called_once()
        assert svc.stream is fake_sd.InputStream.return_value
        assert svc.device_rate == 48000

    @pytest.mark.asyncio
    async def test_second_start_reuses_the_open_stream(self, fake_sd):
        svc = AudioService(asyncio.get_running_loop())

        svc.start_stream()
        svc.start_stream()

        assert fake_sd.InputStream.call_count == 1

    @pytest.mark.asyncio
    async def test_unknown_native_rate_falls_back_to_16k(self, fake_sd):
        del fake_sd.query_devices.return_value["default_samplerate"]
        svc = AudioService(asyncio.get_running_loop())

        svc.start_stream()

        assert svc.device_rate == TARGET_RATE
        assert fake_sd.InputStream.call_args.kwargs["samplerate"] == TARGET_RATE

    @pytest.mark.asyncio
    async def test_missing_device_propagates_and_opens_nothing(self, fake_sd):
        fake_sd.query_devices.side_effect = ValueError("No input device matching 7")
        svc = AudioService(asyncio.get_running_loop())

        with pytest.raises(ValueError, match="No input device"):
            svc.start_stream()

        fake_sd.InputStream.assert_not_called()
        assert svc.stream is None

    @pytest.mark.asyncio
    async def test_stop_after_start_releases_the_device(self, fake_sd):
        svc = AudioService(asyncio.get_running_loop())
        svc.start_stream()
        stream = fake_sd.InputStream.return_value

        svc.stop_stream()

        stream.stop.assert_called_once()
        stream.close.assert_called_once()
        assert svc.stream is None


class TestResampling:
    @pytest.mark.asyncio
    async def test_48k_frames_reach_the_session_as_16k_pcm(self, fake_sd):
        svc = AudioService(asyncio.get_running_loop())
        svc.start_stream()
        callback = _stream_callback(fake_sd)
        session = svc.start_capture()

        callback(np.full((480, 1), 0.5, dtype=np.float32), 480, None, None)

        (chunk,) = await _drain(session)
        samples = np.frombuffer(chunk, dtype=np.int16)
        assert len(samples) == 160  # 10 ms at 16 kHz
        assert set(samples.tolist()) == {16383}

    @pytest.mark.asyncio
    async def test_resampling_preserves_the_waveform_shape(self, fake_sd):
        svc = AudioService(asyncio.get_running_loop())
        svc.start_stream()
        session = svc.start_capture()
        ramp = np.linspace(-1.0, 1.0, 48, dtype=np.float32).reshape(-1, 1)

        _stream_callback(fake_sd)(ramp, 48, None, None)

        (chunk,) = await _drain(session)
        samples = np.frombuffer(chunk, dtype=np.int16).tolist()
        assert len(samples) == 16
        assert samples[0] == -32767
        assert samples[-1] == 32767
        assert samples == sorted(samples)

    @pytest.mark.asyncio
    async def test_stream_status_is_reported_but_audio_is_kept(self, fake_sd):
        warnings: list[str] = []
        sink = logger.add(warnings.append, level="WARNING", format="{message}")
        try:
            svc = AudioService(asyncio.get_running_loop())
            svc.start_stream()
            session = svc.start_capture()

            _stream_callback(fake_sd)(_frames(*[0.1] * 48), 48, None, "input overflow")
        finally:
            logger.remove(sink)

        assert len(await _drain(session)) == 1
        assert any("input overflow" in w for w in warnings)
