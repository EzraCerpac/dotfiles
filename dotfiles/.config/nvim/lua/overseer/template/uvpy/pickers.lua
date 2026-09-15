local M = {}

local function lazy_load(mod)
  local ok, lazy = pcall(require, "lazy")
  if ok then pcall(lazy.load, { plugins = { mod } }) end
end

local function has(mod)
  local ok = pcall(require, mod)
  return ok
end

local function joinpath(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  else
    return a .. "/" .. b
  end
end

-- Collect python files under root (relative paths)
local function list_python(root, limit)
  local results = {}
  local abs_files = vim.fs.find(function(name, path)
    return name:match("%.py$") and not path:find("/%.git/")
  end, { type = "file", limit = limit or 2000, path = root })
  for _, p in ipairs(abs_files) do
    local rel = p:gsub("^" .. vim.pesc(root) .. "/?", "")
    -- Skip hidden/ignored dirs and common noise
    if
      rel ~= ""
      and not rel:match("^%.")
      and not rel:match("/%.")
      and not rel:match("/__pycache__/")
      and not rel:match("/%.venv/")
      and not rel:match("/%.direnv/")
    then
      table.insert(results, rel)
    end
  end
  return results
end

-- Pick a Python main file under the detected project root.
-- callback(path) receives an absolute path.
function M.pick_main(opts, callback)
  opts = opts or {}
  local util = require("overseer.template.uvpy.util")
  local root = util.project_root()

  -- Try fzf-lua first (force-load if managed by lazy)
  lazy_load("fzf-lua")
  if has("fzf-lua") then
    local fzf = require("fzf-lua")
    fzf.files({
      cwd = root,
      prompt = "Main file > ",
      file_icons = false,
      git_icons = false,
      hidden = false,     -- do NOT include hidden files/dirs
      no_ignore = false,  -- respect .gitignore
      -- Prefer fd when available; restrict to *.py and exclude common noise
      fd_opts = [[--color=never --type f --type l --exclude .git --exclude .venv --exclude .direnv --exclude __pycache__ --extension py]],
      rg_opts = [[--color=never --files -g "!.git" -g "!**/.venv/**" -g "!**/.direnv/**" -g "!**/__pycache__/**" -g "*.py"]],
      file_ignore_patterns = { [[^%.venv/]], [[/%.venv/]], [[/__pycache__/]] },
      actions = {
        ["default"] = function(selected)
          local entry = selected and selected[1]
          if not entry then return end
          -- entry is relative to cwd; make absolute
          local path = entry
          if not path:match("^/") and not path:match("^%a:[/\\]") then
            path = joinpath(root, path)
          end
          callback(path)
        end,
      },
    })
    return
  end

  -- Fallback: built-in select
  local entries = list_python(root, opts.limit or 400)
  if #entries == 0 then
    vim.ui.input({ prompt = "Main file (path): ", default = joinpath(root, "main.py") }, function(input)
      if input and input ~= "" then callback(input) end
    end)
  else
    vim.ui.select(entries, { prompt = "Main file" }, function(choice)
      if choice then callback(joinpath(root, choice)) end
    end)
  end
end

return M
