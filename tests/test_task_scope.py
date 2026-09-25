"""Setup tasks must not appear in projects beneath the user's home directory."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MISE = os.environ.get("SETUP_TEST_MISE", "mise")


class TaskScopeTests(unittest.TestCase):
    def test_setup_tasks_are_only_available_from_setup_checkout(self):
        with tempfile.TemporaryDirectory(prefix="mise-task-scope-") as temporary:
            home = Path(temporary).resolve() / "home"
            setup = home / ".config/mise"
            project = home / "project"
            setup.mkdir(parents=True)
            project.mkdir()
            for name in ("config.toml", "setup-tasks.toml"):
                shutil.copy2(ROOT / name, setup / name)
            shutil.copytree(ROOT / "setup-scripts", setup / "setup-scripts")
            (project / "mise.toml").write_text('[tasks.project-only]\nrun = "true"\n')
            project_task = project / ".mise/tasks/project-file"
            project_task.parent.mkdir(parents=True)
            project_task.write_text("#!/bin/sh\ntrue\n")
            project_task.chmod(0o755)

            env = os.environ.copy()
            env.pop("MISE_ENV", None)
            env.pop("MISE_GLOBAL_CONFIG_FILE", None)
            env.update(
                HOME=str(home),
                MISE_CONFIG_DIR=str(setup),
                MISE_CACHE_DIR=str(Path(temporary) / "cache"),
                MISE_DATA_DIR=str(Path(temporary) / "data"),
                MISE_STATE_DIR=str(Path(temporary) / "state"),
                MISE_AUTO_INSTALL="0",
                MISE_TRUSTED_CONFIG_PATHS=os.pathsep.join((str(setup), str(project))),
            )

            def task_names(directory):
                result = subprocess.run(
                    [MISE, "-C", str(directory), "tasks", "ls", "--json"],
                    env=env, text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                return {entry["name"] for entry in json.loads(result.stdout)}

            setup_names = task_names(setup)
            project_names = task_names(project)
            self.assertIn("setup:status", setup_names)
            self.assertIn("setup:fix-codex-acp-mode", setup_names)
            self.assertIn("project-only", project_names)
            self.assertIn("project-file", project_names)
            self.assertNotIn("setup:status", project_names)
            self.assertNotIn("setup:fix-codex-acp-mode", project_names)

            missing = subprocess.run(
                [MISE, "-C", str(project), "tasks", "info", "setup:status"],
                env=env, text=True, capture_output=True, check=False,
            )
            self.assertNotEqual(missing.returncode, 0)


if __name__ == "__main__":
    unittest.main()
