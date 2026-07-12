from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "dot_codex" / "skills" / "work-on-cerpacnas" / "scripts" / "nas.py"
SPEC = importlib.util.spec_from_file_location("nas_cli", SCRIPT)
assert SPEC and SPEC.loader
nas_cli = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nas_cli)


MANIFEST = """
version = 1

[host]
ssh_alias = "nas"
remote_home = "/root"
remote_project_root = "/root/Projects"
dotfiles_branch = "dev"
explore_model = "gpt-5.3-codex-spark"
work_model = "gpt-5.6-sol"

[projects.thesis]
repo = "git@github.com:EzraCerpac/master-thesis.git"
local_path = "/tmp/Projects/Thesis/ezra-cerpac"
remote_path = "/root/Projects/Thesis/ezra-cerpac"
remote_name = "github"
rules_file = "~/.config/cerpacnas/project-rules/thesis.AGENTS.md"

[projects.thesis.artifacts.data]
path = "data"

[projects.thesis.artifacts.output]
path = "code/out"
"""


class ManifestTests(unittest.TestCase):
    def load(self, text: str = MANIFEST):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "projects.toml"
            path.write_text(text)
            return nas_cli.load_manifest(path)

    def test_loads_project_and_artifacts(self):
        manifest = self.load()
        project = manifest.projects["thesis"]
        self.assertEqual(manifest.host.ssh_alias, "nas")
        self.assertEqual(project.remote_name, "github")
        self.assertEqual(project.artifacts["output"].path, Path("code/out"))

    def test_rejects_absolute_artifact_path(self):
        text = MANIFEST.replace('path = "data"', 'path = "/etc"', 1)
        with self.assertRaisesRegex(nas_cli.ManifestError, "relative"):
            self.load(text)

    def test_rejects_path_traversal(self):
        text = MANIFEST.replace('path = "data"', 'path = "../secrets"', 1)
        with self.assertRaisesRegex(nas_cli.ManifestError, "unsafe"):
            self.load(text)

    def test_rejects_repository_metadata(self):
        text = MANIFEST.replace('path = "data"', 'path = ".git/objects"', 1)
        with self.assertRaisesRegex(nas_cli.ManifestError, "unsafe"):
            self.load(text)

    def test_rejects_artifact_paths_with_shell_sensitive_spacing(self):
        text = MANIFEST.replace('path = "data"', 'path = "data files"', 1)
        with self.assertRaisesRegex(nas_cli.ManifestError, "unsafe"):
            self.load(text)

    def test_rejects_remote_project_outside_root(self):
        text = MANIFEST.replace(
            'remote_path = "/root/Projects/Thesis/ezra-cerpac"',
            'remote_path = "/etc/ezra-cerpac"',
        )
        with self.assertRaisesRegex(nas_cli.ManifestError, "below /root/Projects"):
            self.load(text)

    def test_rejects_dotdot_in_absolute_project_path(self):
        text = MANIFEST.replace(
            'remote_path = "/root/Projects/Thesis/ezra-cerpac"',
            'remote_path = "/root/Projects/../etc"',
        )
        with self.assertRaisesRegex(nas_cli.ManifestError, "may not contain"):
            self.load(text)


class SafetyTests(unittest.TestCase):
    def test_reads_last_json_payload_after_command_noise(self):
        self.assertEqual(nas_cli.last_json('fetching\n{"ok": true}\n'), {"ok": True})

    def test_task_names_become_wip_bookmarks(self):
        self.assertEqual(nas_cli.normalize_bookmark("selector-ui"), "wip/selector-ui")
        self.assertEqual(nas_cli.normalize_bookmark("wip/selector-ui"), "wip/selector-ui")

    def test_main_bookmark_is_forbidden(self):
        with self.assertRaisesRegex(nas_cli.NasError, "wip"):
            nas_cli.normalize_bookmark("main")

    def test_workspace_name_is_stable_and_safe(self):
        self.assertEqual(
            nas_cli.workspace_name("thesis", "wip/selector-ui"),
            "thesis-selector-ui",
        )

    def test_remote_command_quotes_arguments(self):
        command = nas_cli.remote_shell_command(["printf", "%s", "hello; touch /tmp/nope"])
        self.assertEqual(command, "printf %s 'hello; touch /tmp/nope'")

    def test_rsync_is_non_deleting_and_dry_by_default(self):
        args = nas_cli.rsync_args(apply=False)
        self.assertIn("--dry-run", args)
        self.assertNotIn("--delete", args)
        self.assertIn("--exclude=.git/", args)
        self.assertIn("--exclude=.jj/", args)
        self.assertIn("--exclude=.env", args)
        self.assertIn("--exclude=*.pem", args)

    def test_rsync_apply_only_removes_dry_run(self):
        args = nas_cli.rsync_args(apply=True)
        self.assertNotIn("--dry-run", args)
        self.assertNotIn("--delete", args)

    def test_agent_modes_pin_models_and_sandboxes(self):
        manifest = ManifestTests().load()
        self.assertEqual(
            nas_cli.agent_spec(manifest.host, "explore"),
            ("gpt-5.3-codex-spark", "read-only"),
        )
        self.assertEqual(
            nas_cli.agent_spec(manifest.host, "work"),
            ("gpt-5.6-sol", "workspace-write"),
        )

    def test_validation_lanes_are_curated_and_sequential(self):
        command, key = nas_cli.validation_command("focus:selector")
        self.assertEqual(key, "focus-selector")
        self.assertEqual(command[-2:], ["--jobs", "1"])
        with self.assertRaisesRegex(nas_cli.NasError, "lane must be"):
            nas_cli.validation_command("all")

    def test_validation_budget_disables_timeout_and_high_rss(self):
        self.assertTrue(nas_cli.validation_within_budget(0, 179.9, 3072))
        self.assertFalse(nas_cli.validation_within_budget(124, 10, 10))
        self.assertFalse(nas_cli.validation_within_budget(0, 181, 10))
        self.assertFalse(nas_cli.validation_within_budget(0, 10, 3072.1))

    def test_remote_agent_uses_jj_workspace_compat_without_bypass(self):
        source = SCRIPT.read_text()
        self.assertIn('"--skip-git-repo-check"', source)
        self.assertNotIn("dangerously-bypass-approvals-and-sandbox", source)

    def test_documented_parser_shapes(self):
        parser = nas_cli.build_parser()
        projects = parser.parse_args(["projects", "status", "--all"])
        self.assertTrue(projects.all_projects)
        start = parser.parse_args(
            ["agent", "start", "thesis", "selector-ui", "--mode", "explore", "--", "quote; $() stays data"]
        )
        self.assertEqual(start.mode, "explore")
        self.assertEqual(start.prompt, ["quote; $() stays data"])
        hidden = parser.parse_args(["_remote", "handoff-release", "thesis", "wip/x", "--no-push"])
        self.assertEqual(hidden.remote_args[-1], "--no-push")
        validate = parser.parse_args(["validate", "thesis", "selector-ui", "focus:selector", "--calibrate"])
        self.assertTrue(validate.calibrate)

    def test_config_update_uses_jj_and_never_integrates_with_git(self):
        source = SCRIPT.read_text()
        self.assertIn('"jj", "-R", str(source), "git", "fetch"', source)
        self.assertNotIn('"git", "checkout"', source)
        self.assertNotIn('"git", "merge"', source)

    def test_project_sync_has_no_plain_git_or_delete_fallback(self):
        source = SCRIPT.read_text()
        self.assertNotIn("shutil.rmtree", source)
        self.assertNotIn('git = ["git"', source)

    def test_remote_workspace_is_resolved_before_use(self):
        source = SCRIPT.read_text()
        self.assertGreaterEqual(source.count("resolved_remote_workspace("), 5)

    def test_resolved_symlink_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root = base / "Projects"
            outside = base / "outside"
            root.mkdir()
            outside.mkdir()
            link = root / "forged-workspace"
            link.symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(nas_cli.ManifestError, "must stay below"):
                nas_cli.require_contained(link.resolve(), root.resolve(), "workspace")


if __name__ == "__main__":
    unittest.main()
