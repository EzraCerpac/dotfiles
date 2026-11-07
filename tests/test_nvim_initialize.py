"""Exercise missing-only initialization without network or user data."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NeovimInitializeTests(unittest.TestCase):
    def run_fixture(self, case):
        nvim = shutil.which("nvim")
        if not nvim:
            self.skipTest("Neovim is required")
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            lua = base / "lua"
            (lua / "lazy/core").mkdir(parents=True)
            existing = base / "existing"
            (existing / ".git").mkdir(parents=True)
            (existing / "dirty-marker").write_text("preserved")
            (lua / "lazy/core/config.lua").write_text('''
local base = vim.env.FIXTURE_BASE
local existing = {name="existing", dir=base.."/existing", url="fixture", pin=true, _={installed=true,tasks={}}}
local missing = {name="missing", dir=base.."/missing", url="fixture", _={installed=false,tasks={}}}
if vim.env.FIXTURE_CASE == "partial" then
  existing.dir=base.."/partial"; vim.fn.mkdir(existing.dir, "p")
end
local items={existing=existing, optional={name="optional",dir=base.."/optional",url="fixture",_={installed=false,cond=false,tasks={}}}}
if vim.env.FIXTURE_CASE ~= "repeat" then items.missing=missing end
return {plugins=items, spec={report=function() return 0 end}}
''')
            (lua / "lazy/core/plugin.lua").write_text('''
return {load=function()
  local c=require("lazy.core.config")
  if vim.env.FIXTURE_CASE == "nested" and not c.plugins.nested then
    c.plugins.nested={name="nested",dir=vim.env.FIXTURE_BASE.."/nested",url="fixture",_={installed=false,tasks={}}}
  end
end}
''')
            (lua / "lazy.lua").write_text('''
return {install=function(opts)
  assert(opts.wait and opts.lockfile and opts.show == false and opts.clear == false)
  local f=assert(io.open(vim.env.FIXTURE_BASE.."/calls", "a"))
  for _, p in ipairs(opts.plugins) do
    assert(p.name ~= "existing")
    f:write(p.name.."\\n")
    if vim.env.FIXTURE_CASE == "failure" then
      p._.tasks={{has_errors=function() return true end,output=function() return "fixture clone failure" end}}
    elseif vim.env.FIXTURE_CASE ~= "incomplete" then
      vim.fn.mkdir(p.dir.."/.git", "p"); p._.installed=true
    end
  end
  f:close()
end}
''')
            env = dict(os.environ, FIXTURE_BASE=str(base), FIXTURE_CASE=case,
                       FIXTURE_LUA=str(lua), FIXTURE_SCRIPT=str(ROOT / "setup-scripts/setup/nvim-initialize.lua"))
            result = subprocess.run([nvim, "--headless", "-u", "NONE", "--cmd",
                "lua package.path=vim.env.FIXTURE_LUA..'/?.lua;'..vim.env.FIXTURE_LUA..'/?/init.lua;'..package.path",
                "-c", "lua dofile(vim.env.FIXTURE_SCRIPT)", "-c", "qa"],
                env=env, capture_output=True, text=True, timeout=20, check=False)
            calls = (base / "calls").read_text().splitlines() if (base / "calls").exists() else []
            self.assertEqual((existing / "dirty-marker").read_text(), "preserved")
            return result, calls

    def test_jj_waltz_uses_local_checkout_or_remote_fallback(self):
        nvim = shutil.which("nvim")
        if not nvim:
            self.skipTest("Neovim is required")
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            directory = home / "Projects/jj-waltz.nvim"
            env = dict(os.environ, HOME=str(home), JW_SPEC=str(ROOT / "dotfiles/.config/nvim/lua/plugins/jujitsu.lua"))
            for local in (False, True):
                with self.subTest(local=local):
                    if local:
                        directory.mkdir(parents=True)
                        (directory / "dirty-marker").write_text("preserved")
                    env["EXPECT_LOCAL"] = "1" if local else "0"
                    command = ("lua local specs=dofile(vim.env.JW_SPEC); local p; "
                               "for _,s in ipairs(specs) do if s.name == 'jj-waltz.nvim' then p=s end end; "
                               "assert(p[1] == 'EzraCerpac/jj-waltz.nvim'); "
                               "assert((p.dir ~= nil) == (vim.env.EXPECT_LOCAL == '1')); "
                               "if p.dir then assert(p.dir == vim.env.HOME .. '/Projects/jj-waltz.nvim') end")
                    result = subprocess.run([nvim, "--headless", "-u", "NONE", "-c", command, "-c", "qa"],
                                            env=env, text=True, capture_output=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if local:
                        self.assertEqual((directory / "dirty-marker").read_text(), "preserved")

    def test_seed_matches_shared_extras_and_preserves_existing_preferences(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            env = dict(os.environ, HOME=str(home), SETUP_PROFILE="nas", SETUP_CONFIG_ROOT=str(ROOT))
            env.pop("SETUP_RESTORE_MACHINE_ID", None)
            cmd = ["bash", str(ROOT / "setup-scripts/local/seed-configs.sh")]
            first = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=20)
            self.assertEqual(first.returncode, 0, first.stderr)
            prefs = home / ".config/nvim/lazyvim.json"
            data = json.loads(prefs.read_text())
            self.assertIn("lazyvim.plugins.extras.util.gitui", data["extras"])
            self.assertNotIn("lazyvim.plugins.extras.ai.sidekick", data["extras"])
            self.assertNotIn("lazyvim.plugins.extras.ai.copilot-native", data["extras"])
            prefs.write_text('{"private":"unchanged"}\n')
            second = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=20)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(prefs.read_text(), '{"private":"unchanged"}\n')

    def test_mason_readiness_uses_resolved_packages_and_checks_results(self):
        nvim = shutil.which("nvim")
        if not nvim:
            self.skipTest("Neovim is required")
        for case in ("success", "missing", "failure", "unknown"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                lua = base / "lua"
                (lua / "lazy/core").mkdir(parents=True)
                (lua / "mason-lspconfig").mkdir(parents=True)
                (lua / "lazy/core/config.lua").write_text(
                    'return {plugins={ ["mason.nvim"]={_={installed=true}}, ["nvim-lspconfig"]={_={installed=true}}, ["mason-lspconfig.nvim"]={_={installed=true}} }}'
                )
                (lua / "lazy/core/plugin.lua").write_text(
                    'return {values=function() return {ensure_installed={"stylua"}} end}'
                )
                (lua / "lazy.lua").write_text('''return {plugins=function() return {} end,load=function(opts)
  for _, name in ipairs(opts.plugins) do require("lazy.core.config").plugins[name]._.loaded=true end
end}
''')
                (lua / "mason-lspconfig/settings.lua").write_text('''return {current={ensure_installed={vim.env.FIXTURE_CASE == "unknown" and "unknown" or "lua_ls"}}}''')
                (lua / "mason-lspconfig/mappings.lua").write_text('''return {get_mason_map=function() return {lspconfig_to_package={lua_ls="lua-language-server"}} end}''')
                (lua / "mason-registry.lua").write_text('''
local installed={}
local M={}
function M.refresh() return true end
function M.get_package(name)
  return {name=name, is_installing=function() return false end, is_installed=function() return installed[name] == true end,
    install=function(_, _, callback)
      local f=assert(io.open(vim.env.FIXTURE_BASE.."/mason-calls", "a"))
      f:write(name.."\\n"); f:close()
      if vim.env.FIXTURE_CASE == "success" then installed[name]=true end
      vim.schedule(function() callback(vim.env.FIXTURE_CASE ~= "failure", "fixture error") end)
      return {on=function(_, kind, output)
        if kind == "stderr" then output("x bin/\\n") end
      end}
    end}
end
return M
''')
                env = dict(os.environ, FIXTURE_BASE=str(base), FIXTURE_CASE=case, FIXTURE_LUA=str(lua),
                           FIXTURE_SCRIPT=str(ROOT / "setup-scripts/setup/nvim-ready.lua"))
                result = subprocess.run([nvim, "--headless", "-u", "NONE", "--cmd",
                    "lua package.path=vim.env.FIXTURE_LUA..'/?.lua;'..vim.env.FIXTURE_LUA..'/?/init.lua;'..package.path",
                    "-c", "lua dofile(vim.env.FIXTURE_SCRIPT)", "-c", "qa"], env=env,
                    text=True, capture_output=True, timeout=20)
                if case == "success":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(set((base / "mason-calls").read_text().splitlines()), {"stylua", "lua-language-server"})
                else:
                    self.assertEqual(result.returncode, 1)
                    self.assertIn({"missing": "still missing", "failure": "fixture error", "unknown": "no package"}[case], result.stderr)

    def test_shell_clone_is_idempotent_and_rejects_partial_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            binary = base / "bin"
            binary.mkdir()
            git = binary / "git"
            git.write_text("#!/bin/sh\nprintf 'clone\\n' >> \"$CLONE_LOG\"\n[ \"${FAIL_CLONE:-0}\" != 1 ] || exit 7\nfor last do :; done\nmkdir -p \"$last/lua/lazy\"\ntouch \"$last/lua/lazy/init.lua\"\n")
            git.chmod(0o755)
            nvim = binary / "nvim"
            nvim.write_text("#!/bin/sh\nprintf 'run\\n' >> \"$NVIM_LOG\"\n")
            nvim.chmod(0o755)
            env = dict(os.environ, HOME=str(base), XDG_DATA_HOME=str(base / "data"),
                       PATH=str(binary) + os.pathsep + os.environ["PATH"],
                       CLONE_LOG=str(base / "clone.log"), NVIM_LOG=str(base / "nvim.log"))
            env.pop("NVIM_APPNAME", None)
            cmd = ["bash", str(ROOT / "setup-scripts/setup/nvim-initialize")]
            for _ in range(2):
                result = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((base / "clone.log").read_text().splitlines(), ["clone"])
            self.assertEqual((base / "nvim.log").read_text().splitlines(), ["run", "run", "run", "run"])
            (base / "data/nvim/lazy/lazy.nvim/lua/lazy/init.lua").unlink()
            result = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("incomplete lazy.nvim checkout", result.stderr)
            self.assertEqual((base / "clone.log").read_text().splitlines(), ["clone"])

    def test_failed_clone_stops_before_neovim(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            binary = base / "bin"
            binary.mkdir()
            git = binary / "git"
            git.write_text("#!/bin/sh\nexit 7\n")
            git.chmod(0o755)
            nvim = binary / "nvim"
            nvim.write_text("#!/bin/sh\ntouch \"$NVIM_LOG\"\n")
            nvim.chmod(0o755)
            env = dict(os.environ, HOME=str(base), XDG_DATA_HOME=str(base / "data"),
                       PATH=str(binary) + os.pathsep + os.environ["PATH"], NVIM_LOG=str(base / "nvim.log"))
            env.pop("NVIM_APPNAME", None)
            result = subprocess.run(["bash", str(ROOT / "setup-scripts/setup/nvim-initialize")],
                                    env=env, text=True, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((base / "nvim.log").exists())
            self.assertFalse((base / "data/nvim/lazy/lazy.nvim").exists())

    def test_installs_only_missing_and_newly_imported_plugins(self):
        result, calls = self.run_fixture("nested")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["missing", "nested"])

    def test_repeat_does_not_install_existing_plugins(self):
        result, calls = self.run_fixture("repeat")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [])

    def test_partial_or_failed_install_is_reported(self):
        for case, message in (("failure", "fixture clone failure"), ("incomplete", "checkout still missing"), ("partial", "incomplete plugin checkout")):
            with self.subTest(case=case):
                result, _ = self.run_fixture(case)
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
