#!/usr/bin/env -S uv run --script
"""Focused release selection and safe application publishing checks."""
import importlib.util
import json
from pathlib import Path
import plistlib
import platform
import struct
import subprocess
import shutil
import tempfile
import tarfile
import urllib.error
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dots_github", ROOT / "setup-scripts/lib/dots-github.py")
github = importlib.util.module_from_spec(spec)
spec.loader.exec_module(github)


def assets(*names):
    return [{"name": name} for name in names]


def make_app(root, name="Example.app"):
    app = root / name
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "test.example", "CFBundleExecutable": "Example"}))
    binary = app / "Contents/MacOS/Example"
    binary.write_bytes(b"fake app executable")
    binary.chmod(0o755)
    return app


class ReleaseTests(unittest.TestCase):
    def test_url_scope(self):
        self.assertEqual(github.repository("https://github.com/Owner/repo.git/"), "Owner/repo")
        for url in ("http://github.com/a/b", "https://github.com.evil/a/b", "https://github.com/a/b/tree/main", "https://github.com/a/b?token=x", "https://github.com/a/..", "https://u@github.com/a/b"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                github.repository(url)

    def test_mac_zip_over_equivalent_dmg(self):
        chosen = github.choose_asset(assets("MacTap-2.1.2.dmg", "MacTap-2.1.2.zip"), system="darwin", machine="arm64")
        self.assertEqual(chosen["name"], "MacTap-2.1.2.zip")

    def test_platform_and_arch(self):
        chosen = github.choose_asset(assets("tool-linux-arm64.tar.gz", "tool-darwin-x86_64.tar.gz", "tool-darwin-aarch64.tar.gz", "tool-darwin-aarch64.tar.gz.sha256"), system="darwin", machine="arm64")
        self.assertEqual(chosen["name"], "tool-darwin-aarch64.tar.gz")

    def test_ambiguity_and_override(self):
        candidates = assets("one-macos-arm64.zip", "two-macos-arm64.zip")
        with self.assertRaisesRegex(ValueError, "--asset"):
            github.choose_asset(candidates, system="darwin", machine="arm64")
        self.assertEqual(github.choose_asset(candidates, "two-*.zip")["name"], "two-macos-arm64.zip")

    def test_source_only(self):
        with self.assertRaisesRegex(ValueError, "source builds"):
            with patch.object(github.urllib.request, "urlopen") as request:
                request.return_value.__enter__.return_value.read.return_value = b'{"assets": []}'
                github.fetch_release("owner/repo")

    def test_no_release(self):
        error = urllib.error.HTTPError("https://api.github.com", 404, "Not found", None, None)
        with patch.object(github.urllib.request, "urlopen", side_effect=error):
            with self.assertRaisesRegex(ValueError, "source builds"):
                github.fetch_release("owner/repo")

    def test_unsupported_installer(self):
        with self.assertRaisesRegex(ValueError, "ZIP/tar"):
            github.choose_asset(assets("Example.dmg"), system="darwin", machine="arm64")

    def test_tar_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "bad.tar"
            with tarfile.open(archive, "w") as stream:
                stream.addfile(tarfile.TarInfo("../escape"))
            with self.assertRaisesRegex(ValueError, "unsafe archive path"):
                github.archive_app(archive)

    def test_app_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "app.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                stream.writestr("Example.app/Contents/Info.plist", b"fixture")
            self.assertEqual(github.archive_app(archive), "Example.app")

    def test_path_traversal(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "bad.zip"
            for name in ("../escape", "/escape", "Example.app/../../escape"):
                with zipfile.ZipFile(archive, "w") as stream:
                    stream.writestr(name, "fixture")
                with self.assertRaisesRegex(ValueError, "unsafe archive path"):
                    github.archive_app(archive)

    def test_symlink_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "bad.zip"
            with zipfile.ZipFile(archive, "w") as stream:
                info = zipfile.ZipInfo("escape")
                info.create_system = 3
                info.external_attr = 0o120777 << 16
                stream.writestr(info, "../../outside")
            with self.assertRaisesRegex(ValueError, "escapes"):
                github.archive_app(archive)

    def test_hook_is_portable_and_version_pattern_upgrades(self):
        release = {"tag_name": "v2.1.2", "assets": assets("MacTap-2.1.2.zip")}
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value="MacTap.app"), patch.object(github.platform, "system", return_value="Darwin"):
            request = github.resolve("https://github.com/owner/repo")
        self.assertIn('asset_pattern="MacTap-*.zip"', request)
        self.assertIn("${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/setup-scripts/lib/dots-github.py", request)
        self.assertIn("strip_components=0", request)
        self.assertIn('when="always"', request)
        self.assertIn("postinstall={run=", request)
        self.assertNotIn(str(ROOT), request)


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.apps = self.root / "Applications"
        self.apps.mkdir()
        self.state = self.root / "state"
        self.source = make_app(self.root)
        self.commands = patch.object(github.subprocess, "run", side_effect=self.run_command)
        self.commands.start()

    def tearDown(self):
        self.commands.stop()
        self.temporary.cleanup()

    def run_command(self, command, **kwargs):
        if command[0] == "/usr/bin/ditto":
            shutil.copytree(command[-2], command[-1], symlinks=True)

    def publish(self, repo="owner/repo"):
        github.publish_app(self.source, repo, self.apps, self.state)

    def test_new_and_managed_upgrade(self):
        self.publish()
        (self.source / "Contents/MacOS/Example").write_bytes(b"updated")
        self.publish()
        self.assertEqual((self.apps / "Example.app/Contents/MacOS/Example").read_bytes(), b"updated")
        marker = next(self.state.glob("*.json"))
        self.assertEqual(json.loads(marker.read_text())["repo"], "owner/repo")

    def test_unmanaged_bundle_preserved(self):
        make_app(self.apps)
        with self.assertRaisesRegex(ValueError, "not managed"):
            self.publish()
        self.assertEqual((self.apps / "Example.app/Contents/MacOS/Example").read_bytes(), b"fake app executable")

    def test_different_repository_cannot_replace(self):
        self.publish()
        with self.assertRaisesRegex(ValueError, "not managed"):
            self.publish("another/repo")

    def test_bundle_symlink_escape(self):
        (self.source / "Contents/escape").symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "escapes"):
            self.publish()
        self.assertFalse((self.apps / "Example.app").exists())

    def test_failed_marker_write_rolls_back_upgrade(self):
        self.publish()
        (self.source / "Contents/MacOS/Example").write_bytes(b"updated")
        with patch.object(github.os, "replace", side_effect=OSError("state write failed")):
            with self.assertRaisesRegex(OSError, "state write failed"):
                self.publish()
        self.assertEqual((self.apps / "Example.app/Contents/MacOS/Example").read_bytes(), b"fake app executable")
        self.assertEqual(len(list(self.state.iterdir())), 1)

    def test_invalid_plist_field(self):
        (self.source / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "test.example", "CFBundleExecutable": 123}))
        with self.assertRaisesRegex(ValueError, "valid executable"):
            self.publish()

    def test_failed_copy_preserves_existing(self):
        self.publish()
        with patch.object(github.subprocess, "run", side_effect=OSError("copy failed")):
            with self.assertRaisesRegex(OSError, "copy failed"):
                self.publish()
        self.assertTrue((self.apps / "Example.app/Contents/Info.plist").is_file())


@unittest.skipUnless(platform.system() == "Darwin", "requires native macOS bundle tools")
class NativeBundleTests(unittest.TestCase):
    def test_appledouble_extraction_preserves_signature(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = make_app(root)
            shutil.copyfile("/usr/bin/true", app / "Contents/MacOS/Example")
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
            metadata = app / "Contents/._Info.plist"
            metadata.write_bytes(struct.pack(">II16sH", 0x00051607, 0x00020000, b"\x00" * 16, 0))
            invalid = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)
            self.assertIn(b"sealed resource", invalid.stderr)
            applications = root / "Applications"
            applications.mkdir()
            github.publish_app(app, "owner/repo", applications, root / "state")
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(applications / app.name)], check=True, capture_output=True)
            self.assertFalse((applications / app.name / "Contents/._Info.plist").exists())
            self.assertTrue(metadata.exists(), "normalization must be limited to the publication stage")


if __name__ == "__main__":
    unittest.main()
