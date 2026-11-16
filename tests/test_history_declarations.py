"""The clean-up in docs/history-declarations.md removes only generated entries.

Step 3 runs an awk program over a machine's config.host-<id>.toml. It may drop
the header comment and tables of exactly the shape the old enroll-history wrote;
every other table, comment and setting must survive byte for byte.
"""

from __future__ import annotations

import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires

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


def step3() -> str:
    text = (ROOT / "docs/history-declarations.md").read_text()
    return text[text.index("## 3. "):text.index("## 4. ")]


def cleanup_program() -> str:
    match = re.search(r"awk -v id=\"\$id\" '(.*?)' \"\$B/\$f\"", step3(), re.S)
    assert match, "step 3 no longer runs an awk program over the backed-up host file"
    return match.group(1)


def cleanup(text: str) -> str:
    return subprocess.run(["awk", "-v", "id=mac-primary", cleanup_program()], input=text,
                          capture_output=True, text=True, check=True).stdout


def replace_host_file(directory: Path) -> subprocess.CompletedProcess[str]:
    """Run step 3 from its backup check to its replacement of config.host-mac-primary.toml."""
    match = re.search(r"^cmp -s .*?^if grep .*?fi$", step3(), re.S | re.M)
    assert match, "step 3 no longer checks the backup before replacing the host file"
    return subprocess.run(["bash", "-c", "id=mac-primary f=config.host-$id.toml B=backup\n" + match.group(0)],
                          cwd=directory, capture_output=True, text=True, check=False)


@requires("awk")
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

    def host_files(self, local: str) -> Path:
        temporary = tempfile.TemporaryDirectory(prefix="history-declarations-")
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        (directory / "backup").mkdir()
        for path in (directory / "config.host-mac-primary.toml", directory / "backup/config.host-mac-primary.toml"):
            path.write_text(local)
            path.chmod(0o600)
        return directory

    def test_a_kept_file_keeps_its_private_mode(self) -> None:
        directory = self.host_files('[env]\nTOKEN = "private"\n\n' + GENERATED.format(path="~/.codex/config.toml"))
        result = replace_host_file(directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        live = directory / "config.host-mac-primary.toml"
        self.assertEqual(live.read_text(), '[env]\nTOKEN = "private"\n\n')
        self.assertEqual(stat.S_IMODE(live.stat().st_mode), 0o600)

    def test_an_edit_since_the_backup_stops_the_replacement(self) -> None:
        directory = self.host_files("[tools]\n" + GENERATED.format(path="~/.codex/config.toml"))
        live = directory / "config.host-mac-primary.toml"
        live.write_text(live.read_text() + '[env]\nLATE = "edit"\n')
        result = replace_host_file(directory)
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed since step 2", result.stdout)
        self.assertIn('LATE = "edit"', live.read_text())
        self.assertFalse((directory / "config.host-mac-primary.toml.new").exists())


if __name__ == "__main__":
    unittest.main()
