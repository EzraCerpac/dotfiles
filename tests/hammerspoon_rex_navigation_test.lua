local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local old_home = vim.env.HOME
local test_home = vim.fn.tempname()
vim.fn.mkdir(test_home .. "/.local/state/rex/navigation", "p", 448)
vim.env.HOME = test_home
local callbacks, bindings, tasks, key, winid = {}, {}, {}, nil, 1
local app = { bundleID = function() return "com.superlogical.rex" end }
local window = { application = function() return app end, id = function() return winid end }
hs = {
  fs = { attributes = function() return "directory" end, mkdir = function() return true end },
  execute = function() return "", true end,
  window = { focusedWindow = function() return window end },
  task = { new = function(_, _, args) return { start = function() tasks[#tasks + 1] = args[1] end } end },
  timer = { absoluteTime = function() return 123 end, doAfter = function() end },
  eventtap = { keyStroke = function(modifiers, k) assert(#modifiers == 1 and modifiers[1] == "cmd"); key = k end },
  urlevent = { bind = function(_, fn) callbacks.reply = fn end },
  hotkey = { bind = function(_, k, fn) bindings[k] = fn end },
}
dofile(root .. "/dotfiles/.hammerspoon/rex_navigation.lua").start()
bindings.h(); assert(key == "f13")
local path = os.getenv("HOME") .. "/.local/state/rex/navigation/request"
local f = assert(io.open(path)); local id = f:read("*l"); f:close()
callbacks.reply(nil, { request = "wrong", state = "edge" }); assert(#tasks == 0)
winid = 2; callbacks.reply(nil, { request = id, state = "edge" }); assert(#tasks == 0)
winid = 1; bindings.l(); f = assert(io.open(path)); id = f:read("*l"); f:close()
callbacks.reply(nil, { request = id, state = "edge" }); assert(tasks[1] == "right")
os.remove(path)
vim.env.HOME = old_home
vim.fn.delete(test_home, "rf")
print("Hammerspoon focus guard tests passed")
