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

-- RTF Syntax Highlighting (via helper script)
vim.api.nvim_create_user_command("RTFHighlight", function(args)
  local home = os.getenv("HOME") or "/Users/ezracerpac"
  local script = home .. "/.config/nvim/lua/helpers/to_clipboard.sh"
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify("to_clipboard.sh not found", vim.log.levels.ERROR)
    return
  end
  local line1, line2 = args.line1, args.line2
  local content = table.concat(vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false), "\n")
  local lexer = vim.bo.filetype ~= "" and vim.bo.filetype or "lua"

  -- Write content to temp file
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(content, "\n"), tmpfile)

  -- Call script with temp file (lexer, input_file, theme)
  local cmd = "sh " .. vim.fn.shellescape(script) .. " " .. lexer .. " " .. vim.fn.shellescape(tmpfile) .. " xcode"
  vim.fn.system(cmd)

  -- Clean up
  vim.fn.delete(tmpfile)

  if vim.v.shell_error ~= 0 then
    vim.notify("clipboard script failed", vim.log.levels.ERROR)
    return
  end
  vim.notify("RTF copied to clipboard", vim.log.levels.INFO)
end, { range = true, desc = "Convert buffer/selection to RTF and copy to clipboard" })
