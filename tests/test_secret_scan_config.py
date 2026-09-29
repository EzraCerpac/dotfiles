"""Secret-scan exceptions must name findings, never contain secrets."""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires

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


@requires("gitleaks")
class ManifestAllowlistTests(unittest.TestCase):
    """Julia package UUIDs pass; anything else in a manifest is still a finding."""

    def scan(self, manifest: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "environments/v1.12"
            directory.mkdir(parents=True)
            (directory / "Manifest.toml").write_text(manifest)
            return subprocess.run(
                [shutil.which("gitleaks") or "gitleaks", "dir", "--no-banner", "--redact", "--exit-code", "1",
                 "--config", str(ROOT / ".gitleaks.toml"), temporary],
                capture_output=True, text=True, check=False, timeout=60,
            )

    def test_package_uuids_are_allowed(self) -> None:
        # Assembled at runtime: outside a manifest, a UUID literal is itself a finding.
        uuid = "-".join(("94b1ba4f", "4ee9", "5380", "92f1", "94cde586c3c5"))
        result = self.scan(f'[deps]\nAxisKeys = "{uuid}"\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_other_generic_secrets_in_a_manifest_are_reported(self) -> None:
        # Assembled at runtime so this file never holds a secret-shaped literal.
        value = "".join(("Zx8Q2mK7", "vB4nR9tL", "1pW6yC3h"))
        result = self.scan(f'[deps]\napi_key = "{value}"\n')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
