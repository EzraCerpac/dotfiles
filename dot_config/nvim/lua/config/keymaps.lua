-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- REMOVED --

-- Tabs
vim.keymap.del("n", "<leader><tab>l")
vim.keymap.del("n", "<leader><tab>o")
vim.keymap.del("n", "<leader><tab>f")
vim.keymap.del("n", "<leader><tab><tab>")
vim.keymap.del("n", "<leader><tab>]")
vim.keymap.del("n", "<leader><tab>d")
vim.keymap.del("n", "<leader><tab>[")
-- Space
vim.keymap.del("n", "<leader><space>")

-- ADDED --

-- Restart --
vim.keymap.set("n", "<leader>qr", "<Cmd>restart<CR>", { desc = "Restart nvim" })

-- Helix-like line nav
vim.keymap.set({ "n", "v", "o" }, "gh", "^", { desc = "First char of line" })
vim.keymap.set({ "n", "v", "o" }, "gl", "$", { desc = "Last char of line" })

-- Ensure <leader>e opens mini.files (override any LazyVim defaults)
vim.keymap.set("n", "<leader>e", function()
  require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
end, { desc = "Open mini.files (Directory of Current File)" })

local actions = require("fzf-lua.actions")

require("fzf-lua").setup({
  files = {
    hidden = false, -- your pref
    actions = {
      ["ctrl-h"] = actions.toggle_hidden, -- your remap
    },
  },
})

vim.api.nvim_create_user_command("LatexToTypst", function()
  require("custom.latex_to_typst").convert()
end, { range = true })
vim.keymap.set("v", "<localleader>lt", ":LatexToTypst<CR>", { desc = "Convert LaTeX to Typst" })
