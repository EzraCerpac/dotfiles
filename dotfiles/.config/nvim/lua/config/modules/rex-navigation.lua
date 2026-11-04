-- An editor-only endpoint for Rex. It never calls the terminal or window manager.
local M = {}
local directions = { left = "h", down = "j", up = "k", right = "l" }

function M.move(direction)
  local key = directions[direction]
  if not key then
    error("invalid direction: " .. tostring(direction))
  end
  local before = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. key)
  return vim.api.nvim_get_current_win() ~= before and "moved" or "edge"
end

function M.start()
  if M.started then return end
  M.started = true
  local uv = vim.uv or vim.loop
  local directory = vim.fn.expand("~/.local/state/rex/nvim")
  vim.fn.mkdir(directory, "p", 448)
  assert(uv.fs_chmod(directory, 448))
  local uid = uv.os_get_passwd().uid
  local sockets = {}
  local editor_pid = vim.fn.getpid()
  local function refresh()
    local wanted = { [editor_pid] = true }
    for _, ui in ipairs(vim.api.nvim_list_uis()) do
      local info = vim.api.nvim_get_chan_info(ui.chan)
      local client = info.client or {}
      local pid = tonumber((client.attributes or {}).pid)
      if client.name == "nvim-tui" and pid and pid > 0 and pid == math.floor(pid) then
        wanted[pid] = true
      end
    end
    for pid, socket in pairs(sockets) do
      if not wanted[pid] then
        pcall(vim.fn.serverstop, socket)
        sockets[pid] = nil
      end
    end
    for pid in pairs(wanted) do
      if not sockets[pid] then
        local socket = string.format("%s/%d-%d", directory, uid, pid)
        local ok, started = pcall(vim.fn.serverstart, socket)
        if ok and started == socket then sockets[pid] = socket end
      end
    end
  end
  refresh()
  vim.api.nvim_create_autocmd({ "UIEnter", "UILeave" }, {
    callback = function() vim.schedule(refresh) end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      for _, socket in pairs(sockets) do
        pcall(vim.fn.serverstop, socket)
      end
    end,
  })
end

return M
