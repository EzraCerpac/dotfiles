local root = os.getenv("NVIM_TYPST_TEST_ROOT") or (arg and arg[1]) or "."
local config = root .. "/dotfiles/.config/rex/init.lua"
local bindings = {}
rex = {
  action = function() end,
  mode = function() end,
  bind = function(key, action, args) bindings[key] = { action = action, args = args } end,
}
local getenv = os.getenv
os.getenv = function(key) return key == "REX_CONFIG" and config or getenv(key) end
dofile(config)
os.getenv = getenv
for _, mode in ipairs({ "", "locked", "pane", "tab", "resize", "move", "scroll", "search", "session", "tmux" }) do
  local key = (mode == "" and "" or mode .. "/") .. "ctrl+s"
  assert(bindings[key].action == "pane.send_key", key .. " intercepted")
  assert(bindings[key].args.key == "ctrl+s")
end
assert(bindings["ctrl+b>["].action == "client.mode.enter")
assert(bindings["ctrl+b>["].args.name == "scroll")
assert(bindings["scroll/esc"].action == "client.mode.exit_all")
print("Rex terminal key passthrough tests passed")
