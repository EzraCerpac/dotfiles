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
  local uv = vim.uv or vim.loop
  local directory = vim.fn.expand("~/.local/state/rex/nvim")
  vim.fn.mkdir(directory, "p", 448)
  assert(uv.fs_chmod(directory, 448))
  local uid = uv.os_get_passwd().uid
  local sockets = {}
  for _, pid in ipairs({ vim.fn.getpid(), uv.os_getppid() }) do
    local socket = string.format("%s/%d-%d", directory, uid, pid)
    local ok, started = pcall(vim.fn.serverstart, socket)
    if ok and started == socket then
      table.insert(sockets, socket)
    end
  end
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      for _, socket in ipairs(sockets) do
        pcall(vim.fn.serverstop, socket)
      end
    end,
  })
end

return M
