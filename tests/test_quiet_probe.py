"""Successful health checks are quiet; failed checks keep their diagnostics."""

from pathlib import Path
import subprocess
import unittest


HELPER = Path(__file__).resolve().parents[1] / "setup-scripts/lib/quiet-probe.sh"


class QuietProbeTests(unittest.TestCase):
    def test_both_streams_are_only_shown_on_failure(self):
        for status in (0, 7):
            with self.subTest(status=status):
                result = subprocess.run(
                    ["bash", "-c", 'source "$1"; quiet_probe bash -c \'printf "help\\n"; printf "warning\\n" >&2; exit "$1"\' bash "$2"',
                     "bash", str(HELPER), str(status)],
                    text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, status)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "" if status == 0 else "help\nwarning\n")
