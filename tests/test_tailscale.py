"""The bootstrap hook passes its Tailscale key only through a private file."""

from __future__ import annotations

import errno
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
UNATTENDED = ("CI", "NONINTERACTIVE", "MISE_NONINTERACTIVE", "SETUP_NONINTERACTIVE", "TAILSCALE_NONINTERACTIVE")


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

args = sys.argv[1:]
with Path(os.environ["FIXTURE_TRACE"]).open("a") as trace:
    trace.write(args[0] + "\\n")

def deny(reason, prefix=""):
    print(prefix + "Access denied: " + reason + " fixture-private-diagnostic", file=sys.stderr)
    print("To not require root, use 'sudo tailscale set --operator=$USER' once.", file=sys.stderr)
    sys.exit(1)

denial = os.environ["FIXTURE_DENIAL"]
if sys.argv[1:] == ["status", "--json"]:
    if denial == "status":
        deny("status access denied", "failed to connect to local tailscaled (fixture): ")
    print(json.dumps({"BackendState": os.environ["FIXTURE_STATE"]}))
    sys.exit(0)

assert sys.argv[1] == "up"
if os.environ["FIXTURE_STATE"] == "Stopped":
    assert sys.argv[1:] == ["up"]
    if denial == "resume":
        deny("prefs write access denied")
    Path(os.environ["FIXTURE_CALL"]).write_text("resume")
    sys.exit(0)
if denial == "browser":
    assert args == ["up"]
    deny("watch ipn bus access denied")
assert sys.argv[2].startswith("--auth-key=file:")
timeout = ["--timeout=30s"] if "CI" in os.environ else []
assert args[2:] == timeout
key_file = Path(sys.argv[2].split(":", 1)[1])
assert stat.S_IMODE(key_file.stat().st_mode) == 0o600
assert key_file.read_text() == "fixture-key\\n"
Path(os.environ["FIXTURE_CALL"]).write_text(str(key_file))
if denial == "keyed":
    deny("checkprefs access denied")
if os.environ["FIXTURE_EXPIRED"] == "1":
    print("expired auth key: " + key_file.read_text(), file=sys.stderr)
    sys.exit(1)
if os.environ["FIXTURE_APPROVAL"] == "1":
    print("Approve device: " + key_file.read_text(), file=sys.stderr)
    print("timeout waiting for Tailscale service to enter a Running state", file=sys.stderr)
    sys.exit(1)
"""
        )
        self.cli.chmod(0o755)
        uv = self.base / "uv"
        uv.write_text(
            '#!/bin/sh\nprintf "uv\\n" >> "$FIXTURE_TRACE"\n'
            '[ "$1 $2 $3" = "run --no-project python" ] || exit 2\nshift 3\nexec python3 "$@"\n'
        )
        uv.chmod(0o755)
        self.call = self.base / "call"
        self.trace = self.base / "trace"
        uname = self.base / "uname"
        uname.write_text("#!/bin/sh\nprintf 'Linux\\n'\n")
        uname.chmod(0o755)

    def run_hook(
        self, state: str, *, expired: bool = False, approval: bool = False, key: str = KEY,
        denial: str = "", terminal: bool = False, unattended: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryFile() as bundle:
            bundle.write(json.dumps({"tailscale_auth_key": key}).encode())
            bundle.seek(0)
            fd = bundle.fileno()
            env = {
                **{name: value for name, value in os.environ.items() if name not in UNATTENDED},
                "PATH": f"{self.base}{os.pathsep}{os.environ['PATH']}",
                "DOTS_ROOT": str(ROOT),
                "DOTS_BUNDLE_FD": str(fd),
                "DOTS_PRIVATE_READY": "1",
                "TAILSCALE_CLI": str(self.cli),
                "SETUP_TAILSCALE_AUTH_KEY": "",
                "FIXTURE_FD": str(fd),
                "FIXTURE_STATE": state,
                "FIXTURE_EXPIRED": str(int(expired)),
                "FIXTURE_APPROVAL": str(int(approval)),
                "FIXTURE_CALL": str(self.call),
                "FIXTURE_TRACE": str(self.trace),
                "FIXTURE_DENIAL": denial,
            }
            if not terminal or unattended:
                env["CI"] = "1"
            if terminal:
                return self.run_on_pty(env, fd)
            return subprocess.run(
                [HOOK], env=env, pass_fds=(fd,), capture_output=True, text=True, timeout=30
            )

    @staticmethod
    def run_on_pty(env: dict[str, str], fd: int) -> subprocess.CompletedProcess[str]:
        master, slave = os.openpty()
        try:
            try:
                child = subprocess.Popen([HOOK], env=env, pass_fds=(fd,), stdin=slave, stdout=slave, stderr=slave)
            finally:
                os.close(slave)
            output = bytearray()
            with child:
                while True:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
            return subprocess.CompletedProcess([HOOK], child.returncode, output.decode(), "")
        finally:
            os.close(master)

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

    def test_device_approval_timeout_defers_without_printing_key(self) -> None:
        result = self.run_hook("NeedsLogin", approval=True)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("device approval", result.stderr)
        self.assertNotIn(KEY, result.stdout + result.stderr)
        self.assertFalse(Path(self.call.read_text()).exists())

    def test_pending_device_approval_does_not_rekey(self) -> None:
        result = self.run_hook("NeedsMachineAuth")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse(self.call.exists())

    def test_stopped_client_uses_bare_resume_even_with_a_key(self) -> None:
        result = self.run_hook("Stopped")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.call.read_text(), "resume")
        self.assertNotIn(KEY, result.stdout + result.stderr)
        self.assertEqual(self.trace.read_text().splitlines(), ["status", "uv", "up"])

    def test_terminal_resume_only_uses_uv_when_explicitly_unattended(self) -> None:
        for unattended, expected in [(False, ["status", "up"]), (True, ["status", "uv", "up"])]:
            with self.subTest(unattended=unattended):
                self.trace.write_text("")
                result = self.run_hook("Stopped", terminal=True, unattended=unattended)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.trace.read_text().splitlines(), expected)

    def test_local_denials_defer_without_printing_diagnostics_or_retrying(self) -> None:
        cases = [
            ("status", "NeedsLogin", KEY, False, ["status"]),
            ("keyed", "NeedsLogin", KEY, True, ["status", "up"]),
            ("resume", "Stopped", KEY, False, ["status", "uv", "up"]),
            ("browser", "NeedsLogin", "", True, ["status", "up"]),
        ]
        for denial, state, key, terminal, expected in cases:
            with self.subTest(denial=denial):
                self.trace.write_text("")
                result = self.run_hook(state, denial=denial, key=key, terminal=terminal)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 3, output)
                self.assertIn('set --operator="$USER"', output)
                self.assertIn("rerun dots tailscale-login", output)
                self.assertNotIn("fixture-private-diagnostic", output)
                self.assertNotIn("Access denied:", output)
                self.assertEqual(self.trace.read_text().splitlines(), expected)

    def test_trailing_newline_in_key_defers_without_using_it(self) -> None:
        result = self.run_hook("NeedsLogin", key=KEY + "\n")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse(self.call.exists())


if __name__ == "__main__":
    unittest.main()
