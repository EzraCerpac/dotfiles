from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MISE = Path("/Users/ezracerpac/.local/state/mise-migration/tools/mise")
HISTORY_ORIGIN = "git@github.com:EzraCerpac/dotfiles-state.git"
PROFILE = "workstation,host-mac-primary"
NAS_PROFILE = "nas,host-cerpacnas"
MAC_BRANCH = "host-mac-primary"
NAS_BRANCH = "host-cerpacnas"


class NativeRestoreIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mise = Path(os.environ.get("SETUP_TEST_MISE", DEFAULT_MISE))
        if not cls.mise.is_file() or not os.access(cls.mise, os.X_OK):
            raise unittest.SkipTest("set SETUP_TEST_MISE to an executable mise installation")
        cls.age = subprocess.run([str(cls.mise), "which", "age"], text=True, capture_output=True).stdout.strip() or shutil.which("age")
        cls.age_keygen = shutil.which("age-keygen")
        cls.git = shutil.which("git")
        cls.node_bins = sorted(Path.home().glob(".local/share/mise/installs/node/*/bin/node"))
        if not cls.age or not cls.age_keygen or not cls.git or not cls.node_bins:
            raise unittest.SkipTest("native restore test needs age, age-keygen, Git, and an installed Node runtime")
        version = subprocess.run([str(cls.mise), "--version"], text=True, capture_output=True, check=False)
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", version.stdout)
        if version.returncode != 0 or not match or tuple(map(int, match.groups())) < (2026, 9, 7):
            raise unittest.SkipTest("native restore integration needs mise 2026.9.7 or newer")

    def _run(self, args: list[str], env: dict[str, str], cwd: Path, *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout, check=False)
        self.assertEqual(result.returncode, 0, f"command failed: {args!r}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        return result

    def test_restore_uses_native_history_without_touching_public_checkout(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mise-native-restore-") as temporary:
            base = Path(temporary)
            home = base / "home"
            config = home / ".config/mise"
            fixture_dir = home / "fixture"
            target = fixture_dir / "private"
            codex_config = home / ".codex/config.toml"
            data_dir = base / "data/mise"
            producer_state = base / "producer-state/mise"
            nas_state = base / "nas-state/mise"
            restore_state = base / "restore-state/mise"
            cache_dir = base / "cache/mise"
            global_git_config = base / "gitconfig"
            remote = base / "dotfiles-state.git"
            key = home / ".age/identity"
            for path in (config, fixture_dir, codex_config.parent, key.parent, data_dir, producer_state, nas_state, restore_state, cache_dir):
                path.mkdir(parents=True, exist_ok=True)
            shutil.copytree(SOURCE_ROOT / "tasks", config / "tasks")

            self._run([self.git, "init", "--bare", "--initial-branch=main", str(remote)], os.environ.copy(), base)
            self._run([self.git, "config", "--file", str(global_git_config), "--add", f"url.file://{remote}.insteadOf", HISTORY_ORIGIN], os.environ.copy(), base)
            self._run([self.age_keygen, "-o", str(key)], os.environ.copy(), base)
            recipient_result = self._run([self.age_keygen, "-y", str(key)], os.environ.copy(), base)
            recipient = recipient_result.stdout.strip()
            self.assertRegex(recipient, r"^age1[0-9a-z]+$")
            nas_key = home / ".age/nas-identity"
            self._run([self.age_keygen, "-o", str(nas_key)], os.environ.copy(), base)
            nas_recipient = self._run([self.age_keygen, "-y", str(nas_key)], os.environ.copy(), base).stdout.strip()
            self.assertRegex(nas_recipient, r"^age1[0-9a-z]+$")
            key.chmod(0o600)
            nas_key.chmod(0o600)

            (config / ".gitignore").write_text("config.local.toml\nmiserc.toml\nconfig.host-*.toml\n")
            (config / "config.toml").write_text(
                f'''min_version = "2026.9.7"

[settings]
dotfiles.root = "~/fixture"
trusted_config_paths = ["{config}"]
history.sync = "manual"

[settings.age]
identity_files = ["~/.age/identity"]

[history.encryption]
recipients = ["{recipient}", "{nas_recipient}"]
'''
            )
            host_config = config / "config.host-mac-primary.toml"
            host_entry = '''[dotfiles."~/fixture/private"]
mode = "track"
encrypt = true
variants = [{ profile = "host-mac-primary" }, { profile = "host-cerpacnas" }]
'''
            host_config.write_text(host_entry)
            (config / "config.host-cerpacnas.toml").write_text(host_entry)
            (config / "config.nas.toml").write_text(
                '''[settings.age]
identity_files = ["~/.age/nas-identity"]
'''
            )
            self._run([self.git, "init", "--initial-branch=main"], os.environ.copy(), config)
            self._run([self.git, "-C", str(config), "add", ".gitignore", "config.toml", "config.nas.toml"], os.environ.copy(), config)
            self._run(
                [self.git, "-C", str(config), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "-m", "fixture public source"],
                os.environ.copy(),
                config,
            )
            self._run([self.git, "-C", str(config), "remote", "add", "origin", "https://github.com/EzraCerpac/dotfiles.git"], os.environ.copy(), config)
            public_head = self._run([self.git, "-C", str(config), "rev-parse", "HEAD"], os.environ.copy(), config).stdout.strip()
            public_origin = self._run([self.git, "-C", str(config), "remote", "get-url", "origin"], os.environ.copy(), config).stdout.strip()
            public_status = self._run([self.git, "-C", str(config), "status", "--porcelain"], os.environ.copy(), config).stdout

            node_bin = self.node_bins[-1].parent
            path = os.pathsep.join([str(node_bin), str(Path(self.age).parent), str(Path(self.git).parent), "/opt/homebrew/bin", "/usr/bin", "/bin"])
            common_env = os.environ.copy()
            for name in list(common_env):
                if name.startswith('__MISE_'):
                    common_env.pop(name)
            common_env.update(
                {
                    "HOME": str(home),
                    "PATH": path,
                    "MISE_CONFIG_DIR": str(config),
                    "MISE_DATA_DIR": str(data_dir),
                    "MISE_CACHE_DIR": str(cache_dir),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_DATA_HOME": str(base / "data"),
                    "XDG_STATE_HOME": str(base / "state"),
                    "XDG_CACHE_HOME": str(base / "cache"),
                    "MISE_TRUSTED_CONFIG_PATHS": str(config),
                    "MISE_AUTO_INSTALL": "0",
                    "GIT_CONFIG_GLOBAL": str(global_git_config),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_AUTHOR_NAME": "Fixture",
                    "GIT_AUTHOR_EMAIL": "fixture@example.test",
                    "GIT_COMMITTER_NAME": "Fixture",
                    "GIT_COMMITTER_EMAIL": "fixture@example.test",
                    "SETUP_MISE_BIN": str(self.mise),
                    "SETUP_PROFILE": "workstation",
                    "SETUP_MACHINE_ID": "mac-primary",
                    "SETUP_HISTORY_ORIGIN": HISTORY_ORIGIN,
                    "SETUP_AGE_IDENTITY": "~/.age/identity",
                    "MISE_STATE_DIR": str(producer_state),
                }
            )

            remote_bytes = b"encrypted history restored through native mise\n"
            target.write_bytes(remote_bytes)
            target.chmod(0o600)
            native_prefix = [str(self.mise), "-C", str(config), "-E", PROFILE]
            self._run(native_prefix + ["bootstrap", "dotfiles", "save"], common_env, base)
            mac_commit = self._run([self.git, "--git-dir", str(producer_state / "history/repo.git"), "rev-parse", "HEAD"], common_env, base).stdout.strip()
            self._run([self.git, "--git-dir", str(producer_state / "history/repo.git"), "push", str(remote), f"HEAD:refs/heads/{MAC_BRANCH}"], common_env, base)

            nas_bytes = b"independent NAS branch state\n"
            target.write_bytes(nas_bytes)
            target.chmod(0o600)
            nas_env = common_env.copy()
            nas_env.update({
                "SETUP_PROFILE": "nas",
                "SETUP_MACHINE_ID": "cerpacnas",
                "SETUP_AGE_IDENTITY": "~/.age/nas-identity",
                "MISE_STATE_DIR": str(nas_state),
            })
            nas_prefix = [str(self.mise), "-C", str(config), "-E", NAS_PROFILE]
            self._run(nas_prefix + ["bootstrap", "dotfiles", "save"], nas_env, base)
            nas_commit = self._run([self.git, "--git-dir", str(nas_state / "history/repo.git"), "rev-parse", "HEAD"], nas_env, base).stdout.strip()
            self.assertNotEqual(mac_commit, nas_commit)
            self._run([self.git, "--git-dir", str(nas_state / "history/repo.git"), "push", str(remote), f"HEAD:refs/heads/{NAS_BRANCH}"], nas_env, base)

            # This fixture reuses one home for two machines. Native origin
            # enrollment captures live bytes, so restore each simulated host's
            # contents before connecting its independent history store.
            target.write_bytes(remote_bytes)
            self._run(native_prefix + ["--yes", "bootstrap", "dotfiles", "origin", "set", HISTORY_ORIGIN, "--branch", MAC_BRANCH, "--sync", "manual"], common_env, base)
            target.write_bytes(nas_bytes)
            self._run(nas_prefix + ["--yes", "bootstrap", "dotfiles", "origin", "set", HISTORY_ORIGIN, "--branch", NAS_BRANCH, "--sync", "manual"], nas_env, base)
            mac_remote_head = self._run([self.git, "--git-dir", str(remote), "rev-parse", f"refs/heads/{MAC_BRANCH}"], common_env, base).stdout.strip()
            nas_remote_head = self._run([self.git, "--git-dir", str(remote), "rev-parse", f"refs/heads/{NAS_BRANCH}"], common_env, base).stdout.strip()
            self.assertTrue(mac_remote_head)
            self.assertTrue(nas_remote_head)
            self.assertNotEqual(mac_remote_head, nas_remote_head)
            self.assertNotEqual(subprocess.run([self.git, "--git-dir", str(remote), "show-ref", "--verify", "refs/heads/main"], env=common_env, capture_output=True, check=False).returncode, 0)

            default_bytes = b"local defaults must be replaced by the saved host state\\n"
            target.write_bytes(default_bytes)
            target.chmod(0o644)
            codex_config.write_text("[fixture]\nrestored = true\n")
            codex_config.chmod(0o644)
            common_env["MISE_STATE_DIR"] = str(restore_state)
            task_env = common_env.copy()
            task_env.update({"SETUP_CONFIG_ROOT": str(config), "SETUP_GIT_BIN": self.git})
            task = subprocess.run(
                [str(SOURCE_ROOT / "tasks/setup/restore")],
                cwd=base,
                env=task_env,
                text=True,
                capture_output=True,
                timeout=90,
                check=False,
            )
            self.assertEqual(task.returncode, 0, f"stdout:\n{task.stdout}\nstderr:\n{task.stderr}")
            self.assertEqual(target.read_bytes(), remote_bytes, f"stdout:\n{task.stdout}\nstderr:\n{task.stderr}")
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(codex_config.stat().st_mode & 0o777, 0o600)
            self.assertIn("fetch-only", task.stdout)
            self.assertFalse((restore_state / "history/.repo.git.restore-pending").exists())
            self.assertEqual(self._run([self.git, "--git-dir", str(remote), "rev-parse", f"refs/heads/{MAC_BRANCH}"], common_env, base).stdout.strip(), mac_remote_head)
            self.assertEqual(self._run([self.git, "--git-dir", str(remote), "rev-parse", f"refs/heads/{NAS_BRANCH}"], common_env, base).stdout.strip(), nas_remote_head)
            self.assertNotEqual(subprocess.run([self.git, "--git-dir", str(remote), "show-ref", "--verify", "refs/heads/main"], env=common_env, capture_output=True, check=False).returncode, 0)

            self.assertEqual(self._run([self.git, "-C", str(config), "rev-parse", "HEAD"], common_env, config).stdout.strip(), public_head)
            self.assertEqual(self._run([self.git, "-C", str(config), "remote", "get-url", "origin"], common_env, config).stdout.strip(), public_origin)
            self.assertEqual(self._run([self.git, "-C", str(config), "status", "--porcelain"], common_env, config).stdout, public_status)


if __name__ == "__main__":
    unittest.main()
