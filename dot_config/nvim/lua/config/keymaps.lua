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

vim.api.nvim_create_user_command("LatexToTypstPaste", function()
  require("custom.latex_to_typst").paste_clipboard()
end, {})

vim.keymap.set("v", "<localleader>tl", ":LatexToTypst<CR>", { desc = "Convert LaTeX to Typst" })
vim.keymap.set("n", "<localleader>tl", ":LatexToTypstPaste<CR>", { desc = "Paste Typst from clipboard LaTeX" })

-- RTF Syntax Highlighting (via pygmentize)
vim.api.nvim_create_user_command("RTFHighlight", function(args)
  if vim.fn.executable("pygmentize") == 0 then
    vim.notify("pygmentize not found", vim.log.levels.ERROR)
    return
  end
  local line1, line2 = args.line1, args.line2
  local content = table.concat(vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false), "\n")
  local lexer = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  local theme = vim.g.rtf_theme or "xcode"
  local output = vim.fn.system("pygmentize -f rtf -O style=" .. theme .. " -l " .. lexer, content)
  if vim.v.shell_error ~= 0 then
    vim.notify("pygmentize failed: " .. output, vim.log.levels.ERROR)
    return
  end
  -- Write to temp file, then use :! to run through shell
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(output, "\n", true), tmpfile)
  vim.cmd("silent !cat " .. vim.fn.shellescape(tmpfile) .. " | pbcopy")
  vim.fn.delete(tmpfile)
  vim.notify("RTF copied to clipboard (length: " .. #output .. ")", vim.log.levels.INFO)
end, { range = true, desc = "Convert buffer/selection to RTF and copy to clipboard" })
