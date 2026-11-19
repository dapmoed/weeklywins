#!/usr/bin/env python3
"""Prepare the adult life stories from spokencorpora.ru for local ASR evaluation."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from html import unescape
import json
from pathlib import Path
import re
import subprocess
from urllib.request import urlopen


BASE = "https://spokencorpora.ru"


def download(path):
    with urlopen(BASE + path, timeout=30) as response:
        return response.read()


def grid(path):
    page = download(path).decode()
    literal = re.search(r"datastr: '(\{[^\n]*\})'", page)
    if literal is None:
        raise ValueError(f"Missing transcript or index data: {path}")
    return json.loads(re.sub(r"\\(['\\])", r"\1", literal[1]))["rows"]


def reference_text(rows):
    # Remove HTML decoration before unescaping the corpus's angle-bracket annotations.
    text = " ".join(unescape(re.sub(r"<[^>]+>", "", row["cell"][2])) for row in rows)
    text = re.sub(r"\(\d+\.\d+\)|\bНРЗБ\d*\b", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"<([^<>|]+)\|[^<>]+>", r"\1", text)
    return " ".join(text.split()) + "\n"


def prepare(output, key, catalog_seconds):
    if not re.fullmatch(r"Sib_\d{2}-[fm]", key):
        raise ValueError(f"Unexpected story identifier: {key!r}")
    audio = output / f"{key}.m4a"
    reference = output / f"{key}.txt"
    text = reference_text(grid(f"/showtrans.py?file=01life/{key}&type=3"))
    source = download(f"/data/01life/sound/mp3/{key}.mp3")
    subprocess.run([
        "ffmpeg", "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", "16000",
        "-c:a", "aac", "-b:a", "48k", str(audio),
    ], input=source, check=True)
    duration = float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(audio),
    ]))
    if not 0 < duration <= 300 or abs(duration - catalog_seconds) >= 2:
        raise ValueError(f"{key}: expected {catalog_seconds:.2f} s, prepared {duration:.2f} s")
    reference.write_text(text, encoding="utf-8")
    return {
        "file": audio.name, "reference_file": reference.name,
        "sha256": sha256(audio.read_bytes()).hexdigest(),
        "reference_sha256": sha256(reference.read_bytes()).hexdigest(),
        "duration_seconds": duration,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory for local audio and references")
    args = parser.parse_args()
    rows = grid("/showcorpus.py?dir=01life")
    stories = [(row["cell"][0], float(row["cell"][3])) for row in rows]
    eligible = [(key, seconds) for key, seconds in stories if 0 < seconds <= 300]
    if not eligible:
        raise ValueError("The corpus has no recordings within the five-minute limit")
    args.output.mkdir(mode=0o700, parents=True)
    with ThreadPoolExecutor(4) as pool:
        records = list(pool.map(lambda story: prepare(args.output, *story), eligible))
    (args.output / "fixtures.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(records)} of {len(stories)} recordings, {sum(r['duration_seconds'] for r in records):.2f} s.")


if __name__ == "__main__":
    main()
