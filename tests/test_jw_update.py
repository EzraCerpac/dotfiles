from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

import test_setup_tasks as maintenance_fixtures


SOURCE_ROOT = Path(__file__).resolve().parents[1]
HELPER = SOURCE_ROOT / "setup-scripts/lib/jw-update.py"
REMOTE = "https://github.com/EzraCerpac/jj-waltz.git"
VERSION = "0.8.0"


# Git still checks real refs, commits, remote configuration and detached
# checkouts. Only the transport is replaced with a disposable local repository;
# every other network protocol is disabled even if a test regresses.
GIT_FIXTURE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import time

args = sys.argv[1:]
state = Path(os.environ["JW_FIXTURE_STATE"])
with (state / "git.jsonl").open("a") as handle:
    handle.write(json.dumps(args) + "\n")
if any(command in args for command in ("ls-remote", "fetch")):
    if (os.environ.get("JW_FIXTURE_NETWORK_FAIL") == "1"
            or "fetch" in args and os.environ.get("JW_FIXTURE_FETCH_FAIL") == "1"):
        print("fixture network unavailable", file=sys.stderr)
        raise SystemExit(42)
if "ls-remote" in args and os.environ.get("JW_FIXTURE_REMOTE_GATE") == "1":
    (state / "remote-entered").touch()
    for _ in range(1000):
        if (state / "remote-release").exists():
            break
        time.sleep(0.01)
    else:
        raise SystemExit(91)
command = [
    os.environ["JW_FIXTURE_REAL_GIT"],
    "-c", "protocol.file.allow=always",
    "-c", "protocol.https.allow=never",
    "-c", "protocol.http.allow=never",
    "-c", "protocol.ssh.allow=never",
    "-c", "url." + Path(os.environ["JW_FIXTURE_REMOTE"]).as_uri() + ".insteadOf=" +
          "https://github.com/EzraCerpac/jj-waltz.git",
    *args,
]
raise SystemExit(subprocess.run(command).returncode)
'''


CARGO_FIXTURE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import tomllib

args = sys.argv[1:]
state = Path(os.environ["JW_FIXTURE_STATE"])
manifest = Path(args[args.index("--manifest-path") + 1]).resolve()
source = manifest.parent
version = tomllib.loads(manifest.read_text())["package"]["version"]
package_id = "path+" + source.as_uri() + "#jj-waltz@" + version
commit = subprocess.check_output(
    [os.environ["JW_FIXTURE_REAL_GIT"], "-C", str(source), "rev-parse", "HEAD"],
    text=True,
).strip()
record = {"args": args, "cwd": os.getcwd(), "manifest": str(manifest), "commit": commit,
          "target_env": os.environ.get("CARGO_TARGET_DIR"),
          "injected_build_vars": {name: os.environ[name] for name in
              ("RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS",
               "CARGO_BUILD_RUSTFLAGS", "CARGO_PROFILE_RELEASE_LTO",
               "CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER", "RUSTDOCFLAGS")
              if name in os.environ}}
with (state / "cargo.jsonl").open("a") as handle:
    handle.write(json.dumps(record) + "\n")
if args[0] == "metadata":
    print(json.dumps({"packages": [{"name": "jj-waltz", "version": version,
        "id": package_id, "manifest_path": str(manifest),
        "targets": [{"name": "jw", "kind": ["bin"]}]}]}))
    raise SystemExit(0)
if args[0] != "build":
    raise SystemExit(90)
if os.environ.get("JW_FIXTURE_BUILD_GATE") == "1":
    (state / "build-entered").touch()
    for _ in range(1000):
        if (state / "build-release").exists():
            break
        time.sleep(0.01)
    else:
        raise SystemExit(91)
if os.environ.get("JW_FIXTURE_BUILD_FAIL") == "1":
    print("fixture compiler failed", file=sys.stderr)
    raise SystemExit(43)
target = Path(args[args.index("--target-dir") + 1]).resolve()
binary = target / "release/jw"
binary.parent.mkdir(parents=True, exist_ok=True)
actual_version = "9.9.9" if os.environ.get("JW_FIXTURE_BAD_VERSION") == "1" else version
contents = '#!/usr/bin/env python3\nimport sys\n# source ' + commit + '\n'
contents += 'if sys.argv[1:] == ["--version"]: print("jw ' + actual_version + '")\n'
contents += 'elif sys.argv[1:] == ["--help"]: print("Usage: jw <COMMAND>\\nCommands: status remove doctor")\n'
contents += 'else: raise SystemExit(2)\n'
binary.write_text(contents)
binary.chmod(0o755)
if os.environ.get("JW_FIXTURE_ARTIFACT_ESCAPE") == "1":
    binary = state / "outside-jw"
    binary.write_text(contents)
    binary.chmod(0o755)
if os.environ.get("JW_FIXTURE_MISSING_BINARY") == "1":
    binary.unlink()
artifact_id = "another-package" if os.environ.get("JW_FIXTURE_BAD_ARTIFACT") == "1" else package_id
print(json.dumps({"reason": "compiler-artifact", "package_id": artifact_id,
    "target": {"name": "jw", "kind": ["bin"]}, "executable": str(binary)}))
print(json.dumps({"reason": "build-finished", "success": True}))
if os.environ.get("JW_FIXTURE_CHANGE_HEAD") == "1":
    subprocess.run([
        os.environ["JW_FIXTURE_REAL_GIT"], "-C", str(source),
        "-c", "user.name=JW Fixture", "-c", "user.email=jw-fixture@example.invalid",
        "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        "commit", "--allow-empty", "--message", "fixture changes source HEAD",
    ], check=True, stdout=subprocess.DEVNULL)
'''


class JwUpdaterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.home = self.base / "home"
        self.home.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.remote = self.base / "upstream"
        self.remote.mkdir()
        self.real_git = shutil.which("git")
        if not self.real_git:
            self.skipTest("git is needed for disposable local source fixtures")
        self.git_env = {name: value for name, value in os.environ.items() if not name.startswith("GIT_")}
        self.git_env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self._git("init", "--initial-branch=main")
        self._git("config", "user.name", "JW Fixture")
        self._git("config", "user.email", "jw-fixture@example.invalid")
        self._git("config", "commit.gpgsign", "false")
        (self.remote / "Cargo.toml").write_text(
            f'[package]\nname = "jj-waltz"\nversion = "{VERSION}"\n'
            '[[bin]]\nname = "jw"\npath = "src/main.rs"\n'
        )
        (self.remote / "Cargo.lock").write_text("# local fixture lockfile\nversion = 4\n")
        (self.remote / "src").mkdir()
        (self.remote / "src/main.rs").write_text("// initial source\n")
        self.old_commit = self.commit("initial")
        self.install = self.home / ".local/bin/jw"
        self.managed = self.home / ".local/libexec/jj-waltz"
        self.write_executable(self.bin / "git", GIT_FIXTURE)
        self.write_executable(self.bin / "cargo", CARGO_FIXTURE)
        self.env = dict(
            self.git_env,
            HOME=str(self.home),
            PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            TMPDIR=str(self.base / "tmp"),
            JW_FIXTURE_STATE=str(self.state),
            JW_FIXTURE_REAL_GIT=str(self.real_git),
            JW_FIXTURE_REMOTE=str(self.remote),
        )
        Path(self.env["TMPDIR"]).mkdir()

    def _git(self, *args: str) -> str:
        return subprocess.check_output(
            [self.real_git, "-C", str(self.remote), *args],
            env=self.git_env, text=True, stderr=subprocess.PIPE,
        ).strip()

    def commit(self, message: str) -> str:
        self._git("add", "--all")
        self._git("commit", "--message", message)
        return self._git("rev-parse", "HEAD")

    def advance_main(self, label: str = "native removal") -> str:
        (self.remote / "src/main.rs").write_text(f"// updated source: {label}\n")
        return self.commit(label)

    @staticmethod
    def write_executable(path: Path, contents: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        path.chmod(0o755)

    def binary(self, path: Path, label: str = "old") -> None:
        self.write_executable(path, f'#!/bin/sh\n# {label}\nprintf "jw {VERSION}\\n"\n')

    def legacy_managed_install(self, commit: str | None = None) -> Path:
        commit = commit or self.old_commit
        release = self.managed / f"{VERSION}-{commit[:12]}"
        self.binary(release / "jw")
        (release / "source-commit").write_text(commit + "\n")
        self.install.parent.mkdir(parents=True, exist_ok=True)
        self.install.symlink_to(release / "jw")
        return release

    def run_helper(self, *args: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(HELPER), *args], env=dict(self.env, **extra_env),
            text=True, capture_output=True, timeout=15, check=False,
        )

    def cargo_calls(self) -> list[dict]:
        log = self.state / "cargo.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def git_calls(self) -> list[list[str]]:
        log = self.state / "git.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def assert_no_build_data(self) -> None:
        for call in self.cargo_calls():
            self.assertFalse(Path(call["manifest"]).parent.exists(), call)
            if call["target_env"]:
                self.assertFalse(Path(call["target_env"]).exists(), call)
        # Apple Git may leave its small xcrun lookup cache in TMPDIR. Source,
        # target and publication directories are all updater-owned artifacts.
        self.assertEqual([path.name for path in Path(self.env["TMPDIR"]).iterdir()
                          if path.name != "xcrun_db"], [])
        if self.managed.exists():
            self.assertEqual(list(self.managed.glob(".build-*")), [])
            self.assertEqual(list(self.managed.glob(".stage-*")), [])
            self.assertEqual(list(self.managed.glob(".previous-*")), [])
        if self.install.parent.exists():
            self.assertEqual(list(self.install.parent.glob(".jw-*")), [])

    def assert_active_commit(self, commit: str) -> Path:
        self.assertTrue(self.install.is_symlink())
        release = self.install.resolve().parent
        self.assertEqual((release / "source-commit").read_text().strip(), commit)
        metadata = json.loads((release / "build.json").read_text())
        self.assertEqual(metadata["schema"], 1)
        self.assertEqual(metadata["source_commit"], commit)
        self.assertEqual(metadata["version"], VERSION)
        self.assertEqual(metadata["repository"], REMOTE)
        self.assertEqual(metadata["sha256"], hashlib.sha256((release / "jw").read_bytes()).hexdigest())
        return release

    def start_gated_update(self, gate: str = "build") -> subprocess.Popen[str]:
        process = subprocess.Popen(
            [sys.executable, str(HELPER), "--update-existing"],
            env=dict(self.env, **{f"JW_FIXTURE_{gate.upper()}_GATE": "1"}),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        def cleanup() -> None:
            if process.poll() is None:
                process.kill()
            process.communicate()
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while not (self.state / f"{gate}-entered").exists():
            if process.poll() is not None:
                out, err = process.communicate()
                self.fail(f"updater exited before fixture {gate} gate: {process.returncode}\n{out}\n{err}")
            if time.monotonic() > deadline:
                self.fail(f"updater did not reach fixture {gate} gate")
            time.sleep(0.01)
        return process

    def test_absent_update_is_skipped_before_network(self) -> None:
        result = self.run_helper("--update-existing", JW_FIXTURE_NETWORK_FAIL="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skip", result.stdout.lower())
        self.assertFalse(self.install.exists())
        self.assertEqual(self.git_calls(), [])
        self.assertEqual(self.cargo_calls(), [])

    def test_unchanged_managed_legacy_layout_gains_identity_without_build(self) -> None:
        previous = self.legacy_managed_install()
        original = (previous / "jw").read_bytes()
        result = self.run_helper("--update-existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.assert_active_commit(self.old_commit), previous)
        self.assertEqual((previous / "jw").read_bytes(), original)
        self.assertEqual(self.cargo_calls(), [])
        self.assert_no_build_data()

    def test_changed_commit_builds_cleanly_and_retains_previous_for_rollback(self) -> None:
        previous = self.legacy_managed_install()
        original = (previous / "jw").read_bytes()
        current = self.advance_main()
        # A development worktree is irrelevant to routine source updates.
        development = self.home / "Projects/jj-waltz"
        development.mkdir(parents=True)
        (development / "unpublished.txt").write_text("keep unpublished source\n")
        result = self.run_helper("--update-existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        active = self.assert_active_commit(current)
        self.assertNotEqual(active, previous)
        self.assertEqual((self.managed / "previous").resolve(), previous / "jw")
        self.assertEqual((previous / "jw").read_bytes(), original)
        self.assertEqual((development / "unpublished.txt").read_text(), "keep unpublished source\n")
        calls = self.cargo_calls()
        self.assertEqual([call["args"][0] for call in calls], ["metadata", "build"])
        self.assertTrue(all(call["commit"] == current for call in calls))
        self.assertIn("--locked", calls[1]["args"])
        self.assertIn("--release", calls[1]["args"])
        self.assertEqual(calls[1]["args"][calls[1]["args"].index("--bin") + 1], "jw")
        self.assert_no_build_data()
        # Repeating a successful update must fetch identity but do no Rust work.
        repeated = self.run_helper("--update-existing")
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(len(self.cargo_calls()), 2)

    def test_network_build_and_validation_failures_preserve_active_binary(self) -> None:
        previous = self.legacy_managed_install()
        original = (previous / "jw").read_bytes()
        original_link = os.readlink(self.install)
        self.advance_main()
        for failure in (
            "JW_FIXTURE_NETWORK_FAIL", "JW_FIXTURE_FETCH_FAIL", "JW_FIXTURE_BUILD_FAIL", "JW_FIXTURE_BAD_VERSION",
            "JW_FIXTURE_BAD_ARTIFACT", "JW_FIXTURE_ARTIFACT_ESCAPE", "JW_FIXTURE_MISSING_BINARY",
            "JW_FIXTURE_CHANGE_HEAD",
        ):
            with self.subTest(failure=failure):
                result = self.run_helper("--update-existing", **{failure: "1"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(os.readlink(self.install), original_link)
                self.assertEqual((previous / "jw").read_bytes(), original)
                self.assertEqual(list(self.managed.glob(f"{VERSION}-*")), [previous])
                self.assert_no_build_data()

    def test_regular_and_known_development_installs_are_snapshotted_before_migration(self) -> None:
        current = self.advance_main()
        for kind in ("regular", "development"):
            with self.subTest(kind=kind):
                shutil.rmtree(self.home / ".local", ignore_errors=True)
                self.install.parent.mkdir(parents=True)
                if kind == "regular":
                    self.binary(self.install, kind)
                else:
                    dev_binary = self.home / "Projects/jj-waltz/target/release/jw"
                    self.binary(dev_binary, kind)
                    self.install.symlink_to(dev_binary)
                old_contents = self.install.read_bytes()
                result = self.run_helper("--update-existing")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_active_commit(current)
                previous = self.managed / "previous"
                self.assertTrue(previous.is_symlink())
                self.assertTrue(previous.resolve().parent.name.startswith("legacy-"))
                self.assertEqual(previous.read_bytes(), old_contents)
                if kind == "development":
                    self.assertEqual(dev_binary.read_bytes(), old_contents)
                self.assert_no_build_data()

    def test_unknown_symlink_and_non_jw_regular_file_are_rejected_without_network(self) -> None:
        outside = self.base / "someone-elses/jw"
        self.binary(outside)
        self.install.parent.mkdir(parents=True)
        self.install.symlink_to(outside)
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), outside)
        self.assertEqual(self.git_calls(), [])
        self.install.unlink()
        self.write_executable(self.install, '#!/bin/sh\nprintf "unrelated program\\n"\n')
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install.is_symlink())
        self.assertEqual(self.git_calls(), [])

    def test_tampered_managed_binary_or_identity_is_rejected(self) -> None:
        self.legacy_managed_install()
        result = self.run_helper("--update-existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        active = self.assert_active_commit(self.old_commit)
        original = (active / "jw").read_bytes()
        (active / "jw").write_bytes(original + b"# unexpected replacement\n")
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), active / "jw")
        self.assertEqual(self.cargo_calls(), [])

    def test_concurrent_updater_does_not_duplicate_build_or_change_active(self) -> None:
        previous = self.legacy_managed_install()
        current = self.advance_main()
        first = self.start_gated_update()
        second = self.run_helper("--update-existing")
        self.assertNotEqual(second.returncode, 0)
        self.assertRegex((second.stdout + second.stderr).lower(), r"lock|busy|another jw updater is running")
        self.assertEqual(self.install.resolve(), previous / "jw")
        (self.state / "build-release").touch()
        out, err = first.communicate(timeout=5)
        self.assertEqual(first.returncode, 0, out + err)
        self.assert_active_commit(current)
        self.assertEqual(sum(call["args"][0] == "build" for call in self.cargo_calls()), 1)
        self.assert_no_build_data()

    def test_external_active_link_change_during_build_is_preserved(self) -> None:
        previous = self.legacy_managed_install()
        self.advance_main()
        first = self.start_gated_update()
        replacement = self.base / "external-owner/jw"
        self.binary(replacement, "external replacement")
        self.install.unlink()
        self.install.symlink_to(replacement)
        (self.state / "build-release").touch()
        out, err = first.communicate(timeout=5)
        self.assertNotEqual(first.returncode, 0, out + err)
        self.assertEqual(self.install.resolve(), replacement)
        self.assertTrue((previous / "jw").exists())
        self.assert_no_build_data()

    def test_injected_build_wrappers_and_flags_are_removed(self) -> None:
        self.legacy_managed_install()
        self.advance_main()
        result = self.run_helper(
            "--update-existing", RUSTC_WRAPPER="unexpected-wrapper",
            RUSTC_WORKSPACE_WRAPPER="unexpected-workspace-wrapper", RUSTFLAGS="--cfg unexpected",
            CARGO_ENCODED_RUSTFLAGS="--cfg\x1funexpected",
            CARGO_BUILD_RUSTFLAGS="--cfg unexpected", CARGO_PROFILE_RELEASE_LTO="off",
            CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="unexpected-linker", RUSTDOCFLAGS="--cfg unexpected",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.cargo_calls())
        self.assertTrue(all(not call["injected_build_vars"] for call in self.cargo_calls()))
        self.assert_no_build_data()

    def test_malformed_managed_marker_and_metadata_preserve_existing_owner(self) -> None:
        previous = self.legacy_managed_install()
        original_link = os.readlink(self.install)
        for marker in ("not-a-commit\n", "a" * 40 + "\n"):
            with self.subTest(marker=marker):
                (previous / "source-commit").write_text(marker)
                result = self.run_helper("--update-existing")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(os.readlink(self.install), original_link)
                self.assertEqual(self.git_calls(), [])
        (previous / "source-commit").write_text(self.old_commit + "\n")
        (previous / "build.json").write_text('{"schema":1,"sha256":"not-a-digest"}\n')
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(os.readlink(self.install), original_link)
        self.assertEqual(self.git_calls(), [])
        self.assertEqual(self.cargo_calls(), [])

    def test_broken_and_traversing_managed_symlinks_are_rejected(self) -> None:
        self.install.parent.mkdir(parents=True)
        self.install.symlink_to(self.managed / f"{VERSION}-{self.old_commit[:12]}/jw")
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.install.is_symlink())
        self.assertEqual(self.git_calls(), [])
        self.install.unlink()
        outside = self.home / ".local/libexec/outside/jw"
        self.binary(outside)
        self.install.symlink_to(self.managed / "../outside/jw")
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), outside)
        self.assertEqual(self.git_calls(), [])

    def test_release_directory_symlink_is_not_treated_as_managed_ownership(self) -> None:
        outside = self.base / "external-release"
        self.binary(outside / "jw")
        (outside / "source-commit").write_text(self.old_commit + "\n")
        self.managed.mkdir(parents=True)
        release = self.managed / f"{VERSION}-{self.old_commit[:12]}"
        release.symlink_to(outside, target_is_directory=True)
        self.install.parent.mkdir(parents=True)
        self.install.symlink_to(release / "jw")
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), outside / "jw")
        self.assertFalse((outside / "build.json").exists())
        self.assertEqual(self.git_calls(), [])

    def test_failed_later_update_preserves_active_and_existing_rollback(self) -> None:
        original = self.legacy_managed_install()
        current = self.advance_main()
        first = self.run_helper("--update-existing")
        self.assertEqual(first.returncode, 0, first.stderr)
        active = self.assert_active_commit(current)
        active_link = os.readlink(self.install)
        rollback_link = os.readlink(self.managed / "previous")
        self.advance_main("subsequent source change")
        failure = self.run_helper("--update-existing", JW_FIXTURE_BUILD_FAIL="1")
        self.assertNotEqual(failure.returncode, 0)
        self.assertEqual(os.readlink(self.install), active_link)
        self.assertEqual(os.readlink(self.managed / "previous"), rollback_link)
        self.assertEqual((self.managed / "previous").resolve(), original / "jw")
        self.assertTrue((active / "jw").exists())
        self.assert_no_build_data()

    def test_unknown_rollback_pointer_is_preserved_and_update_refused(self) -> None:
        original = self.legacy_managed_install()
        outside = self.base / "unmanaged-rollback/jw"
        self.binary(outside)
        previous = self.managed / "previous"
        previous.symlink_to(outside)
        self.advance_main()
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), original / "jw")
        self.assertEqual(previous.resolve(), outside)
        self.assert_no_build_data()

    def test_noop_detects_external_active_change_while_checking_main(self) -> None:
        previous = self.legacy_managed_install()
        updater = self.start_gated_update("remote")
        replacement = self.base / "external-owner/jw"
        self.binary(replacement)
        self.install.unlink()
        self.install.symlink_to(replacement)
        (self.state / "remote-release").touch()
        out, err = updater.communicate(timeout=5)
        self.assertNotEqual(updater.returncode, 0, out + err)
        self.assertEqual(self.install.resolve(), replacement)
        self.assertFalse((previous / "build.json").exists())
        self.assertEqual(self.cargo_calls(), [])

    def test_existing_release_directory_collision_is_refused(self) -> None:
        original = self.legacy_managed_install()
        current = self.advance_main()
        collision = self.managed / f"{VERSION}-{current[:12]}"
        self.binary(collision / "jw", "unrelated cached binary")
        (collision / "source-commit").write_text(self.old_commit + "\n")
        before = (collision / "jw").read_bytes()
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.install.resolve(), original / "jw")
        self.assertEqual((collision / "jw").read_bytes(), before)
        self.assertEqual([call["args"][0] for call in self.cargo_calls()], ["metadata"])
        self.assert_no_build_data()

    def test_inactive_marker_only_cache_is_rejected_without_activation(self) -> None:
        original = self.legacy_managed_install()
        current = self.advance_main()
        cached = self.managed / f"{VERSION}-{current[:12]}"
        self.binary(cached / "jw", "uncertified cached artifact")
        (cached / "source-commit").write_text(current + "\n")
        original_link = os.readlink(self.install)
        result = self.run_helper("--update-existing")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(os.readlink(self.install), original_link)
        self.assertEqual(self.install.resolve(), original / "jw")
        self.assertFalse((self.managed / "previous").exists())
        self.assertFalse((cached / "build.json").exists())
        self.assert_no_build_data()

    def test_unwritable_launcher_preparation_preserves_active_and_existing_rollback(self) -> None:
        if os.geteuid() == 0:
            self.skipTest("root bypasses disposable directory permission checks")
        self.legacy_managed_install()
        self.advance_main()
        first = self.run_helper("--update-existing")
        self.assertEqual(first.returncode, 0, first.stderr)
        active_link = os.readlink(self.install)
        previous_link = os.readlink(self.managed / "previous")
        self.advance_main("update with unwritable launcher directory")
        mode = self.install.parent.stat().st_mode & 0o777
        self.install.parent.chmod(0o555)
        try:
            failure = self.run_helper("--update-existing")
        finally:
            self.install.parent.chmod(mode)
        self.assertNotEqual(failure.returncode, 0)
        self.assertEqual(os.readlink(self.install), active_link)
        self.assertEqual(os.readlink(self.managed / "previous"), previous_link)
        self.assert_no_build_data()

    def test_failed_final_active_replace_restores_existing_rollback(self) -> None:
        self.legacy_managed_install()
        self.advance_main()
        first = self.run_helper("--update-existing")
        self.assertEqual(first.returncode, 0, first.stderr)
        active_link = os.readlink(self.install)
        previous_link = os.readlink(self.managed / "previous")
        self.advance_main("update with final launcher syscall failure")
        # Simulate the OS refusing only the final active-link rename; staging
        # and the rollback pointer use real filesystem operations. Running in
        # a child keeps the monkeypatch independent of other suite processes.
        runner = '''import errno, importlib.util, os, pathlib, sys
helper_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("jw_update_fixture", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
active = pathlib.Path(os.environ["HOME"]) / ".local/bin/jw"
replace = helper.os.replace
def deny_active_replace(source, destination):
    if pathlib.Path(destination) == active:
        raise OSError(errno.EACCES, "fixture final active replacement refused")
    return replace(source, destination)
helper.os.replace = deny_active_replace
sys.argv = sys.argv[1:]
raise SystemExit(helper.main())
'''
        failure = subprocess.run(
            [sys.executable, "-c", runner, str(HELPER), "--update-existing"],
            env=self.env, text=True, capture_output=True, timeout=15, check=False,
        )
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn("fixture final active replacement refused", failure.stderr)
        self.assertEqual(os.readlink(self.install), active_link)
        self.assertEqual(os.readlink(self.managed / "previous"), previous_link)
        self.assert_no_build_data()


class JwShellIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        # Compose the shared maintenance harness instead of subclassing it:
        # unittest must not discover a second copy of its entire suite.
        self.fixture = maintenance_fixtures.SetupTaskTests("runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root = self.fixture.root
        (self.root / "config.toml").write_text("")
        self.home = Path(self.fixture.env["HOME"])
        self.invocations = self.fixture.base / "jw-calls.jsonl"
        mise = self.fixture.bin / "mise"
        contents = mise.read_text()
        needle = 'if [[ "${1:-}" == "settings" && "${2:-}" == "get" ]]; then'
        contents = contents.replace(needle, '''if [[ "${1:-}" == "run" && "${2:-}" == "setup:update" ]]; then
    shift 2
    exec bash "$SETUP_CONFIG_ROOT/setup-scripts/setup/update" "$@"
fi
''' + needle, 1)
        mise.write_text(contents)
        self.fixture.env.update(
            DOTS_ROOT=str(self.root), DOTS_MISE_BIN=str(mise),
            JW_TEST_LOG=str(self.invocations),
        )
        self.fixture._write_executable(
            self.fixture.bin / "uname", '#!/bin/sh\nprintf "Linux\\n"\n',
        )

    def stub_helper(self) -> None:
        self.fixture._write_executable(
            self.root / "setup-scripts/lib/jw-update.py",
            '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["JW_TEST_LOG"], "a") as handle:
    handle.write(json.dumps({"args": sys.argv[1:], "profile": os.environ.get("SETUP_PROFILE"),
        "machine": os.environ.get("SETUP_MACHINE_ID"), "cwd": os.getcwd()}) + "\\n")
print("fixture jw updater result", flush=True)
raise SystemExit(int(os.environ.get("JW_TEST_RESULT", "0")))
''',
        )

    def run_dots(self, *args: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SOURCE_ROOT / "dotfiles/.local/bin/dots"), "up", *args],
            cwd=self.fixture.base, env=dict(self.fixture.env, **extra_env),
            text=True, capture_output=True, timeout=15, check=False,
        )

    def calls(self) -> list[dict]:
        return [json.loads(line) for line in self.invocations.read_text().splitlines()] if self.invocations.exists() else []

    def test_dots_up_runs_existing_only_updater_in_selected_workstation_environment(self) -> None:
        self.stub_helper()
        result = self.run_dots()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.calls()[0]["args"], ["--update-existing"])
        self.assertEqual(self.calls()[0]["profile"], "workstation")
        self.assertEqual(self.calls()[0]["machine"], "mac-primary")
        self.assertIn("jw main source", result.stdout)
        self.assertIn("Update report: completed", result.stdout)

    def test_dots_up_skips_absent_jw_without_fetch_or_install(self) -> None:
        result = self.run_dots("--verbose")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / ".local/bin/jw").exists())
        self.assertEqual(self.fixture._git_calls(), [])
        self.assertIn("jw", result.stdout.lower())
        self.assertIn("skip", result.stdout.lower())

    def test_plain_fallback_cleans_success_and_retains_only_ten_failed_runs(self) -> None:
        xdg_state = self.fixture.base / "xdg-state"
        fallback_state = xdg_state / "dots/up"
        env = {
            "DOTS_UP_BIN": str(self.fixture.base / "missing-dots-up"),
            "XDG_STATE_HOME": str(xdg_state),
        }

        successful = self.run_dots("--plain", **env)
        self.assertEqual(successful.returncode, 0, successful.stderr)
        self.assertEqual(list(fallback_state.glob("*/.fallback")), [])

        old_runs = []
        for index in range(11):
            run = fallback_state / f"20250101T0000{index:02d}Z-old-{index}"
            run.mkdir(parents=True)
            (run / ".fallback").touch()
            (run / "stages").mkdir()
            old_runs.append(run)
        failed = self.run_dots("--plain", FAIL_PACKAGES="1", **env)
        self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
        retained = list(fallback_state.glob("*/.fallback"))
        self.assertEqual(len(retained), 10)
        self.assertTrue(all(not (path.parent / ".active").exists() for path in retained))
        self.assertFalse(old_runs[0].exists(), "the oldest completed fallback log was not pruned")
        current = [path.parent for path in retained if path.parent not in old_runs]
        self.assertEqual(len(current), 1, f"current failed logs are missing: {retained}")
        self.assertTrue(any((current[0] / "stages").glob("*.log")), "failed stage output was not retained")

    def test_dots_up_nas_never_calls_jw_source_updater(self) -> None:
        self.stub_helper()
        jw = self.home / ".local/bin/jw"
        jw.parent.mkdir(parents=True)
        self.fixture._write_executable(jw, '#!/bin/sh\nprintf "jw 0.3.1\\n"\n')
        before = jw.read_bytes()
        result = self.run_dots(SETUP_PROFILE="nas", SETUP_MACHINE_ID="cerpacnas")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(jw.read_bytes(), before)
        self.assertEqual(self.fixture._git_calls(), [])

    def test_jw_failure_is_aggregated_while_independent_stages_continue(self) -> None:
        self.stub_helper()
        result = self.run_dots(JW_TEST_RESULT="52", FAIL_PACKAGES="1", SOURCE_SYNC_RESULT="3")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn("Result: failed (exit 52)", result.stdout)
        report = result.stdout[result.stdout.index("Update report:"):]
        self.assertIn("jw main source", report)
        self.assertIn("declared host packages", report)
        commands = [call[4:] for call in self.fixture._calls() if call[:1] == ["-C"]]
        self.assertIn(["self-update", "--yes"], commands)
        self.assertEqual(commands[-1], ["bootstrap", "dotfiles", "save"])
