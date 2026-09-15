#!/usr/bin/env python3
"""Focused checks for the Kanata and Karabiner compatibility holds."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class KeyboardHoldTests(unittest.TestCase):
    def test_configuration_routes_keyboard_tools_to_hold_tasks(self):
        workstation = (ROOT / "config.workstation.toml").read_text()
        exceptions = (ROOT / "tasks/setup/exceptions.tsv").read_text()
        kanata = (ROOT / "tasks/setup/exceptions/kanata").read_text()
        karabiner = (ROOT / "tasks/setup/exceptions/karabiner-elements").read_text()

        self.assertNotIn('"brew:kanata"', workstation)
        self.assertIn("base\tkanata", exceptions)
        self.assertIn("hold_brew_formula_exception kanata 1.12.0", kanata)
        self.assertIn("hold_brew_cask_exception", karabiner)
        self.assertNotIn("update_brew_cask_exception", karabiner)

    def test_kanata_hold_accepts_only_the_known_version(self):
        with tempfile.TemporaryDirectory(prefix="mise-keyboard-hold-") as temp:
            fake_bin = Path(temp) / "brew"
            fake_bin.write_text(
                "#!/bin/sh\n"
                'if [ "$1" = "--prefix" ]; then printf "/opt/homebrew\\n"; exit 0; fi\n'
                'if [ "$1" = "list" ] && [ "$2" = "--versions" ]; then\n'
                '  if [ "${FAKE_BREW_VERSION:-}" = missing ]; then exit 1; fi\n'
                '  printf "kanata %s\\n" "${FAKE_BREW_VERSION:-1.12.0}"; exit 0\n'
                'fi\n'
                'printf "unexpected brew call: %s\\n" "$*" >&2; exit 97\n'
            )
            fake_bin.chmod(0o755)

            def run(version):
                env = os.environ.copy()
                env["PATH"] = f"{temp}:/usr/bin:/bin"
                if version is not None:
                    env["FAKE_BREW_VERSION"] = version
                return subprocess.run(
                    [
                        "bash",
                        "-c",
                        f"source '{ROOT}/tasks/lib/brew-exception.sh'; "
                        "hold_brew_formula_exception kanata 1.12.0",
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                )

            held = run("1.12.0")
            self.assertEqual(held.returncode, 0, held.stderr)
            self.assertIn("Held: kanata 1.12.0", held.stdout)

            changed = run("1.13.0")
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn("refusing to change it", changed.stderr)

            missing = run("missing")
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("Manual action required", missing.stderr)


if __name__ == "__main__":
    unittest.main()
