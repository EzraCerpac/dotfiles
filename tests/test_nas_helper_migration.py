from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "dotfiles/.codex/skills/work-on-cerpacnas/scripts/nas.py"
SPEC = importlib.util.spec_from_file_location("nas_helper", HELPER)
assert SPEC and SPEC.loader
nas = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nas)


class NasHelperMigrationTests(unittest.TestCase):
    def make_manifest(self) -> tuple[tempfile.TemporaryDirectory[str], nas.Manifest, Path]:
        temporary = tempfile.TemporaryDirectory()
        home = Path(temporary.name)
        source = home / ".config/mise"
        (source / ".jj").mkdir(parents=True)
        manifest = nas.Manifest(
            path=home / ".config/cerpacnas/projects.toml",
            host=nas.HostConfig(
                ssh_alias="nas",
                remote_home=home,
                remote_project_root=home / "Projects",
                dotfiles_branch="main",
            ),
            projects={},
        )
        return temporary, manifest, source

    def test_config_status_uses_mise_source_and_native_status(self) -> None:
        temporary, manifest, source = self.make_manifest()
        self.addCleanup(temporary.cleanup)
        calls: list[tuple[list[str], Path | None]] = []

        def fake_run(arguments: list[str], *, cwd: Path | None = None, **_kwargs: object) -> None:
            calls.append((arguments, cwd))

        before = sorted(path.relative_to(source) for path in source.rglob("*"))
        with patch.object(nas, "run", side_effect=fake_run):
            nas.config_status(manifest)
        after = sorted(path.relative_to(source) for path in source.rglob("*"))

        self.assertEqual(before, after)
        self.assertEqual(
            calls,
            [
                (["jj", "-R", str(source), "status"], None),
                (["jj", "-R", str(source), "bookmark", "list", "--all-remotes", "main"], None),
                (["dots", "status"], source),
            ],
        )
        self.assertFalse(any("chezmoi" in argument for arguments, _cwd in calls for argument in arguments))

    def test_config_update_fetches_main_then_plans_and_applies_native_dots(self) -> None:
        temporary, manifest, source = self.make_manifest()
        self.addCleanup(temporary.cleanup)
        calls: list[tuple[list[str], Path | None]] = []

        def fake_run(arguments: list[str], *, cwd: Path | None = None, **_kwargs: object) -> None:
            calls.append((arguments, cwd))

        with patch.object(nas, "run", side_effect=fake_run), patch.object(nas, "jj_output", return_value=""):
            nas.config_update(manifest)

        self.assertEqual(
            calls,
            [
                (["jj", "-R", str(source), "git", "fetch", "--remote", "origin", "--branch", "main"], None),
                (["jj", "-R", str(source), "bookmark", "set", "main", "-r", "main@origin"], None),
                (["jj", "-R", str(source), "new", "main"], None),
                (["dots", "plan"], source),
                (["dots", "apply"], source),
            ],
        )

    def test_doctor_requires_mise_instead_of_chezmoi(self) -> None:
        temporary, manifest, _source = self.make_manifest()
        self.addCleanup(temporary.cleanup)
        checked: list[str] = []

        def fake_which(name: str) -> str:
            checked.append(name)
            return f"/fake/{name}"

        with patch.object(nas.shutil, "which", side_effect=fake_which):
            nas.doctor(manifest, remote_side=False)

        self.assertIn("mise", checked)
        self.assertNotIn("chezmoi", checked)

    def test_remote_doctor_passes_existing_credential_only_in_environment(self) -> None:
        temporary, manifest, _source = self.make_manifest()
        self.addCleanup(temporary.cleanup)
        calls = []

        def fake_run(arguments, **kwargs):
            calls.append((arguments, kwargs))
            stdout = "fixture-token\n" if arguments[0] == "sh" else "HTTP/2 200\n"
            return subprocess.CompletedProcess(arguments, 0, stdout, "")

        with patch.object(nas.shutil, "which", return_value="/fake/tool"), \
             patch.object(nas.Path, "home", return_value=manifest.host.remote_home), \
             patch.dict(nas.os.environ, {}, clear=True), \
             patch.object(nas, "run", side_effect=fake_run):
            nas.doctor(manifest, remote_side=True)

        self.assertEqual(calls[0][0][0], "sh")
        self.assertEqual(calls[1][1]["env"]["GH_TOKEN"], "fixture-token")
        self.assertTrue(all("fixture-token" not in arguments for arguments, _ in calls))

    def test_nas_remote_policy_drift_is_retained(self) -> None:
        policy = (ROOT / "dotfiles/.codex/skills/work-on-cerpacnas/references/remote-policy.md").read_text()
        self.assertIn("Configuration crosses through dotfiles `main`", policy)
        self.assertNotIn("chezmoi", policy)


if __name__ == "__main__":
    unittest.main()
