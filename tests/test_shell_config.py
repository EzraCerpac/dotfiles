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


INIT_TOOLS = ("atuin", "tv", "zoxide", "starship", "wt", "jw", "carapace", "mole", "fzf")


@requires("fish")
class FishStartupTests(IsolatedShell):
    """The real config, loaded the way fish loads it, against logging stubs."""

    def setUp(self) -> None:
        super().setUp()
        (self.home / ".config").mkdir()
        (self.home / ".config/fish").symlink_to(FISH_DIR)
        self.calls = self.home / "calls"
        self.stub("uname", "echo Linux")
        self.stub("mise", f'echo "mise $*" >> {self.calls}')
        for tool in INIT_TOOLS:
            self.stub(tool, f'echo "{tool} $*" >> {self.calls}\necho "set -g __stub_{tool} loaded"')

    def start(self, *flags: str, script: str = "true", **extra_env: str) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [shutil.which("fish") or "fish", *flags, "-c", script],
            env={**self.env, **extra_env}, capture_output=True, text=True, check=False, timeout=60, stdin=subprocess.DEVNULL,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def logged(self) -> list[str]:
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_scripts_only_activate_mise(self) -> None:
        self.start()
        self.assertEqual(self.logged(), ["mise activate fish"])

    def test_interactive_init_runs_once_then_comes_from_the_cache(self) -> None:
        probe = "echo RESULT=$__stub_starship,$__stub_carapace,$__stub_fzf"
        self.assertIn("RESULT=loaded,loaded,loaded", self.start("-i", script=probe).stdout)
        tools_first = sorted(line.split()[0] for line in self.logged() if not line.startswith("mise"))
        self.assertEqual(tools_first, sorted(INIT_TOOLS))
        self.assertIn("starship init fish --print-full-init", self.logged())

        self.calls.unlink()
        self.assertIn("RESULT=loaded,loaded,loaded", self.start("-i", script=probe).stdout)
        self.assertEqual(self.logged(), ["mise activate fish"])

    def test_an_updated_tool_regenerates_only_its_cache(self) -> None:
        self.start("-i")
        self.calls.unlink()
        later = self.stubs / "starship"
        stamp = later.stat().st_mtime + 60
        os.utime(later, (stamp, stamp))
        self.start("-i")
        self.assertEqual(self.logged(), ["mise activate fish", "starship init fish --print-full-init"])

    def test_a_tool_at_a_new_path_regenerates_its_cache(self) -> None:
        self.start("-i")
        self.calls.unlink()
        # An older binary earlier on PATH (e.g. a switched mise tool version).
        moved = self.home / "moved"
        moved.mkdir()
        shutil.copy2(self.stubs / "starship", moved / "starship")
        stamp = (self.stubs / "starship").stat().st_mtime - 3600
        os.utime(moved / "starship", (stamp, stamp))
        self.start("-i", PATH=os.pathsep.join((str(moved), self.env["PATH"])))
        self.assertEqual(self.logged(), ["mise activate fish", "starship init fish --print-full-init"])

    def test_a_future_mtime_does_not_regenerate_on_every_start(self) -> None:
        future = self.stubs / "starship"
        stamp = future.stat().st_mtime + 86400
        os.utime(future, (stamp, stamp))
        self.start("-i")
        self.calls.unlink()
        self.start("-i")
        self.assertEqual(self.logged(), ["mise activate fish"])

    def test_an_empty_cache_home_means_the_default(self) -> None:
        self.start("-i", XDG_CACHE_HOME="")
        cached = self.home / ".cache/fish/init/starship_init_fish_--print-full-init.fish"
        self.assertTrue(cached.is_file())

    def test_a_tool_behind_a_mise_shim_is_fingerprinted_by_its_selected_binary(self) -> None:
        # Shims link to mise itself, so the selected version must come from `mise which`.
        selected = self.home / "installs/starship-1"
        selected.mkdir(parents=True)
        shutil.copy2(self.stubs / "starship", selected / "starship")
        shims = self.home / "shims"
        shims.mkdir()
        (shims / "starship").symlink_to(self.stubs / "mise")
        # Like a real shim: invoked as the tool, run the version mise selected.
        self.stub("mise", '[ "$(basename "$0")" = starship ] && exec "$SELECTED_STARSHIP" "$@"\n'
                  f'echo "mise $*" >> {self.calls}\n'
                  '[ "$1" = which ] && echo "$SELECTED_STARSHIP"; exit 0')
        path = os.pathsep.join((str(shims), self.env["PATH"]))
        self.start("-i", PATH=path, SELECTED_STARSHIP=str(selected / "starship"))
        self.calls.unlink()
        self.start("-i", PATH=path, SELECTED_STARSHIP=str(selected / "starship"))
        self.assertNotIn("starship init fish --print-full-init", self.logged())
        # A switched version behind the same shim regenerates the cache.
        upgraded = self.home / "installs/starship-2"
        upgraded.mkdir()
        shutil.copy2(self.stubs / "starship", upgraded / "starship")
        self.start("-i", PATH=path, SELECTED_STARSHIP=str(upgraded / "starship"))
        self.assertIn("starship init fish --print-full-init", self.logged())

    def test_an_unwritable_cache_still_loads_the_integrations(self) -> None:
        # A regular file where the cache directory belongs cannot be created
        # into, even by root (chmod-based read-only checks are bypassed there).
        blocked = self.home / "blocked"
        blocked.write_text("")
        probe = "echo RESULT=$__stub_starship,$__stub_carapace"
        result = self.start("-i", script=probe, XDG_CACHE_HOME=str(blocked))
        self.assertIn("RESULT=loaded,loaded", result.stdout)

    def test_missing_tools_are_skipped_quietly(self) -> None:
        for tool in INIT_TOOLS:
            (self.stubs / tool).unlink()
        result = self.start("-i")
        self.assertEqual(result.stderr.strip(), "")


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


@requires("zsh")
class ZshStartupTests(IsolatedShell):
    """The real zsh startup files, read in zsh's own order, against stubs."""

    def setUp(self) -> None:
        super().setUp()
        zdotdir = self.home / "zdot"
        zdotdir.mkdir()
        for name in (".zshenv", ".zprofile", ".zshrc"):
            (zdotdir / name).symlink_to(ROOT / "dotfiles" / name)
        (self.home / ".local/bin").mkdir(parents=True)
        self.env["ZDOTDIR"] = str(zdotdir)
        self.calls = self.home / "calls"
        for tool in ("mise", "gh", "jw", "starship", "tv", "wt"):
            self.stub(tool, f'echo "{tool} $*" >> {self.calls}')

    def start(self, *flags: str, script: str) -> subprocess.CompletedProcess[str]:
        # -d skips /etc/zsh*, so a distribution's own compinit cannot mask ours.
        result = subprocess.run(
            [shutil.which("zsh") or "zsh", "-d", *flags, "-c", script],
            env=self.env, capture_output=True, text=True, check=False, timeout=60, stdin=subprocess.DEVNULL,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def mise_activations(self) -> int:
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return sum(line.startswith("mise activate") for line in calls)

    def test_each_shell_kind_activates_mise_exactly_once(self) -> None:
        for flags in (("-i",), ("-l", "-i"), ("-l",)):
            with self.subTest(flags=flags):
                self.calls.unlink(missing_ok=True)
                self.start(*flags, script="true")
                self.assertEqual(self.mise_activations(), 1)

    def test_interactive_path_starts_with_local_bin_once(self) -> None:
        result = self.start("-i", script="print -rl -- RESULT $path")
        path = result.stdout.split("RESULT\n", 1)[1].split()
        local_bin = str(self.home / ".local/bin")
        self.assertEqual(path[0], local_bin)
        self.assertEqual(path.count(local_bin), 1)

    def test_completion_is_ready_without_optional_tools(self) -> None:
        (self.stubs / "jw").unlink()
        result = self.start("-i", script="(( $+functions[compdef] )) && print COMPDEF-READY")
        self.assertIn("COMPDEF-READY", result.stdout)

    def test_startup_does_not_query_gh_extensions(self) -> None:
        self.start("-i", script="true")
        self.assertNotIn("gh ", self.calls.read_text())


if __name__ == "__main__":
    unittest.main()
