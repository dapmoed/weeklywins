#!/usr/bin/env python3
"""Generate controlled Russian ASR fixtures using the installed local voice."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def probe_audio(path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_entries",
            "format=duration:stream=codec_name,sample_rate,channels",
            "-of", "json", str(path),
        ],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def generate_fixture(reference, seconds, voice, staging):
    text = reference.read_text(encoding="utf-8")
    raw_audio = staging / (reference.stem + ".aiff")
    rate = 120
    for _ in range(8):
        subprocess.run(
            ["say", "-v", voice, "-r", str(rate), "-f", str(reference), "-o", str(raw_audio)],
            check=True, capture_output=True,
        )
        speech_seconds = float(probe_audio(raw_audio)["format"]["duration"])
        print(f"{reference.name} rate={rate} speech_seconds={speech_seconds:.3f}", file=sys.stderr)
        if seconds - 5 <= speech_seconds <= seconds - 0.25:
            break
        rate = max(1, round(rate * speech_seconds / (seconds - 2)))
    else:
        raise RuntimeError(f"Could not fit complete speech into {seconds} seconds")

    audio = staging / (reference.stem + ".m4a")
    subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error", "-i", str(raw_audio),
            "-af", "apad", "-t", str(seconds), "-ar", "16000", "-ac", "1",
            "-c:a", "aac", "-b:a", "48k", "-movflags", "+faststart", str(audio),
        ],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(audio), "-f", "null", "-"],
        check=True, capture_output=True,
    )
    probe = probe_audio(audio)
    stream = probe["streams"][0]
    container_seconds = float(probe["format"]["duration"])
    if stream["codec_name"] != "aac" or stream["sample_rate"] != "16000" or stream["channels"] != 1:
        raise RuntimeError(f"Unexpected audio format for {audio.name}")
    if abs(container_seconds - seconds) > 0.15:
        raise RuntimeError(f"Unexpected container duration for {audio.name}")
    shutil.copyfile(reference, staging / reference.name)
    return {
        "file": audio.name,
        "reference_file": reference.name,
        "voice": voice,
        "speech_rate": rate,
        "speech_seconds": speech_seconds,
        "container_seconds": container_seconds,
        "reference_words": len(re.findall(r"\w+", text)),
        "sha256": hashlib.sha256(audio.read_bytes()).hexdigest(),
        "bytes": audio.stat().st_size,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--voice", default="Milena")
    args = parser.parse_args()
    for command in ("say", "ffmpeg", "ffprobe"):
        if shutil.which(command) is None:
            parser.error(f"Required command is unavailable: {command}")
    args.output.mkdir(parents=True, exist_ok=True)
    references = Path(__file__).resolve().parent / "asr-fixtures"
    with tempfile.TemporaryDirectory(prefix="asr-fixtures-", dir=args.output) as temporary:
        staging = Path(temporary)
        fixtures = [
            generate_fixture(references / "ru-one-minute.txt", 60, args.voice, staging),
            generate_fixture(references / "ru-five-minute.txt", 300, args.voice, staging),
        ]
        for fixture in fixtures:
            for key in ("file", "reference_file"):
                name = fixture[key]
                os.replace(staging / name, args.output / name)
        metadata = staging / "fixtures.json"
        metadata.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(metadata, args.output / metadata.name)
    print(json.dumps(fixtures, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
