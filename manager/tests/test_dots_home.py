"""dots finds its own files through DOTS_HOME, apart from the configuration it manages."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

MANAGER = Path(__file__).resolve().parents[1]


class DotsHomeTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="dots-home-")
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name).resolve()
        # A manager copied away from this checkout, reached through a relative
        # symlink like ~/.local/bin/dots, and a configuration with no manager.
        self.home = base / "tools/manager"
        shutil.copytree(MANAGER, self.home, ignore=shutil.ignore_patterns("dots-up", "tests", "__pycache__"))
        self.config = base / "config"
        self.config.mkdir()
        (self.config / "config.toml").write_text("# minimal configuration\n")
        links = base / "bin"
        links.mkdir()
        self.dots = links / "dots"
        self.dots.symlink_to(os.path.relpath(self.home / "bin/dots", links))
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(("DOTS_", "MISE_"))}
        self.env["DOTS_ROOT"] = str(self.config)

    def run_dots(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(self.dots), *args], env=env or self.env, cwd=self.config,
                              capture_output=True, text=True, timeout=30, check=False)

    def test_help_runs_from_a_separate_manager(self) -> None:
        result = self.run_dots("help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Your machine setup", result.stdout)

    def test_home_is_the_manager_not_the_configuration(self) -> None:
        result = self.run_dots("internal", "home")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.home))
        self.assertNotEqual(result.stdout.strip(), str(self.config))

    def test_explicit_home_wins_for_development(self) -> None:
        other = self.home.parent / "development"
        other.mkdir()
        result = self.run_dots("internal", "home", env={**self.env, "DOTS_HOME": str(other)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(other))


if __name__ == "__main__":
    unittest.main()
