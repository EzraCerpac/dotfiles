"""The clean-up in docs/history-declarations.md removes only generated entries.

Step 3 runs an awk program over a machine's config.host-<id>.toml. It may drop
the header comment and tables of exactly the shape the old enroll-history wrote;
every other table, comment and setting must survive byte for byte.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

GENERATED = '''[dotfiles."{path}"]
mode = "track"
encrypt = true
variants = [{{ profile = "host-mac-primary" }}]
'''

KEPT_TOP = '''# Local notes kept by hand.

'''

KEPT_TABLES = '''[dotfiles."~/.custom"]
mode = "track"
encrypt = true

[dotfiles."~/.other-host"]
mode = "track"
encrypt = true
variants = [{ profile = "host-cerpacnas" }]

[dotfiles."~/.extra-key"]
mode = "track"
encrypt = true
variants = [{ profile = "host-mac-primary" }]
autosave = false

# Tools only this machine uses.
[tools]
"aqua:foo" = "1"

[dotfiles."~/.commented"]
mode = "track"
# keep this one
encrypt = true
variants = [{ profile = "host-mac-primary" }]

[dotfiles."~/.reordered"]
encrypt = true
variants = [{ profile = "host-mac-primary" }]
'''


def cleanup_program() -> str:
    text = (ROOT / "docs/history-declarations.md").read_text()
    step = text[text.index("## 3. "):text.index("## 4. ")]
    match = re.search(r"awk -v id=\"\$id\" '(.*?)' \"\$B/\$f\"", step, re.S)
    assert match, "step 3 no longer runs an awk program over the backed-up host file"
    return match.group(1)


def cleanup(text: str) -> str:
    return subprocess.run(["awk", "-v", "id=mac-primary", cleanup_program()], input=text,
                          capture_output=True, text=True, check=True).stdout


class HostDeclarationCleanupTests(unittest.TestCase):
    def test_removes_only_generated_tables(self) -> None:
        local = ("# Encrypted exact-file history entries for host-mac-primary.\n" + KEPT_TOP
                 + GENERATED.format(path="~/.codex/config.toml") + "\n" + KEPT_TABLES + "\n"
                 + GENERATED.format(path="~/.config/fish/fish_variables"))
        result = cleanup(local)
        self.assertNotIn("~/.codex/config.toml", result)
        self.assertNotIn("fish_variables", result)
        self.assertNotIn("Encrypted exact-file history entries", result)
        # Every other line survives in order, byte for byte.
        self.assertEqual([line for line in result.splitlines() if line],
                         [line for line in (KEPT_TOP + KEPT_TABLES).splitlines() if line])
        self.assertIn(KEPT_TABLES, result)

    def test_a_file_of_generated_tables_becomes_blank(self) -> None:
        local = ("# Encrypted exact-file history entries for host-mac-primary.\n\n"
                 + GENERATED.format(path="~/.codex/config.toml") + "\n"
                 + GENERATED.format(path="~/.wakatime.cfg"))
        self.assertEqual(cleanup(local).strip(), "")


if __name__ == "__main__":
    unittest.main()
