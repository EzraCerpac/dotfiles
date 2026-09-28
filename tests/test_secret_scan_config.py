"""Secret-scan exceptions must name findings, never contain secrets."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FINGERPRINT = re.compile(r"[0-9a-f]{40}:[^:\s]+:[a-z0-9-]+:\d+")


class SecretScanConfigTests(unittest.TestCase):
    def test_gitleaksignore_holds_only_commit_fingerprints(self) -> None:
        entries = [
            line for line in (ROOT / ".gitleaksignore").read_text().splitlines() if line and not line.startswith("#")
        ]
        self.assertTrue(entries)
        for entry in entries:
            with self.subTest(entry=entry):
                self.assertRegex(entry, f"^{FINGERPRINT.pattern}$")

    def test_ignored_findings_are_documented_for_rotation(self) -> None:
        security = (ROOT / "docs/security.md").read_text()
        for line in (ROOT / ".gitleaksignore").read_text().splitlines():
            if line and not line.startswith("#"):
                commit, path = line.split(":")[:2]
                with self.subTest(path=path):
                    self.assertIn(commit[:8], security)
                    self.assertIn(Path(path).parent.name, security)


if __name__ == "__main__":
    unittest.main()
