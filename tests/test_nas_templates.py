from __future__ import annotations

import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

from lib.tera import render_template

ROOT = Path(__file__).parents[1]
NAS_CONFIG = tomllib.loads((ROOT / "config.nas.toml").read_text())
WORKSTATION_CONFIG = tomllib.loads((ROOT / "config.workstation.toml").read_text())
SHARED_CONFIG = tomllib.loads((ROOT / "config.toml").read_text())


def render_dotfile(profile: str, managed_path: str, scratch: Path) -> str:
    config = {"nas": NAS_CONFIG, "workstation": WORKSTATION_CONFIG}[profile]
    entry = {**SHARED_CONFIG["dotfiles"], **config.get("dotfiles", {})}[managed_path]
    if entry["mode"] != "template":
        raise AssertionError(f"{profile} {managed_path} is not a template")

    target = scratch / "home" / managed_path.removeprefix("~/")
    return render_template(
        ROOT / entry["source"],
        target=target,
        scratch=scratch,
        vars={**SHARED_CONFIG["vars"], **config["vars"]},
    )


class NasTemplateTests(unittest.TestCase):


    def test_nas_git_config_has_shared_pagers_without_workstation_integrations(self):
        with tempfile.TemporaryDirectory() as temp:
            rendered = render_dotfile(
                "nas", "~/.config/git/config", Path(temp)
            )

        self.assertIn("pager = hunk pager", rendered)
        pager = subprocess.run(
            ["git", "config", "--file", "-", "--get", "pager.diff"],
            input=rendered, text=True, capture_output=True,
        )
        self.assertEqual(pager.returncode, 1, pager.stderr)
        self.assertIn("show = delta", rendered)
        self.assertIn("tool = nvimdiff", rendered)
        self.assertIn("local = blue", rendered)
        self.assertIn("defaultBranch = main", rendered)
        for workstation_tool in (
            "pycharm",
            "git-lfs",
            "git.overleaf.com",
        ):
            self.assertNotIn(workstation_tool, rendered)


    def test_nas_profile_owns_only_its_declared_dotfiles(self):
        managed = set(SHARED_CONFIG["dotfiles"]) | set(NAS_CONFIG.get("dotfiles", {}))
        self.assertNotIn("~/.config/herdr/config.toml", managed)
        self.assertNotIn("~/.config/keyboard/corne-qmk/USAGE", managed)
        self.assertNotIn("~/.zshrc", managed)
        self.assertIn("~/.codex/AGENTS.md", managed)
        self.assertIn("~/.config/git/config", managed)


if __name__ == "__main__":
    unittest.main()
