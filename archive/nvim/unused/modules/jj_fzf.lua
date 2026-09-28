local M = {}

-- Open jj-fzf in a terminal split using PATH-resolved executable
local function resolve_cmd()
  if vim.fn.executable("jj-fzf") == 1 then
    return "jj-fzf"
  end
  return nil
end

function M.open()
  local cmd = resolve_cmd()
  if not cmd then
    vim.notify("jj-fzf not found in PATH. Please ensure it is installed and on PATH.", vim.log.levels.ERROR)
    return
  end

  -- Open a bottom split with a reasonable height and start a terminal
  vim.cmd("botright split | resize 18")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.fn.termopen(cmd, {
    cwd = vim.loop.cwd(),
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("jj-fzf exited with code " .. code, vim.log.levels.WARN)
      end
    end,
  })

  vim.cmd("startinsert")
end

return M
