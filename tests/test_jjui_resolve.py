"""Exercise resolve against jjui's asynchronous terminal-command boundary."""
import os
import shlex
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("lua"), "Lua is needed to exercise jjui actions")
class ResolveActionTests(unittest.TestCase):
    def run_action(self, harness):
        config = tomllib.loads((ROOT / "dotfiles/.config/jjui/config.toml").read_text())
        action = next(item["lua"] for item in config["actions"] if item["name"] == "resolve")
        result = subprocess.run(
            ["lua", "-"], input="local ACTION = [====[" + action + "]====]\n" + harness,
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_refresh_waits_for_terminal_completion(self):
        self.run_action(r'''
local id, queued, refreshed, messages = "highlighted-not-working-copy", {}, 0, {}
context = { change_id = function() return id end }
function jj_interactive(...) table.insert(queued, {mode = "interactive", args = {...}}) end
function exec_shell(command) table.insert(queued, {mode = "shell", command = command}) end
revisions = { refresh = function() table.insert(queued, {mode = "refresh"}) end }
function flash(message) table.insert(messages, message) end
local action = assert(load(ACTION))

-- jjui collects command steps during Lua evaluation, before the terminal starts.
-- jj_interactive has no completion continuation. exec_shell instead emits
-- ExecProcessCompletedMsg; the UI then refreshes, including on an error exit.
for _, outcome in ipairs({"success", "failed", "cancelled"}) do
  queued, refreshed = {}, 0
  id = "highlighted-not-working-copy"
  action()
  assert(#queued == 1, "refresh request queued before the terminal command completed")
  assert(refreshed == 0)
  assert(queued[1].command == "jj resolve --revision '" .. id .. "'")

  -- Dispatch the queued command. Selection changes cannot retarget this resolve.
  local terminal = queued[1]
  id = "another-highlighted-change"
  assert(terminal.mode == "shell" and refreshed == 0)
  assert(terminal.command:find("highlighted-not-working-copy", 1, true))

  -- Deliver the native terminal completion separately from action evaluation.
  local completion = {kind = "ExecProcessCompletedMsg", error = outcome ~= "success"}
  if terminal.mode == "shell" and completion.kind == "ExecProcessCompletedMsg" then
    -- UI completion schedules common.Refresh independently of the Lua action.
    table.insert(queued, {mode = "refresh"})
  end
  assert(#queued == 2 and queued[2].mode == "refresh")
  refreshed = refreshed + 1 -- Dispatch the refresh request and update the graph.
  assert(refreshed == 1, "terminal completion did not refresh the graph")
end

id = nil
local count, previous_refreshes = #queued, refreshed
action()
assert(#queued == count and refreshed == previous_refreshes and #messages == 1)
assert(messages[1].text == "No change selected" and messages[1].error)
''')

    def test_selected_change_is_one_shell_argument(self):
        selected = "selected'change $(printf injected)"
        command = self.run_action(r'''
context = { change_id = function() return "selected'change $(printf injected)" end }
function exec_shell(command) print(command) end
assert(load(ACTION))()
''').strip()
        with tempfile.TemporaryDirectory(prefix="jjui-resolve-shell-") as directory:
            fake_jj = Path(directory) / "jj"
            fake_jj.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            fake_jj.chmod(0o755)
            self.assertTrue(command.startswith("jj "))
            probe_command = shlex.quote(str(fake_jj)) + command[len("jj"):]
            environment = {
                "HOME": directory,
                "XDG_CONFIG_HOME": str(Path(directory) / "config"),
                "PATH": directory + os.pathsep + os.defpath,
                "LANG": "C",
            }
            for shell, flags in (
                ("sh", []), ("bash", ["--noprofile", "--norc"]),
                ("zsh", ["-f"]), ("fish", ["--no-config"]),
            ):
                executable = shutil.which(shell)
                if executable is None:
                    continue
                with self.subTest(shell=shell):
                    result = subprocess.run(
                        [executable, *flags, "-c", probe_command], env=environment,
                        text=True, capture_output=True, timeout=30,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(result.stdout.splitlines(), ["resolve", "--revision", selected])

if __name__ == "__main__":
    unittest.main()
