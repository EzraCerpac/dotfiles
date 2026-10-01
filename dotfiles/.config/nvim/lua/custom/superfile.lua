local M = {}
local active
local last_directory
local uv = vim.uv or vim.loop

local function notify(message)
  vim.notify("Superfile: " .. message, vim.log.levels.WARN)
end

local function directory(path)
  if path and path ~= "" then
    path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    local stat = uv.fs_stat(path)
    if stat then
      if stat.type == "directory" then
        return path
      elseif stat.type == "file" then
        return vim.fn.fnamemodify(path, ":h")
      end
    end
  end
  return vim.fn.getcwd()
end

local function current_directory()
  local buffer = vim.api.nvim_get_current_buf()
  if vim.bo[buffer].buftype == "" then
    local name = vim.api.nvim_buf_get_name(buffer)
    local stat = name ~= "" and uv.fs_stat(name)
    if stat and stat.type == "file" then
      return directory(name)
    end
  end
  return vim.fn.getcwd()
end

local function float_config()
  local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.9)))
  local height = math.max(1, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.85)))
  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    style = "minimal",
    border = "rounded",
  }
end

local function show(session)
  if session.window and vim.api.nvim_win_is_valid(session.window) then
    vim.api.nvim_set_current_win(session.window)
  else
    session.window = vim.api.nvim_open_win(session.buffer, true, float_config())
  end
  vim.cmd.startinsert()
end

local function cleanup(session)
  session.closed = true
  if active == session then
    active = nil
  end
  vim.fn.delete(session.chooser_file)
  if session.window and vim.api.nvim_win_is_valid(session.window) then
    vim.api.nvim_win_close(session.window, true)
  end
  if vim.api.nvim_buf_is_valid(session.buffer) then
    vim.api.nvim_buf_delete(session.buffer, { force = true })
  end
end

local launch
local function finish(session, code)
  if session.closed then
    return
  end
  local path = ""
  if code == 0 and vim.fn.filereadable(session.chooser_file) == 1 then
    path = table.concat(vim.fn.readfile(session.chooser_file, "b"), "\n")
  end
  cleanup(session)
  if code ~= 0 then
    notify("chooser exited with status " .. code)
    return
  end
  if not vim.api.nvim_win_is_valid(session.origin) then
    return
  end
  if path == "" then
    return
  end
  if not vim.startswith(path, "/") then
    path = session.directory .. "/" .. path
  end
  local stat = uv.fs_stat(path)
  if stat and stat.type == "directory" then
    launch(path, session.origin)
  elseif stat and stat.type == "file" then
    vim.api.nvim_set_current_win(session.origin)
    local ok, err = pcall(vim.api.nvim_win_call, session.origin, function()
      vim.cmd.edit({ args = { path }, magic = { file = false, bar = false } })
    end)
    if not ok then
      notify(tostring(err))
    end
  end
end

launch = function(path, origin)
  if vim.fn.executable("spf") ~= 1 then
    notify("spf is unavailable; install or enable Superfile first")
    return
  end
  local session = {
    directory = directory(path),
    origin = origin,
    chooser_file = vim.fn.tempname(),
    buffer = vim.api.nvim_create_buf(false, true),
  }
  active = session
  last_directory = session.directory
  vim.bo[session.buffer].bufhidden = "hide"
  show(session)
  session.job = vim.fn.jobstart({ "spf", "--chooser-file", session.chooser_file, session.directory }, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        finish(session, code)
      end)
    end,
  })
  if session.job <= 0 then
    cleanup(session)
    notify("could not start spf")
    return
  end
  vim.keymap.set("t", "<leader>cy", M.toggle, {
    buffer = session.buffer,
    desc = "Hide Superfile",
    noremap = true,
    silent = true,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = session.buffer,
    once = true,
    callback = function()
      if not session.closed then
        session.closed = true
        if active == session then
          active = nil
        end
        vim.fn.delete(session.chooser_file)
        vim.fn.jobstop(session.job)
      end
    end,
  })
end

function M.open(path)
  if active then
    show(active)
    return
  end
  launch(path and directory(path) or current_directory(), vim.api.nvim_get_current_win())
end

function M.open_cwd()
  M.open(vim.fn.getcwd())
end

function M.toggle()
  if not active then
    launch(directory(last_directory), vim.api.nvim_get_current_win())
  elseif active.window and vim.api.nvim_win_is_valid(active.window) then
    vim.api.nvim_win_close(active.window, true)
    active.window = nil
  else
    show(active)
  end
end

local group = vim.api.nvim_create_augroup("SuperfileChooser", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    if active and active.window and vim.api.nvim_win_is_valid(active.window) then
      vim.api.nvim_win_set_config(active.window, float_config())
    end
  end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    if active then
      local session = active
      vim.fn.jobstop(session.job)
      cleanup(session)
    end
  end,
})

return M
