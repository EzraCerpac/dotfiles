"""Exercise the jjui Lua action against its UI/command boundary."""
import shutil
import subprocess
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("lua"), "Lua is needed to exercise jjui actions")
class HunkActionTests(unittest.TestCase):
    def test_contextual_comparisons(self):
        config = tomllib.loads((ROOT / "dotfiles/.config/jjui/config.toml").read_text())
        action = next(a["lua"] for a in config["actions"] if a["name"] == "hunk")
        harness = r'''
local run = assert(load(ACTION))
local ids, target, choice = {}, "abc123", nil
local calls, menus, messages = {}, {}, {}
context = {
  checked_commit_ids = function() return ids end,
  commit_id = function() return target end,
}
function choose(opts) table.insert(menus, opts); return choice end
function flash(msg) table.insert(messages, type(msg) == "table" and msg.text or msg) end
function jj_interactive(...) table.insert(calls, {...}) end
local full_id = string.rep("a", 40)
function jj(...) return full_id, nil end
local function compare_args(base, to)
  local call = calls[#calls]
  assert(call[#call - 3] == "--from" and call[#call - 2] == base)
  assert(call[#call - 1] == "--to" and call[#call] == to)
  assert(table.concat(call, " "):find('ui.pager=["hunk", "pager"]', 1, true))
end

-- No selection: cancellation is inert; missing base is explained.
run(); assert(#menus == 1 and #calls == 0 and _G.hunk_base == nil)
choice = "Compare base → highlighted"
run(); assert(#calls == 0 and messages[#messages]:find("No Hunk base", 1, true))

-- One check still uses the highlighted revision and the menu.
ids = {"checked_other"}; choice = "Set base"
run(); assert(_G.hunk_base == full_id)
choice = nil
run(); assert(menus[#menus].title:find(full_id:sub(1, 12), 1, true))
target = "def456"; choice = "Compare base → highlighted"
run(); compare_args(full_id, target)

-- Two checks bypass the menu, use displayed lower -> upper, retain base.
local menu_count = #menus
ids = {"upper", "lower"}
run(); compare_args("lower", "upper"); assert(#menus == menu_count)
assert(_G.hunk_base == full_id)

-- Three checks reject instead of choosing endpoints silently.
local call_count = #calls
ids = {"upper", "middle", "lower"}
run(); assert(#calls == call_count and #menus == menu_count)
assert(messages[#messages] == "Select exactly two revisions to compare.")

ids = {}; choice = "Clear base"
run(); assert(_G.hunk_base == nil)
choice = "Set base"; target = nil
run(); assert(messages[#messages] == "No revision highlighted")
print("Hunk action scenarios passed")
'''
        # Lua long strings avoid interpolation or shell quoting of the action.
        result = subprocess.run(
            ["lua", "-"], input="local ACTION = [====[" + action + "]====]\n" + harness,
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
