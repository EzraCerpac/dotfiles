-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--
-- vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
--   pattern = { "*" },
--   command = "silent! wall",
--   nested = true,
-- })

-- Autosave implementation
local autosave_enabled = false

-- Function to save current buffer only if modified
local function autosave()
  if autosave_enabled and vim.bo.modifiable and not vim.bo.readonly and vim.bo.buftype == "" and vim.bo.modified then
    vim.cmd("silent! update")
  end
end

-- Define the augroup once
local autosave_group = vim.api.nvim_create_augroup("CustomAutosave", { clear = true })
vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost" }, {
  group = autosave_group,
  callback = autosave,
})

-- Toggle function
vim.api.nvim_create_user_command("AutosaveToggle", function()
  autosave_enabled = not autosave_enabled
  print("Autosave " .. (autosave_enabled and "enabled" or "disabled"))
end, {})
vim.keymap.set("n", "<leader>uv", ":AutosaveToggle<CR>", { desc = "Toggle autosave" })

-- -- Ensures that when exiting NeoVim, Zellij returns to normal mode
-- vim.api.nvim_create_autocmd("VimLeave", {
--   pattern = "*",
--   command = "silent !zellij action switch-mode normal",
-- })
