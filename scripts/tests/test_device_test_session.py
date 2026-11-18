import argparse
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[1] / "device-test-session.py"
spec = importlib.util.spec_from_file_location("device_test_session", path)
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class FakeSession(session.DeviceSession):
    def __init__(self, args):
        super().__init__(args)
        self.actions = []
        self.marker_enabled = False
        self.fail_active = False
        self.fail_restore = False
        self.recording = False

    def assert_no_capture(self):
        self.actions.append("check-capture")
        if self.recording:
            raise RuntimeError("Recording is active")

    def write_marker(self, enabled):
        self.assert_checkpoint_exists()
        self.marker_enabled = enabled
        self.actions.append(("marker", enabled))

    def assert_checkpoint_exists(self):
        if not self.args.state.exists():
            raise AssertionError("The checkpoint must precede a remote change")

    def launch(self, restart=False):
        self.actions.append(("launch", restart))
        return 42

    def wait_status(self, process_id, active):
        if active and self.fail_active:
            raise RuntimeError("Awake acknowledgement failed")
        if not active and self.fail_restore:
            raise RuntimeError("Restoration acknowledgement failed")
        return {"active": active, "idleTimerDisabled": active, "processID": process_id}


class DeviceTestSessionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.args = argparse.Namespace(state=Path(self.directory.name) / "state.json", device="phone")
        self.session = FakeSession(self.args)

    def testCheckpointPrecedesRemoteChanges(self):
        self.session.begin()
        self.assertEqual(json.loads(self.args.state.read_text())["device"], "phone")
        self.assertTrue(self.session.marker_enabled)
        self.assertEqual(self.session.actions[0], "check-capture")

    def testFailedBeginRestoresTheAppAndRemovesCheckpoint(self):
        self.session.fail_active = True
        with self.assertRaises(RuntimeError):
            self.session.begin()
        self.assertFalse(self.session.marker_enabled)
        self.assertFalse(self.args.state.exists())

    def testFailedTestCommandStillEndsItsOwnedSession(self):
        with patch.object(session, "execute", return_value=7):
            self.assertEqual(self.session.run(["test-command"]), 7)
        self.assertFalse(self.session.marker_enabled)
        self.assertFalse(self.args.state.exists())

    def testInterruptedCommandStillEndsItsOwnedSession(self):
        with patch.object(session, "execute", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.session.run(["test-command"])
        self.assertFalse(self.session.marker_enabled)
        self.assertFalse(self.args.state.exists())

    def testNestedRunResumesTheOuterSession(self):
        self.session.begin()
        with patch.object(session, "execute", return_value=0):
            self.assertEqual(self.session.run(["test-command"]), 0)
        self.assertTrue(self.session.marker_enabled)
        self.assertTrue(self.args.state.exists())
        self.session.end()
        self.assertFalse(self.args.state.exists())

    def testNestedCLIUsesTheInheritedDeviceSession(self):
        entry = [sys.executable, str(Path(__file__).resolve()), "fake-cli", "run",
                 "--device", "phone", "--state", str(self.args.state), "--command"]
        command = entry + entry + [sys.executable, "-c", "pass"]
        process = subprocess.Popen(command, start_new_session=True, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        try:
            status = process.wait(timeout=5)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        self.assertEqual(status, 0)
        self.assertFalse(self.args.state.exists())

    def testFailedEndKeepsTheRecoveryCheckpoint(self):
        self.session.begin()
        self.session.fail_restore = True
        with self.assertRaises(RuntimeError):
            self.session.end()
        self.assertFalse(self.session.marker_enabled)
        self.assertTrue(self.args.state.exists())

    def testActiveCapturePreventsAnAppRestart(self):
        self.session.recording = True
        with self.assertRaises(RuntimeError):
            self.session.begin()
        self.assertFalse(self.args.state.exists())
        self.assertNotIn(("launch", True), self.session.actions)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "fake-cli":
        sys.argv.pop(1)
        session.DeviceSession = FakeSession
        raise SystemExit(session.main())
    else:
        unittest.main()
