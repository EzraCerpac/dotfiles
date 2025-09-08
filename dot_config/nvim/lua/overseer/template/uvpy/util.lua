local M = {}

-- Find a project root using common Python markers
function M.project_root()
  local buf_dir = vim.fn.expand("%:p:h")
  -- Prefer project files; then .git directory
  local found = vim.fs.find({ "pyproject.toml", "uv.lock" }, {
    upward = true,
    type = "file",
    path = buf_dir,
  })[1]
  if found then
    return vim.fs.dirname(found)
  end
  -- Look for a .git directory and use its parent
  local gitdir = vim.fs.find({ ".git" }, { upward = true, type = "directory", path = buf_dir })[1]
  if gitdir then
    return vim.fs.dirname(gitdir)
  end
  return buf_dir
end

-- Split a string into argv respecting simple quotes and escapes.
-- Examples:
--   "--flag one\ two 'three four' \"five six\"" -> {"--flag", "one two", "three four", "five six"}
function M.split_args(str)
  if not str or str == "" then
    return {}
  end
  local args, cur, in_squote, in_dquote = {}, {}, false, false
  local i = 1
  while i <= #str do
    local c = string.sub(str, i, i)
    if c == "\\" then
      -- escape next char
      i = i + 1
      local n = string.sub(str, i, i)
      table.insert(cur, n)
    elseif c == "'" and not in_dquote then
      in_squote = not in_squote
    elseif c == '"' and not in_squote then
      in_dquote = not in_dquote
    elseif c:match("%s") and not in_squote and not in_dquote then
      if #cur > 0 then
        table.insert(args, table.concat(cur))
        cur = {}
      end
    else
      table.insert(cur, c)
    end
    i = i + 1
  end
  if #cur > 0 then
    table.insert(args, table.concat(cur))
  end
  return args
end

-- Join args into a single string with minimal quoting
function M.join_args(list)
  if not list or #list == 0 then
    return ""
  end
  local out = {}
  for _, a in ipairs(list) do
    if a:find("%s") or a == "" then
      -- quote if contains spaces
      table.insert(out, string.format('"%s"', a:gsub('"', '\\"')))
    else
      table.insert(out, a)
    end
  end
  return table.concat(out, " ")
end

-- Return tail of args after a given base prefix
function M.args_tail(args, base)
  if not args or not base then
    return {}
  end
  for i = 1, #base do
    if args[i] ~= base[i] then
      return {}
    end
  end
  local tail = {}
  for i = #base + 1, #args do
    table.insert(tail, args[i])
  end
  return tail
end

function M.extend_args(base, extra)
  local ret = {}
  for _, v in ipairs(base or {}) do
    table.insert(ret, v)
  end
  for _, v in ipairs(extra or {}) do
    table.insert(ret, v)
  end
  return ret
end

return M
