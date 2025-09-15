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

local actions = require("fzf-lua.actions")

-- Override LazyVim defaults that move lines with Alt-j/k so Alt+hjkl can be
-- dedicated to Navigator.nvim + WezTerm pane navigation.
local function set_navigator_alt_keymaps()
  -- local del = vim.keymap.del
  -- -- Remove any existing Alt+hjkl mappings from common modes
  -- for _, m in ipairs({ "n", "i", "v", "x", "s", "o", "t" }) do
  --   pcall(del, m, "<A-h>")
  --   pcall(del, m, "<A-j>")
  --   pcall(del, m, "<A-k>")
  --   pcall(del, m, "<A-l>")
  -- end
  --
  local ok, Navigator = pcall(require, "Navigator")
  if not ok then
    return
  end

  local map = vim.keymap.set
  local opts = { silent = true, noremap = true }
  local modes = { "n", "i", "v", "x", "s", "o", "t" }
  for _, m in ipairs(modes) do
    map(m, "<A-h>", Navigator.left, opts)
    map(m, "<A-j>", Navigator.down, opts)
    map(m, "<A-k>", Navigator.up, opts)
    map(m, "<A-l>", Navigator.right, opts)
  end
end

-- Run once now (this file loads on VeryLazy in LazyVim)
set_navigator_alt_keymaps()

-- Belt-and-suspenders: ensure our Alt mappings win after all plugins load
vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    set_navigator_alt_keymaps()
    -- Reassert shortly after UI starts to beat any late mappings
    vim.defer_fn(set_navigator_alt_keymaps, 50)
    vim.defer_fn(set_navigator_alt_keymaps, 200)
  end,
})

-- Also after Lazy fully initializes plugins
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    set_navigator_alt_keymaps()
  end,
})

-- TODO: Split into files
-- classify “home dot targets”
local function is_home_dot_target(abs, home)
  if not vim.startswith(abs, home .. "/") then
    return false
  end
  local tail = abs:sub(#home + 2) -- strip "$HOME/"
  return tail:match("^%.") -- ~/.zshrc, ~/.github/...
    or tail:match("^%.config/")
    or tail:match("^%.local/")
    or tail:match("^%.ssh/")
end

-- convert a chezmoi source path -> target path under $HOME
local function source_to_target(src_abs, chezmoi_dir, home)
  local rel = src_abs:sub(#chezmoi_dir + 1)
  local out = {}
  for seg in rel:gmatch("[^/]+") do
    seg = seg
      :gsub("^private_", "")
      :gsub("^exact_", "")
      :gsub("^executable_", "")
      :gsub("^readonly_", "")
      :gsub("^literal_", "")
      :gsub("^encrypted_", "")
    if seg:sub(1, 4) == "dot_" then
      seg = "." .. seg:sub(5)
    end
    seg = seg:gsub("slash", "/")
    seg = seg:gsub("%.tmpl$", "")
    table.insert(out, seg)
  end
  return home .. "/" .. table.concat(out, "/")
end

-- normalize one fzf-lua line into an absolute path
local function normalize_selected(line)
  if not line or line == "" then
    return nil
  end
  -- strip nerd-font icons / unicode spaces
  line = line:gsub("^[%z\1-\31\u{E000}-\u{F8FF}\u{2000}-\u{200B}]+", ""):gsub("^%s+", "")
  -- keep printable path-ish chars
  line = line:match("([%w%p%/%.%_%-~]+.*)") or line

  -- expand to absolute:
  if line:sub(1, 1) == "~" then
    return vim.fn.expand(line)
  elseif line:sub(1, 1) == "/" then
    return line
  else
    -- heuristic: “dotfile-like” relative paths belong under $HOME,
    -- everything else is relative to cwd
    if line:match("^%.") then
      return vim.fn.expand("~/" .. line)
    else
      return vim.fn.getcwd() .. "/" .. line
    end
  end
end

require("fzf-lua").setup({
  files = {
    hidden = false, -- your pref
    actions = {
      ["ctrl-h"] = actions.toggle_hidden, -- your remap

      ["default"] = function(sel)
        if not sel or #sel == 0 then
          return
        end
        local raw = sel[1]
        local file = normalize_selected(raw)
        if not file then
          return
        end

        local home = vim.fn.expand("~")
        local chezmoi_dir = vim.fn.expand("~/.local/share/chezmoi/")

        if vim.startswith(file, chezmoi_dir) then
          -- selected a source path: map to target, then ChezmoiEdit
          local target = source_to_target(file, chezmoi_dir, home)
          vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(target))
          return
        end

        if is_home_dot_target(file, home) then
          -- selected a home “dot target”: always go through chezmoi
          vim.cmd("ChezmoiEdit " .. vim.fn.fnameescape(file))
          return
        end

        -- normal project file
        vim.cmd("edit " .. vim.fn.fnameescape(file))
      end,
    },
  },
})
