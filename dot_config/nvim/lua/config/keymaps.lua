-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<leader>j", "*``cgn", { desc = "Search word under cursor and change next match" })
--
-- vim.keymap.set("x", "<leader>j", function()
--   -- Yank visual selection to register z
--   vim.cmd('normal! "zy')
--   -- Escape for search
--   local text = vim.fn.getreg("z")
--   text = vim.fn.escape(text, "\\/.*$^~[]")
--   vim.fn.setreg("/", text)
--   -- Exit visual mode and feed 'n' and 'cgn' as keypresses
--   vim.api.nvim_feedkeys("n", "n", false)
--   vim.api.nvim_feedkeys("cgn", "n", false)
-- end, { desc = "Change visual selection and repeat with dot" })

-- Ensure <leader>e opens mini.files (override any LazyVim defaults)
vim.keymap.set("n", "<leader>e", function()
  require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
end, { desc = "Open mini.files (Directory of Current File)" })

require("fzf-lua").setup({
  files = {
    hidden = false,
    actions = {
      -- remap toggle hidden from Alt-h to Ctrl-h
      ["ctrl-h"] = require("fzf-lua.actions").toggle_hidden,

      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        local file = selected[1]

        -- 1. Strip any leading icons + whitespace
        --    Nerd Font icons live in private use area (E000–F8FF), but sometimes
        --    other Unicode glyphs slip in, so just nuke non-path-safe chars.
        file = file:gsub("^[%z\1-\31\u{E000}-\u{F8FF}\u{2000}-\u{200B}]+", "")
        file = file:gsub("^%s+", "")
        -- keep only printable chars after the last icon/space run
        file = file:match("([%w%p%/%.%_%-~]+.*)")

        -- 2. Expand relative paths like `.config/...` → `$HOME/.config/...`
        if not file:match("^/") then
          file = vim.fn.expand("~/" .. file)
        end

        -- 3. Map chezmoi source dir paths → target paths
        local chezmoi_dir = vim.fn.expand("~/.local/share/chezmoi/")
        if file:sub(1, #chezmoi_dir) == chezmoi_dir then
          file = file:gsub(chezmoi_dir, vim.fn.expand("~") .. "/")
          file = file:gsub("^dot_", ".") -- dotfile convention
          file = file:gsub("private_", "") -- strip private_ prefix
          file = file:gsub("slash", "/") -- chezmoi escape convention
        end

        vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(file))
      end,
    },
  },
})
