from __future__ import annotations

import base64
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]
HELPER = SOURCE_ROOT / "tasks/bootstrap/atuin.py"
PASSWORD = "fixture-password-value"
HISTORY_KEY = "fixture-history-key-value"
RECIPIENT = "age1fixturefixturefixturefixturefixturefixturefixture"
SESSION_ID = "01a0beec82b57e11830bd9d29f70f8ed"


FAKE_ATUIN = r'''#!/usr/bin/env python3
import json
import os
import pathlib
import sys
import termios
import time

state = pathlib.Path(os.environ["ATUIN_FAKE_STATE"])
state.mkdir(parents=True, exist_ok=True)
calls = state / "calls.jsonl"
password = "fixture-password-value"
history_key = "fixture-history-key-value"
leaked = password in sys.argv or history_key in sys.argv or password in os.environ.values() or history_key in os.environ.values()
with calls.open("a") as handle:
    handle.write(json.dumps({
        "args": sys.argv[1:],
        "atuin_session": os.environ.get("ATUIN_SESSION"),
        "secret_env_or_argv": leaked,
    }) + "\n")

args = sys.argv[1:]
if args == ["--version"]:
    print("atuin 18.fixture (test)")
elif args == ["uuid"]:
    if (state / "fail-uuid").exists():
        raise SystemExit(1)
    if (state / "hyphenated-uuid").exists():
        print("01a0beec-82b5-7e11-830b-d9d29f70f8ed")
    else:
        print("01a0beec82b57e11830bd9d29f70f8ed")
elif args == ["key"]:
    if (state / "missing-key").exists():
        raise SystemExit(1)
    print(history_key)
elif args == ["status"]:
    if (state / "fail-status").exists():
        print("temporary status failure", file=sys.stderr)
        raise SystemExit(1)
    account = state / "account"
    if not account.exists():
        print("You are not logged in to a sync server - cannot show sync status", file=sys.stderr)
        raise SystemExit(1)
    print("Atuin v18.fixture")
    print("\n[Local]\nLast sync: 2026-09-20 12:00:00 +00:00")
    print("\n[Remote]\nUsername: " + account.read_text())
elif args == ["doctor"]:
    sync = None
    if (state / "account").exists():
        auth_state = "Hub (authenticated)" if (state / "hub-auth").exists() else "Hub (legacy token)"
        sync = {"auth_state": auth_state, "auto_sync": True, "last_sync": "fixture"}
    print("Atuin Doctor\n\nPlease include the output below with any bug reports or issues\n")
    print(json.dumps({"atuin": {"sync": sync}, "shell": {}, "system": {}}))
elif len(args) >= 2 and args[:2] == ["config", "set"]:
    config_path = state / "config.json"
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    config[args[2]] = args[3]
    config_path.write_text(json.dumps(config))
elif len(args) == 3 and args[:2] == ["config", "get"]:
    config_path = state / "config.json"
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    if args[2] not in config:
        raise SystemExit(1)
    print(config[args[2]])
elif args == ["sync"]:
    if not os.environ.get("ATUIN_SESSION"):
        print("Failed to find $ATUIN_SESSION in environment", file=sys.stderr)
        raise SystemExit(1)
    if (state / "fail-sync").exists():
        raise SystemExit(1)
    print("Sync complete")
elif args == ["login", "--username", "EzraCerpac"]:
    def input_line(prompt):
        sys.stdout.write(prompt)
        sys.stdout.flush()
        return sys.stdin.readline().rstrip("\r\n")
    def hidden_tty_line(prompt):
        fd = os.open("/dev/tty", os.O_RDWR)
        before = termios.tcgetattr(fd)
        after = termios.tcgetattr(fd)
        after[3] &= ~termios.ECHO
        termios.tcsetattr(fd, termios.TCSADRAIN, after)
        try:
            os.write(fd, prompt.encode())
            value = bytearray()
            while not value.endswith(b"\n"):
                value.extend(os.read(fd, 1))
            return value.decode().rstrip("\r\n")
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, before)
            os.write(fd, b"\n")
            os.close(fd)
    supplied_key = input_line("Please enter encryption key [blank to use existing key file]: ")
    if supplied_key != history_key:
        print("Invalid encryption key. Please try again.")
        input_line("Please enter encryption key [blank to use existing key file]: ")
        time.sleep(30)
        raise SystemExit(1)
    supplied_password = hidden_tty_line("Please enter password: ")
    (state / "login-input.json").write_text(json.dumps({
        "key_ok": supplied_key == history_key,
        "password_ok": supplied_password == password,
        "password_length": len(supplied_password),
    }))
    if supplied_password != password:
        print("invalid credentials")
        raise SystemExit(1)
    if (state / "two-factor").exists():
        print("Please enter two-factor code:", flush=True)
        time.sleep(30)
        raise SystemExit(1)
    (state / "account").write_text("EzraCerpac")
    print("Successfully authenticated")
else:
    raise SystemExit(2)
'''


FAKE_AGE = r'''#!/usr/bin/env python3
import base64
import json
import os
import pathlib
import sys

state = pathlib.Path(os.environ["ATUIN_FAKE_STATE"])
password = "fixture-password-value"
history_key = "fixture-history-key-value"
leaked = password in sys.argv or history_key in sys.argv or password in os.environ.values() or history_key in os.environ.values()
with (state / "calls.jsonl").open("a") as handle:
    handle.write(json.dumps({"args": ["age", *sys.argv[1:]], "secret_env_or_argv": leaked}) + "\n")
if "--decrypt" in sys.argv:
    raw = pathlib.Path(sys.argv[-1]).read_bytes()
    if not raw.startswith(b"AGE-FIXTURE\n"):
        raise SystemExit(1)
    sys.stdout.buffer.write(base64.b64decode(raw.split(b"\n", 1)[1]))
else:
    payload = sys.stdin.buffer.read()
    if (state / "fail-age").exists():
        raise SystemExit(1)
    sys.stdout.buffer.write(b"AGE-FIXTURE\n" + base64.b64encode(payload))
'''


class AtuinEnrollmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.root = self.base / "mise"
        self.root.mkdir()
        (self.root / "encrypted").mkdir()
        self.home = self.base / "home"
        self.home.mkdir()
        self.identity = self.home / ".config/age/keys.txt"
        self.identity.parent.mkdir(parents=True)
        self.identity.write_text("AGE-SECRET-IDENTITY-FIXTURE\n")
        self.identity.chmod(0o600)
        self.fake_state = self.base / "state"
        self.fake_state.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.write_executable(self.bin / "atuin", FAKE_ATUIN)
        self.write_executable(self.bin / "age", FAKE_AGE)
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                "ATUIN_FAKE_STATE": str(self.fake_state),
                "ATUIN_PASSWORD": PASSWORD,
            }
        )
        self.env.pop("ATUIN_SESSION", None)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def write_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def run_helper(self, *args: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(HELPER), *args],
            env=self.env,
            input=stdin,
            text=True,
            capture_output=True,
            timeout=10,
            check=False,
        )

    def calls(self) -> list[dict[str, object]]:
        path = self.fake_state / "calls.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines()]

    def write_bundle(self, history_key: str = HISTORY_KEY, password: str = PASSWORD) -> Path:
        document = {
            "version": 1,
            "username": "EzraCerpac",
            "password": password,
            "history_key": history_key,
        }
        target = self.root / "encrypted/atuin.json.age"
        target.write_bytes(b"AGE-FIXTURE\n" + base64.b64encode(json.dumps(document).encode()))
        target.chmod(0o600)
        return target

    def enroll(self) -> subprocess.CompletedProcess[str]:
        return self.run_helper(
            "enroll", "--root", str(self.root), "--identity", str(self.identity)
        )

    def test_bundle_is_atomic_private_and_secrets_never_reach_argv_env_or_plaintext_file(self) -> None:
        output = self.root / "encrypted/atuin.json.age"
        result = self.run_helper(
            "bundle", "--output", str(output), "--recipient", RECIPIENT, stdin=PASSWORD
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertNotIn(PASSWORD, result.stdout + result.stderr)
        self.assertNotIn(HISTORY_KEY, result.stdout + result.stderr)
        self.assertTrue(all(not call["secret_env_or_argv"] for call in self.calls()))
        for path in self.base.rglob("*"):
            if path.is_file() and self.bin not in path.parents:
                self.assertNotIn(PASSWORD.encode(), path.read_bytes())
                self.assertNotIn(HISTORY_KEY.encode(), path.read_bytes())

        before = output.read_bytes()
        repeated = self.run_helper(
            "bundle", "--output", str(output), "--recipient", RECIPIENT, stdin=PASSWORD
        )
        self.assertEqual(repeated.returncode, 2)
        self.assertEqual(output.read_bytes(), before)

    def test_bundle_requires_existing_native_history_key(self) -> None:
        (self.fake_state / "missing-key").touch()
        result = self.run_helper(
            "bundle",
            "--output",
            str(self.root / "encrypted/atuin.json.age"),
            "--recipient",
            RECIPIENT,
            stdin=PASSWORD,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("no readable local history key", result.stderr)

    def test_failed_age_encryption_leaves_no_output_or_partial_file(self) -> None:
        (self.fake_state / "fail-age").touch()
        output = self.root / "encrypted/atuin.json.age"
        result = self.run_helper(
            "bundle", "--output", str(output), "--recipient", RECIPIENT, stdin=PASSWORD
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse(output.exists())
        self.assertEqual(list(output.parent.glob(f".{output.name}.*")), [])

    def test_missing_bundle_and_identity_are_clear_and_do_not_run_login(self) -> None:
        missing_bundle = self.enroll()
        self.assertEqual(missing_bundle.returncode, 3)
        self.assertIn("login deferred because the Atuin bundle is missing", missing_bundle.stderr)
        self.assertFalse(any(call["args"][:1] == ["login"] for call in self.calls()))
        self.assertTrue(any(call["args"][:2] == ["config", "set"] for call in self.calls()))

        self.write_bundle()
        self.identity.unlink()
        missing_identity = self.enroll()
        self.assertEqual(missing_identity.returncode, 3)
        self.assertIn("login deferred because the age identity is missing", missing_identity.stderr)

    def test_new_login_preserves_local_history_and_syncs_with_native_client(self) -> None:
        self.write_bundle()
        history = self.home / ".local/share/atuin/history.db"
        history.parent.mkdir(parents=True)
        history.write_bytes(b"fixture local history")
        before = history.read_bytes()

        result = self.enroll()

        login_input = self.fake_state / "login-input.json"
        detail = login_input.read_text() if login_input.exists() else result.stderr
        self.assertEqual(result.returncode, 0, detail)
        self.assertEqual(history.read_bytes(), before)
        self.assertEqual((self.fake_state / "account").read_text(), "EzraCerpac")
        args = [call["args"] for call in self.calls()]
        self.assertIn(["login", "--username", "EzraCerpac"], args)
        self.assertEqual(args.count(["uuid"]), 1)
        self.assertIn(["sync"], args)
        sync_call = next(call for call in self.calls() if call["args"] == ["sync"])
        self.assertEqual(sync_call["atuin_session"], SESSION_ID)
        self.assertNotIn("ATUIN_SESSION", self.env)
        self.assertTrue(all(not call["secret_env_or_argv"] for call in self.calls()))
        rendered = json.dumps(args)
        self.assertNotIn(PASSWORD, rendered)
        self.assertNotIn(HISTORY_KEY, rendered)

    def test_existing_correct_login_is_preserved(self) -> None:
        (self.fake_state / "account").write_text("EzraCerpac")
        result = self.enroll()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = [call["args"] for call in self.calls()]
        self.assertFalse(any(call[:1] == ["login"] for call in args))
        self.assertFalse(any(call[:1] == ["age"] for call in args))
        self.assertEqual(args.count(["uuid"]), 1)
        self.assertIn(["sync"], args)
        self.assertIn("preserving the current session", result.stdout)

    def test_existing_native_session_is_scoped_to_sync_without_new_uuid(self) -> None:
        existing_session = "018f47cf-9cf4-7b5e-a4fd-65d1366c20a8"
        self.env["ATUIN_SESSION"] = existing_session
        (self.fake_state / "account").write_text("EzraCerpac")
        result = self.enroll()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertFalse(any(call["args"] == ["uuid"] for call in calls))
        sync_call = next(call for call in calls if call["args"] == ["sync"])
        self.assertEqual(sync_call["atuin_session"], existing_session)

    def test_native_hyphenated_uuid_variant_is_also_accepted(self) -> None:
        (self.fake_state / "account").write_text("EzraCerpac")
        (self.fake_state / "hyphenated-uuid").touch()
        result = self.enroll()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        sync_call = next(call for call in calls if call["args"] == ["sync"])
        self.assertEqual(
            sync_call["atuin_session"], "01a0beec-82b5-7e11-830b-d9d29f70f8ed"
        )

    def test_failed_native_uuid_defers_before_sync(self) -> None:
        (self.fake_state / "account").write_text("EzraCerpac")
        (self.fake_state / "fail-uuid").touch()
        result = self.enroll()
        self.assertEqual(result.returncode, 3)
        self.assertIn("native session", result.stderr)
        calls = self.calls()
        self.assertTrue(any(call["args"] == ["uuid"] for call in calls))
        self.assertFalse(any(call["args"] == ["sync"] for call in calls))

    def test_unknown_status_failure_defers_without_mutating_configuration(self) -> None:
        (self.fake_state / "fail-status").touch()
        result = self.enroll()
        self.assertEqual(result.returncode, 3)
        args = [call["args"] for call in self.calls()]
        self.assertFalse(any(call[:2] == ["config", "set"] for call in args))
        self.assertFalse(any(call[:1] == ["login"] for call in args))

    def test_other_account_is_refused_before_configuration_or_sync(self) -> None:
        self.write_bundle()
        (self.fake_state / "account").write_text("SomeoneElse")
        result = self.enroll()
        self.assertEqual(result.returncode, 20)
        args = [call["args"] for call in self.calls()]
        self.assertFalse(any(call[:2] == ["config", "set"] for call in args))
        self.assertNotIn(["sync"], args)

    def test_wrong_history_key_is_rejected_by_native_login_without_disclosure(self) -> None:
        self.write_bundle(history_key="fixture-wrong-history-key")
        result = self.enroll()
        self.assertEqual(result.returncode, 21)
        self.assertNotIn(PASSWORD, result.stdout + result.stderr)
        self.assertNotIn("fixture-wrong-history-key", result.stdout + result.stderr)
        self.assertFalse((self.fake_state / "account").exists())

    def test_two_factor_prompt_defers_and_can_be_rerun(self) -> None:
        self.write_bundle()
        (self.fake_state / "two-factor").touch()
        result = self.enroll()
        self.assertEqual(result.returncode, 3)
        self.assertIn("two-factor", result.stderr)
        self.assertFalse((self.fake_state / "account").exists())

    def test_configure_uses_native_settings_and_preserves_unrelated_values(self) -> None:
        (self.fake_state / "config.json").write_text(json.dumps({"keep": "yes"}))
        result = self.run_helper("configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads((self.fake_state / "config.json").read_text())
        self.assertEqual(config["keep"], "yes")
        self.assertEqual(config["auto_sync"], "true")
        self.assertEqual(config["sync_frequency"], "5m")
        self.assertEqual(config["filter_mode"], "global")
        self.assertEqual(config["ai.enabled"], "true")

    def test_status_does_not_treat_history_login_as_hub_authentication(self) -> None:
        (self.fake_state / "account").write_text("EzraCerpac")
        (self.fake_state / "config.json").write_text(json.dumps({"ai.enabled": "true"}))
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "Installation: atuin 18.fixture (test)",
                "Login: ready (EzraCerpac)",
                "Last sync: 2026-09-20 12:00:00 +00:00",
                "AI readiness: enabled; Hub authentication unverified",
            ],
        )

    def test_status_accepts_native_doctor_hub_authentication_evidence(self) -> None:
        (self.fake_state / "account").write_text("EzraCerpac")
        (self.fake_state / "hub-auth").touch()
        (self.fake_state / "config.json").write_text(json.dumps({"ai.enabled": "true"}))
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("AI readiness: enabled; Hub authentication verified", result.stdout)

    def test_status_recognizes_native_nonzero_logged_out_result(self) -> None:
        (self.fake_state / "config.json").write_text(json.dumps({"ai.enabled": "true"}))
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Login: not logged in", result.stdout)
        self.assertIn("AI readiness: enabled; Hub authentication unverified", result.stdout)


if __name__ == "__main__":
    unittest.main()
