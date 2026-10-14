import tomllib, subprocess, unittest, shutil
from pathlib import Path
c=tomllib.loads((Path(__file__).resolve().parents[1] / 'dotfiles/.config/jjui/config.toml').read_text())
a=next(a['lua'] for a in c['actions'] if a['name']=='resolve')
h='''
local id, calls, refreshed, messages = "highlighted-not-working-copy", {}, 0, {}
context = { change_id = function() return id end }
function jj_interactive(...) table.insert(calls, {...}) end
revisions = { refresh = function() refreshed = refreshed + 1 end }
function flash(m) table.insert(messages, m) end
local action = assert(load(ACTION))
action()
assert(calls[1][1] == "resolve" and calls[1][2] == "--revision" and calls[1][3] == id)
assert(refreshed == 1)
id=nil; action(); assert(#calls == 1 and refreshed == 1 and #messages == 1)
print("Highlighted revision and no-selection checks passed")
'''
@unittest.skipUnless(shutil.which("lua"), "Lua is needed for jjui actions")
class ResolveActionTests(unittest.TestCase):
    def test_highlighted_revision_and_no_selection(self):
        r=subprocess.run(['lua','-'], input='local ACTION=[====['+a+']====]\n'+h,text=True,capture_output=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

if __name__ == "__main__":
    unittest.main()
