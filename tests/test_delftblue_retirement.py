"""The retired DelftBlue profile stays retired.

Only the retirement guard, the retirement bookkeeping, and the SSH/Herdr
access that deliberately outlived the profile may still mention DelftBlue.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires
from lib.tera import render_profile_dotfile

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {
    "config.delftblue.toml",  # throws when the retired selector is used
    "setup-scripts/bootstrap/common.sh",  # replaces a stale selector
    "setup-scripts/bootstrap/persist-selected",  # rejects a stale selector
    "setup-scripts/setup/retired-dotfiles",  # cleans up old links
    "templates/.ssh/config.tera",  # opt-in SSH host, NetID kept local
    "dotfiles/.config/herdr/plugins/config/cloudmanic.herdr-plus/projects/remote-shells.toml",
}
SEARCHED = ("config.toml", "config.workstation.toml", "config.nas.toml", "config.delftblue.toml", "dotfiles", "templates", "setup-scripts")


class DelftBlueRetirementTests(unittest.TestCase):
    def test_only_deliberate_references_remain(self) -> None:
        listing = subprocess.run(
            ["git", "grep", "-l", "-i", "-e", "delftblue", "-e", "DB_MODULE_STACK", "--", *SEARCHED],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertIn(listing.returncode, (0, 1), listing.stderr)
        self.assertEqual(sorted(set(listing.stdout.split()) - ALLOWED), [])

    def test_public_config_has_no_cluster_identity(self) -> None:
        for name in ("config.toml", "config.workstation.toml", "config.nas.toml"):
            text = (ROOT / name).read_text()
            with self.subTest(config=name):
                self.assertNotIn("netid", text)
                self.assertNotIn("slurm", text.lower())


@requires("mise")
class RenderedStartupTests(unittest.TestCase):
    def render(self, profile: str, target: str, **extra_vars: str) -> str:
        with tempfile.TemporaryDirectory() as scratch:
            return render_profile_dotfile(profile, target, Path(scratch), extra_vars=extra_vars)

    def test_delftblue_ssh_host_needs_a_local_netid(self) -> None:
        self.assertNotIn("Host delftblue", self.render("workstation", "~/.ssh/config"))
        rendered = self.render("workstation", "~/.ssh/config", delftblue_netid="someone")
        self.assertIn("Host delftblue\n    HostName login.delftblue.tudelft.nl\n    User someone\n", rendered)

    def test_bashrc_loads_cleanly_without_optional_tools(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            bashrc = home / "bashrc"
            bashrc.write_text(self.render("nas", "~/.bashrc"))
            env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "TERM": "dumb"}
            quiet = subprocess.run(
                ["bash", "--norc", "--noprofile", "-c", f"source {bashrc}"],
                env=env, capture_output=True, text=True, check=False,
            )
            self.assertEqual((quiet.returncode, quiet.stderr), (0, ""))
            interactive = subprocess.run(
                ["bash", "--norc", "--noprofile", "-i", "-c", f"source {bashrc}; bind -X"],
                env=env, capture_output=True, text=True, check=False, stdin=subprocess.DEVNULL,
            )
            self.assertEqual(interactive.returncode, 0, interactive.stderr)
            self.assertNotIn("__atuin_history", interactive.stdout)
            self.assertNotIn("tv_smart_autocomplete", interactive.stdout)
            self.assertFalse((home / ".config/television").exists())
            self.assertNotIn("/tmp/", bashrc.read_text())


if __name__ == "__main__":
    unittest.main()
