"""This repository's dots settings and executable entry points."""

from __future__ import annotations

import os
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DotsConfigurationTests(unittest.TestCase):
    def test_this_configuration_declares_the_manager_settings(self) -> None:
        text = (ROOT / "config.toml").read_text()
        for name in ("dots_profiles", "dots_source_repo", "dots_state_repo"):
            self.assertRegex(text, rf'(?m)^{name} = "[^"]+"$')

    def test_macos_preferences_use_the_settings_spelling(self) -> None:
        # mise before 2026.11.8 silently ignores [bootstrap.settings.macos], so
        # the config must require that version wherever it uses the new tables.
        minimum = tomllib.loads((ROOT / "config.toml").read_text())["min_version"]
        self.assertGreaterEqual(tuple(map(int, minimum.split("."))), (2026, 11, 8))
        for config in sorted(ROOT.glob("config*.toml")):
            with self.subTest(config=config.name):
                macos = tomllib.loads(config.read_text()).get("bootstrap", {}).get("macos", {})
                self.assertLessEqual(set(macos), {"launchd"}, "move these tables under [bootstrap.settings.macos]")

    def test_enrollment_entry_points_are_executable(self) -> None:
        for name in ("atuin-bundle", "atuin-login", "atuin-status", "tailscale-login"):
            self.assertTrue(os.access(ROOT / "dots/commands" / name, os.X_OK), name)
        for name in ("80-Atuin", "90-Tailscale"):
            self.assertTrue(os.access(ROOT / "dots/hooks/bootstrap.d" / name, os.X_OK), name)


if __name__ == "__main__":
    unittest.main()
