#!/usr/bin/env python3
"""Align a video of a physical Action Button press with the saved WeeklyWins audio."""

import argparse
import json
from pathlib import Path
import subprocess
from statistics import median

import numpy as np


RATE = 8000
WINDOW_SAMPLES = RATE
MAX_ALIGNMENT_SPREAD_SECONDS = 0.04


def frame_times(path, stream, count=None):
    command = ["ffprobe", "-v", "error", "-select_streams", stream]
    if count is not None:
        command.extend(["-read_intervals", f"%+#{count}"])
    result = subprocess.check_output([
        *command, "-show_frames", "-show_entries", "frame=best_effort_timestamp_time",
        "-of", "json", str(path),
    ])
    frames = json.loads(result)["frames"]
    return [float(frame["best_effort_timestamp_time"]) for frame in frames]


def read_audio(path):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
        "-ac", "1", "-ar", str(RATE), "-f", "f32le", "pipe:1",
    ])
    # Differences remove DC and reduce the effect of a low-frequency room hum.
    return np.diff(np.frombuffer(data, dtype="<f4").astype(np.float64))


def match_offsets(reference, captured):
    if len(captured) < 3 * RATE or len(reference) < len(captured):
        raise ValueError("Use at least three seconds of overlapping audio and film the whole recording.")
    fft_size = 1 << (len(reference) + WINDOW_SAMPLES - 1).bit_length()
    spectrum = np.fft.rfft(reference, fft_size)
    wins = len(reference) - WINDOW_SAMPLES + 1
    sums = np.concatenate(([0], np.cumsum(reference)))
    squares = np.concatenate(([0], np.cumsum(reference * reference)))
    window_sums = sums[WINDOW_SAMPLES:] - sums[:-WINDOW_SAMPLES]
    window_squares = squares[WINDOW_SAMPLES:] - squares[:-WINDOW_SAMPLES]
    reference_energy = np.maximum(window_squares - window_sums**2 / WINDOW_SAMPLES, 0)
    offsets = []
    for start in range(0, min(len(captured), 8 * RATE) - WINDOW_SAMPLES + 1, WINDOW_SAMPLES):
        window = captured[start:start + WINDOW_SAMPLES].copy()
        window -= window.mean()
        expected_energy = float(window @ window)
        if expected_energy < 1e-8:
            continue
        convolution = np.fft.irfft(spectrum * np.conj(np.fft.rfft(window, fft_size)), fft_size)[:wins]
        denominator = np.sqrt(reference_energy * expected_energy)
        correlation = np.divide(np.abs(convolution), denominator, out=np.zeros(wins), where=denominator > 1e-8)
        peak = int(correlation.argmax())
        strength = float(correlation[peak])
        # Ignore nearby echoes when deciding whether another placement is plausible.
        radius = round(RATE * MAX_ALIGNMENT_SPREAD_SECONDS)
        correlation[max(0, peak - radius):peak + radius + 1] = 0
        if strength >= 0.30 and strength - float(correlation.max()) >= 0.06:
            offsets.append((peak - start) / RATE)
    if len(offsets) < 2 or max(offsets) - min(offsets) > MAX_ALIGNMENT_SPREAD_SECONDS:
        raise ValueError("Audio alignment is ambiguous. Use distinct shared sounds, such as speech or varied taps.")
    return offsets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path, help="external camera video with the iPhone and shared ambient audio")
    parser.add_argument("recording", type=Path, help="the original saved WeeklyWins audio")
    parser.add_argument("--press-frame", required=True, type=int,
                        help="zero-based first frame showing the button depressed")
    args = parser.parse_args()
    video_times = frame_times(args.video, "v:0")
    if not 0 < args.press_frame < len(video_times):
        parser.error("press-frame needs a preceding video frame and must be within the clip.")
    press_before, press_by = video_times[args.press_frame - 1:args.press_frame + 1]
    if press_by <= press_before:
        parser.error("The two frames around the press must have increasing timestamps.")
    try:
        audio_times = frame_times(args.video, "a:0", count=8)
        if not audio_times:
            parser.error("The external video needs an audio track.")
        offsets = match_offsets(read_audio(args.video), read_audio(args.recording))
    except ValueError as error:
        parser.error(str(error))
    audio_start = audio_times[0]
    earliest_capture = audio_start + min(offsets)
    latest_capture = audio_start + max(offsets)
    print(json.dumps({
        "press_frame": args.press_frame,
        "press_bracket_video_seconds": [press_before, press_by],
        "capture_video_seconds": round(audio_start + median(offsets), 4),
        "aligned_windows": len(offsets),
        "alignment_spread_seconds": round(max(offsets) - min(offsets), 4),
        "latency_bracket_seconds": [round(earliest_capture - press_by, 4), round(latest_capture - press_before, 4)],
    }, indent=2))


if __name__ == "__main__":
    main()
