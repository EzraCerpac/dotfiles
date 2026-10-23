import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALID_REVISION = "a" * 40


class CapdSourceMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.app = Path(self.temp_dir.name) / "capd.app"
        contents = self.app / "Contents"
        contents.mkdir(parents=True)
        self.plist = contents / "Info.plist"

    def validate(self, metadata, revision=VALID_REVISION):
        with self.plist.open("wb") as stream:
            plistlib.dump(metadata, stream)
        helper = ROOT / "setup-scripts/local/capd-provenance.sh"
        command = 'source "$1"; capd_validate_source "$2" "$3"'
        return subprocess.run(
            ["bash", "-c", command, "test", str(helper), str(self.app), revision],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_accepts_matching_fork_main_revision(self):
        result = self.validate(
            {
                "CapdSourceRepository": "https://github.com/EzraCerpac/capd",
                "CapdSourceBranch": "main",
                "CapdSourceRevision": VALID_REVISION,
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_other_repository(self):
        result = self.validate(
            {
                "CapdSourceRepository": "https://github.com/jamiedavenport/capd",
                "CapdSourceBranch": "main",
                "CapdSourceRevision": VALID_REVISION,
            }
        )
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_non_main_branch(self):
        result = self.validate(
            {
                "CapdSourceRepository": "https://github.com/EzraCerpac/capd",
                "CapdSourceBranch": "wip/local-capd",
                "CapdSourceRevision": VALID_REVISION,
            }
        )
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_stale_revision(self):
        result = self.validate(
            {
                "CapdSourceRepository": "https://github.com/EzraCerpac/capd",
                "CapdSourceBranch": "main",
                "CapdSourceRevision": "b" * 40,
            }
        )
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_malformed_expected_revision(self):
        result = self.validate(
            {
                "CapdSourceRepository": "https://github.com/EzraCerpac/capd",
                "CapdSourceBranch": "main",
                "CapdSourceRevision": VALID_REVISION,
            },
            revision="short",
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
