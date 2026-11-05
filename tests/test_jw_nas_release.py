"""NAS jw installs are pinned and never replace an existing path on routine setup."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "setup-scripts/install/jw-nas-release.sh"


class JwNasReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "curl.log"
        self.write_exe("mise", '''#!/bin/sh
while [ "$1" = -C ] || [ "$1" = -E ]; do shift 2; done
[ "$1" = exec ] && shift
[ "$1" = -- ] && shift
exec "$@"
''')
        self.write_exe("uname", '''#!/bin/sh
if [ "$1" = -m ]; then echo "${FIXTURE_ARCH:-x86_64}"; else echo "$FIXTURE_OS"; fi
''')
        self.write_exe("curl", '''#!/bin/sh
printf '%s\\n' "$*" >> "$CURL_LOG"
for last do :; done
cp "$FIXTURE_ARCHIVE" "$last"
''')
        self.write_exe("sha256sum", '#!/bin/sh\nexec /usr/bin/shasum -a 256 "$@"\n')
        self.env = dict(os.environ, HOME=str(self.home), SETUP_PROFILE="nas", SETUP_MACHINE_ID="fixture",
                        SETUP_MISE_BIN=str(self.bin / "mise"), PATH=str(self.bin) + ":/usr/bin:/bin:/usr/sbin:/sbin",
                        CURL_LOG=str(self.log), FIXTURE_OS="Linux")
        self.env.pop("JW_INSTALL_DIR", None)
        self.dest = self.home / ".local/bin/jw"

    def write_exe(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)
        return path

    def run_script(self, *args, **overrides):
        return subprocess.run(["bash", str(SCRIPT), *args], env=dict(self.env, **overrides),
                              text=True, capture_output=True, timeout=20)

    def test_existing_jw_and_symlink_are_kept_without_network(self):
        target = self.base / "owned-jw"
        target.write_text('#!/bin/sh\nprintf "jw 0.3.1\\n"\n')
        target.chmod(0o755)
        self.dest.parent.mkdir(parents=True)
        self.dest.symlink_to(target)
        result = self.run_script("--if-missing", FIXTURE_OS="unsupported")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.dest.is_symlink())
        self.assertEqual(self.dest.resolve(), target.resolve())
        self.assertFalse(self.log.exists())

    def test_bad_or_dangling_existing_path_is_preserved(self):
        self.dest.parent.mkdir(parents=True)
        self.dest.symlink_to(self.base / "missing")
        result = self.run_script("--if-missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not executable", result.stderr)
        self.assertTrue(self.dest.is_symlink())
        self.assertFalse(self.log.exists())

    def test_release_archives_install_on_linux_and_intel_mac(self):
        for platform, arch, directory, version, digest_key in (
            ("Linux", "x86_64", "jj-waltz-x86_64-unknown-linux-musl", "0.3.1", "JW_NAS_SHA256"),
            ("Darwin", "x86_64", "jj-waltz-x86_64-apple-darwin", "0.8.0", "JW_NAS_MAC_SHA256"),
            ("Linux", "aarch64", "jj-waltz-aarch64-unknown-linux-gnu", "0.8.0", "JW_NAS_LINUX_ARM_SHA256"),
            ("Darwin", "arm64", "jj-waltz-aarch64-apple-darwin", "0.8.0", "JW_NAS_MAC_ARM_SHA256"),
        ):
            with self.subTest(platform=platform, arch=arch):
                self.dest.unlink(missing_ok=True)
                source = self.base / "jw-source"
                source.write_text(f'#!/bin/sh\nprintf "jw {version}\\n"\n')
                source.chmod(0o755)
                archive = self.base / f"{platform}.tar.gz"
                with tarfile.open(archive, "w:gz") as file:
                    file.add(source, arcname=f"{directory}/jw")
                    for name in ("README.md", "CHANGELOG.md", "LICENSE"):
                        file.add(source, arcname=f"{directory}/{name}")
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                result = self.run_script("--if-missing", FIXTURE_OS=platform, FIXTURE_ARCH=arch, FIXTURE_ARCHIVE=str(archive), **{digest_key: digest})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(os.access(self.dest, os.X_OK))
                self.assertIn(f"/v{version}/{directory}.tar.gz", self.log.read_text())

    def test_archive_links_are_not_accepted_as_binary(self):
        for link_type in (tarfile.SYMTYPE, tarfile.LNKTYPE):
            with self.subTest(link_type=link_type):
                archive = self.base / "link.tar.gz"
                member = tarfile.TarInfo("jj-waltz-x86_64-unknown-linux-musl/jw")
                member.type = link_type
                member.linkname = "../../outside"
                with tarfile.open(archive, "w:gz") as file:
                    file.addfile(member)
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                result = self.run_script("--if-missing", FIXTURE_ARCHIVE=str(archive), JW_NAS_SHA256=digest)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("not a regular file", result.stderr)
                self.assertFalse(self.dest.exists())

    def test_mismatched_checksum_does_not_install(self):
        archive = self.base / "bad-archive"
        archive.write_bytes(b"invalid")
        result = self.run_script("--if-missing", FIXTURE_ARCHIVE=str(archive), JW_NAS_SHA256="0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.dest.exists())


if __name__ == "__main__":
    unittest.main()
