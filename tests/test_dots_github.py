#!/usr/bin/env -S uv run --script
"""Focused release selection and safe application publishing checks."""
import importlib.util
import io
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
        self.assertEqual(github.repository("https://github.com/Owner/Repo.git/"), "owner/repo")
        for url in ("http://github.com/a/b", "https://github.com.evil/a/b", "https://github.com/a/b/tree/main", "https://github.com/a/b?token=x", "https://github.com/a/..", "https://u@github.com/a/b"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                github.repository(url)

    def test_mac_zip_over_equivalent_dmg(self):
        chosen = github.choose_asset(assets("MacTap-2.1.2.dmg", "MacTap-2.1.2.zip"), system="darwin", machine="arm64")
        self.assertEqual(chosen["name"], "MacTap-2.1.2.zip")

    def test_platform_and_arch(self):
        chosen = github.choose_asset(assets("tool-linux-arm64.tar.gz", "tool-darwin-x86_64.tar.gz", "tool-darwin-aarch64.tar.gz", "tool-darwin-aarch64.tar.gz.sha256"), system="darwin", machine="arm64")
        self.assertEqual(chosen["name"], "tool-darwin-aarch64.tar.gz")

    def test_win_archive_is_excluded_on_mac_and_linux(self):
        for system in ("darwin", "linux"):
            with self.subTest(system=system):
                self.assertIsNone(github.asset_score("tool-win-x64.zip", system, "x86_64"))
        self.assertEqual(github.choose_asset(assets("tool-win-x64.zip", "tool-linux-x64.zip"), system="windows", machine="x86_64")["name"], "tool-win-x64.zip")

    def test_source_product_name_is_not_a_source_archive(self):
        candidates = assets("SourceGit-2026-macos-arm64.zip", "SourceGit-source.zip", "SourceGit-sources.tar.gz")
        self.assertEqual(github.choose_asset(candidates, system="darwin", machine="arm64")["name"], "SourceGit-2026-macos-arm64.zip")
        for name in ("SourceGit-source.zip", "SourceGit-sources.tar.gz", "source.zip", "tool-source-code.zip"):
            with self.subTest(name=name):
                self.assertIsNone(github.asset_score(name, "darwin", "arm64"))

    def test_other_architectures_do_not_select_x64(self):
        for machine in ("riscv64", "ppc64le", "i686"):
            for suffix in ("x64", "amd64", "x86_64", "x86-64"):
                with self.subTest(machine=machine, suffix=suffix):
                    self.assertIsNone(github.asset_score(f"tool-linux-{suffix}.zip", "linux", machine))
                    self.assertIsNone(github.asset_score(f"tool-linux-{suffix}-universal.zip", "linux", machine))
        self.assertEqual(github.asset_score("tool-linux-x64.zip", "linux", "x86_64"), 30)
        self.assertIsNotNone(github.asset_score("tool-macos-x64-universal.zip", "darwin", "arm64"))

    def test_hyphenated_x86_64_is_excluded_on_arm(self):
        self.assertIsNone(github.asset_score("tool-darwin-x86-64.tar.gz", "darwin", "arm64"))
        self.assertEqual(github.asset_score("tool-darwin-x86-64.tar.gz", "darwin", "x86_64"), 30)

    def test_32bit_architectures_are_excluded_on_64bit_hosts(self):
        for machine in ("arm64", "x86_64"):
            for suffix in ("arm", "armv6", "armv7", "armv7l", "armhf", "x86", "i386", "i686", "386"):
                with self.subTest(machine=machine, suffix=suffix):
                    self.assertIsNone(github.asset_score(f"tool-linux-{suffix}.zip", "linux", machine))

    def test_foreign_architectures_are_excluded_on_supported_hosts(self):
        for machine in ("arm64", "x86_64"):
            for suffix in ("riscv64", "ppc64le", "powerpc64", "s390x", "loongarch64", "loong64", "mips", "mipsel", "mipsle", "mips64", "mips64el", "mips64le", "sparc", "sparc64"):
                with self.subTest(machine=machine, suffix=suffix):
                    self.assertIsNone(github.asset_score(f"tool-linux-{suffix}.zip", "linux", machine))
                    self.assertIsNone(github.asset_score(f"tool-linux-{suffix}-universal.zip", "linux", machine))

    def test_zstandard_tar_is_rejected_before_cli_registration(self):
        for name in ("Example.tar.zst", "Example.tzst"):
            release = {"tag_name": "v1.2.3", "assets": assets(name)}
            with self.subTest(name=name), patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset") as download:
                with self.assertRaisesRegex(ValueError, "Zstandard tar archives"):
                    github.resolve("https://github.com/owner/repo")
                download.assert_not_called()

    def test_compressed_tar_aliases_are_inspected_for_app_bundles(self):
        for suffix, compression in (("txz", "xz"), ("tbz", "bz2"), ("tbz2", "bz2")):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as temp:
                archive = Path(temp) / f"Example-1.2.3.{suffix}"
                with tarfile.open(archive, f"w:{compression}") as stream:
                    info = tarfile.TarInfo("Example.app/Contents/Info.plist")
                    info.size = len(b"fixture")
                    stream.addfile(info, io.BytesIO(b"fixture"))
                self.assertEqual(github.archive_app(archive), "Example.app")
                release = {"tag_name": "v1.2.3", "assets": assets(archive.name)}

                def download(asset, repo, destination):
                    shutil.copyfile(archive, destination)

                with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset", side_effect=download), patch.object(github.platform, "system", return_value="Darwin"):
                    request = github.resolve("https://github.com/owner/repo")
                self.assertIn(f'_asset_pattern="Example-*.{suffix}"', request)
                self.assertIn("postinstall={run=", request)
                self.assertIn("strip_components=0", request)

    def test_other_operating_system_assets_are_excluded(self):
        for system in ("darwin", "linux"):
            for asset_system in ("freebsd", "netbsd", "openbsd", "android"):
                with self.subTest(system=system, asset_system=asset_system):
                    self.assertIsNone(github.asset_score(f"tool-{asset_system}-arm64.zip", system, "arm64"))
        self.assertEqual(github.asset_score("tool-freebsd-x64.zip", "freebsd", "x86_64"), 30)

    def test_linux_distribution_assets_are_excluded_on_other_systems(self):
        for distribution in ("ubuntu", "debian", "alpine", "fedora", "archlinux", "opensuse"):
            for system in ("darwin", "windows"):
                with self.subTest(distribution=distribution, system=system):
                    self.assertIsNone(github.asset_score(f"tool-{distribution}-x64.zip", system, "x86_64"))
            self.assertEqual(github.asset_score(f"tool-{distribution}-x64.zip", "linux", "x86_64"), 30)

    def test_renamed_repository_uses_canonical_release_identity(self):
        asset = {"name": "Tool-1.2.3.zip", "browser_download_url": "https://github.com/NewOwner/NewRepo/releases/download/v1.2.3/Tool-1.2.3.zip"}
        release = {"url": "https://api.github.com/repos/NewOwner/NewRepo/releases/123", "tag_name": "v1.2.3", "assets": [asset]}
        with patch.object(github, "fetch_release", return_value=release) as lookup, patch.object(github, "download_asset") as download, patch.object(github, "archive_app", return_value="Tool.app"), patch.object(github.platform, "system", return_value="Darwin"):
            request = github.resolve("https://github.com/oldowner/oldrepo")
        lookup.assert_called_once_with("oldowner/oldrepo")
        self.assertEqual(download.call_args.args[1], "newowner/newrepo")
        self.assertTrue(request.startswith("github:newowner/newrepo["))
        self.assertIn("install-app newowner/newrepo", request)

    def test_canonical_release_identity_rejects_spoofed_api_urls(self):
        for url in ("https://api.github.com.evil/repos/owner/repo/releases/1", "https://u@api.github.com/repos/owner/repo/releases/1", "https://api.github.com/repos/owner/repo/releases/1?repo=other", "https://api.github.com/repos/owner/../releases/1", "http://api.github.com/repos/owner/repo/releases/1"):
            release = {"url": url, "tag_name": "v1", "assets": assets("tool.zip")}
            with self.subTest(url=url), patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset") as download:
                with self.assertRaises(ValueError):
                    github.resolve("https://github.com/owner/repo")
                download.assert_not_called()

    def test_metadata_words_do_not_filter_product_names(self):
        self.assertEqual(github.choose_asset(assets("mydebugger-linux-x64.zip", "mydebugger-linux-x64-debug.zip"), system="linux", machine="x86_64")["name"], "mydebugger-linux-x64.zip")
        for name in ("tool-debug.zip", "tool-symbols.zip", "tool-checksums.txt", "tool.zip.sha256", "tool.zip.sig", "tool.zip.asc", "tool-sbom.json", "tool-provenance.json", "tool-intoto.json"):
            with self.subTest(name=name):
                self.assertIsNone(github.asset_score(name, "linux", "x86_64"))

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

    def test_app_patterns_remain_scoped_to_host_architecture(self):
        release = {"tag_name": "v1.2.3", "assets": assets("Tool-1.2.3-macos-arm64.zip", "Tool-1.2.3-macos-x64.zip")}
        for machine, architecture in (("arm64", "arm64"), ("x86_64", "x64")):
            with self.subTest(machine=machine), patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value="Tool.app"), patch.object(github.platform, "system", return_value="Darwin"), patch.object(github.platform, "machine", return_value=machine):
                request = github.resolve("https://github.com/owner/repo")
            self.assertIn(f'platform_macos_{architecture}_asset_pattern="Tool-*-macos-{architecture}.zip"', request)
            self.assertNotIn("[asset_pattern=", request)
            self.assertIn("postinstall={run=", request)
            self.assertIn("strip_components=0", request)

    def test_private_asset_download_and_redirect_do_not_leak_token(self):
        asset = {"name": "tool.zip", "id": 123, "browser_download_url": "https://github.com/owner/repo/releases/download/v1/tool.zip"}
        for token_name in ("GITHUB_TOKEN", "GH_TOKEN"):
            with self.subTest(token=token_name), tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "tool.zip"
                with patch.dict(github.os.environ, {token_name: "secret"}, clear=True), patch.object(github.urllib.request, "urlopen", return_value=io.BytesIO(b"asset")) as download:
                    github.download_asset(asset, "owner/repo", path)
                request = download.call_args.args[0]
                self.assertEqual(request.full_url, "https://api.github.com/repos/owner/repo/releases/assets/123")
                self.assertEqual(request.get_header("Accept"), "application/octet-stream")
                self.assertEqual(request.get_header("Authorization"), "Bearer secret")
                redirected = github.urllib.request.HTTPRedirectHandler().redirect_request(request, None, 302, "Found", {}, "https://release-assets.githubusercontent.com/signed")
                self.assertIsNone(redirected.get_header("Authorization"))
                self.assertEqual(path.read_bytes(), b"asset")

    def test_public_asset_uses_browser_download_without_token(self):
        url = "https://github.com/owner/repo/releases/download/v1/tool.zip"
        with tempfile.TemporaryDirectory() as temp, patch.dict(github.os.environ, {}, clear=True), patch.object(github.urllib.request, "urlopen", return_value=io.BytesIO(b"asset")) as download:
            github.download_asset({"browser_download_url": url}, "owner/repo", Path(temp) / "tool.zip")
        self.assertEqual(download.call_args.args[0].full_url, url)
        self.assertIsNone(download.call_args.args[0].get_header("Authorization"))

    def test_authenticated_asset_requires_valid_id(self):
        for asset_id in (None, "123", -1, True):
            with self.subTest(asset_id=asset_id), patch.dict(github.os.environ, {"GH_TOKEN": "secret"}, clear=True), patch.object(github.urllib.request, "urlopen") as download:
                with self.assertRaisesRegex(ValueError, "asset ID"):
                    github.download_asset({"id": asset_id, "browser_download_url": "https://github.com/owner/repo/releases/download/v1/tool.zip"}, "owner/repo", Path("unused"))
                download.assert_not_called()

    def test_download_repository_identity_is_case_insensitive(self):
        url = "https://github.com/BurntSushi/ripgrep/releases/download/v1/tool.zip"
        with tempfile.TemporaryDirectory() as temp, patch.dict(github.os.environ, {}, clear=True), patch.object(github.urllib.request, "urlopen", return_value=io.BytesIO(b"asset")) as download:
            github.download_asset({"browser_download_url": url}, "burntsushi/Ripgrep", Path(temp) / "tool.zip")
        self.assertEqual(download.call_args.args[0].full_url, url)

    def test_download_rejects_other_origins_and_repositories(self):
        for url in ("https://github.com.evil/owner/repo/releases/download/v1/tool.zip", "https://github.com/other/repo/releases/download/v1/tool.zip", "https://github.com/owner/repo-other/releases/download/v1/tool.zip", "https://github.com/owner/repo/releases/download-evil/v1/tool.zip", "https://u@github.com/owner/repo/releases/download/v1/tool.zip", "http://github.com/owner/repo/releases/download/v1/tool.zip"):
            with self.subTest(url=url), patch.object(github.urllib.request, "urlopen") as download:
                with self.assertRaisesRegex(ValueError, "official GitHub"):
                    github.download_asset({"browser_download_url": url}, "owner/repo", Path("unused"))
                download.assert_not_called()

    def test_prefixed_tags_generate_upgrade_patterns(self):
        for tag, filename, expected in (("release-1.2.3", "tool-1.2.3.zip", "tool-*.zip"), ("version-1.2.3", "tool-1.2.3.zip", "tool-*.zip"), ("release-1.2.3", "tool-release-1.2.3.zip", "tool-*.zip"), ("release-1.2.3", "tool-11.2.3.zip", "tool-11.2.3.zip"), ("release-1.2.3", "tool-1.2.30.zip", "tool-1.2.30.zip"), ("release-1.2.3", "tool-9.1.2.3.zip", "tool-9.1.2.3.zip")):
            release = {"tag_name": tag, "assets": assets(filename)}
            with self.subTest(tag=tag, filename=filename), patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value=None):
                request = github.resolve("https://github.com/owner/repo")
            self.assertIn(f'_asset_pattern="{expected}"', request)
            self.assertIn(f'version_prefix="{tag.rsplit("-", 1)[0]}-"', request)
            if expected == "tool-*.zip":
                self.assertTrue(github.fnmatch.fnmatchcase(filename.replace("1.2.3", "1.2.4"), expected))

    def test_single_component_prefixed_version_upgrades(self):
        release = {"tag_name": "release-2", "assets": assets("tool-2-linux-x64.tar.gz")}
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value=None), patch.object(github.platform, "system", return_value="Linux"), patch.object(github.platform, "machine", return_value="x86_64"):
            request = github.resolve("https://github.com/owner/repo")
        self.assertIn('platform_linux_x64_asset_pattern="tool-*-linux-x64.tar.gz"', request)
        self.assertIn('version_prefix="release-"', request)
        self.assertTrue(github.fnmatch.fnmatchcase("tool-3-linux-x64.tar.gz", "tool-*-linux-x64.tar.gz"))
        release["assets"] = assets("tool-12-linux-x64.tar.gz")
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value=None), patch.object(github.platform, "system", return_value="Linux"), patch.object(github.platform, "machine", return_value="x86_64"):
            request = github.resolve("https://github.com/owner/repo")
        self.assertIn('_asset_pattern="tool-12-linux-x64.tar.gz"', request)

    def test_explicit_asset_pattern_is_preserved_for_prefixed_tag(self):
        release = {"tag_name": "release-1.2.3", "assets": assets("tool-1.2.3.zip")}
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value="Tool.app"), patch.object(github.platform, "system", return_value="Darwin"):
            request = github.resolve("https://github.com/owner/repo", "tool-1.2.3.zip")
        self.assertIn('asset_pattern="tool-1.2.3.zip"', request)
        self.assertNotIn("[asset_pattern=", request)
        self.assertIn('version_prefix="release-"', request)

    def test_explicit_app_asset_pattern_is_scoped_to_host(self):
        release = {"tag_name": "v1.2.3", "assets": assets("Tool-macos-arm64.zip")}
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value="Tool.app"), patch.object(github.platform, "system", return_value="Darwin"), patch.object(github.platform, "machine", return_value="arm64"):
            request = github.resolve("https://github.com/owner/repo", "Tool-macos-arm64.zip")
        self.assertIn('platform_macos_arm64_asset_pattern="Tool-macos-arm64.zip"', request)
        self.assertNotIn("[asset_pattern=", request)
        with patch.object(github, "fetch_release", return_value=release), patch.object(github, "download_asset"), patch.object(github, "archive_app", return_value=None):
            cli_request = github.resolve("https://github.com/owner/repo", "Tool-macos-arm64.zip")
        self.assertIn('[asset_pattern="Tool-macos-arm64.zip"', cli_request)


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

    def test_bundle_rename_replaces_previous_app_and_marker(self):
        self.publish()
        self.source = make_app(self.root, "Renamed.app")
        self.publish()
        self.assertEqual([path.name for path in self.apps.iterdir()], ["Renamed.app"])
        markers = list(self.state.glob("*.json"))
        self.assertEqual(len(markers), 1)
        self.assertEqual(json.loads(markers[0].read_text())["path"], str(self.apps / "Renamed.app"))

    def test_case_only_bundle_rename_replaces_managed_app(self):
        self.publish()
        old_marker = next(self.state.glob("*.json"))
        # Temp storage is on the native macOS volume; case-insensitive lookup
        # exposes the original failure before the differently hashed marker exists.
        self.source = self.source.rename(self.root / "example.app")
        (self.source / "Contents/MacOS/Example").write_bytes(b"updated")
        self.publish()
        self.assertEqual([path.name for path in self.apps.iterdir()], ["example.app"])
        self.assertFalse(old_marker.exists())
        marker = next(self.state.glob("*.json"))
        self.assertEqual(json.loads(marker.read_text())["path"], str(self.apps / "example.app"))

    def test_existing_mixed_case_ownership_upgrades_same_name_and_rename(self):
        for rename in (False, True):
            with self.subTest(rename=rename):
                self.publish()
                old_marker = next(self.state.glob("*.json"))
                owner = json.loads(old_marker.read_text())
                owner["repo"] = "Owner/Repo"
                old_marker.write_text(json.dumps(owner))
                if rename:
                    self.source = make_app(self.root, "Renamed.app")
                (self.source / "Contents/MacOS/Example").write_bytes(b"updated")
                self.publish("OWNER/REPO")
                self.assertEqual([path.name for path in self.apps.iterdir()], [self.source.name])
                self.assertEqual((self.apps / self.source.name / "Contents/MacOS/Example").read_bytes(), b"updated")
                markers = list(self.state.glob("*.json"))
                self.assertEqual(len(markers), 1)
                self.assertEqual(json.loads(markers[0].read_text())["repo"], "owner/repo")

    def test_bundle_rename_preserves_unmanaged_destination(self):
        self.publish()
        self.source = make_app(self.root, "Renamed.app")
        make_app(self.apps, "Renamed.app")
        with self.assertRaisesRegex(ValueError, "not managed"):
            self.publish()
        self.assertEqual({path.name for path in self.apps.iterdir()}, {"Example.app", "Renamed.app"})
        self.assertEqual(len(list(self.state.glob("*.json"))), 1)

    def test_bundle_rename_state_failure_restores_previous_app(self):
        self.publish()
        old_marker = next(self.state.glob("*.json"))
        old_state = old_marker.read_bytes()
        self.source = make_app(self.root, "Renamed.app")
        with patch.object(github.os, "replace", side_effect=OSError("state write failed")):
            with self.assertRaisesRegex(OSError, "state write failed"):
                self.publish()
        self.assertEqual([path.name for path in self.apps.iterdir()], ["Example.app"])
        self.assertEqual(old_marker.read_bytes(), old_state)
        self.assertEqual(len(list(self.state.iterdir())), 1)

    def test_bundle_rename_marker_cleanup_failure_rolls_back(self):
        self.publish()
        old_marker = next(self.state.glob("*.json"))
        old_state = old_marker.read_bytes()
        self.source = make_app(self.root, "Renamed.app")
        unlink = Path.unlink

        def fail_old_marker(path, *args, **kwargs):
            if path == old_marker:
                raise OSError("marker cleanup failed")
            return unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", fail_old_marker):
            with self.assertRaisesRegex(OSError, "marker cleanup failed"):
                self.publish()
        self.assertEqual([path.name for path in self.apps.iterdir()], ["Example.app"])
        self.assertEqual(old_marker.read_bytes(), old_state)
        self.assertEqual(len(list(self.state.iterdir())), 1)

    def test_bundle_rename_rejects_ownership_outside_applications(self):
        self.publish()
        marker = next(self.state.glob("*.json"))
        owner = json.loads(marker.read_text())
        owner["path"] = str(self.source)
        marker.write_text(json.dumps(owner))
        self.source = make_app(self.root, "Renamed.app")
        with self.assertRaisesRegex(ValueError, "ownership"):
            self.publish()
        self.assertTrue((self.apps / "Example.app").exists())
        self.assertFalse((self.apps / "Renamed.app").exists())

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
