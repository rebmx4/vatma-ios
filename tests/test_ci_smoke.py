"""Run the real smoke script with fake Apple tools; no Mac or network is needed."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEMP_ROOT = ROOT / "out/test-tmp"
TEMP_ROOT.mkdir(parents=True, exist_ok=True)
if os.name == "nt":
    git = shutil.which("git")
    BASH = str(Path(git).parents[1] / "bin/bash.exe") if git else None
else:
    BASH = shutil.which("bash")


@unittest.skipUnless(BASH and Path(BASH).is_file(), "Bash is required")
class SmokeScriptTests(unittest.TestCase):
    def run_smoke(self, failed_device=""):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as temporary:
            root = Path(temporary)
            (root / "release").mkdir()
            (root / "ATMA.xcodeproj").mkdir()
            binary = root / "bin"
            binary.mkdir()
            for name in ("ci.sh", "simulators.py"):
                shutil.copyfile(ROOT / "release" / name, root / "release" / name)
            payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-" + version: [
                {"name": "iPhone test", "udid": "phone" + suffix, "isAvailable": True},
                {"name": "iPad test", "udid": "tablet" + suffix, "isAvailable": True}]
                for version, suffix in (("26-4", ""), ("26-5", "-newer"))}}
            (root / "devices.json").write_text(json.dumps(payload), encoding="utf-8")
            commands = {
                "python3": 'exec "$ATMA_TEST_PYTHON" "$@"\n',
                "xcrun": '''if [[ "$1 $2 $3" = "--sdk iphonesimulator --show-sdk-version" ]]; then
  printf '26.4\\n'
elif [[ "$1 $2" = "simctl list" ]]; then
  cat "$CM_BUILD_DIR/devices.json"
elif [[ "$1 $2" = "xcresulttool export" ]]; then
  printf 'export %s\\n' "$*" >> "$CM_BUILD_DIR/calls.log"
fi
''',
                "xcodebuild": '''printf 'test %s\\n' "$*" >> "$CM_BUILD_DIR/calls.log"
arguments="$*"
while [[ $# -gt 0 ]]; do
  if [[ "$1" = "-resultBundlePath" ]]; then mkdir -p "$2"; fi
  shift
done
if [[ -n "$ATMA_TEST_FAIL" && "$arguments" = *"id=$ATMA_TEST_FAIL"* ]]; then exit 65; fi
''',
            }
            for name, body in commands.items():
                command = binary / name
                command.write_text("#!/bin/bash\nset -eu\n" + body, encoding="utf-8", newline="\n")
                command.chmod(0o755)
            environment = dict(os.environ, CM_BUILD_DIR=root.as_posix(),
                               ATMA_TEST_PYTHON=Path(sys.executable).as_posix(),
                               ATMA_TEST_FAIL=failed_device, ATMA_TEST_BIN=binary.as_posix(),
                               HOME=root.as_posix(),
                               TMPDIR=root.as_posix(), TEMP=root.as_posix(), TMP=root.as_posix(),
                               BASH_ENV="", ENV="", HISTFILE="/dev/null")
            shell = 'export PATH="$ATMA_TEST_BIN:$PATH"; source release/ci.sh smoke'
            result = subprocess.run([BASH, "--noprofile", "--norc", "-c", shell],
                                    cwd=root, env=environment, capture_output=True, text=True, timeout=30)
            calls = (root / "calls.log").read_text(encoding="utf-8").splitlines()
            marker = root / "out/verified-commit.txt"
            return result, calls, marker.read_text(encoding="utf-8").strip() if marker.exists() else None

    def test_both_devices_run_before_revision_is_verified(self):
        result, calls, revision = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        tests = [line for line in calls if line.startswith("test ")]
        self.assertEqual(len(tests), 2)
        for command in tests:
            self.assertIn("-configuration Release", command)
            self.assertIn("ENABLE_TESTABILITY=YES", command)
            self.assertIn("ONLY_ACTIVE_ARCH=YES", command)
        self.assertIn("id=tablet", tests[0])
        self.assertIn("-only-testing:BrowserNativeUITests", tests[0])
        self.assertIn("id=phone", tests[1])
        self.assertNotIn("-only-testing:", tests[1])
        self.assertNotIn("-newer", " ".join(tests))
        expected = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        self.assertEqual(revision, expected)

    def test_ipad_failure_stops_phone_and_does_not_verify_revision(self):
        result, calls, revision = self.run_smoke("tablet")
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(len([line for line in calls if line.startswith("test ")]), 1)
        self.assertTrue(any(line.startswith("export ") and "ATMA-ipad.xcresult" in line for line in calls))
        self.assertIsNone(revision)

    def test_phone_failure_does_not_verify_revision_and_exports_ipad_evidence(self):
        result, calls, revision = self.run_smoke("phone")
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertEqual(len([line for line in calls if line.startswith("test ")]), 2)
        self.assertTrue(any(line.startswith("export ") and "ATMA-ipad.xcresult" in line for line in calls))
        self.assertIsNone(revision)


if __name__ == "__main__":
    unittest.main()
