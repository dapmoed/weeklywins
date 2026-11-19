#!/usr/bin/env python3
"""Compare battery current samples within the on-device ASR workload intervals."""

import argparse
from datetime import datetime
import json
from pathlib import Path
from statistics import mean, median


def readings(path):
    by_time = {}
    for line in path.read_text().splitlines():
        sample = json.loads(line)
        updated = sample["UpdateTime"]
        read = sample["reader_unix_seconds"]
        if not isinstance(updated, int) or updated in by_time or not -1 <= read - updated <= 3:
            continue
        if sample["ExternalConnected"] is not False or sample["IsCharging"] is not False:
            raise ValueError("A fresh sample reported external power or charging.")
        current, voltage = sample["InstantAmperage"], sample["Voltage"]
        if (not isinstance(current, int) or not -5000 <= current <= 0
                or not isinstance(voltage, int) or not 3000 <= voltage <= 5000):
            raise ValueError("A fresh sample has invalid current or voltage.")
        by_time[updated] = -current * voltage / 1_000_000
    return by_time


def compare(workloads, samples):
    blocks = workloads["blocks"]
    expected = ["idle", "apple", "idle", "whisper", "idle", "whisper", "idle", "apple", "idle"]
    if [block["workload"] for block in blocks] != expected:
        raise ValueError("The workload report did not finish its matched sequence.")
    repeats = {block["transcriptions"] for block in blocks if block["workload"] != "idle"}
    if len(repeats) != 1 or min(repeats) <= 0:
        raise ValueError("Workload blocks must have the same positive transcription count.")

    results = []
    brightness = blocks[0]["before"]["brightness"]
    for block in blocks:
        for state in (block["before"], block["after"]):
            if state["charging_state"] != 1 or abs(state["brightness"] - brightness) > 0.01:
                raise ValueError("Workload report shows charging or a display brightness change.")
            if block["workload"] != "idle" and state["thermal_state"] != 0:
                raise ValueError("A workload did not stay in nominal thermal state at its endpoints.")
        start, finish = (datetime.fromisoformat(block[key]).timestamp() for key in ("started_at", "finished_at"))
        # Do not assign samples within one second of a transition between workloads.
        values = [watts for timestamp, watts in samples.items() if start + 1 <= timestamp <= finish - 1]
        if not values:
            raise ValueError(f"No fresh battery sample in {block['workload']} block starting at {block['started_at']}.")
        results.append({
            "workload": block["workload"],
            "elapsed_seconds": block["elapsed_seconds"],
            "sample_count": len(values),
            "observed_mean_watts": mean(values),
            "observed_watt_range": [min(values), max(values)],
        })
    for index in (1, 3, 5, 7):
        result = results[index]
        baseline = mean(results[neighbor]["observed_mean_watts"] for neighbor in (index - 1, index + 1))
        result["adjacent_idle_mean_watts"] = baseline
        result["estimated_extra_joules_per_transcription"] = (
            (result["observed_mean_watts"] - baseline) * result["elapsed_seconds"] / blocks[index]["transcriptions"]
        )
    times = sorted(samples)
    return {
        "fixture_sha256": workloads["fixture_sha256"],
        "transcriptions_per_workload_block": repeats.pop(),
        "median_refresh_seconds": median(right - left for left, right in zip(times, times[1:])),
        "blocks": results,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workloads", type=Path)
    parser.add_argument("samples", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(compare(json.loads(args.workloads.read_text()), readings(args.samples)), indent=2))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
