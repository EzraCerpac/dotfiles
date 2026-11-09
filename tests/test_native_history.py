"""Integration tests for mise's native encrypted dotfile history."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import shutil
import stat
import subprocess
import tempfile
import unittest

from lib.prereq import mise_binary


MISE_ENV_VAR = "SETUP_TEST_MISE"
TARGET_KEY = "~/fixture/private"


class NativeFixture:
    """One fully isolated mise home, config, state, cache, and Git identity."""

    def __init__(
        self,
        root: Path,
        *,
        mise: str,
        age_keygen: str,
        git: str,
    ) -> None:
        self.root = root
        self.home = root / "home"
        self.config = self.home / ".config/mise"
        self.data = root / "data"
        self.state = root / "state"
        self.cache = root / "cache"
        self.xdg = root / "xdg"
        self.tmp = root / "tmp"
        self.identity = self.home / ".age/identity"
        self.repo = self.state / "history/repo.git"
        self.mise = mise
        self.age_keygen = age_keygen
        self.git = git

        for directory in (
            self.home,
            self.config,
            self.data,
            self.state,
            self.cache,
            self.xdg / "config",
            self.xdg / "data",
            self.xdg / "state",
            self.xdg / "cache",
            self.tmp,
        ):
            directory.mkdir(parents=True, exist_ok=True)

        path_entries = (
            str(Path(mise).parent),
            str(Path(age_keygen).parent),
            str(Path(git).parent),
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        )
        self.env = {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.xdg / "config"),
            "XDG_DATA_HOME": str(self.xdg / "data"),
            "XDG_STATE_HOME": str(self.xdg / "state"),
            "XDG_CACHE_HOME": str(self.xdg / "cache"),
            "MISE_CONFIG_DIR": str(self.config),
            "MISE_DATA_DIR": str(self.data),
            "MISE_STATE_DIR": str(self.state),
            "MISE_CACHE_DIR": str(self.cache),
            "MISE_TRUSTED_CONFIG_PATHS": str(self.config),
            "MISE_AUTO_INSTALL": "0",
            "MISE_QUIET": "1",
            "PATH": os.pathsep.join(dict.fromkeys(path_entries)),
            "TMPDIR": str(self.tmp),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(root / "gitconfig"),
            "LANG": "C.UTF-8",
        }

    def make_identity(self) -> str:
        self.identity.parent.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [self.age_keygen, "-o", str(self.identity)],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError("age-keygen could not create the fixture identity")
        self.identity.chmod(0o600)
        result = subprocess.run(
            [self.age_keygen, "-y", str(self.identity)],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError("age-keygen could not read the fixture recipient")
        recipient = result.stdout.strip()
        if not recipient.startswith("age1"):
            raise AssertionError("age-keygen did not return a public age recipient")
        return recipient

    def copy_identity_from(self, source: NativeFixture) -> None:
        self.identity.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source.identity, self.identity)
        self.identity.chmod(0o600)

    def write_config(
        self,
        recipients: str | tuple[str, ...],
        *,
        entries: tuple[str, ...] = (),
        public_source_sentinel: str | None = None,
    ) -> bytes:
        if isinstance(recipients, str):
            recipients = (recipients,)
        sections = [
            'min_version = "2026.9.7"',
            "",
            "[settings.age]",
            'identity_files = ["~/.age/identity"]',
            "",
            "[history.encryption]",
            f"recipients = {json.dumps(list(recipients))}",
        ]
        if public_source_sentinel is not None:
            sections.extend(
                [
                    "",
                    "[vars]",
                    f'public_source_sentinel = "{public_source_sentinel}"',
                ]
            )
        if entries:
            sections.extend(["", "[dotfiles]", *entries])
        contents = "\n".join(sections) + "\n"
        path = self.config / "config.toml"
        path.write_text(contents)
        return contents.encode()


class NativeHistoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        mise = mise_binary()
        if not mise:
            raise unittest.SkipTest(f"requires mise (or set {MISE_ENV_VAR})")
        cls.mise = str(Path(mise).resolve())
        if not Path(cls.mise).is_file():
            raise RuntimeError(f"{MISE_ENV_VAR} does not name a file")

        age_keygen = shutil.which("age-keygen")
        git = shutil.which("git")
        if not age_keygen or not git:
            raise unittest.SkipTest("native history tests need age-keygen and git")
        cls.age_keygen = str(Path(age_keygen).resolve())
        cls.git_bin = str(Path(git).resolve())

        with tempfile.TemporaryDirectory(prefix="mise-native-version-") as tmp:
            root = Path(tmp)
            for directory in ("home", "config", "data", "state", "cache", "xdg"):
                (root / directory).mkdir()
            env = {
                "HOME": str(root / "home"),
                "MISE_CONFIG_DIR": str(root / "config"),
                "MISE_DATA_DIR": str(root / "data"),
                "MISE_STATE_DIR": str(root / "state"),
                "MISE_CACHE_DIR": str(root / "cache"),
                "XDG_CONFIG_HOME": str(root / "xdg"),
                "XDG_DATA_HOME": str(root / "xdg"),
                "XDG_STATE_HOME": str(root / "xdg"),
                "XDG_CACHE_HOME": str(root / "xdg"),
                "PATH": os.pathsep.join(
                    (str(Path(cls.mise).parent), str(Path(cls.git_bin).parent), "/usr/bin", "/bin")
                ),
            }
            version = subprocess.run(
                [cls.mise, "--version"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )
        match = __import__("re").search(r"(\d+)\.(\d+)\.(\d+)", version.stdout)
        if version.returncode != 0 or not match or tuple(map(int, match.groups())) < (2026, 9, 7):
            raise RuntimeError(f"{MISE_ENV_VAR} must point to mise 2026.9.7 or newer")
        cls.mise_version = tuple(map(int, match.groups()))

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="mise-native-history-")
        self.base = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def fixture(self, name: str) -> NativeFixture:
        return NativeFixture(
            self.base / name,
            mise=self.mise,
            age_keygen=self.age_keygen,
            git=self.git_bin,
        )

    def run_mise(
        self,
        fixture: NativeFixture,
        *args: str,
        profile: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = fixture.env.copy()
        if profile is None:
            env.pop("MISE_ENV", None)
        else:
            env["MISE_ENV"] = profile
        return subprocess.run(
            [fixture.mise, *args],
            cwd=fixture.root,
            env=env,
            text=True,
            capture_output=True,
            timeout=60,
            check=False,
        )

    def assert_mise_ok(
        self,
        fixture: NativeFixture,
        *args: str,
        profile: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        result = self.run_mise(fixture, *args, profile=profile)
        self.assertEqual(
            result.returncode,
            0,
            f"mise {args!r} failed:\n{result.stdout}{result.stderr}",
        )
        return result

    def run_git(self, fixture: NativeFixture, *args: str, git_dir: Path | None = None):
        return subprocess.run(
            [fixture.git, *( ["--git-dir", str(git_dir)] if git_dir else [] ), *args],
            cwd=fixture.root,
            env=fixture.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )

    def assert_git_ok(self, fixture: NativeFixture, *args: str, git_dir: Path | None = None):
        result = self.run_git(fixture, *args, git_dir=git_dir)
        self.assertEqual(result.returncode, 0, f"git {args!r} failed: {result.stderr}")
        return result

    def write_private_entry(
        self,
        fixture: NativeFixture,
        recipients: str | tuple[str, ...],
        profile: str,
    ) -> bytes:
        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, '
            f'variants = [{{ profile = "{profile}" }}] }}'
        )
        return fixture.write_config(recipients, entries=(entry,))

    def create_remote(self, fixture: NativeFixture) -> Path:
        bare = self.base / "history-origin.git"
        result = subprocess.run(
            [fixture.git, "init", "--bare", "--initial-branch=main", str(bare)],
            cwd=fixture.root,
            env=fixture.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, f"git init --bare failed: {result.stderr}")
        return bare

    def initialize_public_source_checkout(self, fixture: NativeFixture) -> Path:
        """Model an existing public mise-config checkout and a separate origin."""
        bare = self.base / "public-source-origin.git"
        result = subprocess.run(
            [fixture.git, "init", "--bare", "--initial-branch=main", str(bare)],
            cwd=fixture.root,
            env=fixture.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, f"could not create public fixture origin: {result.stderr}")

        for args in (
            ("init", "--initial-branch=main"),
            ("config", "user.name", "mise history fixture"),
            ("config", "user.email", "mise-history-fixture@example.invalid"),
        ):
            self.assert_git_ok(fixture, "-C", str(fixture.config), *args)

        (fixture.config / ".gitignore").write_text(
            "config.local.toml\nmiserc.toml\nconfig.host-*.toml\n"
        )
        for args in (
            ("add", ".gitignore", "config.toml"),
            ("commit", "-m", "fixture public config"),
            ("remote", "add", "origin", str(bare)),
            ("push", "--set-upstream", "origin", "main"),
        ):
            self.assert_git_ok(fixture, "-C", str(fixture.config), *args)

        self.assertEqual(
            self.assert_git_ok(
                fixture,
                "-C",
                str(fixture.config),
                "status",
                "--porcelain",
            ).stdout,
            "",
            "public config fixture should start clean",
        )
        return bare

    def test_first_checkpoint_is_encrypted_and_rollback_restores_content_and_mode(self) -> None:
        fixture = self.fixture("single")
        recipient = fixture.make_identity()
        self.write_private_entry(fixture, recipient, "host-mac-primary")
        live = fixture.home / "fixture/private"
        live.parent.mkdir(parents=True)
        first = f"native-history-fixture-{secrets.token_hex(24)}\n".encode()
        second = f"native-history-fixture-{secrets.token_hex(24)}\n".encode()
        live.write_bytes(first)
        live.chmod(0o640)
        first_snapshot = (live.read_bytes(), stat.S_IMODE(live.stat().st_mode), live.stat().st_ino)

        self.assertFalse(live.is_symlink())
        self.assertTrue(stat.S_ISREG(live.lstat().st_mode))
        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "save",
            profile="host-mac-primary",
        )
        self.assertEqual(
            (live.read_bytes(), stat.S_IMODE(live.stat().st_mode), live.stat().st_ino),
            first_snapshot,
            "native save must leave the live regular file and its mode intact",
        )

        manifest_result = self.assert_git_ok(
            fixture,
            "show",
            "HEAD:.mise-history/manifest.json",
            git_dir=fixture.repo,
        )
        manifest = json.loads(manifest_result.stdout)
        enrolled = next(item for item in manifest["enrollment"] if item["path"] == "home/fixture/private")
        self.assertTrue(enrolled["encrypt"])
        self.assertEqual(enrolled["variants"][0]["profile"], "host-mac-primary")
        self.assertEqual(
            manifest["permissions"]["home@host-mac-primary/fixture/private"],
            0o640,
        )

        live.write_bytes(second)
        live.chmod(0o600)
        second_snapshot = (live.read_bytes(), stat.S_IMODE(live.stat().st_mode), live.stat().st_ino)
        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "save",
            profile="host-mac-primary",
        )
        self.assertEqual(
            (live.read_bytes(), stat.S_IMODE(live.stat().st_mode), live.stat().st_ino),
            second_snapshot,
            "a later native save must not rewrite the live file",
        )

        objects = subprocess.run(
            [fixture.git, "--git-dir", str(fixture.repo), "cat-file", "--batch-all-objects", "--batch"],
            cwd=fixture.root,
            env=fixture.env,
            input=b"",
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(objects.returncode, 0, "could not read native Git objects")
        self.assertNotIn(first, objects.stdout, "the first plaintext fixture reached a Git object")
        self.assertNotIn(second, objects.stdout, "the second plaintext fixture reached a Git object")

        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "rollback",
            TARGET_KEY,
            "--yes",
            profile="host-mac-primary",
        )
        self.assertEqual(live.read_bytes(), first)
        self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o640)
        self.assertFalse(live.is_symlink())
        self.assertTrue(stat.S_ISREG(live.lstat().st_mode))

    def test_fresh_fetch_only_restore_fails_closed_without_key_and_keeps_existing_default(self) -> None:
        source = self.fixture("source")
        recipient = source.make_identity()
        self.write_private_entry(source, recipient, "host-mac-primary")
        source_live = source.home / "fixture/private"
        source_live.parent.mkdir(parents=True)
        remote_content = f"shared-private-{secrets.token_hex(24)}\n".encode()
        source_live.write_bytes(remote_content)
        source_live.chmod(0o640)
        self.assert_mise_ok(
            source,
            "bootstrap",
            "dotfiles",
            "save",
            profile="host-mac-primary",
        )

        bare = self.create_remote(source)
        self.assert_mise_ok(
            source,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "manual",
            "--yes",
            profile="host-mac-primary",
        )
        self.assert_mise_ok(source, "bootstrap", "dotfiles", "sync", profile="host-mac-primary")
        remote_tip = self.assert_git_ok(source, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip()

        destination = self.fixture("destination")
        destination_config = destination.write_config(
            recipient,
            public_source_sentinel="must-stay-local",
        )
        public_bare = self.initialize_public_source_checkout(destination)
        public_head = self.assert_git_ok(
            destination,
            "-C",
            str(destination.config),
            "rev-parse",
            "HEAD",
        ).stdout.strip()
        public_tree = self.assert_git_ok(
            destination,
            "-C",
            str(destination.config),
            "ls-tree",
            "-r",
            "--name-only",
            "HEAD",
        ).stdout
        public_remote_head = self.assert_git_ok(
            destination,
            "rev-parse",
            "refs/heads/main",
            git_dir=public_bare,
        ).stdout.strip()
        public_origin = self.assert_git_ok(
            destination,
            "-C",
            str(destination.config),
            "config",
            "--get",
            "remote.origin.url",
        ).stdout.strip()
        destination_live = destination.home / "fixture/private"
        destination_live.parent.mkdir(parents=True)
        local_default = f"local-default-{secrets.token_hex(24)}\n".encode()
        destination_live.write_bytes(local_default)
        destination_live.chmod(0o600)
        store = destination.repo
        store.parent.mkdir(parents=True, exist_ok=True)
        clone = subprocess.run(
            [
                destination.git,
                "clone",
                "--bare",
                "--single-branch",
                "--branch",
                "main",
                str(bare),
                str(store),
            ],
            cwd=destination.root,
            env=destination.env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        self.assertEqual(clone.returncode, 0, f"could not seed the native bare history store: {clone.stderr}")

        missing_key = self.run_mise(
            destination,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile="host-mac-primary",
        )
        self.assertNotEqual(missing_key.returncode, 0)
        self.assertIn("no age identity is available", (missing_key.stdout + missing_key.stderr).lower())
        self.assertEqual(destination_live.read_bytes(), local_default)
        self.assertEqual(stat.S_IMODE(destination_live.stat().st_mode), 0o600)
        self.assertEqual((destination.config / "config.toml").read_bytes(), destination_config)

        destination.copy_identity_from(source)
        self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile="host-mac-primary",
        )
        status = self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "status",
            "--json",
            profile="host-mac-primary",
        )
        sync_status = json.loads(status.stdout)["history"]["sync"]
        self.assertEqual(sync_status["mode"], "fetch-only")
        self.assertIsNone(sync_status["last_publish"])

        self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "pull",
            "--yes",
            profile="host-mac-primary",
        )
        self.assertEqual(destination_live.read_bytes(), local_default)
        self.assertEqual((destination.config / "config.toml").read_bytes(), destination_config)

        remote_rollback = self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{remote_tip}",
            "--all",
            "--dry-run",
            profile="host-mac-primary",
        )
        self.assertIn("write", remote_rollback.stdout)
        self.assertEqual(destination_live.read_bytes(), local_default)
        self.assertEqual(stat.S_IMODE(destination_live.stat().st_mode), 0o600)

        self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{remote_tip}",
            "--all",
            "--yes",
            profile="host-mac-primary",
        )
        self.assertEqual(destination_live.read_bytes(), remote_content)
        self.assertEqual(stat.S_IMODE(destination_live.stat().st_mode), 0o640)
        self.assertEqual((destination.config / "config.toml").read_bytes(), destination_config)

        self.assert_mise_ok(
            destination,
            "bootstrap",
            "dotfiles",
            "undo",
            "--yes",
            profile="host-mac-primary",
        )
        self.assertEqual(destination_live.read_bytes(), local_default)
        self.assertEqual(stat.S_IMODE(destination_live.stat().st_mode), 0o600)
        self.assertEqual((destination.config / "config.toml").read_bytes(), destination_config)
        remote_tip_after = self.assert_git_ok(
            destination,
            "rev-parse",
            "refs/heads/main",
            git_dir=bare,
        ).stdout.strip()
        self.assertEqual(remote_tip_after, remote_tip, "fetch-only restore must not publish to the origin")

        self.assertEqual(
            self.assert_git_ok(
                destination,
                "-C",
                str(destination.config),
                "rev-parse",
                "HEAD",
            ).stdout.strip(),
            public_head,
        )
        self.assertEqual(
            self.assert_git_ok(
                destination,
                "-C",
                str(destination.config),
                "status",
                "--porcelain",
            ).stdout,
            "",
        )
        self.assertEqual(
            self.assert_git_ok(
                destination,
                "-C",
                str(destination.config),
                "ls-tree",
                "-r",
                "--name-only",
                "HEAD",
            ).stdout,
            public_tree,
        )
        self.assertEqual(
            self.assert_git_ok(
                destination,
                "rev-parse",
                "refs/heads/main",
                git_dir=public_bare,
            ).stdout.strip(),
            public_remote_head,
        )
        self.assertEqual(
            self.assert_git_ok(
                destination,
                "-C",
                str(destination.config),
                "config",
                "--get",
                "remote.origin.url",
            ).stdout.strip(),
            public_origin,
        )


if __name__ == "__main__":
    unittest.main()
