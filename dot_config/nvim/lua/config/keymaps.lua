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
-- dedicated to smart-splits + WezTerm/AeroSpace navigation.
-- local function set_smart_splits_alt_keymaps()
--   local ok, smart_splits = pcall(require, "smart-splits")
--   if not ok then
--     return
--   end
--
--   local del = vim.keymap.del
--   local map = vim.keymap.set
--   local modes = { "n", "i", "v", "x", "s", "t" }
--   for _, m in ipairs(modes) do
--     pcall(del, m, "<A-h>")
--     pcall(del, m, "<A-j>")
--     pcall(del, m, "<A-k>")
--     pcall(del, m, "<A-l>")
--   end
--
--   local moves = {
--     left = smart_splits.move_cursor_left,
--     down = smart_splits.move_cursor_down,
--     up = smart_splits.move_cursor_up,
--     right = smart_splits.move_cursor_right,
--   }
--
--   local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
--
--   local function meta_move(direction)
--     local move = moves[direction]
--     return function()
--       if not move then
--         return
--       end
--
--       local mode = vim.api.nvim_get_mode().mode
--       local prefix = mode:sub(1, 1)
--       local is_insert = prefix == "i" or prefix == "R"
--       local is_term = prefix == "t"
--       local is_visual = prefix == "v" or prefix == "V" or mode == "\22"
--       local is_select = prefix == "s" or prefix == "S"
--       local should_reselect = is_visual or is_select
--
--       if is_insert or is_term then
--         vim.cmd("stopinsert")
--       elseif should_reselect then
--         vim.api.nvim_feedkeys(esc, "nx", false)
--       end
--
--       local ok_move, err = pcall(move)
--       if not ok_move then
--         vim.schedule(function()
--           vim.notify(("smart-splits %s failed: %s"):format(direction, err), vim.log.levels.ERROR)
--         end)
--       end
--
--       if should_reselect then
--         vim.schedule(function()
--           vim.cmd("normal! gv")
--         end)
--       end
--
--       if is_insert then
--         vim.schedule(function()
--           if vim.api.nvim_get_mode().mode:sub(1, 1) == "n" then
--             vim.cmd("startinsert")
--           end
--         end)
--       elseif is_term then
--         vim.schedule(function()
--           if vim.bo.buftype == "terminal" then
--             vim.cmd("startinsert")
--           end
--         end)
--       end
--     end
--   end
--
--   local opts = { silent = true, noremap = true }
--   local bindings = {
--     { dir = "left", key = "h" },
--     { dir = "down", key = "j" },
--     { dir = "up", key = "k" },
--     { dir = "right", key = "l" },
--   }
--
--   for _, binding in ipairs(bindings) do
--     map(
--       modes,
--       "<A-" .. binding.key .. ">",
--       meta_move(binding.dir),
--       vim.tbl_extend("force", opts, { desc = "Smart-splits: focus " .. binding.dir })
--     )
--   end
-- end

-- Run once now (this file loads on VeryLazy in LazyVim)
set_smart_splits_alt_keymaps()

-- Belt-and-suspenders: ensure our Alt mappings win after all plugins load
vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    set_smart_splits_alt_keymaps()
    -- Reassert shortly after UI starts to beat any late mappings
    vim.defer_fn(set_smart_splits_alt_keymaps, 50)
    vim.defer_fn(set_smart_splits_alt_keymaps, 200)
  end,
})

-- Also after Lazy fully initializes plugins
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    set_smart_splits_alt_keymaps()
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
