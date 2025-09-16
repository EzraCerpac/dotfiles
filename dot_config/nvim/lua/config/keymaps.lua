-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Removed --
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
vim.keymap.del("n", "<leader><leader>")

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
