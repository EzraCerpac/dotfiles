"""Update hooks report changed local builds through DOTS_CHANGES."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JW_HOOK = ROOT / "dots/hooks/update.d/50-jw-main-source@workstation"
OLD, NEW = "1" * 40, "2" * 40


class JwMainSourceHookTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.changes = self.base / "changes"
        self.changes.touch()
        # A stand-in build installs the NEXT revision as a new versioned jw.
        build = self.base / "config/setup-scripts/install/jw-build-install.sh"
        build.parent.mkdir(parents=True)
        build.write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            '[[ -f "$TEST_BASE/next" ]] || exit "${TEST_STATUS:-0}"\n'
            'version="$TEST_BASE/versions/$(cat "$TEST_BASE/next")"\nmkdir -p "$version"\n'
            'touch "$version/jw"\ncp "$TEST_BASE/next" "$version/source-commit"\n'
            'ln -sfn "$version/jw" "$JW_INSTALL_DIR/jw"\nexit "${TEST_STATUS:-0}"\n')
        build.chmod(0o755)

    def install(self, revision: str | None) -> None:
        version = self.base / "versions/current"
        version.mkdir(parents=True)
        (version / "jw").touch()
        if revision:
            (version / "source-commit").write_text(revision + "\n")
        (self.bin / "jw").symlink_to(version / "jw")

    def run_hook(self, next_revision: str | None = None, status: int = 0) -> subprocess.CompletedProcess[str]:
        if next_revision:
            (self.base / "next").write_text(next_revision + "\n")
        env = {**os.environ, "DOTS_ROOT": str(self.base / "config"), "DOTS_CHANGES": str(self.changes),
               "JW_INSTALL_DIR": str(self.bin), "TEST_BASE": str(self.base), "TEST_STATUS": str(status)}
        return subprocess.run(["bash", str(JW_HOOK)], env=env, capture_output=True, text=True, timeout=30, check=False)

    def test_a_new_revision_is_reported(self) -> None:
        self.install(OLD)
        self.assertEqual(self.run_hook(NEW).returncode, 0)
        self.assertEqual(self.changes.read_text(), f"jw\t{OLD}\t{NEW}\n")

    def test_an_unchanged_revision_is_not_reported(self) -> None:
        self.install(OLD)
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual(self.changes.read_text(), "")

    def test_an_unknown_previous_revision_is_not_reported(self) -> None:
        self.install(None)
        self.assertEqual(self.run_hook(NEW).returncode, 0)
        self.assertEqual(self.changes.read_text(), "")

    def test_a_first_install_is_reported_and_the_build_status_kept(self) -> None:
        result = self.run_hook(NEW, status=3)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(self.changes.read_text(), f"jw\tnot installed\t{NEW}\n")


if __name__ == "__main__":
    unittest.main()
