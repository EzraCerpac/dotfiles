"""toml_check validates through mise and never echoes what it read."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import mise_binary, requires

LIBRARY = Path(__file__).resolve().parents[1] / "setup-scripts/lib/toml.sh"
SECRET = "fixture-secret-value"


class TomlCheckTests(unittest.TestCase):
    def check(self, mise: str, text: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            file = Path(temporary) / "input.toml"
            file.write_text(text)
            return subprocess.run(
                ["bash", "-c", 'source "$1"; toml_check "$2" "$3"', "toml-check", str(LIBRARY), mise, str(file)],
                capture_output=True, text=True, check=False,
            )

    @requires("mise")
    def test_valid_toml_with_foreign_tables_passes(self) -> None:
        result = self.check(mise_binary(), f'[accounts.personal]\nemail = "{SECRET}"\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    @requires("mise")
    def test_invalid_toml_fails_without_echoing_the_input(self) -> None:
        result = self.check(mise_binary(), f'[accounts.personal\npassword = "{SECRET}"\n')
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(SECRET, result.stdout + result.stderr)

    def test_missing_mise_is_reported_separately(self) -> None:
        self.assertEqual(self.check("/nonexistent/mise", 'key = "value"\n').returncode, 2)
        self.assertEqual(self.check("mise-command-that-does-not-exist", 'key = "value"\n').returncode, 2)
        with tempfile.TemporaryDirectory() as temporary:
            # Executable, but its interpreter is missing, so launching exits 126/127.
            broken = Path(temporary) / "mise"
            broken.write_text("#!/nonexistent/interpreter\n")
            broken.chmod(0o755)
            self.assertEqual(self.check(str(broken), 'key = "value"\n').returncode, 2)
        # A failed resolver yields an empty path; that is "no mise", not an abort.
        empty = self.check("", 'key = "value"\n')
        self.assertEqual((empty.returncode, empty.stderr), (2, ""))


if __name__ == "__main__":
    unittest.main()
