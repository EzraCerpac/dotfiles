from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
OVERRIDE = json.dumps(
    {
        "profile": "nas",
        "nas": {
            "host_alias": "nas",
            "dotfiles_branch": "dev",
            "jj_waltz_version": "0.3.1",
            "jj_waltz_sha256": "d175a4922264c32378f538ed7b6382028df68ecd2eaec564e4db75e2361ae2f8",
        },
    }
)


def chezmoi(*args: str, input_text: str | None = None, nas: bool = False) -> str:
    command = ["chezmoi", "--source", str(ROOT)]
    if nas:
        command.extend(["--override-data", OVERRIDE])
    command.extend(args)
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
    ).stdout


class TemplateTests(unittest.TestCase):
    def test_workstation_keeps_live_codex_config_unmanaged(self):
        self.assertIn(".codex/config.toml", chezmoi("ignored").splitlines())

    def test_nas_mise_is_minimal(self):
        rendered = chezmoi("cat", str(Path.home() / ".config/mise/config.toml"), nas=True)
        self.assertIn('codex = "latest"', rendered)
        self.assertIn('jj = "latest"', rendered)
        self.assertNotIn('rust = "latest"', rendered)
        self.assertNotIn("neovim", rendered)
        self.assertNotIn("[tools.julia]", rendered)

    def test_nas_manifest_uses_root_paths(self):
        rendered = chezmoi("cat", str(Path.home() / ".config/cerpacnas/projects.toml"), nas=True)
        self.assertIn('local_path = "/root/Projects/Thesis/ezra-cerpac"', rendered)
        self.assertIn('rules_file = "/root/.config/cerpacnas/project-rules/thesis.AGENTS.md"', rendered)
        self.assertNotIn("explore_model", rendered)
        self.assertNotIn("work_model", rendered)

    def test_nas_package_script_contains_no_apt_or_sudo(self):
        source = (ROOT / "run_onchange_03-install-packages.sh.tmpl").read_text()
        rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=source)
        self.assertIn("user-space mise tools only", rendered)
        self.assertNotIn("apt-get", rendered)
        self.assertNotIn("sudo", rendered)

    def test_nas_tool_script_skips_heavy_workstation_tools(self):
        source = (ROOT / "run_once_03-install-tools.sh.tmpl").read_text()
        rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=source)
        self.assertIn("minimal CerpacNAS tools", rendered)
        self.assertNotIn("Herdr", rendered)
        self.assertNotIn("keymap-drawer", rendered)
        self.assertNotIn("codex-acp", rendered)

    def test_nas_ignores_workstation_reconciliation_hooks(self):
        for name in (
            "run_after_03-reconcile-tools.sh.tmpl",
            "run_after_27-install-herdr-plugins.sh.tmpl",
            "run_once_07-remove-legacy-kbd-commands.sh.tmpl",
        ):
            rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=(ROOT / name).read_text())
            self.assertIn("CerpacNAS profile detected", rendered)
            self.assertNotIn("sudo apt-get", rendered)
            self.assertNotIn("herdr plugin install", rendered)

    def test_nas_ignores_workstation_credentials(self):
        ignored = chezmoi("ignored", nas=True).splitlines()
        self.assertIn(".wakatime.cfg", ignored)
        self.assertIn(".cli-proxy-api", ignored)
        self.assertIn(".ssh/config", ignored)

    def test_nas_managed_set_excludes_workstation_surfaces(self):
        managed = chezmoi("managed", nas=True).splitlines()
        for forbidden in (
            ".bashrc",
            ".config/herdr/config.toml",
            ".config/keyboard/corne-qmk/USAGE",
            ".hammerspoon/init.lua",
            ".local/bin/brew-promote",
            ".local/bin/jw",
            ".zshrc",
            "27-install-herdr-plugins.sh",
        ):
            self.assertNotIn(forbidden, managed)
        for required in (
            ".codex/AGENTS.md",
            ".codex/skills/work-on-cerpacnas/SKILL.md",
            ".config/cerpacnas/projects.toml",
            ".config/git/config",
            ".config/jj-waltz/config.toml",
            ".config/mise/config.toml",
            ".local/bin/nas",
            "06-build-jj-waltz.sh",
        ):
            self.assertIn(required, managed)

    def test_nas_modern_git_hook_is_user_space_only(self):
        source = (ROOT / "run_onchange_05-install-nas-git.sh.tmpl").read_text()
        rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=source)
        self.assertIn("micromamba", rendered)
        self.assertIn("git-modern", rendered)
        self.assertNotIn("sudo", rendered)
        self.assertNotIn("apt-get", rendered)

    def test_nas_git_config_has_no_workstation_tool_dependencies(self):
        rendered = chezmoi("cat", str(Path.home() / ".config/git/config"), nas=True)
        self.assertIn("local = blue", rendered)
        for workstation_tool in ("hunk", "pycharm", "diffnav", "delta", "git-lfs", "git.overleaf.com"):
            self.assertNotIn(workstation_tool, rendered)

    def test_nas_does_not_remove_aerospace_files(self):
        source = (ROOT / ".chezmoiremove.tmpl").read_text()
        rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=source)
        self.assertNotIn("aerospace", rendered)

    def test_nas_jw_installer_requires_config_pinned_checksum(self):
        source = (ROOT / "run_onchange_06-build-jj-waltz.sh.tmpl").read_text()
        rendered = chezmoi("execute-template", "--init=false", nas=True, input_text=source)
        self.assertIn("EXPECTED_SHA256", rendered)
        self.assertIn("d175a4922264c32378f538ed7b6382028df68ecd2eaec564e4db75e2361ae2f8", rendered)
        self.assertIn("pin nas.jj_waltz_sha256", rendered)
        self.assertNotIn("${ASSET}.sha256", rendered)

    def test_nas_global_rules_keep_root_but_forbid_bypass(self):
        rendered = chezmoi("cat", str(Path.home() / ".codex/AGENTS.md"), nas=True)
        self.assertIn("Root login is intentional", rendered)
        self.assertIn("never use `sudo`, Docker", rendered)
        self.assertIn("Never run `validate all`", rendered)


if __name__ == "__main__":
    unittest.main()
