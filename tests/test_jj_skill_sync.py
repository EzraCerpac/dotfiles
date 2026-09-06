"""Exercise skill distribution without touching installed skills."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "dot_local/bin/executable_codex-sync-jj-waltz"


class SkillSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "source/jj-waltz"
        self.source.mkdir(parents=True)
        self.chezmoi = root / "chezmoi"
        self.chezmoi.mkdir()
        (self.source / "references").mkdir()
        (self.source / "references/codex.md").write_text("# Codex\n")
        (self.source / "evals").mkdir()
        (self.source / "evals/private.md").write_text("Test data\n")
        self.write_skill("[Codex](references/codex.md)")

    def write_skill(self, body):
        (self.source / "SKILL.md").write_text(
            "---\nname: jj-waltz\ndescription: Test skill\n---\n" + body + "\n"
        )

    def run_sync(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env={**os.environ, "CHEZMOI_SOURCE_DIR": str(self.chezmoi),
                 "JJ_WALTZ_SKILL_SOURCE": str(self.source)},
            capture_output=True, text=True,
        )

    def test_distributes_references_but_not_evals(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        for target in ("dot_codex/skills/jj-waltz", "dot_config/opencode/skills/jj-waltz"):
            dest = self.chezmoi / target
            self.assertEqual((dest / "references/codex.md").read_text(), "# Codex\n")
            self.assertFalse((dest / "evals").exists())
        (self.source / "references/codex.md").unlink()
        self.write_skill("No references now.")
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertFalse((self.chezmoi / "dot_codex/skills/jj-waltz/references/codex.md").exists())

    def test_missing_link_leaves_destinations_untouched(self):
        self.write_skill("[Missing](references/missing.md)")
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or external local link", result.stderr)
        self.assertEqual(list(self.chezmoi.iterdir()), [])

    def test_runtime_cannot_link_to_excluded_evals(self):
        self.write_skill("[Test](evals/private.md)")
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("link is not distributed", result.stderr)
        self.assertEqual(list(self.chezmoi.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
