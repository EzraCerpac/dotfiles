"""The bootstrap hook passes its Tailscale key only through a private file."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "dots/hooks/bootstrap.d/90-Tailscale"
KEY = "fixture-key"


@requires("jq")
class TailscaleEnrollmentTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.cli = self.base / "tailscale"
        self.cli.write_text(
            """#!/usr/bin/env python3
import json
import os
import stat
import sys
from pathlib import Path

assert "SETUP_TAILSCALE_AUTH_KEY" not in os.environ
assert "DOTS_BUNDLE_FD" not in os.environ
try:
    os.fstat(int(os.environ["FIXTURE_FD"]))
except OSError:
    pass
else:
    raise AssertionError("bundle descriptor leaked to Tailscale")

if sys.argv[1:] == ["status", "--json"]:
    print(json.dumps({"BackendState": os.environ["FIXTURE_STATE"]}))
    sys.exit(0)

assert sys.argv[1] == "up"
assert len(sys.argv) == 3 and sys.argv[2].startswith("--auth-key=file:")
key_file = Path(sys.argv[2].split(":", 1)[1])
assert stat.S_IMODE(key_file.stat().st_mode) == 0o600
assert key_file.read_text() == "fixture-key\\n"
Path(os.environ["FIXTURE_CALL"]).write_text(str(key_file))
if os.environ["FIXTURE_EXPIRED"] == "1":
    print("expired auth key: " + key_file.read_text(), file=sys.stderr)
    sys.exit(1)
"""
        )
        self.cli.chmod(0o755)
        self.call = self.base / "call"

    def run_hook(self, state: str, *, expired: bool = False, key: str = KEY) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryFile() as bundle:
            bundle.write(json.dumps({"tailscale_auth_key": key}).encode())
            bundle.seek(0)
            fd = bundle.fileno()
            env = {
                **os.environ,
                "DOTS_ROOT": str(ROOT),
                "DOTS_BUNDLE_FD": str(fd),
                "DOTS_PRIVATE_READY": "1",
                "TAILSCALE_CLI": str(self.cli),
                "CI": "1",
                "SETUP_TAILSCALE_AUTH_KEY": "",
                "FIXTURE_FD": str(fd),
                "FIXTURE_STATE": state,
                "FIXTURE_EXPIRED": str(int(expired)),
                "FIXTURE_CALL": str(self.call),
            }
            return subprocess.run(
                [HOOK], env=env, pass_fds=(fd,), capture_output=True, text=True, timeout=30
            )

    def test_connected_client_preserves_identity(self) -> None:
        result = self.run_hook("Running")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already connected", result.stdout)
        self.assertFalse(self.call.exists())

    def test_key_is_private_and_removed_after_enrollment(self) -> None:
        result = self.run_hook("NeedsLogin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(Path(self.call.read_text()).exists())
        self.assertNotIn(KEY, result.stdout + result.stderr)

    def test_expired_key_defers_and_is_not_printed(self) -> None:
        result = self.run_hook("NeedsLogin", expired=True)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse(Path(self.call.read_text()).exists())
        self.assertNotIn(KEY, result.stdout + result.stderr)

    def test_trailing_newline_in_key_defers_without_using_it(self) -> None:
        result = self.run_hook("NeedsLogin", key=KEY + "\n")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse(self.call.exists())


if __name__ == "__main__":
    unittest.main()
