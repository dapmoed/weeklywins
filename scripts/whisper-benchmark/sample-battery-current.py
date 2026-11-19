#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pymobiledevice3==11.61.0", "cryptography==46.0.7"]
# ///
"""Read whole-device battery current over an existing iPhone Wi-Fi pairing."""

import argparse
import asyncio
import json
import time

from pymobiledevice3.lockdown import create_using_mobdev2
from pymobiledevice3.services.diagnostics import DiagnosticsService


BATTERY_FIELDS = (
    "InstantAmperage", "Voltage", "ExternalConnected", "IsCharging",
    "CurrentCapacity", "UpdateTime",
)


async def collect(device, seconds):
    async with asyncio.timeout(seconds + 15):
        async with await create_using_mobdev2(udid=device, timeout=8) as client:
            if not client.paired:
                raise RuntimeError("An existing trusted Wi-Fi pairing is required.")
            async with DiagnosticsService(lockdown=client) as diagnostics:
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    started = time.time()
                    async with asyncio.timeout(4):
                        raw = await diagnostics.ioregistry(ioclass="IOPMPowerSource")
                    finished = time.time()
                    if raw is None:
                        raise RuntimeError("The iPhone did not report battery state.")
                    sample = {key: raw.get(key) for key in BATTERY_FIELDS}
                    sample["reader_unix_seconds"] = round((started + finished) / 2, 6)
                    sample["poll_seconds"] = round(finished - started, 4)
                    print(json.dumps(sample), flush=True)
                    await asyncio.sleep(0.95)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="UDID of the already paired test device")
    parser.add_argument("seconds", type=int)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("seconds must be positive.")
    try:
        asyncio.run(collect(args.device, args.seconds))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
