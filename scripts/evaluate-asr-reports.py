#!/usr/bin/env python3
"""Measure word errors against the controlled ASR fixture references."""

import argparse
import json
from pathlib import Path
import re


def words(text):
    return re.findall(r"\w+", text.lower().replace("ё", "е"))


def word_errors(reference, transcript):
    previous = list(range(len(transcript) + 1))
    for index, expected in enumerate(reference, 1):
        current = [index]
        for position, actual in enumerate(transcript, 1):
            substitution = previous[position - 1] + int(expected != actual)
            deletion = previous[position] + 1
            insertion = current[position - 1] + 1
            current.append(min(substitution, deletion, insertion))
        previous = current
    return previous[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", required=True, type=Path)
    parser.add_argument("reports", nargs="+", type=Path)
    args = parser.parse_args()
    fixtures = json.loads((args.fixtures / "fixtures.json").read_text())
    summaries = []
    for path in args.reports:
        report = json.loads(path.read_text())
        fixture = next(item for item in fixtures if item["file"] == report["fixture"])
        if report["sha256"] != fixture["sha256"]:
            raise ValueError(f"Fixture identity differs in {path.name}")
        reference = words((args.fixtures / fixture["reference_file"]).read_text())
        transcript = words(report.get("transcript", ""))
        errors = word_errors(reference, transcript)
        ending = " ".join(transcript[-20:])
        summaries.append({
            "report": path.name,
            "provider": report["provider"],
            "fixture": report["fixture"],
            "reference_words": len(reference),
            "transcript_words": len(transcript),
            "word_errors": errors,
            "word_error_rate": errors / len(reference),
            "ending_marker_present": re.search(r"\bпоследн\w+\s+замет\w+\b", ending) is not None,
            "processing_seconds": report.get("processing_seconds"),
            "audio_seconds": report["audio_seconds"],
            "network_before": report.get("network_before"),
            "error": report.get("error"),
        })
    print(json.dumps(summaries, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
