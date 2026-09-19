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


MISE_ENV_VAR = "SETUP_TEST_MISE"
HOST_ONE = "host-one"
HOST_TWO = "host-two"
MAC_PROFILE = "host-mac-primary"
NAS_PROFILE = "host-cerpacnas"
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
        mise = os.environ.get(MISE_ENV_VAR)
        if not mise:
            raise unittest.SkipTest(f"set {MISE_ENV_VAR} to the staged mise binary")
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

    def test_host_profile_variants_keep_distinct_contents(self) -> None:
        fixture = self.fixture("profiles")
        recipient = fixture.make_identity()
        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, variants = '
            f'[{{ profile = "{HOST_ONE}" }}, {{ profile = "{HOST_TWO}" }}] }}'
        )
        fixture.write_config(recipient, entries=(entry,))
        live = fixture.home / "fixture/private"
        live.parent.mkdir(parents=True)
        first = f"profile-one-{secrets.token_hex(24)}\n".encode()
        second = f"profile-two-{secrets.token_hex(24)}\n".encode()
        live.write_bytes(first)
        live.chmod(0o600)
        self.assert_mise_ok(fixture, "bootstrap", "dotfiles", "save", profile=HOST_ONE)

        live.write_bytes(second)
        live.chmod(0o600)
        self.assert_mise_ok(fixture, "bootstrap", "dotfiles", "save", profile=HOST_TWO)

        tree = self.assert_git_ok(
            fixture,
            "ls-tree",
            "-r",
            "--name-only",
            "HEAD",
            git_dir=fixture.repo,
        ).stdout.splitlines()
        self.assertIn(f"home@{HOST_ONE}/fixture/private", tree)
        self.assertIn(f"home@{HOST_TWO}/fixture/private", tree)

        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "rollback",
            TARGET_KEY,
            "--yes",
            profile=HOST_ONE,
        )
        self.assertEqual(live.read_bytes(), first)
        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "rollback",
            TARGET_KEY,
            "--yes",
            profile=HOST_TWO,
        )
        self.assertEqual(live.read_bytes(), second)

    def test_single_recipient_host_separation_is_a_native_join_blocker(self) -> None:
        mac = self.fixture("single-recipient-mac")
        nas = self.fixture("single-recipient-nas")
        mac_recipient = mac.make_identity()
        nas_recipient = nas.make_identity()
        self.assertNotEqual(mac_recipient, nas_recipient)

        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, variants = '
            f'[{{ profile = "{MAC_PROFILE}" }}, {{ profile = "{NAS_PROFILE}" }}] }}'
        )
        mac.write_config(mac_recipient, entries=(entry,))
        nas.write_config(nas_recipient, entries=(entry,))
        mac_live = mac.home / "fixture/private"
        mac_live.parent.mkdir(parents=True)
        mac_content = f"mac-only-private-{secrets.token_hex(24)}\n".encode()
        mac_live.write_bytes(mac_content)
        mac_live.chmod(0o600)
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "save", profile=MAC_PROFILE)
        bare = self.create_remote(mac)
        self.assert_mise_ok(
            mac,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "manual",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "sync", profile=MAC_PROFILE)
        mac_commit = self.assert_git_ok(mac, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip()

        nas.repo.parent.mkdir(parents=True, exist_ok=True)
        clone = subprocess.run(
            [nas.git, "clone", "--bare", "--single-branch", "--branch", "main", str(bare), str(nas.repo)],
            cwd=nas.root,
            env=nas.env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        self.assertEqual(clone.returncode, 0, f"could not seed NAS native history: {clone.stderr}")
        nas_live = nas.home / "fixture/private"
        nas_live.parent.mkdir(parents=True)
        local_head_before = self.assert_git_ok(nas, "rev-parse", "HEAD", git_dir=nas.repo).stdout.strip()
        remote_head_before = self.assert_git_ok(nas, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip()

        # Single-recipient history cannot be joined by a host holding only its
        # own identity. Keep the native diagnostic and no-change behavior
        # explicit beside the passing multi-recipient acceptance test.
        result = self.run_mise(
            nas,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile=NAS_PROFILE,
        )
        self.assertNotEqual(result.returncode, 0, "single-recipient history unexpectedly accepted the NAS identity")
        self.assertIn("No matching keys found", result.stdout + result.stderr)
        self.assertIn("cannot unlock", result.stdout + result.stderr)
        self.assertFalse(nas_live.exists(), "failed connection applied a file to the NAS")
        self.assertEqual(
            self.assert_git_ok(nas, "rev-parse", "HEAD", git_dir=nas.repo).stdout.strip(),
            local_head_before,
            "failed connection changed the local history head",
        )
        self.assertEqual(
            self.assert_git_ok(nas, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip(),
            remote_head_before,
            "failed fetch-only connection published to the origin",
        )

    def test_full_recipient_set_allows_fresh_host_variant_restore(self) -> None:
        mac = self.fixture("multi-recipient-mac")
        nas = self.fixture("multi-recipient-nas")
        mac_recipient = mac.make_identity()
        nas_recipient = nas.make_identity()
        recipients = (mac_recipient, nas_recipient)
        self.assertNotEqual(mac.identity.read_bytes(), nas.identity.read_bytes())

        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, variants = '
            f'[{{ profile = "{MAC_PROFILE}" }}, {{ profile = "{NAS_PROFILE}" }}] }}'
        )
        # Both public recipients are present before either host saves its first
        # encrypted version. The private identities remain in separate homes.
        mac.write_config(recipients, entries=(entry,))
        nas.write_config(recipients, entries=(entry,))

        mac_live = mac.home / "fixture/private"
        mac_live.parent.mkdir(parents=True)
        mac_content = f"multi-recipient-mac-{secrets.token_hex(24)}\n".encode()
        mac_live.write_bytes(mac_content)
        mac_live.chmod(0o600)
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "save", profile=MAC_PROFILE)
        bare = self.create_remote(mac)
        self.assert_mise_ok(
            mac,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "manual",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "sync", profile=MAC_PROFILE)
        mac_commit = self.assert_git_ok(mac, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip()

        # A fresh NAS state store connects with its own key. The Mac variant is
        # decryptable through the shared public-recipient list, but selection
        # of the NAS profile must not apply that variant to the NAS live path.
        nas.repo.parent.mkdir(parents=True, exist_ok=True)
        clone = subprocess.run(
            [nas.git, "clone", "--bare", "--single-branch", "--branch", "main", str(bare), str(nas.repo)],
            cwd=nas.root,
            env=nas.env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        self.assertEqual(clone.returncode, 0, f"could not seed fresh NAS state: {clone.stderr}")
        nas_live = nas.home / "fixture/private"
        nas_live.parent.mkdir(parents=True)
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile=NAS_PROFILE,
        )
        self.assert_mise_ok(nas, "bootstrap", "dotfiles", "pull", "--yes", profile=NAS_PROFILE)
        self.assertFalse(nas_live.exists(), "fresh NAS profile applied the Mac variant")

        # Publish the NAS variant, then rebuild its local native store from the
        # remote to exercise an actual fresh-host restore of that variant.
        nas_content = f"multi-recipient-nas-{secrets.token_hex(24)}\n".encode()
        nas_live.write_bytes(nas_content)
        nas_live.chmod(0o600)
        nas.env["MISE_QUIET"] = "0"
        nas_save = self.run_mise(nas, "bootstrap", "dotfiles", "save", profile=NAS_PROFILE)
        self.assertEqual(nas_save.returncode, 0, f"NAS save failed: {nas_save.stdout}{nas_save.stderr}")
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "manual",
            "--yes",
            profile=NAS_PROFILE,
        )
        nas_sync = self.run_mise(nas, "bootstrap", "dotfiles", "sync", profile=NAS_PROFILE)
        self.assertEqual(nas_sync.returncode, 0, f"NAS sync failed: {nas_sync.stdout}{nas_sync.stderr}")
        nas_commit = self.assert_git_ok(nas, "rev-parse", "refs/heads/main", git_dir=bare).stdout.strip()
        self.assertNotEqual(
            mac_commit,
            nas_commit,
            f"NAS save/sync created no remote commit:\nsave:\n{nas_save.stdout}{nas_save.stderr}\nsync:\n{nas_sync.stdout}{nas_sync.stderr}",
        )

        for commit in (mac_commit, nas_commit):
            manifest = json.loads(
                self.assert_git_ok(
                    nas,
                    "show",
                    f"{commit}:.mise-history/manifest.json",
                    git_dir=bare,
                ).stdout
            )
            self.assertEqual(set(manifest["recipients"]), set(recipients))

        objects = subprocess.run(
            [nas.git, "--git-dir", str(bare), "cat-file", "--batch-all-objects", "--batch"],
            cwd=nas.root,
            env=nas.env,
            input=b"",
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(objects.returncode, 0, "could not inspect shared native history objects")
        for secret_value in (mac_content, nas_content, mac.identity.read_bytes(), nas.identity.read_bytes()):
            self.assertNotIn(secret_value, objects.stdout)

        shutil.rmtree(nas.repo)
        clone = subprocess.run(
            [nas.git, "clone", "--bare", "--single-branch", "--branch", "main", str(bare), str(nas.repo)],
            cwd=nas.root,
            env=nas.env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        self.assertEqual(clone.returncode, 0, f"could not recreate fresh NAS state: {clone.stderr}")
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile=NAS_PROFILE,
        )
        nas_live.write_bytes(f"nas-edited-{secrets.token_hex(16)}\n".encode())
        nas_live.chmod(0o600)
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{nas_commit}",
            "--all",
            "--yes",
            profile=NAS_PROFILE,
        )
        self.assertEqual(nas_live.read_bytes(), nas_content)

        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "sync", "--fetch-only", profile=MAC_PROFILE)
        self.assert_mise_ok(
            mac,
            "bootstrap",
            "dotfiles",
            "pull",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assertEqual(mac_live.read_bytes(), mac_content, "Mac selection applied the NAS variant")

    def test_recipient_change_does_not_reencrypt_old_history_for_a_new_host(self) -> None:
        mac = self.fixture("recipient-rotation-mac")
        nas = self.fixture("recipient-rotation-nas")
        mac_recipient = mac.make_identity()
        nas_recipient = nas.make_identity()
        all_recipients = (mac_recipient, nas_recipient)
        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, variants = '
            f'[{{ profile = "{MAC_PROFILE}" }}, {{ profile = "{NAS_PROFILE}" }}] }}'
        )
        mac.write_config(mac_recipient, entries=(entry,))
        mac_live = mac.home / "fixture/private"
        mac_live.parent.mkdir(parents=True)
        first_content = f"recipient-rotation-old-{secrets.token_hex(24)}\n".encode()
        mac_live.write_bytes(first_content)
        mac_live.chmod(0o600)
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "save", profile=MAC_PROFILE)
        first_commit = self.assert_git_ok(mac, "rev-parse", "HEAD", git_dir=mac.repo).stdout.strip()
        first_manifest = json.loads(
            self.assert_git_ok(
                mac,
                "show",
                f"{first_commit}:.mise-history/manifest.json",
                git_dir=mac.repo,
            ).stdout
        )
        self.assertEqual(set(first_manifest["recipients"]), {mac_recipient})

        # A recipient-only save creates a new native checkpoint. The save CLI
        # has no --force flag for a more explicit rotation operation.
        mac.write_config(all_recipients, entries=(entry,))
        force_result = self.run_mise(mac, "bootstrap", "dotfiles", "save", "--force", profile=MAC_PROFILE)
        self.assertNotEqual(force_result.returncode, 0, "native save unexpectedly accepted --force")
        self.assertIn("--force", force_result.stderr + force_result.stdout)
        after_force = self.assert_git_ok(mac, "rev-parse", "HEAD", git_dir=mac.repo).stdout.strip()
        self.assertEqual(after_force, first_commit)

        unchanged_save = self.run_mise(mac, "bootstrap", "dotfiles", "save", profile=MAC_PROFILE)
        self.assertEqual(
            unchanged_save.returncode,
            0,
            f"native save rejected an unchanged file after recipient change: {unchanged_save.stderr}",
        )
        rotated_commit = self.assert_git_ok(mac, "rev-parse", "HEAD", git_dir=mac.repo).stdout.strip()
        self.assertNotEqual(rotated_commit, first_commit)
        rotated_manifest = json.loads(
            self.assert_git_ok(
                mac,
                "show",
                f"{rotated_commit}:.mise-history/manifest.json",
                git_dir=mac.repo,
            ).stdout
        )
        self.assertEqual(set(rotated_manifest["recipients"]), set(all_recipients))

        second_content = f"recipient-rotation-new-{secrets.token_hex(24)}\n".encode()
        mac_live.write_bytes(second_content)
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "save", profile=MAC_PROFILE)
        newest_commit = self.assert_git_ok(mac, "rev-parse", "HEAD", git_dir=mac.repo).stdout.strip()

        bare = self.create_remote(mac)
        self.assert_mise_ok(
            mac,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "manual",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assert_mise_ok(mac, "bootstrap", "dotfiles", "sync", profile=MAC_PROFILE)

        nas.write_config(all_recipients, entries=(entry,))
        nas.repo.parent.mkdir(parents=True, exist_ok=True)
        clone = subprocess.run(
            [nas.git, "clone", "--bare", "--single-branch", "--branch", "main", str(bare), str(nas.repo)],
            cwd=nas.root,
            env=nas.env,
            text=True,
            capture_output=True,
            timeout=45,
            check=False,
        )
        self.assertEqual(clone.returncode, 0, f"could not seed NAS rotation probe: {clone.stderr}")
        nas_live = nas.home / "fixture/private"
        nas_live.parent.mkdir(parents=True)
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "origin",
            "set",
            str(bare),
            "--sync",
            "fetch-only",
            "--yes",
            profile=NAS_PROFILE,
        )
        self.assert_mise_ok(nas, "bootstrap", "dotfiles", "pull", "--yes", profile=NAS_PROFILE)
        self.assertFalse(nas_live.exists(), "fresh NAS profile applied the inactive Mac variant")
        nas_live.write_bytes(b"local-default-before-history-restore\n")
        nas_live.chmod(0o600)
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{rotated_commit}",
            "--all",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assertEqual(
            nas_live.read_bytes(),
            first_content,
            "native recipient-only save did not make the unchanged HEAD readable by the new identity",
        )
        old_restore = self.run_mise(
            nas,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{first_commit}",
            "--all",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assertNotEqual(old_restore.returncode, 0, "new identity unexpectedly restored the old Mac-only checkpoint")
        self.assertIn("No matching keys found", old_restore.stdout + old_restore.stderr)
        self.assertEqual(nas_live.read_bytes(), first_content, "failed old-checkpoint restore changed the live file")
        self.assert_mise_ok(
            nas,
            "bootstrap",
            "dotfiles",
            "rollback",
            "--to",
            f"commit:{newest_commit}",
            "--all",
            "--yes",
            profile=MAC_PROFILE,
        )
        self.assertEqual(nas_live.read_bytes(), second_content)

    def test_native_variant_permission_metadata_is_shared_between_profiles(self) -> None:
        fixture = self.fixture("permission-variants")
        recipient = fixture.make_identity()
        entry = (
            f'"{TARGET_KEY}" = {{ mode = "track", encrypt = true, variants = '
            f'[{{ profile = "{HOST_ONE}" }}, {{ profile = "{HOST_TWO}" }}] }}'
        )
        fixture.write_config(recipient, entries=(entry,))
        live = fixture.home / "fixture/private"
        live.parent.mkdir(parents=True)
        first = f"mode-one-{secrets.token_hex(24)}\n".encode()
        second = f"mode-two-{secrets.token_hex(24)}\n".encode()
        live.write_bytes(first)
        live.chmod(0o640)
        self.assert_mise_ok(fixture, "bootstrap", "dotfiles", "save", profile=HOST_ONE)

        live.write_bytes(second)
        live.chmod(0o600)
        self.assert_mise_ok(fixture, "bootstrap", "dotfiles", "save", profile=HOST_TWO)

        manifest = json.loads(
            self.assert_git_ok(
                fixture,
                "show",
                "HEAD:.mise-history/manifest.json",
                git_dir=fixture.repo,
            ).stdout
        )
        permissions = manifest["permissions"]
        self.assertEqual(permissions[f"home@{HOST_ONE}/fixture/private"], 0o640)
        self.assertEqual(permissions[f"home@{HOST_TWO}/fixture/private"], 0o600)

        self.assert_mise_ok(
            fixture,
            "bootstrap",
            "dotfiles",
            "rollback",
            TARGET_KEY,
            "--yes",
            profile=HOST_ONE,
        )
        self.assertEqual(live.read_bytes(), first)
        # On mise 2026.9.7, rollback to one profile's bytes retains the current
        # live mode and rewrites both variants' permission metadata to that mode.
        # Encrypted files shared across hosts therefore need one common mode.
        self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o600)
        after_rollback = json.loads(
            self.assert_git_ok(
                fixture,
                "show",
                "HEAD:.mise-history/manifest.json",
                git_dir=fixture.repo,
            ).stdout
        )["permissions"]
        self.assertEqual(after_rollback[f"home@{HOST_ONE}/fixture/private"], 0o600)
        self.assertEqual(after_rollback[f"home@{HOST_TWO}/fixture/private"], 0o600)

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
            profile="host-mac-primary",
        )
        self.assertIn("mode fetch-only", status.stdout)
        self.assertIn("last publish never", status.stdout)

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
