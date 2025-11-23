-- Override the project root for this session
local function override_root()
  local cwd = vim.loop.cwd()

  -- Override LazyVim's root detection to use current directory only
  vim.g.root_spec = { "cwd" }
  vim.g.lazyvim_root_spec = vim.g.root_spec

  -- Optional: notify
  vim.notify("Project root temporarily set to: " .. cwd, vim.log.levels.WARN)
end

-- Auto-enable local root mode if environment variable is set
if vim.env.NVIM_LOCAL_ROOT == "1" then
  override_root()
end

-- Create a user command for convenience
-- BUG: Doesn't work, env above does
vim.api.nvim_create_user_command("TempRoot", function()
  override_root()
end, { desc = "Set project root to current directory" })
