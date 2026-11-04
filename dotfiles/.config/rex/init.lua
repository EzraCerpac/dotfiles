rex.action{
  name = "then_normal",
  title = "Run an action and return to normal mode",
  args = { action = "string", args = "object?" },
  run = function(ctx, args)
    rex.client.queue(args.action, args.args or {})
    rex.client.queue("client.mode.exit_all")
  end,
}
local modes = { "locked", "pane", "tab", "resize", "move", "scroll", "search", "session", "tmux" }
for _, mode in ipairs(modes) do rex.mode(mode, { exclusive = true }) end
local function bind(key, action, args) rex.bind(key, action, args) end
local function done(key, action, args) bind(key, "then_normal", { action = action, args = args }) end
local function direction(mode, keys, action, leave)
  for key, dir in pairs(keys) do
    if leave then done(mode .. "/" .. key, action, { direction = dir })
    else bind(mode .. "/" .. key, action, { direction = dir }) end
  end
end
local arrows = { left = "left", down = "down", up = "up", right = "right", h = "left", j = "down", k = "up", l = "right" }
direction("pane", arrows, "pane.focus")
direction("resize", arrows, "pane.resize")
direction("move", arrows, "pane.move")
direction("tmux", arrows, "pane.focus", true)
for _, mode in ipairs({ "", "locked", "pane", "tab", "resize", "move", "scroll", "search", "session", "tmux" }) do
  local prefix = mode == "" and "" or mode .. "/"
  bind(prefix .. "alt+i", "client.tab.move", { direction = "backward" })
  bind(prefix .. "alt+n", "pane.split.auto")
  bind(prefix .. "alt+o", "client.tab.move", { direction = "forward" })
  bind(prefix .. "ctrl+s", "pane.send_key", { key = "ctrl+s" })
  local focus = { ["alt+left"] = "left", ["alt+down"] = "down", ["alt+up"] = "up", ["alt+right"] = "right", ["alt+h"] = "left", ["alt+j"] = "down", ["alt+k"] = "up", ["alt+l"] = "right" }
  for key, dir in pairs(focus) do
    if mode == "scroll" and (key == "alt+left" or key == "alt+down" or key == "alt+up" or key == "alt+right") then
      done(prefix .. key, "pane.focus", { direction = dir })
    elseif mode ~= "scroll" then bind(prefix .. key, "pane.focus", { direction = dir }) end
  end
  if mode ~= "locked" then
    bind(prefix .. "ctrl+g", "client.mode.enter", { name = "locked" })
    for key, target in pairs({ ["ctrl+m"] = "move", ["ctrl+o"] = "session", ["ctrl+t"] = "tab", ["ctrl+p"] = "pane", ["ctrl+n"] = "resize" }) do
      if mode ~= target then bind(prefix .. key, "client.mode.enter", { name = target }) end
    end
    if mode ~= "" and mode ~= "scroll" and mode ~= "search" and mode ~= "tmux" then bind(prefix .. "ctrl+b", "client.mode.enter", { name = "tmux" }) end
  end
end
for _, mode in ipairs({ "locked", "pane", "tab", "resize", "move", "session" }) do
  local keys = { locked = "ctrl+g", pane = "ctrl+p", tab = "ctrl+t", resize = "ctrl+n", move = "ctrl+m", session = "ctrl+o" }
  bind(mode .. "/" .. keys[mode], "client.mode.exit_all")
end
for _, mode in ipairs({ "pane", "tab", "resize", "move", "scroll", "search", "session", "tmux" }) do
  bind(mode .. "/enter", "client.mode.exit_all")
  bind(mode .. "/esc", "client.mode.exit_all")
end
bind("pane/p", "pane.focus_next")
done("pane/d", "pane.split", { direction = "down" })
done("pane/f", "pane.zoom")
done("pane/n", "pane.split", { direction = "auto" })
done("pane/r", "pane.split", { direction = "right" })
done("pane/x", "pane.close")
for _, key in ipairs({ "left", "up", "h", "k" }) do bind("tab/" .. key, "client.tab.previous") end
for _, key in ipairs({ "right", "down", "j", "l" }) do bind("tab/" .. key, "client.tab.next") end
for i = 1, 9 do done("tab/" .. i, "client.tab.goto", { index = i }) end
done("tab/b", "pane.move_to_new_tab")
done("tab/n", "client.tab.new")
done("tab/x", "client.tab.close")
for key, dir in pairs({ ["ctrl+h"] = "left", ["ctrl+j"] = "down", ["ctrl+k"] = "up", ["ctrl+l"] = "right" }) do done("scroll/" .. key, "pane.focus", { direction = dir }) end
done("tmux/shift+'", "pane.split", { direction = "down" })
done("tmux/shift+5", "pane.split", { direction = "right" })
bind("tmux/[", "client.mode.enter", { name = "scroll" })
done("tmux/ctrl+b", "pane.send_key", { key = "ctrl+b" })
done("tmux/c", "client.tab.new")
bind("tmux/o", "pane.focus_next")
done("tmux/n", "client.tab.next")
done("tmux/p", "client.tab.previous")
done("tmux/x", "pane.close")
done("tmux/z", "pane.zoom")
rex.bind("ctrl+b>left", "session.previous")
rex.bind("ctrl+b>right", "session.next")
rex.bind("ctrl+b>d", "session.close")
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })
rex.bind("ctrl+b>[", "client.mode.enter", { name = "scroll" })
for _, key in ipairs({ "up", "down", "left", "right", "v" }) do bind("ctrl+" .. key, "pane.send_key", { key = "ctrl+" .. key }) end
bind("ctrl+shift+v", "pane.send_key", { key = "ctrl+v" })

local config_file = os.getenv("REX_CONFIG") or ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/init.lua")
local config_dir = assert(config_file:match("^(.*)/[^/]+$"))
dofile(config_dir .. "/navigation.lua")
dofile(config_dir .. "/projects.lua")
local hosts = io.open(config_dir .. "/hosts.lua", "r")
if hosts then hosts:close(); dofile(config_dir .. "/hosts.lua") end
for _, mode in ipairs({ "", "locked", "pane", "tab", "resize", "move", "scroll", "search", "session", "tmux" }) do
  local prefix = mode == "" and "" or mode .. "/"
  for key, direction in pairs({ f13 = "left", f14 = "down", f15 = "up", f16 = "right" }) do
    bind(prefix .. "ctrl+shift+" .. key, "rex_navigate", { direction = direction })
  end
end
