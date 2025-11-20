local M = {}

-- Override the project root for this session
function M.override_root()
  local project = require("project_nvim.project")
  local cwd = vim.loop.cwd()

  -- Set the project root to current working directory
  project.set_cwd(cwd)

  -- Optional: notify
  vim.notify("Project root temporarily set to: " .. cwd, vim.log.levels.WARN)
end

-- Create a user command for convenience
vim.api.nvim_create_user_command("TempRoot", function()
  M.override_root()
end, {})

return M
