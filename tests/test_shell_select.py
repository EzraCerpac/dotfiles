"""Focused tests for the profile-wide native Fish login-shell task."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ShellSelectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / "setup-root"
        shutil.copytree(ROOT / "tasks", self.root / "tasks")
        (self.root / "tasks/setup/exceptions.tsv").write_text("")
        self.home = self.base / "home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "calls.log"
        self.local = self.root / "config.local.toml"
        self.local.write_text("")
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            PATH=f"{self.bin}:{os.environ.get('PATH', '')}",
            SETUP_CONFIG_ROOT=str(self.root),
            SETUP_MISE_BIN=str(self.bin / "mise"),
            SETUP_PROFILE="nas",
            SETUP_MACHINE_ID="fixture-nas",
            SHELL_SELECT_LOG=str(self.log),
            SUDO_OK="1",
            MISE_FISH_INSTALL="",
            MISE_USER_STATUS="1",
            MISE_APPLY_STATUS="0",
        )
        self.env.pop("MISE_DATA_DIR", None)
        self.env.pop("XDG_DATA_HOME", None)
        self._write_executable(
            self.bin / "mise",
            """#!/usr/bin/env bash
set -u
printf 'mise' >> "$SHELL_SELECT_LOG"
printf '\\t%s' "$@" >> "$SHELL_SELECT_LOG"
printf '\\n' >> "$SHELL_SELECT_LOG"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -C|-E) shift 2 ;;
        --yes|--missing) shift ;;
        *) break ;;
    esac
done
case "${1:-} ${2:-} ${3:-}" in
    'config get --file')
        key="${@: -1}"
        if [[ "$key" == bootstrap.user.login_shell ]] && [[ -f "$SETUP_CONFIG_ROOT/config.local.toml" ]]; then
            sed -n 's/^bootstrap.user.login_shell = "\\(.*\\)"$/\\1/p' "$SETUP_CONFIG_ROOT/config.local.toml"
        fi
        ;;
    'config set --file')
        value="${@: -1}"
        printf 'bootstrap.user.login_shell = "%s"\\n' "$value" > "$SETUP_CONFIG_ROOT/config.local.toml"
        ;;
    'ls --current --json')
        printf '{"github:fish-shell/fish-shell":[{"active":true,"installed":true,"requested_version":"latest","install_path":"%s"}]}\\n' "$MISE_FISH_INSTALL"
        ;;
    'bootstrap user status')
        exit "${MISE_USER_STATUS:-0}"
        ;;
    'bootstrap user apply')
        exit "${MISE_APPLY_STATUS:-0}"
        ;;
esac
exit 0
""",
        )
        self._write_executable(
            self.bin / "sudo",
            "#!/usr/bin/env bash\n[[ \"${SUDO_OK:-0}\" == 1 ]]\n",
        )
        self._write_executable(
            self.bin / "id",
            "#!/usr/bin/env bash\n[[ \"${1:-}\" == -u ]] || exit 2\nprintf '%s\\n' \"${FAKE_UID:-501}\"\n",
        )
        self._write_executable(
            self.bin / "jq",
            "#!/usr/bin/env bash\ncat >/dev/null\nprintf '%s\\n' \"$MISE_FISH_INSTALL\"\n",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _write_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def _write_fish(self, path: Path) -> None:
        self._write_executable(
            path,
            """#!/usr/bin/env bash
if [[ "${1:-}" == --no-config && "${3:-}" == -c ]]; then
    exit 0
fi
printf 'fish, version 4.9.3\\n'
""",
        )

    def _run(self, *, profile: str = "nas", extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        env["SETUP_PROFILE"] = profile
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.root / "tasks/local/shell-select.sh")],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def _calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_nas_uses_host_fish_and_native_user_bootstrap(self) -> None:
        fish = self.bin / "fish"
        self._write_fish(fish)

        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('bootstrap.user.login_shell', self.local.read_text())
        self.assertIn(str(fish), self.local.read_text())
        self.assertTrue(any('bootstrap\tuser\tapply' in call for call in self._calls()))

    def test_host_fish_stable_link_is_not_replaced(self) -> None:
        host_fish = self.bin / "host-fish"
        self._write_fish(host_fish)
        stable = self.home / ".local/bin/fish"
        stable.parent.mkdir(parents=True)
        stable.symlink_to(host_fish)
        data_dir = self.base / "custom-mise-data"
        install = data_dir / "installs/github-fish-shell-fish-shell/4.9.3"
        install.mkdir(parents=True)
        (install.parent / "latest").symlink_to(install.name)
        self._write_fish(install / "fish")

        result = self._run(
            extra_env={
                "MISE_DATA_DIR": str(data_dir),
                "MISE_FISH_INSTALL": str(install),
                "PATH": f"{stable.parent}:{self.bin}:{os.environ.get('PATH', '')}",
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(stable), str(host_fish))

    def test_mise_fish_gets_a_stable_latest_link(self) -> None:
        jq = shutil.which("jq")
        if not jq:
            self.skipTest("jq required to check real mise metadata parsing")
        (self.bin / "jq").unlink()
        (self.bin / "jq").symlink_to(jq)
        install = self.home / ".local/share/mise/installs/github-fish-shell-fish-shell/4.9.3"
        install.mkdir(parents=True)
        (install.parent / "latest").symlink_to(install.name)
        fish = install / "fish"
        self._write_fish(fish)
        shim = self.home / ".local/share/mise/shims/fish"
        shim.parent.mkdir(parents=True)
        self._write_fish(shim)
        self.env["PATH"] = f"{shim.parent}:{self.bin}:{os.environ.get('PATH', '')}"
        self.env["MISE_FISH_INSTALL"] = str(install)

        result = self._run(extra_env={"PATH": self.env["PATH"], "MISE_FISH_INSTALL": str(install)})

        self.assertEqual(result.returncode, 0, result.stderr)
        stable = self.home / ".local/bin/fish"
        self.assertTrue(stable.is_symlink())
        self.assertEqual(os.readlink(stable), str(install.parent / "latest/fish"))
        self.assertIn(str(stable), self.local.read_text())

    def _assert_custom_mise_data_dir_uses_stable_latest_link(
        self, *, data_dir: Path, data_env: dict[str, str]
    ) -> None:
        jq = shutil.which("jq")
        if not jq:
            self.skipTest("jq required to check real mise metadata parsing")
        (self.bin / "jq").unlink()
        (self.bin / "jq").symlink_to(jq)
        install = data_dir / "installs/github-fish-shell-fish-shell/4.9.3"
        install.mkdir(parents=True)
        (install.parent / "latest").symlink_to(install.name)
        fish = install / "fish"
        self._write_fish(fish)
        shim = data_dir / "shims/fish"
        shim.parent.mkdir(parents=True)
        self._write_fish(shim)
        env = {
            **data_env,
            "PATH": f"{shim.parent}:{self.bin}:{os.environ.get('PATH', '')}",
            "MISE_FISH_INSTALL": str(install),
        }

        result = self._run(extra_env=env)

        self.assertEqual(result.returncode, 0, result.stderr)
        stable = self.home / ".local/bin/fish"
        self.assertTrue(stable.is_symlink())
        self.assertEqual(os.readlink(stable), str(install.parent / "latest/fish"))
        self.assertIn(str(stable), self.local.read_text())

    def test_mise_fish_honors_custom_data_dir(self) -> None:
        data_dir = self.base / "custom-mise-data"
        self._assert_custom_mise_data_dir_uses_stable_latest_link(
            data_dir=data_dir, data_env={"MISE_DATA_DIR": str(data_dir)}
        )

    def test_mise_fish_honors_xdg_data_home(self) -> None:
        xdg_data_home = self.base / "xdg-data"
        self._assert_custom_mise_data_dir_uses_stable_latest_link(
            data_dir=xdg_data_home / "mise",
            data_env={"XDG_DATA_HOME": str(xdg_data_home)},
        )

    def _assert_stale_stable_link_is_repointed(
        self, *, old_data_dir: Path, new_data_dir: Path, data_env: dict[str, str], shim_first: bool = False
    ) -> None:
        jq = shutil.which("jq")
        if not jq:
            self.skipTest("jq required to check real mise metadata parsing")
        (self.bin / "jq").unlink()
        (self.bin / "jq").symlink_to(jq)

        old_install = old_data_dir / "installs/github-fish-shell-fish-shell/4.8.2"
        old_install.mkdir(parents=True)
        self._write_fish(old_install / "fish")
        stable = self.home / ".local/bin/fish"
        stable.parent.mkdir(parents=True)
        stable.symlink_to(old_install / "fish")

        new_install = new_data_dir / "installs/github-fish-shell-fish-shell/4.9.3"
        new_install.mkdir(parents=True)
        (new_install.parent / "latest").symlink_to(new_install.name)
        self._write_fish(new_install / "fish")
        shim = new_data_dir / "shims/fish"
        shim.parent.mkdir(parents=True)
        self._write_fish(shim)
        env = {
            **data_env,
            # The existing stable link wins PATH lookup, as it does on an
            # already-bootstrapped host before a data-directory migration.
            "PATH": f"{shim.parent if shim_first else stable.parent}:{stable.parent if shim_first else shim.parent}:{self.bin}:{os.environ.get('PATH', '')}",
            "MISE_FISH_INSTALL": str(new_install),
        }

        result = self._run(extra_env=env)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(stable.is_symlink())
        self.assertEqual(os.readlink(stable), str(new_install.parent / "latest/fish"))
        self.assertIn(str(stable), self.local.read_text())

    def test_stale_default_mise_link_is_repointed_after_custom_data_dir(self) -> None:
        self._assert_stale_stable_link_is_repointed(
            old_data_dir=self.home / ".local/share/mise",
            new_data_dir=self.base / "custom-mise-data",
            data_env={"MISE_DATA_DIR": str(self.base / "custom-mise-data")},
        )

    def test_stale_custom_mise_link_is_repointed_after_new_custom_data_dir(self) -> None:
        old_data_dir = self.base / "old-custom-mise-data"
        new_data_dir = self.base / "new-custom-mise-data"
        self._assert_stale_stable_link_is_repointed(
            old_data_dir=old_data_dir,
            new_data_dir=new_data_dir,
            data_env={"MISE_DATA_DIR": str(new_data_dir)},
        )

    def test_stale_link_is_repointed_when_active_shim_wins_path(self) -> None:
        target = self.base / "active-mise-data"
        self._assert_stale_stable_link_is_repointed(
            old_data_dir=self.base / "previous-mise-data",
            new_data_dir=target,
            data_env={"MISE_DATA_DIR": str(target)},
            shim_first=True,
        )

    def test_unchanged_account_skips_native_apply(self) -> None:
        fish = self.bin / "fish"
        self._write_fish(fish)
        self.local.write_text(f'bootstrap.user.login_shell = "{fish}"\n')
        self.env["MISE_USER_STATUS"] = "0"

        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any('bootstrap\tuser\tapply' in call for call in self._calls()))
        self.assertIn("already the configured login shell", result.stdout)

    def test_existing_fish_account_can_enroll_without_admin(self) -> None:
        self._write_fish(self.bin / "fish")
        result = self._run(extra_env={"FAKE_UID": "501", "SUDO_OK": "0", "MISE_USER_STATUS": "0"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any('bootstrap\tuser\tapply' in call for call in self._calls()))

    def test_root_nas_does_not_need_sudo(self) -> None:
        fish = self.bin / "fish"
        self._write_fish(fish)

        result = self._run(extra_env={"FAKE_UID": "0", "SUDO_OK": "0"})

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any('bootstrap\tuser\tapply' in call for call in self._calls()))

    def test_noninteractive_without_passwordless_sudo_defers_account_change(self) -> None:
        fish = self.bin / "fish"
        self._write_fish(fish)
        self.env["SUDO_OK"] = "0"

        result = self._run(extra_env={"SUDO_OK": "0"})

        self.assertEqual(result.returncode, 3)
        self.assertIn("administrator approval", result.stderr)
        self.assertIn('bootstrap.user.login_shell', self.local.read_text())
        self.assertFalse(any('bootstrap\tuser\tapply' in call for call in self._calls()))

    def test_missing_fish_does_not_fallback_to_xonsh_or_write_config(self) -> None:
        xonsh = self.bin / "xonsh"
        self._write_executable(xonsh, "#!/usr/bin/env bash\nexit 0\n")
        result = self._run(extra_env={"PATH": f"{self.bin}:/usr/bin:/bin"})

        self.assertEqual(result.returncode, 1)
        self.assertIn("Fish is not installed", result.stderr)
        self.assertEqual(self.local.read_text(), "")


if __name__ == "__main__":
    unittest.main()
