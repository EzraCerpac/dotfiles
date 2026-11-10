"""The manager against fixtures/config, a small configuration with every part of the contract.

The fixture has [vars], a profile file, update and bootstrap hooks (one scoped
to a profile), a command, and an installer exception with its recipe. Like the
contract tests, each test copies the manager and the fixture into a temporary
directory and uses a fake mise.
"""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires
from test_dots_contract import Fixture

FIXTURE = Path(__file__).resolve().parent / "fixtures/config"


class FixtureConfigurationTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="dots-fixture-")
        self.addCleanup(temporary.cleanup)
        # Profiles come from the fixture's config.toml, not from the fake mise.
        self.f = Fixture(Path(temporary.name).resolve(), profiles=None)
        shutil.rmtree(self.f.config)
        shutil.copytree(FIXTURE, self.f.config)

    def test_profiles_and_commands_come_from_the_configuration(self) -> None:
        self.assertEqual(self.f.dots("internal", "profiles").stdout, "laptop\nserver\n")
        self.assertEqual(self.f.dots("internal", "commands").stdout, "hello\n")
        self.assertIn("  dots hello [ARGS...]", self.f.dots("help").stdout)
        result = self.f.dots("hello", "there", SETUP_PROFILE="server")
        self.assertEqual((result.returncode, result.stdout), (0, "hello there from server\n"), result.stderr)

    def test_bootstrap_hooks_are_listed_for_every_profile(self) -> None:
        directory = self.f.config / "dots/hooks/bootstrap.d"
        for profile in ("laptop", "server"):
            with self.subTest(profile=profile):
                result = self.f.bash(f'"$DOTS_HOME/lib/dots-hooks" "{directory}" {profile} laptop server')
                self.assertEqual(result.stdout, f"Login shell\t{directory}/10-Login-shell\n", result.stderr)

    @requires("jq")
    def test_update_runs_the_profiles_exceptions_and_hooks(self) -> None:
        laptop = self.f.update()
        self.assertEqual(laptop.returncode, 0, laptop.stdout + laptop.stderr)
        self.assertIn("== installer exception: example-app ==\nexample-app recipe --install-only", laptop.stdout)
        self.assertIn("== Greeting ==\nHello from laptop", laptop.stdout)
        self.assertNotIn("Server backups", laptop.stdout)
        server = self.f.update(SETUP_PROFILE="server")
        self.assertEqual(server.returncode, 0, server.stdout + server.stderr)
        self.assertNotIn("example-app", server.stdout)
        self.assertIn("== Server backups ==\nSkipped: nothing to back up in a fixture\nResult: skipped", server.stdout)


if __name__ == "__main__":
    unittest.main()
