"""Tests for bounded silence-aware PCM chunk planning."""

from __future__ import annotations

import sys
from array import array

import pytest

from engine.silence_chunker import plan_silence_aware_chunks

SAMPLE_RATE = 16000


def _pcm(
    duration_seconds: float,
    *,
    silence_ranges: tuple[tuple[float, float], ...] = (),
) -> bytes:
    samples = array("h", [4000]) * round(SAMPLE_RATE * duration_seconds)
    for start_seconds, end_seconds in silence_ranges:
        start = round(SAMPLE_RATE * start_seconds)
        end = round(SAMPLE_RATE * end_seconds)
        samples[start:end] = array("h", [0]) * (end - start)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples.tobytes()


def test_short_audio_remains_one_unmodified_window():
    pcm = _pcm(9.16)

    windows = plan_silence_aware_chunks(
        pcm,
        sample_rate=SAMPLE_RATE,
        max_audio_seconds=30,
    )

    assert len(windows) == 1
    assert windows[0].audio_start_sample == 0
    assert windows[0].audio_end_sample == len(pcm) // 2
    assert windows[0].keep_start_sample == 0
    assert windows[0].keep_end_sample == len(pcm) // 2


def test_long_audio_prefers_latest_silence_near_target_boundary():
    pcm = _pcm(40, silence_ranges=((26.0, 27.0),))

    windows = plan_silence_aware_chunks(
        pcm,
        sample_rate=SAMPLE_RATE,
        max_audio_seconds=30,
    )

    first_boundary_seconds = windows[0].keep_end_sample / SAMPLE_RATE
    assert first_boundary_seconds == pytest.approx(26.5, abs=0.03)
    assert windows[0].cut_at_silence is True
    assert windows[1].keep_start_sample == windows[0].keep_end_sample


def test_forced_boundaries_are_bounded_and_logical_ranges_partition_audio():
    pcm = _pcm(65)

    windows = plan_silence_aware_chunks(
        pcm,
        sample_rate=SAMPLE_RATE,
        max_audio_seconds=30,
    )

    assert len(windows) == 3
    assert all(
        window.audio_end_sample - window.audio_start_sample <= 30 * SAMPLE_RATE
        for window in windows
    )
    assert all(window.cut_at_silence is False for window in windows)
    assert windows[0].keep_start_sample == 0
    assert windows[-1].keep_end_sample == len(pcm) // 2
    assert all(
        current.keep_end_sample == following.keep_start_sample
        for current, following in zip(windows, windows[1:], strict=False)
    )


def test_rejects_incomplete_pcm_sample():
    with pytest.raises(ValueError, match="complete 16-bit samples"):
        plan_silence_aware_chunks(
            b"\x00",
            sample_rate=SAMPLE_RATE,
            max_audio_seconds=30,
        )
