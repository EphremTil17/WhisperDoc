"""
Tests for AudioService capture sessions and PCM conversion.

The hardware stream itself requires a real device and is not covered here;
audio_callback is driven directly with synthetic frames.
"""

import asyncio
from unittest.mock import MagicMock

import numpy as np
import pytest

from whisper_shell.services.audio_service import AudioService


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
