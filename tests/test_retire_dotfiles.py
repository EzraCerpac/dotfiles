"""Retired dotfile links are removed only when they are provably ours."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "setup-scripts/lib/retire-dotfiles.sh"


class RetireDotfilesTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="retire-dotfiles-")
        self.addCleanup(temporary.cleanup)
        base = Path(temporary.name).resolve()
        self.home = base / "home"
        self.root = self.home / ".config/mise"
        (self.root / "setup-scripts/setup").mkdir(parents=True)
        (self.root / "dotfiles").mkdir()
        self.outside = base / "elsewhere"
        self.outside.mkdir()

    def retire(self, *entries: str) -> subprocess.CompletedProcess[str]:
        (self.root / "setup-scripts/setup/retired-dotfiles").write_text(
            "# comment\n\n" + "\n".join(entries) + "\n"
        )
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.root)],
            env={**os.environ, "HOME": str(self.home)},
            capture_output=True,
            text=True,
            check=False,
        )

    def link(self, target: str, points_to: Path) -> Path:
        path = self.home / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(points_to)
        return path

    def test_dangling_link_into_the_checkout_is_removed(self) -> None:
        path = self.link(".config/nvim/lua/plugins/old.lua", self.root / "dotfiles/old.lua")
        result = self.retire("~/.config/nvim/lua/plugins/old.lua")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(path.is_symlink())
        self.assertIn("Removed retired link ~/.config/nvim/lua/plugins/old.lua", result.stdout)

    def test_links_spelled_through_a_symlinked_directory_match(self) -> None:
        # macOS spells temporary paths as /var/... while `pwd -P` says
        # /private/var/...; a retired directory may also be gone entirely.
        alias = self.outside / "alias"
        alias.symlink_to(self.root)
        path = self.link(".config/nvim/lua/gone/init.lua", alias / "dotfiles/gone/init.lua")
        relative = self.link(".config/relative.lua", Path("mise/dotfiles/old.lua"))
        result = self.retire("~/.config/nvim/lua/gone/init.lua", "~/.config/relative.lua")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(path.is_symlink())
        self.assertFalse(relative.is_symlink())

    def test_live_link_is_kept_because_it_was_redeclared(self) -> None:
        source = self.root / "dotfiles/live.lua"
        source.write_text("live\n")
        path = self.link(".config/live.lua", source)
        self.assertEqual(self.retire("~/.config/live.lua").returncode, 0)
        self.assertTrue(path.is_symlink())

    def test_foreign_links_and_regular_files_are_kept(self) -> None:
        foreign = self.link(".config/foreign.lua", self.outside / "missing.lua")
        regular = self.home / ".local/bin/rendered"
        regular.parent.mkdir(parents=True)
        regular.write_text("#!/bin/sh\n")
        result = self.retire("~/.config/foreign.lua", "~/.local/bin/rendered", "~/.config/absent.lua")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(foreign.is_symlink())
        self.assertTrue(regular.is_file())
        self.assertEqual(result.stdout, "")

    def test_entries_outside_home_are_refused(self) -> None:
        victim = self.outside / "victim"
        victim.symlink_to(self.root / "dotfiles/gone")
        result = self.retire(str(victim), "~/../elsewhere/victim")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(victim.is_symlink())
        self.assertEqual(result.stderr.count("ignoring entry outside HOME"), 2)

    def test_the_real_retirement_list_only_names_home_paths(self) -> None:
        listing = SCRIPT.parents[1] / "setup/retired-dotfiles"
        for line in listing.read_text().splitlines():
            if line and not line.startswith("#"):
                with self.subTest(entry=line):
                    self.assertTrue(line.startswith("~/"))


if __name__ == "__main__":
    unittest.main()
