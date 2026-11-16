"""This repository as a dots configuration: its settings and its dots/ templates."""

from __future__ import annotations

import subprocess
import tomllib
import unittest
from pathlib import Path

from lib import prereq

ROOT = Path(__file__).resolve().parents[1]

PINNED = tomllib.loads((ROOT / "config.toml").read_text())["tools"]["github:EzraCerpac/dots"]


def pinned_dots_home() -> Path | None:
    """The installed dots release config.toml pins, or None when it is not installed."""
    mise = prereq.mise_binary()
    if mise is None:
        return None
    result = subprocess.run([mise, "where", f"github:EzraCerpac/dots@{PINNED}"],
                            capture_output=True, text=True, check=False, cwd=ROOT.parent)
    home = Path(result.stdout.strip())
    return home if result.returncode == 0 and (home / "init").is_dir() else None


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

    def test_dots_readme_is_the_shipped_template(self) -> None:
        home = pinned_dots_home()
        if home is None:
            self.skipTest(f"dots {PINNED} is not installed (mise install github:EzraCerpac/dots@{PINNED})")
        self.assertEqual((ROOT / "dots/README.md").read_text(), (home / "init/README.md").read_text())


if __name__ == "__main__":
    unittest.main()
