"""Shared ~/.agents skills are linked into Claude Code's skills folder."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "setup-scripts/local/link-agent-skills.sh"


class AgentSkillLinksTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.shared = self.home / ".agents/skills"
        self.claude = self.home / ".claude/skills"

    def add_shared(self, name):
        (self.shared / name).mkdir(parents=True)
        (self.shared / name / "SKILL.md").write_text(f"---\nname: {name}\n---\n")

    def run_link(self):
        result = subprocess.run(
            ["bash", str(SCRIPT)], env={**os.environ, "HOME": str(self.home)},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_no_shared_folder_is_a_no_op(self):
        self.run_link()
        self.assertFalse(self.claude.exists())

    def test_links_shared_skills_and_keeps_claude_owned_ones(self):
        self.add_shared("rex")
        self.add_shared("sembr")
        (self.claude / "sembr").mkdir(parents=True)
        (self.shared / "notes").mkdir()  # no SKILL.md: not a skill
        out = self.run_link()
        self.assertEqual(os.readlink(self.claude / "rex"), str(self.shared / "rex"))
        self.assertFalse((self.claude / "sembr").is_symlink())
        self.assertFalse((self.claude / "notes").exists())
        self.assertIn("Kept existing ~/.claude/skills/sembr", out)
        self.assertEqual(self.run_link(), "Kept existing ~/.claude/skills/sembr; not linking the shared copy\n")

    def test_prunes_links_to_removed_shared_skills_only(self):
        self.add_shared("rex")
        self.run_link()
        foreign = self.claude / "other"
        foreign.symlink_to(self.home / "missing")
        (self.shared / "rex" / "SKILL.md").unlink()
        (self.shared / "rex").rmdir()
        out = self.run_link()
        self.assertFalse((self.claude / "rex").is_symlink())
        self.assertTrue(foreign.is_symlink())
        self.assertIn("Removed stale Claude skill link", out)


if __name__ == "__main__":
    unittest.main()
