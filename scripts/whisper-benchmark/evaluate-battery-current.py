#!/usr/bin/env python3
"""Compare iPhone battery telemetry within matched on-device ASR workloads."""

import argparse
from datetime import datetime
import json
from pathlib import Path
from statistics import mean, median


def fresh_records(path):
    by_time = {}
    for line in path.read_text().splitlines():
        sample = json.loads(line)
        updated = sample["UpdateTime"]
        read = sample["reader_unix_seconds"]
        if not isinstance(updated, int) or updated in by_time or not -1 <= read - updated <= 3:
            continue
        if sample["ExternalConnected"] is not False or sample["IsCharging"] is not False:
            raise ValueError("A fresh sample reported external power or charging.")
        by_time[updated] = sample
    return dict(sorted(by_time.items()))


def readings(path):
    watts = {}
    for updated, sample in fresh_records(path).items():
        current, voltage = sample["InstantAmperage"], sample["Voltage"]
        if (not isinstance(current, int) or not -5000 <= current <= 0
                or not isinstance(voltage, int) or not 3000 <= voltage <= 5000):
            raise ValueError("A fresh sample has invalid current or voltage.")
        watts[updated] = -current * voltage / 1_000_000
    return watts


def matched_blocks(workloads):
    blocks = workloads["blocks"]
    expected = ["idle", "apple", "idle", "whisper", "idle", "whisper", "idle", "apple", "idle"]
    if [block["workload"] for block in blocks] != expected:
        raise ValueError("The workload report did not finish its matched sequence.")
    repeats = {block["transcriptions"] for block in blocks if block["workload"] != "idle"}
    if len(repeats) != 1 or min(repeats) <= 0:
        raise ValueError("Workload blocks must have the same positive transcription count.")

    brightness = blocks[0]["before"]["brightness"]
    for block in blocks:
        for state in (block["before"], block["after"]):
            if state["charging_state"] != 1 or abs(state["brightness"] - brightness) > 0.01:
                raise ValueError("Workload report shows charging or a display brightness change.")
            if block["workload"] != "idle" and state["thermal_state"] != 0:
                raise ValueError("A workload did not stay in nominal thermal state at its endpoints.")
    return blocks, repeats.pop()


def interval(block):
    return tuple(datetime.fromisoformat(block[key]).timestamp() for key in ("started_at", "finished_at"))


def compare(workloads, samples):
    blocks, repeats = matched_blocks(workloads)
    results = []
    for block in blocks:
        start, finish = interval(block)
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
        "transcriptions_per_workload_block": repeats,
        "median_refresh_seconds": median(right - left for left, right in zip(times, times[1:])),
        "blocks": results,
    }


def cumulative_energy(samples, first, last):
    duration = last - first
    if duration <= 0:
        raise ValueError("The counter interval is empty.")
    updates = samples[first]["AccumulatedBatteryDischarge"] - samples[last]["AccumulatedBatteryDischarge"]
    seconds = samples[last]["BatteryDischargeAccumulatorCount"] - samples[first]["BatteryDischargeAccumulatorCount"]
    if updates < 0 or abs(seconds - duration) > max(3, duration * 0.10):
        raise ValueError("The discharge counter reset or did not advance at its expected cadence.")
    return updates / 1000, duration


def compare_cumulative(workloads, samples):
    blocks, repeats = matched_blocks(workloads)
    for sample in samples.values():
        if (not isinstance(sample.get("AccumulatedBatteryDischarge"), int)
                or not isinstance(sample.get("BatteryDischargeAccumulatorCount"), int)
                or sample.get("PowerTelemetryErrorCount") != 0):
            raise ValueError("A fresh sample has missing or invalid cumulative telemetry.")
    times = list(samples)
    if len(times) < 2:
        raise ValueError("At least two fresh counter readings are required.")
    for first, last in zip(times, times[1:]):
        if (samples[last]["AccumulatedBatteryDischarge"] > samples[first]["AccumulatedBatteryDischarge"]
                or samples[last]["BatteryDischargeAccumulatorCount"] < samples[first]["BatteryDischargeAccumulatorCount"]):
            raise ValueError("The discharge counter reset within the sample sequence.")

    def contained_times(start, end):
        return [time for time in times if start <= time <= end]

    baseline = {}
    for index in range(0, len(blocks), 2):
        start, end = interval(blocks[index])
        idle_times = contained_times(start + 3, end - 1)
        if len(idle_times) < 2:
            raise ValueError(f"Idle block {index} needs two fresh counter readings.")
        baseline[index] = cumulative_energy(samples, idle_times[0], idle_times[-1])

    results = []
    for index in (1, 3, 5, 7):
        start, end = interval(blocks[index])
        prior_start, _ = interval(blocks[index - 1])
        _, next_end = interval(blocks[index + 1])
        before = contained_times(prior_start, start - 1)
        after = contained_times(end + 1, next_end)
        if not before or not after:
            raise ValueError(f"Workload block {index} has no counter readings that bracket it within its adjacent idle blocks.")
        first, last = before[-1], after[0]
        energy, duration = cumulative_energy(samples, first, last)
        before_joules, before_seconds = baseline[index - 1]
        after_joules, after_seconds = baseline[index + 1]
        idle_watts = (before_joules + after_joules) / (before_seconds + after_seconds)
        results.append({
            "workload": blocks[index]["workload"],
            "workload_seconds": blocks[index]["elapsed_seconds"],
            "counter_bracket_unix_seconds": [first, last],
            "total_discharge_joules": energy,
            "idle_watts_before": before_joules / before_seconds,
            "idle_watts_after": after_joules / after_seconds,
            "adjacent_idle_mean_watts": idle_watts,
            "estimated_extra_joules_per_transcription": (energy - idle_watts * duration) / repeats,
        })
    return {
        "fixture_sha256": workloads["fixture_sha256"],
        "transcriptions_per_workload_block": repeats,
        "median_refresh_seconds": median(right - left for left, right in zip(times, times[1:])),
        "blocks": results,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workloads", type=Path)
    parser.add_argument("samples", type=Path)
    parser.add_argument("--cumulative", action="store_true", help="Measure the change in the device's discharge counter.")
    args = parser.parse_args()
    try:
        workloads = json.loads(args.workloads.read_text())
        if args.cumulative:
            result = compare_cumulative(workloads, fresh_records(args.samples))
        else:
            result = compare(workloads, readings(args.samples))
        print(json.dumps(result, indent=2))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
