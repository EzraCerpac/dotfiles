from __future__ import annotations

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
    def test_nas_project_manifest_renders_root_project_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            rendered = render_dotfile(
                "nas", "~/.config/cerpacnas/projects.toml", Path(temp)
            )

        manifest = tomllib.loads(rendered)
        thesis = manifest["projects"]["thesis"]
        jj_waltz = manifest["projects"]["jj-waltz"]
        self.assertEqual(thesis["local_path"], "/root/Projects/Thesis/ezra-cerpac")
        self.assertEqual(
            thesis["rules_file"],
            "/root/.config/cerpacnas/project-rules/thesis.AGENTS.md",
        )
        self.assertEqual(jj_waltz["local_path"], "/root/Projects/jj-waltz")
        self.assertNotIn("{{", rendered)

    def test_nas_thesis_rules_include_the_nas_validation_limits(self):
        with tempfile.TemporaryDirectory() as temp:
            rendered = render_dotfile(
                "nas",
                "~/.config/cerpacnas/project-rules/thesis.AGENTS.md",
                Path(temp),
            )

        self.assertIn("## CerpacNAS validation policy", rendered)
        self.assertIn("Set `JULIA_NUM_THREADS=1`", rendered)
        self.assertIn("Never run `validate all`", rendered)
        self.assertNotIn("{% if", rendered)

    def test_nas_git_config_has_shared_pagers_without_workstation_integrations(self):
        with tempfile.TemporaryDirectory() as temp:
            rendered = render_dotfile(
                "nas", "~/.config/git/config", Path(temp)
            )

        self.assertIn("pager = hunk pager", rendered)
        self.assertIn("diff = diffnav --side-by-side", rendered)
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

    def test_workstation_manifest_uses_the_selected_home(self):
        with tempfile.TemporaryDirectory() as temp:
            scratch = Path(temp)
            rendered = render_dotfile(
                "workstation", "~/.config/cerpacnas/projects.toml", scratch
            )

        manifest = tomllib.loads(rendered)
        self.assertEqual(
            manifest["projects"]["thesis"]["local_path"],
            str(scratch.resolve() / "home/Projects/Thesis/ezra-cerpac"),
        )
        self.assertEqual(
            manifest["projects"]["thesis"]["rules_file"],
            str(
                scratch.resolve()
                / "home/.config/cerpacnas/project-rules/thesis.AGENTS.md"
            ),
        )

    def test_nas_profile_owns_only_its_declared_dotfiles(self):
        managed = set(SHARED_CONFIG["dotfiles"]) | set(NAS_CONFIG.get("dotfiles", {}))
        self.assertNotIn("~/.config/herdr/config.toml", managed)
        self.assertNotIn("~/.config/keyboard/corne-qmk/USAGE", managed)
        self.assertNotIn("~/.zshrc", managed)
        self.assertIn("~/.codex/AGENTS.md", managed)
        self.assertIn("~/.config/cerpacnas/projects.toml", managed)
        self.assertIn("~/.config/git/config", managed)


if __name__ == "__main__":
    unittest.main()
