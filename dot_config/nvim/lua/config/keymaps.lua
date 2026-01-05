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

-- Text editting --
vim.keymap.set("v", "<C-b>", "gsa*", { desc = "Surround selection with *" })
vim.keymap.set("n", "<C-b>", "gsaiw*", { desc = "Surround word with *" })
vim.keymap.set("v", "<C-i>", "gsa_", { desc = "Surround selection with _" })
vim.keymap.set("n", "<C-i>", "gsaiw_", { desc = "Surround word with _" })

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

vim.api.nvim_create_user_command("LatexToTypstPaste", function()
  require("custom.latex_to_typst").paste_clipboard()
end, {})

vim.keymap.set("v", "<localleader>tl", ":LatexToTypst<CR>", { desc = "Convert LaTeX to Typst" })
vim.keymap.set("n", "<localleader>tl", ":LatexToTypstPaste<CR>", { desc = "Paste Typst from clipboard LaTeX" })

-- RTF Syntax Highlighting (direct pygmentize)
vim.api.nvim_create_user_command("RTFHighlight", function()
  vim.cmd("update") -- save current file
  local lexer = vim.bo.filetype ~= "" and vim.bo.filetype or "lua"
  local file = vim.fn.expand("%")
  local cmd = "pygmentize -f rtf -O style=xcode -l " .. lexer .. " " .. vim.fn.shellescape(file) .. " | pbcopy"
  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("pygmentize failed", vim.log.levels.ERROR)
    return
  end
  vim.notify("RTF copied to clipboard", vim.log.levels.INFO)
end, { desc = "Convert buffer to RTF and copy to clipboard" })
