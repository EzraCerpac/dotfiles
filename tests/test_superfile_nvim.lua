-- Run: nvim --headless -u NONE -l tests/test_superfile_nvim.lua
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/dotfiles/.config/nvim")
vim.o.hidden = true
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/bin", "p")
temp = assert((vim.uv or vim.loop).fs_realpath(temp))
local old_path = vim.env.PATH
local old_notify = vim.notify
local notifications = {}
vim.notify = function(message)
  table.insert(notifications, message)
end
vim.env.PATH = temp .. "/bin:" .. old_path
vim.env.SPF_LOG = temp .. "/calls"
vim.env.SPF_RELEASE = temp .. "/release"
vim.env.SPF_MARKER = temp .. "/directory-picked"

vim.fn.writefile({
  "#!/bin/sh",
  '[ "$1" = "--chooser-file" ] || exit 91',
  '[ "$#" = 3 ] || exit 92',
  'printf "%s\\t%s\\n" "$2" "$3" >> "$SPF_LOG"',
  'case "$SPF_MODE" in',
  '  file) printf "%s" "$SPF_SELECTED" > "$2" ;;',
  '  directory) if [ ! -e "$SPF_MARKER" ]; then : > "$SPF_MARKER"; printf "%s" "$SPF_DIRECTORY" > "$2"; else printf "%s" "$SPF_SELECTED" > "$2"; fi ;;',
  '  hold) while [ ! -e "$SPF_RELEASE" ]; do sleep 0.02; done ;;',
  '  delayed-file) while [ ! -e "$SPF_RELEASE" ]; do sleep 0.02; done; printf "%s" "$SPF_SELECTED" > "$2" ;;',
  '  failure) printf "%s" "$SPF_SELECTED" > "$2"; exit 7 ;;',
  "esac",
}, temp .. "/bin/spf")
assert((vim.uv or vim.loop).fs_chmod(temp .. "/bin/spf", 493))
local origin_file = temp .. "/origin.txt"
-- Include shell/Ex metacharacters and a newline: the chooser returns one raw path.
local selected = temp .. "/picked space's | file\nnext.txt"
vim.fn.writefile({ "origin" }, origin_file)
vim.fn.writefile({ "selected" }, selected)
local child = temp .. "/child space's"
vim.fn.mkdir(child)
vim.env.SPF_SELECTED = selected
vim.env.SPF_DIRECTORY = child
vim.cmd.edit({ args = { origin_file } })
local origin = vim.api.nvim_get_current_win()
local chooser = require("custom.superfile")

local function calls()
  if vim.fn.filereadable(vim.env.SPF_LOG) == 0 then
    return {}
  end
  local result = {}
  for _, line in ipairs(vim.fn.readfile(vim.env.SPF_LOG)) do
    local file, dir = line:match("^(.-)\t(.*)$")
    result[#result + 1] = { file = file, dir = dir }
  end
  return result
end

local function terminal_count()
  local count = 0
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buffer].buftype == "terminal" then
      count = count + 1
    end
  end
  return count
end

local function settled(count)
  assert(vim.wait(3000, function()
    return #calls() == count and terminal_count() == 0
  end, 10), "chooser did not exit and clean its terminal")
  for _, call in ipairs(calls()) do
    assert(vim.fn.filereadable(call.file) == 0, "chooser tempfile leaked")
  end
  assert(vim.api.nvim_get_current_win() == origin, "original window was not restored")
end

local function reset_origin()
  vim.api.nvim_set_current_win(origin)
  vim.cmd.edit({ args = { origin_file } })
end

local function origin_unchanged()
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)) == origin_file)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(origin), 0, -1, false), { "origin" }))
end

local ok, err = xpcall(function()
  vim.env.SPF_MODE = "file"
  chooser.open()
  settled(1)
  assert(calls()[1].dir == temp, "current file directory not used: " .. calls()[1].dir .. " != " .. temp)
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)) == selected, "raw selected path was changed")

  reset_origin()
  vim.env.SPF_MODE = "directory"
  chooser.open_cwd()
  settled(3)
  assert(calls()[2].dir == root, "open_cwd did not use cwd")
  assert(calls()[3].dir == child, "selected directory did not relaunch chooser")
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)) == selected)

  reset_origin()
  vim.env.SPF_MODE = "cancel"
  chooser.toggle()
  settled(4)
  assert(calls()[4].dir == child, "toggle did not reuse last launch directory")
  origin_unchanged()

  vim.env.SPF_MODE = "hold"
  chooser.open(temp)
  assert(vim.wait(3000, function() return #calls() == 5 end, 10))
  local terminal = vim.api.nvim_get_current_buf()
  local job = vim.bo[terminal].channel
  chooser.toggle()
  assert(vim.api.nvim_get_current_win() == origin)
  assert(vim.fn.jobwait({ job }, 0)[1] == -1, "hide killed the process")
  chooser.toggle()
  assert(vim.api.nvim_get_current_buf() == terminal, "toggle started another terminal")
  chooser.open(child)
  assert(vim.api.nvim_get_current_buf() == terminal, "repeat open started another terminal")
  assert(#calls() == 5)
  vim.o.columns = 100
  vim.o.lines = 40
  vim.api.nvim_exec_autocmds("VimResized", {})
  local config = vim.api.nvim_win_get_config(0)
  assert(config.width == 90 and config.height == 34, "float was not resized")
  vim.fn.writefile({}, vim.env.SPF_RELEASE)
  settled(5)
  origin_unchanged()

  vim.env.SPF_MODE = "failure"
  chooser.open()
  settled(6)
  origin_unchanged()
  assert(notifications[#notifications]:find("status 7", 1, true))

  vim.env.PATH = temp .. "/empty-path"
  chooser.open()
  origin_unchanged()
  assert(#calls() == 6 and terminal_count() == 0)
  assert(notifications[#notifications]:find("unavailable", 1, true))
  vim.env.PATH = temp .. "/bin:" .. old_path

  vim.env.SPF_MODE = "cancel"
  vim.cmd.enew()
  chooser.open()
  settled(7)
  assert(calls()[7].dir == root, "unnamed buffer should use cwd")
  vim.api.nvim_buf_set_name(0, temp .. "/does-not-exist")
  chooser.open()
  settled(8)
  assert(calls()[8].dir == root, "nonexistent buffer should use cwd")
  vim.api.nvim_buf_set_name(0, child)
  chooser.open()
  settled(9)
  assert(calls()[9].dir == root, "directory buffer should use cwd")
  vim.bo.buftype = "nofile"
  chooser.open()
  settled(10)
  assert(calls()[10].dir == root, "special buffer should use cwd")

  vim.fn.delete(vim.env.SPF_RELEASE)
  vim.env.SPF_MODE = "hold"
  chooser.open(temp)
  assert(vim.wait(3000, function() return #calls() == 11 end, 10))
  local leave_job = vim.bo.channel
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  assert(terminal_count() == 0, "VimLeavePre did not clean terminal")
  assert(vim.fn.filereadable(calls()[11].file) == 0, "VimLeavePre left chooser tempfile")
  assert(vim.fn.jobwait({ leave_job }, 1000)[1] ~= -1, "VimLeavePre left process running")

  reset_origin()
  vim.env.SPF_MODE = "delayed-file"
  chooser.open_cwd()
  assert(vim.wait(3000, function() return #calls() == 12 end, 10))
  chooser.toggle()
  vim.cmd.vsplit()
  local other_window = vim.api.nvim_get_current_win()
  vim.fn.writefile({}, vim.env.SPF_RELEASE)
  settled(12)
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)) == selected, "hidden chooser did not edit original window")
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(other_window)) == origin_file, "hidden chooser edited another window")
  vim.api.nvim_win_close(other_window, true)
  local seen = {}
  for _, call in ipairs(calls()) do
    assert(not seen[call.file], "chooser tempfile reused across launches")
    seen[call.file] = true
  end
end, debug.traceback)

vim.api.nvim_exec_autocmds("VimLeavePre", {})
vim.env.PATH = old_path
vim.notify = old_notify
vim.fn.delete(temp, "rf")
assert(ok, err)
print("Superfile chooser: selection, directory navigation, cancellation, toggle, failures, and cleanup passed")
