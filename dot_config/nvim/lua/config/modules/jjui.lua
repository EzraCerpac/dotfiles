local M = {}

-- Open jjui (must be available on PATH) in a terminal split
local function resolve_cmd()
  if vim.fn.executable("jjui") == 1 then
    return "jjui"
  end
  return nil
end

function M.open()
  local cmd = resolve_cmd()
  if not cmd then
    vim.notify("jjui not found in PATH. Please install jjui and try again.", vim.log.levels.ERROR)
    return
  end

  vim.cmd("botright split | resize 18")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.fn.termopen(cmd, {
    cwd = vim.loop.cwd(),
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("jjui exited with code " .. code, vim.log.levels.WARN)
      end
    end,
  })

  vim.cmd("startinsert")
end

return M
