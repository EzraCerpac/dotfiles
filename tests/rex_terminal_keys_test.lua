local root = os.getenv("NVIM_TYPST_TEST_ROOT") or (arg and arg[1]) or "."
local config = root .. "/dotfiles/.config/rex/init.lua"
local bindings, removed = {}, {}
rex = {
  action = function() end,
  mode = function() error("Terminal shortcuts must not enter Rex modes") end,
  bind = function(key, action, args) bindings[key] = { action = action, args = args } end,
  unbind = function(key) removed[key] = true end,
}
local getenv = os.getenv
os.getenv = function(key) return key == "REX_CONFIG" and config or getenv(key) end
dofile(config)
os.getenv = getenv
for key in pairs(bindings) do
  assert(key:find("cmd+", 1, true), "Terminal shortcut intercepted: " .. key)
  assert(not key:find("/", 1, true), "Unexpected modal binding")
end
for _, key in ipairs({ "ctrl+tab", "ctrl+shift+tab", "ctrl+shift+pageup", "ctrl+shift+pagedown", "alt+left", "alt+right" }) do
  assert(removed[key], "Native terminal shortcut still reserved: " .. key)
end
assert(bindings["shift+cmd+o"].action == "open_recent_project")
assert(bindings["cmd+f13"].action == "rex_navigate")
print("Rex terminal key passthrough tests passed")
