"""The Atuin account comes from [vars] dots_atuin_username, or is accepted as found."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib.prereq import mise_binary, requires

spec = importlib.util.spec_from_file_location("atuin", Path(__file__).resolve().parents[1] / "dots/lib/atuin.py")
atuin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(atuin)

BUNDLE = {"version": 1, "username": "someone", "password": "secret", "history_key": "key"}


class AtuinAccountTest(unittest.TestCase):
    def config(self, text: str) -> Path:
        root = Path(tempfile.mkdtemp(prefix="dots-atuin-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        (root / "config.toml").write_text(text)
        return root

    @requires("mise")
    def test_account_is_read_from_vars_and_optional(self) -> None:
        with mock.patch.dict(os.environ, {"DOTS_MISE_BIN": mise_binary()}):
            self.assertEqual(atuin.configured_account(self.config('[vars]\ndots_atuin_username = "someone"\n')), "someone")
            self.assertIsNone(atuin.configured_account(self.config("[vars]\n")))
            with self.assertRaisesRegex(atuin.AtuinError, "could not read"):
                atuin.configured_account(self.config("[vars\n"))
            with self.assertRaisesRegex(atuin.AtuinError, "not a valid Atuin username"):
                atuin.configured_account(self.config('[vars]\ndots_atuin_username = ""\n'))

    def test_status_reports_identity_with_auto_sync_disabled(self) -> None:
        result = subprocess.CompletedProcess([], 0, "Username: someone\n", "")
        with mock.patch.dict(os.environ, {"ATUIN_AUTO_SYNC": "false"}):
            with mock.patch.object(atuin, "run_atuin", return_value=result) as status:
                self.assertEqual(atuin.remote_state(), ("someone", None, "ready"))
            status.assert_called_once_with("status", extra_env={"ATUIN_AUTO_SYNC": "true"})
            self.assertEqual(os.environ["ATUIN_AUTO_SYNC"], "false")

    def test_bundle_must_name_the_configured_account_when_set(self) -> None:
        self.assertEqual(atuin.validate_bundle(BUNDLE, None)["username"], "someone")
        self.assertEqual(atuin.validate_bundle(BUNDLE, "someone")["username"], "someone")
        with self.assertRaisesRegex(atuin.AtuinError, "different account"):
            atuin.validate_bundle(BUNDLE, "other")

    def enroll(self, configured: str | None, logged_in: str) -> int:
        with mock.patch.multiple(
            atuin,
            executable=mock.DEFAULT,
            configure=mock.DEFAULT,
            current_key=mock.DEFAULT,
            configured_account=mock.Mock(return_value=configured),
            remote_state=mock.Mock(return_value=(logged_in, None, "ready")),
            run_atuin=mock.Mock(return_value=subprocess.CompletedProcess([], 0, "", "")),
        ):
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    atuin.enroll(Path("/nonexistent"), None)
            except atuin.AtuinError as error:
                return error.code
        return 0

    def test_existing_login_is_checked_only_against_a_configured_account(self) -> None:
        self.assertEqual(self.enroll("someone", "other"), atuin.EXIT_ACCOUNT)
        self.assertEqual(self.enroll("someone", "someone"), 0)
        self.assertEqual(self.enroll(None, "other"), 0)


if __name__ == "__main__":
    unittest.main()
