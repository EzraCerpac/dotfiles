"""Focused tests for failed and successful `dots add` config writes."""

import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "setup-scripts/lib/dots-add-config.py"
TOOL_ADD = ROOT / "setup-scripts/lib/dots-tool-add.sh"
COMMON = ROOT / "setup-scripts/lib/dots-add-common.sh"


FAKE_MISE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if args[:1] == ["-C"]:
    args = args[2:]
log = Path(os.environ["DOTS_FAKE_LOG"])
events = json.loads(log.read_text()) if log.exists() else []
if args[0] == "reshim":
    events.append({"command": "reshim"})
    log.write_text(json.dumps(events))
    raise SystemExit(int(os.environ.get("DOTS_RESHIM_STATUS", "0")))

assert args[0] == "use", args
target = Path(args[args.index("--path") + 1])
request = args[-1]
events.append({"command": "use", "request": request, "path": str(target),
               "staged": target.read_text(), "trusted": os.environ.get("MISE_TRUSTED_CONFIG_PATHS", "")})
log.write_text(json.dumps(events))

if request in set(os.environ.get("DOTS_FAKE_SUCCEED", "").split(",")):
    with target.open("a") as stream:
        if not target.read_text().endswith("\n"):
            stream.write("\n")
        stream.write(f'"native:{request}" = {{ version = "resolved-1.2.3", native_option = true }}\n')
    raise SystemExit(0)

# Mimic a native command that writes its selected config before a later error.
with target.open("a") as stream:
    if not target.read_text().endswith("\n"):
        stream.write("\n")
    stream.write(f'"partial:{request}" = "must-not-reach-target"\n')
raise SystemExit(int(os.environ.get("DOTS_FAKE_FAILURE", "42")))
'''


class DotsAddConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dots-add-config-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_editor(self, *args):
        env = dict(os.environ)
        return subprocess.run(
            ["uv", "run", "--script", str(EDITOR), *map(str, args)],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=30,
        )

    def test_record_package_copies_one_staged_key_and_removes_exact_old_key(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        staged = self.root / "staged.toml"
        baseline = (
            "[bootstrap.packages]\n"
            '"brew:old" = { os = "macos/arm64" } # old entry\n'
            '"brew:old-extra" = "keep"\n'
            '"brew:existing" = "latest"\n'
        )
        target.write_text(baseline)
        snapshot.write_text(baseline)
        target.chmod(0o640)
        target.write_text(baseline + '\n[vars]\nlatest = "kept"\n')
        staged.write_text(
            "[bootstrap.packages]\n"
            '"brew:new" = { os = "macos/arm64", adopt = true }\n'
        )

        result = self.run_editor("record-package", target, staged, "brew:new", "--replace-key", "brew:old", "--before", snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = target.read_text()
        packages = tomllib.loads(text)["bootstrap"]["packages"]
        self.assertNotIn("brew:old", packages)
        self.assertEqual(packages["brew:old-extra"], "keep")
        self.assertEqual(packages["brew:new"], {"os": "macos/arm64", "adopt": True})
        self.assertIn('latest = "kept"', text)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_record_package_does_not_rewrite_an_unchanged_declaration(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        staged = self.root / "staged.toml"
        content = '[bootstrap.packages]\n"brew:kept" = { os = "macos/arm64" } # note\n'
        for path in (target, snapshot, staged):
            path.write_text(content)
        before = target.read_bytes()
        result = self.run_editor("record-package", target, staged, "brew:kept", "--before", snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), before)

    def test_record_package_rejects_a_changed_relevant_key(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        staged = self.root / "staged.toml"
        snapshot.write_text('[bootstrap.packages]\n"brew:new" = "old"\n')
        target.write_text('[bootstrap.packages]\n"brew:new" = "someone-else"\n')
        staged.write_text('[bootstrap.packages]\n"brew:new" = "desired"\n')
        before = target.read_bytes()
        result = self.run_editor("record-package", target, staged, "brew:new", "--before", snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target changed since snapshot", result.stderr)
        self.assertEqual(target.read_bytes(), before)

    def test_show_tool_handles_scoped_npm_backend_urls_and_inline_options(self):
        target = self.root / "config.toml"
        target.write_text('[tools]\n"cargo:https://example.invalid/acme/tool" = { os = ["linux/x64"] }\n')
        scoped = self.run_editor("show-tool", target, "npm:@scope/package@2.0.0")
        self.assertEqual(scoped.returncode, 0, scoped.stderr)
        scoped_entry = tomllib.loads(scoped.stdout)["tools"]["npm:@scope/package"]
        self.assertEqual(scoped_entry["version"], "2.0.0")

        request = 'cargo:https://example.invalid/acme/tool@rev:abc[features=pcre2, label="a b", default-features=false, extra=["one", "two"]]'
        shown = self.run_editor("show-tool", target, request)
        self.assertEqual(shown.returncode, 0, shown.stderr)
        entries = tomllib.loads(shown.stdout)["tools"]
        self.assertEqual(list(entries), ["cargo:https://example.invalid/acme/tool"])
        declaration = entries["cargo:https://example.invalid/acme/tool"]
        self.assertEqual(declaration["version"], "rev:abc")
        self.assertEqual(declaration["os"], ["linux/x64"])
        self.assertEqual(declaration["features"], "pcre2")
        self.assertEqual(declaration["label"], "a b")
        self.assertIs(declaration["default-features"], False)
        self.assertEqual(declaration["extra"], ["one", "two"])

    def test_show_tool_defaults_to_latest_for_scoped_npm_without_version(self):
        target = self.root / "missing.toml"
        result = self.run_editor("show-tool", target, "npm:@scope/package")
        self.assertEqual(result.returncode, 0, result.stderr)
        entry = tomllib.loads(result.stdout)["tools"]["npm:@scope/package"]
        self.assertEqual(entry["version"], "latest")

    def test_record_tool_updates_only_request_and_keeps_latest_unrelated_edits(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        baseline = (
            "# current setup\n[tools]\n"
            '# Keep node available on Linux\n'
            'node = { version = "18", os = ["linux/x64"], alias = "node" } # inline note\n'
            'other = "1"\n'
        )
        snapshot.write_text(baseline)
        target.write_text(baseline + '\n[env]\nNEW = "latest"\n')
        target.chmod(0o640)
        result = self.run_editor("record-tool", target, 'node@20[features=pcre2]', "--before", snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = target.read_text()
        node = tomllib.loads(text)["tools"]["node"]
        self.assertEqual(node["version"], "20")
        self.assertEqual(node["os"], ["linux/x64"])
        self.assertEqual(node["alias"], "node")
        self.assertEqual(node["features"], "pcre2")
        self.assertIn("# Keep node available on Linux", text)
        self.assertIn("# inline note", text)
        self.assertIn('NEW = "latest"', text)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_record_tool_fails_closed_if_existing_tool_changed_since_snapshot(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        snapshot.write_text('[tools]\nnode = "18"\n')
        target.write_text('[tools]\nnode = "20"\n')
        before = target.read_bytes()
        result = self.run_editor("record-tool", target, "node@22", "--before", snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target changed since snapshot", result.stderr)
        self.assertEqual(target.read_bytes(), before)

    def test_record_tools_uses_native_resolved_entries_and_preserves_latest_other_config(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        staged = self.root / "staged.toml"
        before = '[tools]\nnode = "latest"\nother = "1"\n\n[env]\nOLD = "yes"\n'
        snapshot.write_text(before)
        target.write_text(before.replace('other = "1"', 'other = "2"') + '\nLATEST = "yes"\n')
        staged.write_text(
            '[tools]\nnode = { version = "22.4.0", native_option = true }\n'
            'other = "1"\n"native:npm:foo@latest" = { version = "3.1.7" }\n\n'
            '[env]\nOLD = "yes"\n'
        )
        result = self.run_editor("record-tools", target, staged, "--before", snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = target.read_text()
        tools = tomllib.loads(text)["tools"]
        self.assertEqual(tools["node"], {"version": "22.4.0", "native_option": True})
        self.assertEqual(tools["native:npm:foo@latest"], {"version": "3.1.7"})
        self.assertEqual(tools["other"], "2")
        self.assertIn('LATEST = "yes"', text)

    def test_record_tools_rejects_concurrent_change_to_changed_entry(self):
        target = self.root / "config.toml"
        snapshot = self.root / "before.toml"
        staged = self.root / "staged.toml"
        snapshot.write_text('[tools]\nnode = "18"\n')
        staged.write_text('[tools]\nnode = "22"\n')
        target.write_text('[tools]\nnode = "20"\n')
        before = target.read_bytes()
        result = self.run_editor("record-tools", target, staged, "--before", snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("target changed since snapshot", result.stderr)
        self.assertEqual(target.read_bytes(), before)

    def make_tool_fixture(self, target_text="[tools]\nother = \"1\"\n"):
        setup = self.root / "setup"
        lib = setup / "setup-scripts/lib"
        lib.mkdir(parents=True)
        (setup / "config.toml").write_text('[tools]\nuv = "latest"\n')
        shutil.copy2(COMMON, lib / COMMON.name)
        shutil.copy2(EDITOR, lib / EDITOR.name)
        wrapper = setup / "setup-scripts/lib/dots-tool-add.sh"
        shutil.copy2(TOOL_ADD, wrapper)
        target = self.root / "target.toml"
        target.write_text(target_text)
        fake = self.root / "fake-mise"
        fake.write_text(FAKE_MISE)
        fake.chmod(0o755)
        log = self.root / "events.json"
        return setup, target, fake, log, wrapper

    def run_interactive(self, command, env, answer):
        master, slave = pty.openpty()
        process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, cwd=ROOT, env=env, close_fds=True)
        os.close(slave)
        output = bytearray()
        sent = False
        deadline = time.monotonic() + 20
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 8192)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                    if not sent and b"Record this request for a later retry? [y/N]" in output:
                        os.write(master, answer + b"\n")
                        sent = True
                if process.poll() is not None and not ready:
                    break
            try:
                status = process.wait(timeout=max(0.1, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                process.kill()
                self.fail("tool add prompt did not finish: " + output.decode(errors="replace"))
            return status, bytes(output), sent
        finally:
            os.close(master)
            if process.poll() is None:
                process.kill()
                process.wait()

    def run_tool_wrapper(self, setup, target, fake, log, wrapper, requests, *, answer, env_extra=None):
        env = dict(
            os.environ,
            DOTS_FAKE_LOG=str(log),
            DOTS_FAKE_FAILURE="42",
            MISE_CACHE_DIR=str(self.root / "mise-cache"),
            MISE_TRUSTED_CONFIG_PATHS=str(setup),
        )
        env.update(env_extra or {})
        command = ["bash", str(wrapper), str(fake), str(setup), str(target), *requests]
        return self.run_interactive(command, env, answer)

    def test_failed_tool_yes_records_but_preserves_mise_failure_status(self):
        setup, target, fake, log, wrapper = self.make_tool_fixture(
            '[tools]\nnode = { version = "18", os = ["linux/x64"] }\n'
        )
        status, output, prompted = self.run_tool_wrapper(setup, target, fake, log, wrapper, ["node@20"], answer=b"y")
        self.assertTrue(prompted, output.decode(errors="replace"))
        self.assertEqual(status, 42, output.decode(errors="replace"))
        node = tomllib.loads(target.read_text())["tools"]["node"]
        self.assertEqual(node["version"], "20")
        self.assertEqual(node["os"], ["linux/x64"])
        self.assertIn(b"recorded failed request", output)
        self.assertNotIn("partial:node@20", target.read_text())
        events = json.loads(log.read_text())
        self.assertEqual([event["request"] for event in events], ["node@20"])

    def test_failed_tool_no_keeps_target_unchanged(self):
        setup, target, fake, log, wrapper = self.make_tool_fixture()
        before = target.read_bytes()
        status, output, prompted = self.run_tool_wrapper(setup, target, fake, log, wrapper, ["node@20"], answer=b"n")
        self.assertTrue(prompted, output.decode(errors="replace"))
        self.assertEqual(status, 42, output.decode(errors="replace"))
        self.assertEqual(target.read_bytes(), before)
        self.assertNotIn("partial:node@20", target.read_text())

    def test_success_is_recorded_natively_then_failure_stops_later_requests(self):
        setup, target, fake, log, wrapper = self.make_tool_fixture()
        status, output, prompted = self.run_tool_wrapper(
            setup,
            target,
            fake,
            log,
            wrapper,
            ["node@22", "broken@1", "later@latest"],
            answer=b"n",
            env_extra={"DOTS_FAKE_SUCCEED": "node@22"},
        )
        self.assertTrue(prompted, output.decode(errors="replace"))
        self.assertEqual(status, 42, output.decode(errors="replace"))
        content = target.read_text()
        tools = tomllib.loads(content)["tools"]
        self.assertEqual(tools["native:node@22"], {"version": "resolved-1.2.3", "native_option": True})
        self.assertEqual(tools["other"], "1")
        self.assertNotIn("partial:broken@1", content)
        events = json.loads(log.read_text())
        self.assertEqual(
            [(event["command"], event.get("request")) for event in events],
            [("use", "node@22"), ("reshim", None), ("use", "broken@1")],
        )
        self.assertIn(b"saved its native declaration", output)


    def test_success_stages_only_requested_tool_without_target_hooks_or_templates(self):
        setup, target, fake, log, wrapper = self.make_tool_fixture(
            '[tools]\nnode = { version = "18", os = ["macos/arm64"] }\n'
            'other = "{{ exec(command=\'must-not-run\') }}"\n'
            '\n[env]\nUNSAFE = "{{ exec(command=\'must-not-run\') }}"\n'
            '\n[hooks]\nenter = "must-not-run"\n'
        )
        status, output, prompted = self.run_tool_wrapper(
            setup, target, fake, log, wrapper, ["node@22"], answer=b"n",
            env_extra={"DOTS_FAKE_SUCCEED": "node@22"},
        )
        self.assertEqual(status, 0, output.decode(errors="replace"))
        self.assertFalse(prompted)
        event = json.loads(log.read_text())[0]
        staged = tomllib.loads(event["staged"])
        self.assertEqual(staged, {"tools": {"node": {"version": "18", "os": ["macos/arm64"]}}})
        trusted = [Path(path).resolve() for path in event["trusted"].split(os.pathsep)]
        self.assertIn(Path(event["path"]).parent.resolve(), trusted)
        self.assertNotIn(target.parent.resolve(), trusted)
        after = tomllib.loads(target.read_text())
        self.assertEqual(after["tools"]["other"], "{{ exec(command='must-not-run') }}")
        self.assertEqual(after["hooks"]["enter"], "must-not-run")

    def test_requested_tool_template_stops_before_native_execution(self):
        setup, target, fake, log, wrapper = self.make_tool_fixture(
            '[tools]\nnode = "{{ exec(command=\'must-not-run\') }}"\n'
        )
        before = target.read_bytes()
        status, output, _ = self.run_tool_wrapper(setup, target, fake, log, wrapper, ["node@22"], answer=b"n")
        self.assertNotEqual(status, 0)
        self.assertIn(b"templated tool declarations cannot be staged safely", output)
        self.assertFalse(log.exists())
        self.assertEqual(target.read_bytes(), before)

    @unittest.skipUnless(shutil.which("mise"), "native mise unavailable")
    def test_native_mise_accepts_narrow_stage_without_installing_tools(self):
        setup = self.root / "setup"
        setup.mkdir()
        (setup / "config.toml").write_text("")
        target = self.root / "target.toml"
        target.write_text('[tools]\nnode = { version = "system" }\n\n[hooks]\nenter = "must-not-run"\n')
        stage_dir = self.root / "stage"
        stage_dir.mkdir()
        staged = stage_dir / "mise.toml"
        result = self.run_editor("stage-tools", target, staged, "node@system")
        self.assertEqual(result.returncode, 0, result.stderr)
        env = dict(os.environ, MISE_CONFIG_DIR=str(setup), MISE_ENV="",
                   MISE_TRUSTED_CONFIG_PATHS=os.pathsep.join((str(setup), str(stage_dir))),
                   MISE_AUTO_INSTALL="0", MISE_AUTO_UPDATE="0")
        result = subprocess.run(
            [shutil.which("mise"), "-C", str(setup), "use", "--dry-run", "--path", str(staged), "node@system"],
            env=env, text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("not trusted", result.stderr)
        self.assertNotIn("must-not-run", result.stderr)
        self.assertEqual(tomllib.loads(staged.read_text()), {"tools": {"node": {"version": "system"}}})


if __name__ == "__main__":
    unittest.main()
