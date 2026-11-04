-- Terminal programs own Ctrl/Alt shortcuts. Keep Rex controls on Cmd.
-- Remove the native tab/word-navigation defaults that don't include Cmd.
for _, key in ipairs({ "ctrl+tab", "ctrl+shift+tab", "ctrl+shift+pageup", "ctrl+shift+pagedown", "alt+left", "alt+right" }) do
  rex.unbind(key)
end
local config_file = os.getenv("REX_CONFIG") or ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/init.lua")
local config_dir = assert(config_file:match("^(.*)/[^/]+$"))
dofile(config_dir .. "/navigation.lua")
dofile(config_dir .. "/projects.lua")
local hosts = io.open(config_dir .. "/hosts.lua", "r")
if hosts then hosts:close(); dofile(config_dir .. "/hosts.lua") end
for key, direction in pairs({ f13 = "left", f14 = "down", f15 = "up", f16 = "right" }) do
  rex.bind("cmd+" .. key, "rex_navigate", { direction = direction })
end
