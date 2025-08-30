-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>j", "*``cgn", { desc = "Search word under cursor and change next match" })

vim.keymap.set("x", "<leader>j", function()
  -- Yank visual selection to register z
  vim.cmd('normal! "zy')
  -- Escape for search
  local text = vim.fn.getreg("z")
  text = vim.fn.escape(text, "\\/.*$^~[]")
  vim.fn.setreg("/", text)
  -- Exit visual mode and feed 'n' and 'cgn' as keypresses
  vim.api.nvim_feedkeys("n", "n", false)
  vim.api.nvim_feedkeys("cgn", "n", false)
end, { desc = "Change visual selection and repeat with dot" })

-- Ensure <leader>e opens mini.files (override any LazyVim defaults)
vim.keymap.set("n", "<leader>e", function()
  require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
end, { desc = "Open mini.files (Directory of Current File)" })
