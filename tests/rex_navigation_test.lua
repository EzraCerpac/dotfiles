local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local old_home = vim.env.HOME
local test_home = vim.fn.tempname()
vim.fn.mkdir(test_home .. "/.local/state/rex/navigation", "p", 448)
vim.env.HOME = test_home
local actions, bound = {}, {}
local mode, focus, reply, calls = "edge", "a", nil, 0
local function view()
  return { active_window_id = "w", windows = { { window_id = "w", focused_block_id = focus, layers = { { blocks = { { block_id = focus, creator_name = "com.superlogical.terminal" } } } } } } }
end
rex = {
  action = function(a) actions[a.name] = a.run end,
  session = {
    view = function() return view() end,
    focus_direction = function() calls = calls + 1; if mode == "pane" then focus = "b" end; return {} end,
  },
  block = { call = function() return { foreground = { name = "nvim", path = "/nvim", pid = 42, user_id = 501 } } end },
  exec = function(argv)
    if argv[1] == "/usr/bin/open" then reply = argv[3]; return { ok = true } end
    if mode == "error" then return { ok = false, stderr = "rpc failed" } end
    return { ok = true, stdout = mode == "editor" and "moved\n" or "edge\n" }
  end,
}
rex.invoke = function(name, args) return actions[name]({ block_id = "a" }, args) end
dofile(root .. "/dotfiles/.config/rex/navigation.lua")
local f = assert(io.open(os.getenv("HOME") .. "/.local/state/rex/navigation/request", "w")); f:write("123\nright\n"); f:close()
for _, case in ipairs({ {"editor", "handled", 0}, {"pane", "handled", 1}, {"edge", "edge", 1}, {"error", "error", 0} }) do
  mode, focus, reply, calls = case[1], "a", nil, 0
  actions.rex_navigate({ session_id = "s", block_id = "a" }, { direction = "right" })
  assert(reply and reply:match("state=" .. case[2] .. "$"), tostring(reply))
  assert(calls == case[3])
end
os.remove(os.getenv("HOME") .. "/.local/state/rex/navigation/request")
vim.env.HOME = old_home
vim.fn.delete(test_home, "rf")
print("Rex navigation flow tests passed")
