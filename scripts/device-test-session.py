#!/usr/bin/env python3
"""Keep WeeklyWins awake across physical tests without changing system Auto-Lock."""

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def execute(command, **options):
    with subprocess.Popen(command, **options) as process:
        try:
            return process.wait()
        except BaseException:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise


class DeviceSession:
    bundle = "com.weeklywins.app"
    marker = "Library/Application Support/WeeklyWinsDeviceTestSession.json"
    status = "Library/Application Support/WeeklyWinsDeviceTestSession.status.json"

    def __init__(self, args):
        self.args = args
        self.logs = args.state.with_suffix(".logs")
        self.logs.mkdir(parents=True, exist_ok=True)
        self.environment = os.environ.copy()
        self.environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"

    def device(self, arguments, name, allow_missing=False):
        report = self.logs / (name + ".json")
        log = self.logs / (name + ".log")
        command = ["xcrun", "devicectl", "device", *arguments[:2], "--device", self.args.device,
                   "--json-output", str(report), "--quiet", *arguments[2:]]
        with log.open("wb") as output:
            status = execute(command, env=self.environment, stdout=output, stderr=subprocess.STDOUT)
        if status:
            error = log.read_text(errors="replace")
            if allow_missing and ("No such file or directory" in error or "Code=260" in error):
                return None
            raise RuntimeError(f"Device operation {name} failed. See {log}")
        return json.loads(report.read_text()).get("result", {})

    def copy_from(self, source, destination, name, allow_missing=False):
        return self.device(["copy", "from", "--domain-type", "appDataContainer",
                            "--domain-identifier", self.bundle, "--source", source,
                            "--destination", str(destination)], name, allow_missing)

    def write_marker(self, enabled):
        path = self.logs / "marker.json"
        path.write_text(json.dumps({"enabled": enabled}))
        self.device(["copy", "to", "--domain-type", "appDataContainer", "--domain-identifier", self.bundle,
                     "--source", str(path), "--destination", self.marker], "marker-copy")

    def assert_no_capture(self):
        path = self.logs / "recordings.json"
        result = self.copy_from("Documents/recordings.json", path, "recordings-copy", allow_missing=True)
        if result is None:
            return
        rows = json.loads(path.read_text())
        if any(row.get("deletedAt") is None and row.get("state") == "recording" for row in rows):
            raise RuntimeError("Finish the active recording before starting the test session")

    def launch(self, restart=False):
        arguments = ["process", "launch"]
        if restart:
            arguments.append("--terminate-existing")
        arguments.append(self.bundle)
        result = self.device(arguments, "launch")
        process = result.get("process", result)
        return int(process["processIdentifier"])

    def wait_status(self, process_id, active):
        destination = self.logs / "awake-status.json"
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            result = self.copy_from(self.status, destination, "status-copy", allow_missing=True)
            if result is not None:
                status = json.loads(destination.read_text())
                if status.get("processID") == process_id and status.get("active") == active:
                    if not active or status.get("idleTimerDisabled") is True:
                        return status
            time.sleep(0.5)
        raise RuntimeError("The debug app did not confirm its awake-session state")

    def checkpoint(self):
        state = json.loads(self.args.state.read_text())
        if state["device"] != self.args.device:
            raise RuntimeError("The session belongs to another device. Use its --state file")
        return state

    def begin(self):
        if self.args.state.exists():
            self.checkpoint()
            return self.keep()
        self.assert_no_capture()
        state = {"device": self.args.device, "started_at": datetime.now(timezone.utc).isoformat()}
        pending = self.args.state.with_suffix(".pending")
        pending.write_text(json.dumps(state, indent=2) + "\n")
        os.replace(pending, self.args.state)
        try:
            self.write_marker(True)
            status = self.wait_status(self.launch(restart=True), True)
        except BaseException:
            self.end()
            raise
        print("Test session awake", status, flush=True)

    def keep(self):
        self.checkpoint()
        self.write_marker(True)
        status = self.wait_status(self.launch(), True)
        print("Test session resumed", status, flush=True)

    def end(self):
        if not self.args.state.exists():
            return
        self.checkpoint()
        self.write_marker(False)
        status = self.wait_status(self.launch(), False)
        self.args.state.unlink()
        print("Test session ended", status, flush=True)

    def run(self, command):
        owned = not self.args.state.exists()
        self.begin()
        try:
            return execute(command, env=self.environment)
        finally:
            if owned:
                self.end()
            else:
                self.keep()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["begin", "keep", "end", "run"])
    parser.add_argument("--device", required=True)
    parser.add_argument("--state", type=Path, default=Path("/private/tmp/weeklywins-device-test-session.json"))
    parser.add_argument("--command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "run" and not args.command:
        parser.error("run requires --command followed by the test command")
    args.state = args.state.resolve()
    args.state.parent.mkdir(parents=True, exist_ok=True)
    with args.state.with_suffix(".lock").open("a") as lock:
        owner = inherited_owner(args)
        if owner is None:
            fcntl.flock(lock, fcntl.LOCK_EX)
            owner = os.getpid()
        session = DeviceSession(args)
        session.environment["WEEKLYWINS_DEVICE_SESSION_STATE"] = str(args.state.resolve())
        session.environment["WEEKLYWINS_DEVICE_SESSION_OWNER"] = str(owner)
        if args.action == "run":
            return session.run(args.command)
        getattr(session, args.action)()
    return 0


def inherited_owner(args):
    path = os.environ.get("WEEKLYWINS_DEVICE_SESSION_STATE")
    value = os.environ.get("WEEKLYWINS_DEVICE_SESSION_OWNER", "")
    if path != str(args.state.resolve()) or not value.isdigit() or not args.state.exists():
        return None
    owner = int(value)
    try:
        os.kill(owner, 0)
    except (ProcessLookupError, PermissionError):
        return None
    return owner


if __name__ == "__main__":
    def terminate(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, terminate)
    raise SystemExit(main())
