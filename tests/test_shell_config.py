"""Behavior of the managed shell startup files in an isolated home.

Each test sources a startup file with a throwaway HOME and a PATH that holds
only stubs plus the system directories, so no personal tool or credential is
consulted.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires

ROOT = Path(__file__).resolve().parents[1]
FISH_DIR = ROOT / "dotfiles/.config/fish"


class IsolatedShell(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="shell-config-")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.stubs = self.home / "stubs"
        self.stubs.mkdir()
        # Keychain lookups must never reach a real keychain.
        self.stub("security", "exit 44")
        self.env = {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "PATH": os.pathsep.join((str(self.stubs), "/usr/bin", "/bin")),
            "TERM": "dumb",
        }

    def stub(self, name: str, body: str) -> None:
        path = self.stubs / name
        path.write_text(f"#!/bin/sh\n{body}\n")
        path.chmod(0o755)

    def run_shell(self, command: list[str], **extra_env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command, env={**self.env, **extra_env}, capture_output=True, text=True, check=False, timeout=60
        )


@requires("fish")
class FishConfigTests(IsolatedShell):
    def fish(self, script: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        return self.run_shell([shutil.which("fish") or "fish", "--no-config", "-c", script], **extra_env)

    def test_macos_exports_the_launchd_dbus_session_address(self) -> None:
        self.stub("uname", 'if [ "$1" = "-m" ]; then echo arm64; else echo Darwin; fi')
        result = self.fish(
            f"source {FISH_DIR / 'conf.d/10-macos.fish'}; "
            "functions -q DBUS_SESSION_BUS_ADDRESS; and echo shadowed-by-function; "
            "command env | string match 'DBUS_SESSION_BUS_ADDRESS=*'",
            DBUS_LAUNCHD_SESSION_BUS_SOCKET="/tmp/launchd-dbus",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/launchd-dbus")

    def test_cc_launches_claude_with_permission_prompts(self) -> None:
        result = self.fish(f"source {FISH_DIR / 'config.fish'}; functions cc")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("claude", result.stdout)
        self.assertIn("agent-config.toml", result.stdout)
        self.assertNotIn("--dangerously-skip-permissions", result.stdout)


@requires("zsh")
class ZshConfigTests(IsolatedShell):
    def test_zshenv_tolerates_a_home_without_rustup(self) -> None:
        result = self.run_shell([shutil.which("zsh") or "zsh", "-f", "-c", f"source {ROOT / 'dotfiles/.zshenv'}"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_zshenv_loads_rustup_environment_when_present(self) -> None:
        cargo = self.home / ".cargo"
        cargo.mkdir()
        (cargo / "env").write_text('export RUSTUP_FIXTURE_LOADED=1\n')
        result = self.run_shell(
            [shutil.which("zsh") or "zsh", "-f", "-c", f"source {ROOT / 'dotfiles/.zshenv'}; print -r -- $RUSTUP_FIXTURE_LOADED"]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1")


if __name__ == "__main__":
    unittest.main()
