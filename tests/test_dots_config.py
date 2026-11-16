"""This repository as a dots configuration: its settings and its dots/ templates."""

from __future__ import annotations

import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "manager"


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

    @unittest.skipUnless((MANAGER / "init").is_dir(), "the manager is not in this checkout")
    def test_dots_readme_is_the_shipped_template(self) -> None:
        self.assertEqual((ROOT / "dots/README.md").read_text(), (MANAGER / "init/README.md").read_text())


if __name__ == "__main__":
    unittest.main()
