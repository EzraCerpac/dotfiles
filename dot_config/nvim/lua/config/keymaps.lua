-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

require("config.keymaps.jabref")

local function safe_del(mode, lhs)
  pcall(vim.keymap.del, mode, lhs)
end

-- REMOVED --

-- Tabs
safe_del("n", "<leader><tab>l")
safe_del("n", "<leader><tab>o")
safe_del("n", "<leader><tab>f")
safe_del("n", "<leader><tab><tab>")
safe_del("n", "<leader><tab>]")
safe_del("n", "<leader><tab>d")
safe_del("n", "<leader><tab>[")
-- Space
safe_del("n", "<leader><space>")
-- Window group (LazyVim default)
safe_del("n", "<leader>w")

-- ADDED --

-- Restart --
vim.keymap.set("n", "<leader>qr", function()
  if vim.fn.exists(":restart") > 0 then
    vim.cmd("restart")
    return
  end
  vim.notify("`:restart` is not available in this Neovim build", vim.log.levels.WARN)
end, { desc = "Restart nvim" })

-- Save
vim.keymap.set("n", "<leader>w", "<Cmd>write<CR>", { desc = "Save file", nowait = true })
vim.keymap.set("n", "<leader>W", "<Cmd>wall<CR>", { desc = "Save all files", nowait = true })

-- Helix-like line nav
vim.keymap.set({ "n", "v", "o" }, "g<Left>", "^", { desc = "First char of line" })
vim.keymap.set({ "n", "v", "o" }, "g<Right>", "$", { desc = "Last char of line" })

-- Text editting --
vim.keymap.set("v", "<C-b>", "gsa*", { desc = "Surround selection with *" })
vim.keymap.set("n", "<C-b>", "gsaiw*", { desc = "Surround word with *" })
vim.keymap.set("v", "<C-i>", "gsa_", { desc = "Surround selection with _" })
vim.keymap.set("n", "<C-i>", "gsaiw_", { desc = "Surround word with _" })

local has_fzf, fzf = pcall(require, "fzf-lua")
if has_fzf then
  local actions = require("fzf-lua.actions")
  fzf.setup({
    files = {
      hidden = false,
      actions = {
        ["ctrl-h"] = actions.toggle_hidden,
      },
    },
  })
end

vim.api.nvim_create_user_command("LatexToTypst", function()
  require("custom.latex_to_typst").convert()
end, { range = true })

vim.api.nvim_create_user_command("LatexToTypstPaste", function()
  require("custom.latex_to_typst").paste_clipboard()
end, {})

vim.keymap.set("v", "<localleader>tl", ":LatexToTypst<CR>", { desc = "Convert LaTeX to Typst" })
vim.keymap.set("n", "<localleader>tl", ":LatexToTypstPaste<CR>", { desc = "Paste Typst from clipboard LaTeX" })

vim.keymap.set({ "n", "v" }, "<localleader>tt", ":TypstPreview<CR>", { desc = "Open Typst preview" })

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
