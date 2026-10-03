"""Hermetic presentation-mode tests: no real app, agent, HTTP or signal actions."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PRESENT = ROOT / "dotfiles/.local/bin/present"
TREE = """    1 0 launchd
   90 1 /Applications/Codex.app/Contents/MacOS/Codex
  100 90 npm run dev
  110 100 pnpm dev
  120 110 python demo.py
  121 120 uvicorn worker:app
  130 110 npm run dev unrelated-sibling
  200 1 uvicorn unrelated:app
  300 1 /Applications/Steam.app/Contents/MacOS/steam
"""

STUB = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["FIXTURE"])
with (root / "calls").open("a") as stream:
    stream.write(json.dumps([name, *args]) + "\n")
if name == "uname":
    print("Darwin")
elif name == "id":
    print("501")
elif name == "ps":
    if args == ["-Ao", "pid=,ppid=,command="]:
        count_file = root / "tree-count"
        count = int(count_file.read_text()) + 1 if count_file.exists() else 1
        count_file.write_text(str(count))
        if os.environ.get("TREE_ERROR") == "1":
            sys.exit(1)
        tree = (root / "tree").read_text()
        if count > int(os.environ.get("TREE_GONE_AFTER", "999")):
            tree = "\n".join(line for line in tree.splitlines() if line.split()[0] != "120") + "\n"
        print(tree, end="")
    elif args == ["-Ao", "pid=,command="]:
        for line in (root / "tree").read_text().splitlines():
            pid, parent, command = line.split(maxsplit=2)
            print(f"  {pid} {command}")
    elif args == ["-A", "-o", "%cpu="]:
        print(os.environ.get("CPU", "10"))
    elif args == ["-A", "-o", "%cpu,%mem,pid,comm"]:
        print("10 1 120 demo")
    elif args == ["-Ao", "pid=,ppid=,%cpu=,%mem=,command="]:
        print("120 110 10 1 python demo.py")
    else:
        sys.exit(97)
elif name == "curl":
    count_file = root / "curl-count"
    count = int(count_file.read_text()) + 1 if count_file.exists() else 1
    count_file.write_text(str(count))
    mode = os.environ.get("CURL_MODE", "ok")
    if mode == "fail" or (mode == "post-fail" and count > 1):
        print("curl: (22) HTTP 503", file=sys.stderr)
        sys.exit(22)
elif name == "shortcuts":
    if args == ["list"] and os.environ.get("SHORTCUT_MISSING") != "1":
        print("Presentation Mode")
elif name == "launchctl":
    label = args[-1].split("/")[-1].removesuffix(".plist")
    stopped = root / ("stopped-" + label)
    if args[0] == "bootout":
        stopped.touch()
    elif args[0] == "bootstrap":
        stopped.unlink(missing_ok=True)
    elif args[0] == "print":
        if stopped.exists():
            sys.exit(1)
        label = args[1].split("/")[-1]
        print("pid = " + ("100" if label == "homebrew.mxcl.cliproxyapi" else "200"))
elif name == "osascript":
    script = sys.stdin.read()
    if "processIds" in script:
        app = os.environ.get("PRESENT_APP_NAME", "")
        bundle = os.environ.get("PRESENT_APP_BUNDLE", "")
        if app == "Codex" or bundle == "com.openai.codex":
            print("90")
        elif app == "Steam" or bundle == "com.valvesoftware.steam":
            print("300")
    elif "to quit" in script:
        with (root / "actions").open("a") as stream:
            stream.write("quit " + os.environ["PRESENT_APP_NAME"] + "\n")
elif name == "memory_pressure":
    print("System-wide memory free percentage: " + os.environ.get("MEM", "50") + "%")
elif name == "df":
    print("Filesystem 1024-blocks Used Available Capacity Mounted on")
    print("fixture 100000000 10000000 90000000 10% /")
elif name == "tmutil":
    if args == ["status"]:
        print("Running = " + os.environ.get("BACKUP", "0") + ";")
elif name == "system_profiler":
    print("Displays: Fixture")
elif name in {"caffeinate", "sleep"}:
    pass
else:
    sys.exit(97)
'''


class PresentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="present-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.state = self.root / "state" / "present"
        (self.root / "tree").write_text(TREE)
        for name in ("uname", "id", "ps", "curl", "shortcuts", "launchctl", "osascript",
                     "memory_pressure", "df", "tmutil", "system_profiler", "caffeinate", "sleep"):
            path = self.bin / name
            path.write_text(f"#!{sys.executable}\n" + STUB)
            path.chmod(0o755)
        agents = self.home / "Library/LaunchAgents"
        agents.mkdir(parents=True)
        for label in ("homebrew.mxcl.cliproxyapi", "ai.openclaw.gateway", "com.steipete.summarize.daemon"):
            (agents / f"{label}.plist").write_text("fixture")
        self.env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home),
                    "XDG_STATE_HOME": str(self.root / "state"), "FIXTURE": str(self.root),
                    "LC_ALL": "C"}

    def run_present(self, *args, **env):
        # Override Bash's builtin kill too. Even a regression cannot signal a real PID.
        launcher = 'kill() { printf "kill %s\\n" "$*" >> "$FIXTURE/actions"; }; export -f kill; exec /bin/bash "$@"'
        return subprocess.run(["/bin/bash", "-c", launcher, "fixture", str(PRESENT), *args],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=20)

    def showcase(self, *extra, pid="120", **env):
        return self.run_present("showcase", "--pid", pid, "--url", "https://demo.localhost", *extra, **env)

    def calls(self, name=None):
        path = self.root / "calls"
        calls = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [call for call in calls if name is None or call[0] == name]

    def actions(self):
        path = self.root / "actions"
        return path.read_text() if path.exists() else ""

    def assert_no_mutations(self):
        self.assertEqual(self.actions(), "")
        self.assertFalse(self.state.exists())
        for call in self.calls():
            self.assertFalse(call[0] == "caffeinate" or
                             call[:2] in [["launchctl", "bootout"], ["launchctl", "bootstrap"],
                                          ["shortcuts", "run"], ["tmutil", "stopbackup"]], call)

    def test_showcase_preserves_server_children_launchers_app_and_agent(self):
        result = self.showcase()
        self.assertEqual(result.returncode, 0, result.stderr)
        actions = self.actions().splitlines()
        self.assertEqual(actions, ["quit Steam", "kill -TERM 300", "kill -TERM 200"])
        self.assertNotIn("kill -TERM 130", self.actions())
        self.assertIn("keep app: Codex", result.stdout)
        self.assertIn("keep launch agent: homebrew.mxcl.cliproxyapi", result.stdout)
        self.assertNotIn(["launchctl", "bootout", "gui/501/homebrew.mxcl.cliproxyapi"], self.calls())
        self.assertIn(["launchctl", "bootout", "gui/501/ai.openclaw.gateway"], self.calls())
        self.assertEqual(len(self.calls("curl")), 2)
        self.assertEqual(self.calls("curl")[0], ["curl", "--disable", "--fail", "--silent", "--show-error", "--max-time", "5", "--output", "/dev/null", "--url", "https://demo.localhost"])
        self.assertIn("demo_pid=120", (self.state / "state").read_text())
        self.assertIn("demo PID: 120", self.run_present("status").stdout)
        self.assertIn("demo URL: https://demo.localhost", self.run_present("status").stdout)
        result = self.run_present("off")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "state").exists())
        self.assertIn(["launchctl", "bootstrap", "gui/501", str(self.home / "Library/LaunchAgents/ai.openclaw.gateway.plist")], self.calls())

    def test_selecting_launcher_preserves_all_its_children(self):
        result = self.showcase(pid="100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kill -TERM 130", self.actions())
        self.assertNotIn("kill -TERM 121", self.actions())
        self.assertIn("kill -TERM 200", self.actions())

    def test_showcase_dry_run_checks_readiness_without_mutation(self):
        result = self.showcase("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("keep dev process: 100 npm run dev", result.stdout)
        self.assertIn("keep dev process: 121 uvicorn", result.stdout)
        self.assertIn("[dry-run] kill -TERM 200", result.stdout)
        self.assertNotIn("[dry-run] kill -TERM 100", result.stdout)
        self.assertEqual(len(self.calls("curl")), 2)
        self.assert_no_mutations()

    def test_readiness_failure_aborts_before_cleanup(self):
        for extra in ((), ("--dry-run",)):
            with self.subTest(extra=extra):
                result = self.showcase(*extra, CURL_MODE="fail")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("demo URL is not ready", result.stderr)
                self.assertNotIn("present: on", result.stdout)
                self.assert_no_mutations()

    def test_post_cleanup_failure_leaves_state_restorable(self):
        result = self.showcase(CURL_MODE="post-fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Presentation Mode remains active", result.stderr)
        self.assertIn("demo URL is not ready", result.stderr)
        self.assertTrue((self.state / "state").exists())
        self.assertEqual(self.run_present("off").returncode, 0)

    def test_process_inspection_failure_aborts_before_cleanup(self):
        result = self.showcase(TREE_ERROR="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot inspect demo process tree", result.stderr)
        self.assert_no_mutations()

    def test_server_exit_during_cleanup_leaves_state_restorable(self):
        result = self.showcase(TREE_GONE_AFTER="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("demo PID 120 is no longer running", result.stderr)
        self.assertIn("Presentation Mode remains active", result.stderr)
        self.assertTrue((self.state / "state").exists())
        self.assertEqual(self.run_present("off").returncode, 0)
        self.assertFalse((self.state / "state").exists())

    def test_missing_pid_aborts_before_cleanup(self):
        result = self.showcase(pid="999")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("demo PID 999 is no longer running", result.stderr)
        self.assert_no_mutations()

    def test_cli_rejects_missing_or_invalid_selection(self):
        for args in (("showcase",), ("showcase", "--pid"),
                     ("showcase", "--pid", "0", "--url", "http://demo.localhost"),
                     ("showcase", "--pid", "1", "--url", "http://demo.localhost"),
                     ("showcase", "--pid", "-2", "--url", "http://demo.localhost"),
                     ("showcase", "--pid", "120", "--url", "file:///tmp/demo"),
                     ("on", "--pid", "120"), ("showcase", "--wat")):
            with self.subTest(args=args):
                self.assertNotEqual(self.run_present(*args).returncode, 0)
                self.assert_no_mutations()

    def test_existing_on_still_quits_apps_and_dev_servers(self):
        result = self.run_present("on")
        self.assertEqual(result.returncode, 0, result.stderr)
        for action in ("quit Codex", "quit Steam", "kill -TERM 100", "kill -TERM 110", "kill -TERM 121", "kill -TERM 200"):
            self.assertIn(action, self.actions())
        self.assertEqual(self.calls("curl"), [])
        self.assertNotIn("demo_pid=", (self.state / "state").read_text())
        self.assertNotEqual(self.run_present("on").returncode, 0)
        self.assertEqual(self.run_present("off").returncode, 0)

    def test_existing_on_and_off_dry_runs_do_not_mutate(self):
        for mode in ("on", "off"):
            result = self.run_present(mode, "--dry-run")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("[dry-run] shortcuts run", result.stdout)
            self.assert_no_mutations()

    def test_retired_summarize_agent_is_not_stopped(self):
        result = self.run_present("on", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("launchctl bootout gui/501/ai.openclaw.gateway", result.stdout)
        self.assertNotIn("com.steipete.summarize.daemon", result.stdout)
        self.assertFalse(any("summarize" in str(call) for call in self.calls("launchctl")))
        self.assert_no_mutations()

    def test_existing_status_and_doctor_health_thresholds(self):
        self.assertEqual(self.run_present("status").returncode, 0)
        self.assertEqual(self.run_present("doctor").returncode, 0)
        result = self.run_present("doctor", CPU="150", MEM="10", BACKUP="1", SHORTCUT_MISSING="1")
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertIn("top CPU 150%", result.stderr)
        self.assert_no_mutations()


if __name__ == "__main__":
    unittest.main()
