"""Process-boundary acceptance tests for the shared dots CLI frontend.

These tests use a temporary setup root and executable shims. They never reach
the real mise installation, network, package managers, backup store, or SSH.
"""

import fcntl
import json
import os
import pty
import select
import signal
import struct
import termios
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "dotfiles/.local/bin/dots"


class SharedDotsCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / "setup"
        self.root.mkdir()
        (self.root / "config.toml").write_text("# fixture\n")
        self.cwd = self.base / "project dir"
        self.cwd.mkdir()
        self.home = self.base / "home"
        self.home.mkdir()
        self.calls = self.base / "renderer-calls.jsonl"
        self.mise_log = self.base / "mise-calls.jsonl"
        self.renderer = self.base / "dots-up"
        self.renderer.write_text(
            """#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ["--capabilities"]:
    if os.environ.get("OLD_RENDERER") == "1":
        print("dots-up/1")
    else:
        print("dots-shared-cli/1")
    raise SystemExit(0)
with open(os.environ["RENDERER_CALLS"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("RENDERER_EXIT"):
    raise SystemExit(int(os.environ["RENDERER_EXIT"]))
"""
        )
        self.renderer.chmod(0o755)
        self.mise = self.base / "mise"
        self.mise.write_text(
            """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["MISE_CALLS"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if "which" in sys.argv:
    print(os.environ["DOTS_UP_BIN"])
"""
        )
        self.mise.chmod(0o755)
        self.env = dict(
            os.environ,
            DOTS_ROOT=str(self.root),
            DOTS_MISE_BIN=str(self.mise),
            DOTS_UP_BIN=str(self.renderer),
            HOME=str(self.home),
            MISE_ENV="thesis",
            MISE_CONFIG_DIR=str(self.cwd),
            RENDERER_CALLS=str(self.calls),
            MISE_CALLS=str(self.mise_log),
            PATH=str(self.base) + os.pathsep + os.environ.get("PATH", ""),
        )

    def run_dots(self, *args, **env):
        return subprocess.run(
            ["bash", str(SOURCE), *args], cwd=self.cwd,
            env=dict(self.env, **env), text=True, capture_output=True,
        )

    def renderer_calls(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def mise_calls(self):
        if not self.mise_log.exists():
            return []
        return [json.loads(line) for line in self.mise_log.read_text().splitlines()]

    def expected(self, command, *args, frontend=()):
        return ["--root", str(self.root), "--command", command, *frontend, "--", *args]

    def test_every_registered_command_routes_as_argv_without_side_effects(self):
        cases = [
            ("status", ()),
            ("reports", ()),
            ("sync", ()),
            ("apply", ("~/.ssh/config",)),
            ("add", ("--path=relative/config.toml", "npm:prettier@3")),
            ("remove", ("--path", "relative/config.toml", "watchexec")),
            ("backup", ()),
            ("restore", ("--host", "nas")),
            ("atuin-login", ("--identity=keys/age key.txt", "--browser")),
            ("atuin-bundle", ("--dry-run",)),
            ("bootstrap", ("--dry-run",)),
            ("remote", ("nas", "--profile", "nas", "--dry-run")),
            ("bundle", ("create", "--dry-run")),
            ("test", ("python", "shell")),
            ("publish", ("--bookmark", "wip/example")),
        ]
        for command, args in cases:
            with self.subTest(command=command, args=args):
                result = self.run_dots(command, *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.renderer_calls()[-1], self.expected(command, *args))
                self.assertEqual(self.mise_calls(), [])

    def test_up_alias_keeps_legacy_renderer_argv(self):
        for invocation, flags in ((('up', '--mas'), ('--mas',)),
                                  (('update', '--plain', '--no-wait'), ('--plain', '--no-wait'))):
            with self.subTest(invocation=invocation):
                result = self.run_dots(*invocation)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.renderer_calls()[-1], ['--root', str(self.root), *flags])
        self.assertEqual(self.mise_calls(), [])

    def test_source_only_stays_in_setup_root_with_automatic_mise_actions_disabled(self):
        result = self.run_dots('sync', '--source-only', MISE_AUTO_INSTALL='1',
                               MISE_EXEC_AUTO_INSTALL='1', MISE_AUTO_UPDATE='1', MISE_NO_HOOKS='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.mise_calls()[-1]
        self.assertEqual(call[:3], ['-C', str(self.root), 'exec'])
        self.assertEqual(call[call.index('--') + 1:], [
            '/usr/bin/env', 'MISE_AUTO_INSTALL=0', 'MISE_EXEC_AUTO_INSTALL=0',
            'MISE_AUTO_UPDATE=0', 'MISE_NO_HOOKS=1', 'node',
            str(self.root / 'setup-scripts/lib/source-repo.mjs'), 'sync',
            str(self.root), '--source-only',
        ])
        self.assertEqual(self.renderer_calls(), [])

    def test_plan_stays_on_native_mise_plan_path(self):
        result = self.run_dots('plan')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mise_calls(), [['-C', str(self.root), 'bootstrap', 'plan']])
        self.assertEqual(self.renderer_calls(), [])

    def test_houseatlas_maintenance_bypasses_shared_renderer_and_mise(self):
        result = self.run_dots("up", "houseatlas", "status")
        self.assertIn(result.returncode, (2, 3))
        self.assertEqual(self.renderer_calls(), [])
        self.assertEqual(self.mise_calls(), [])

    def test_alias_and_prefix_flags_preserve_boundary_and_token_order(self):
        cases = [
            (("uninstall", "--keep-installed", "npm:prettier"), "remove",
             ("--keep-installed", "npm:prettier"), ()),
            (("--plain", "--no-wait", "apply", "one two"), "apply",
             ("one two",), ("--plain", "--no-wait")),
        ]
        for invocation, command, args, frontend in cases:
            with self.subTest(invocation=invocation):
                result = self.run_dots(*invocation)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.renderer_calls()[-1], self.expected(command, *args, frontend=frontend))
        self.assertEqual(self.mise_calls(), [])

    def test_bare_non_tty_and_help_do_not_dispatch_or_create_state(self):
        for invocation in ((), ("--help",), ("help",)):
            with self.subTest(invocation=invocation):
                result = self.run_dots(*invocation)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("dots", result.stdout.lower())
                self.assertEqual(self.renderer_calls(), [])
                self.assertEqual(self.mise_calls(), [])
                self.assertFalse((self.home / ".local/state/dots").exists())

    def test_explicit_incomplete_or_invalid_cli_does_not_open_guided_menu(self):
        for invocation in (("up", "--bogus"),):
            with self.subTest(invocation=invocation):
                result = self.run_dots(*invocation)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.renderer_calls(), [])
                self.assertEqual(self.mise_calls(), [])

    def test_old_renderer_is_only_used_for_legacy_up_and_other_commands_fall_back(self):
        up = self.run_dots("up", "--mas", OLD_RENDERER="1")
        self.assertEqual(up.returncode, 0, up.stderr)
        self.assertEqual(self.renderer_calls()[-1], ["--root", str(self.root), "--mas"])
        calls_before = self.renderer_calls()
        status = self.run_dots("status", OLD_RENDERER="1")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(self.renderer_calls(), calls_before)
        self.assertEqual(self.mise_calls()[-1], ["-C", str(self.root), "run", "setup:status"])

    def test_missing_renderer_keeps_legacy_up_fallback_and_generic_command_fallback(self):
        self.renderer.unlink()
        up = self.run_dots("up", "--plain")
        self.assertEqual(up.returncode, 0, up.stderr)
        self.assertTrue(any("setup:update" in call for call in self.mise_calls()))
        calls_before = self.mise_calls()
        status = self.run_dots("status")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(self.mise_calls()[-1], ["-C", str(self.root), "run", "setup:status"])
        self.assertGreater(len(self.mise_calls()), len(calls_before))


class SharedDotsReportTest(unittest.TestCase):
    """Exercise report redaction and remote cancellation through real Go CLI."""

    @classmethod
    def setUpClass(cls):
        go = shutil.which("go")
        if go is None:
            raise unittest.SkipTest("Go toolchain is not installed")
        cls.build_dir = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.build_dir.cleanup)
        cls.binary = Path(cls.build_dir.name) / "dots-up"
        module = Path(__file__).resolve().parents[1] / "setup-scripts/dots-up"
        result = subprocess.run(
            [go, "build", "-o", str(cls.binary), "./cmd/dots-up"],
            cwd=module, text=True, capture_output=True,
        )
        if result.returncode:
            raise RuntimeError(f"building dots-up for report tests failed: {result.stderr}")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / "setup"
        self.root.mkdir()
        (self.root / "config.toml").write_text("# fixture\n")
        self.state = self.base / "state"
        self.runner = self.base / "runner.py"
        self.runner_log = self.base / "runner.json"
        self.runner.write_text(
            """#!/usr/bin/env python3
import json, os, sys, time
with open(os.environ["RUNNER_LOG"], "w") as f:
    json.dump(sys.argv[1:], f)
nonce = os.environ.get("DOTS_UP_STREAM_NONCE", "")
event = json.dumps({"v": 1, "kind": "run_start", "profile": "workstation", "host": "fixture"})
sys.stdout.write("\\x1edots-up/1:" + nonce + ":" + event + "\\x1f")
sys.stdout.write(os.environ.get("SENTINEL", ""))
sys.stdout.flush()
if os.environ.get("RUNNER_BLOCK") == "1":
    while True:
        time.sleep(1)
"""
        )
        self.runner.chmod(0o755)
        self.env = dict(
            os.environ,
            HOME=str(self.base / "home"),
            DOTS_UP_RUNNER=str(self.runner),
            DOTS_STATE_DIR=str(self.state),
            RUNNER_LOG=str(self.runner_log),
            SENTINEL="fixture-credential-should-never-be-saved",
        )

    def run_cli(self, command, *args, **env):
        return subprocess.run(
            [str(self.binary), "--root", str(self.root), "--command", command,
             "--plain", "--no-wait", "--", *args],
            env=dict(self.env, **env), text=True, capture_output=True,
        )

    def reports(self, command):
        return sorted((self.state / command).glob("*/report.json"))

    def read_report(self, command):
        paths = self.reports(command)
        self.assertEqual(len(paths), 1)
        return json.loads(paths[0].read_text()), paths[0].parent

    @unittest.skipUnless(shutil.which("uv") and shutil.which("jq"), "uv and jq are required for the live suite fixture")
    def test_live_test_command_isolates_fixture_protocol_and_keeps_suite_progress(self):
        source_root = SOURCE.parents[3]
        for relative in (
            "dotfiles/.local/bin/dots", "tests/run",
            "setup-scripts/lib/dots-command-backend",
            "setup-scripts/lib/dots-command-backend.py",
            "setup-scripts/lib/dots-up-events.sh",
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_root / relative, target)
        (self.root / "tests/test_nested_protocol.py").write_text(
            "import os, sys, unittest\nfrom pathlib import Path\n"
            f"sys.path.insert(0, {str(source_root / 'tests')!r})\n"
            "import test_dots_packages as packages\n"
            "class NestedPackageFixture(unittest.TestCase):\n"
            "    def test_new_mac_entries_are_guarded_in_staging(self):\n"
            "        case = packages.DotsPackageTest('test_new_mac_entries_are_guarded_in_staging')\n"
            "        result = unittest.TestResult()\n"
            "        case.run(result)\n"
            "        self.assertEqual(result.testsRun, 1)\n"
            "        self.assertTrue(result.wasSuccessful(), result.errors + result.failures)\n"
            "        for key in ('DOTS_UP_ACK_FD', 'DOTS_UP_EVENT_FD', 'DOTS_UP_STREAM_NONCE', 'DOTS_UP_RUN_DIR'):\n"
            "            self.assertNotIn(key, os.environ)\n"
            "        Path(os.environ['NESTED_FIXTURE_RESULT']).write_text('passed')\n"
        )
        mise = self.base / "mise"
        mise.write_text(
            "#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "assert args[0] == '-C' and args[2:4] == ['run', 'setup:test'], args\n"
            "Path(os.environ['LIVE_PROTOCOL_LOG']).write_text(json.dumps({key: os.environ.get(key) for key in ('DOTS_UP_ACK_FD', 'DOTS_UP_STREAM_NONCE')}))\n"
            "os.execvp('bash', ['bash', str(Path(args[1]) / 'tests/run'), *args[4:]])\n"
        )
        mise.chmod(0o755)
        env = dict(self.env, DOTS_MISE_BIN=str(mise), TERM="xterm-256color",
                   LIVE_PROTOCOL_LOG=str(self.base / "live-protocol.json"),
                   NESTED_FIXTURE_RESULT=str(self.base / "nested-result"))
        env.pop("DOTS_UP_RUNNER", None)
        env.pop("CI", None)
        env["UV_CACHE_DIR"] = subprocess.run(
            ["uv", "cache", "dir"], env=os.environ, text=True, capture_output=True, check=True,
        ).stdout.strip()
        gate_read, gate_write = os.pipe()
        pid, master = pty.fork()
        if pid == 0:
            os.close(gate_write)
            os.read(gate_read, 1)
            os.close(gate_read)
            os.execve(str(self.binary), [str(self.binary), "--root", str(self.root), "--command", "test", "--no-wait", "--", "python"], env)
        os.close(gate_read)
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        os.write(gate_write, b"1")
        os.close(gate_write)
        output = bytearray()
        status = None
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        output.extend(os.read(master, 16384))
                    except OSError:
                        pass
                waited, code = os.waitpid(pid, os.WNOHANG)
                if waited:
                    status = os.waitstatus_to_exitcode(code)
                    break
            self.assertEqual(status, 0, output.decode(errors="replace"))
        finally:
            if status is None:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)
        live_protocol = json.loads((self.base / "live-protocol.json").read_text())
        self.assertEqual(live_protocol["DOTS_UP_ACK_FD"], "4")
        self.assertTrue(live_protocol["DOTS_UP_STREAM_NONCE"])
        self.assertEqual((self.base / "nested-result").read_text(), "passed")
        report, _ = self.read_report("test")
        suite = [event for event in report["events"] if event.get("id") == "suite:python"]
        self.assertEqual([event["status"] for event in suite], ["unknown", "ok"])
        self.assertEqual(report["exit_code"], 0)

    def test_sensitive_backend_output_never_enters_saved_report_or_logs(self):
        result = self.run_cli("restore", "--host", "nas")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.runner_log.read_text()), ["restore", "--host", "nas"])
        report, run_dir = self.read_report("restore")
        self.assertEqual(report["command"], "restore")
        saved = "\n".join(path.read_text(errors="replace") for path in run_dir.rglob("*") if path.is_file())
        self.assertNotIn(self.env["SENTINEL"], saved)
        self.assertFalse((run_dir / "backend.log").exists())
        self.assertEqual(list((run_dir / "stages").glob("*.log")), [])

    def test_remote_interrupt_records_unknown_remote_state_and_preserves_130(self):
        process = subprocess.Popen(
            [str(self.binary), "--root", str(self.root), "--command", "remote",
             "--plain", "--no-wait", "--", "nas", "--profile", "nas"],
            env=dict(self.env, RUNNER_BLOCK="1"), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 5
            while not self.runner_log.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.runner_log.exists(), "remote backend did not start")
            self.assertEqual(json.loads(self.runner_log.read_text()), ["remote", "nas", "--profile", "nas"])
            process.send_signal(2)  # SIGINT to the local supervisor only.
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 130, f"stdout={stdout}\nstderr={stderr}")
            report, run_dir = self.read_report("remote")
            self.assertEqual(report["exit_code"], 130)
            notices = [event for event in report["events"] if event.get("kind") == "notice"]
            self.assertEqual(len(notices), 1)
            notice = notices[0]
            self.assertEqual(notice.get("severity"), "attention")
            self.assertIn("unknown", notice.get("summary", "").lower())
            self.assertNotIn("stopped", notice.get("summary", "").lower())
            self.assertNotIn("rolled back", notice.get("summary", "").lower())
            saved = "\n".join(path.read_text(errors="replace") for path in run_dir.rglob("*") if path.is_file())
            self.assertNotIn(self.env["SENTINEL"], saved)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
