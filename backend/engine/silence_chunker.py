"""Dependency-free silence-aware chunk planning for 16-kHz PCM audio."""

from __future__ import annotations

import math
import sys
from array import array
from dataclasses import dataclass

PCM_SAMPLE_WIDTH_BYTES = 2


@dataclass(frozen=True, slots=True)
class ChunkWindow:
    """Audio sent to the model and the non-overlapping range it owns."""

    audio_start_sample: int
    audio_end_sample: int
    keep_start_sample: int
    keep_end_sample: int
    cut_at_silence: bool


def _decode_pcm16le(pcm: bytes) -> array[int]:
    if len(pcm) % PCM_SAMPLE_WIDTH_BYTES:
        raise ValueError("PCM input must contain complete 16-bit samples.")

    samples = array("h")
    samples.frombytes(pcm)
    if samples.itemsize != PCM_SAMPLE_WIDTH_BYTES:
        raise RuntimeError("This platform does not provide 16-bit signed short arrays.")
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def _latest_silence_midpoint(
    samples: array[int],
    *,
    search_start: int,
    search_end: int,
    sample_rate: int,
    silence_threshold_dbfs: float,
    min_silence_seconds: float,
) -> int | None:
    """Return the latest qualifying silence midpoint in the search range."""

    analysis_frame_samples = max(1, round(sample_rate * 0.02))
    min_silence_samples = max(1, round(sample_rate * min_silence_seconds))
    silence_amplitude = round(32767 * math.pow(10.0, silence_threshold_dbfs / 20.0))
    silence_power_limit = silence_amplitude * silence_amplitude

    latest_midpoint: int | None = None
    silent_run_start: int | None = None
    silent_run_end = search_start

    for frame_start in range(search_start, search_end, analysis_frame_samples):
        frame_end = min(frame_start + analysis_frame_samples, search_end)
        frame = samples[frame_start:frame_end]
        sum_squares = sum(sample * sample for sample in frame)
        is_silent = sum_squares <= silence_power_limit * len(frame)

        if is_silent:
            if silent_run_start is None:
                silent_run_start = frame_start
            silent_run_end = frame_end
            continue

        if (
            silent_run_start is not None
            and silent_run_end - silent_run_start >= min_silence_samples
        ):
            latest_midpoint = (silent_run_start + silent_run_end) // 2
        silent_run_start = None

    if (
        silent_run_start is not None
        and silent_run_end - silent_run_start >= min_silence_samples
    ):
        latest_midpoint = (silent_run_start + silent_run_end) // 2

    return latest_midpoint


def plan_silence_aware_chunks(
    pcm: bytes,
    *,
    sample_rate: int,
    max_audio_seconds: float,
    overlap_seconds: float = 0.8,
    silence_search_seconds: float = 6.0,
    min_silence_seconds: float = 0.3,
    silence_threshold_dbfs: float = -35.0,
) -> tuple[ChunkWindow, ...]:
    """Plan bounded model requests with silence-preferred logical boundaries.

    Adjacent model requests overlap for acoustic context. ``keep_*`` ranges
    partition the original recording without overlap; word timestamps are used
    by the caller to retain each decoded word from exactly one partition.
    """

    if sample_rate <= 0:
        raise ValueError("sample_rate must be greater than zero.")
    if max_audio_seconds <= 0:
        raise ValueError("max_audio_seconds must be greater than zero.")
    if overlap_seconds < 0:
        raise ValueError("overlap_seconds cannot be negative.")
    if silence_search_seconds <= 0:
        raise ValueError("silence_search_seconds must be greater than zero.")
    if min_silence_seconds <= 0:
        raise ValueError("min_silence_seconds must be greater than zero.")
    if silence_threshold_dbfs >= 0:
        raise ValueError("silence_threshold_dbfs must be negative.")

    samples = _decode_pcm16le(pcm)
    total_samples = len(samples)
    max_audio_samples = max(1, round(sample_rate * max_audio_seconds))
    overlap_samples = round(sample_rate * overlap_seconds)
    if overlap_samples * 2 >= max_audio_samples:
        raise ValueError("overlap_seconds must be less than half max_audio_seconds.")

    if total_samples <= max_audio_samples:
        return (
            ChunkWindow(
                audio_start_sample=0,
                audio_end_sample=total_samples,
                keep_start_sample=0,
                keep_end_sample=total_samples,
                cut_at_silence=False,
            ),
        )

    logical_span = max_audio_samples - (2 * overlap_samples)
    search_samples = min(round(sample_rate * silence_search_seconds), logical_span // 2)
    minimum_progress = max(1, logical_span - search_samples)

    windows: list[ChunkWindow] = []
    keep_start = 0
    while keep_start < total_samples:
        audio_start = max(0, keep_start - overlap_samples)
        if total_samples - audio_start <= max_audio_samples:
            windows.append(
                ChunkWindow(
                    audio_start_sample=audio_start,
                    audio_end_sample=total_samples,
                    keep_start_sample=keep_start,
                    keep_end_sample=total_samples,
                    cut_at_silence=False,
                )
            )
            break

        ideal_boundary = keep_start + logical_span
        search_start = keep_start + minimum_progress
        silence_boundary = _latest_silence_midpoint(
            samples,
            search_start=search_start,
            search_end=ideal_boundary,
            sample_rate=sample_rate,
            silence_threshold_dbfs=silence_threshold_dbfs,
            min_silence_seconds=min_silence_seconds,
        )
        keep_end = silence_boundary or ideal_boundary
        audio_end = min(total_samples, keep_end + overlap_samples)

        windows.append(
            ChunkWindow(
                audio_start_sample=audio_start,
                audio_end_sample=audio_end,
                keep_start_sample=keep_start,
                keep_end_sample=keep_end,
                cut_at_silence=silence_boundary is not None,
            )
        )
        keep_start = keep_end

    return tuple(windows)
