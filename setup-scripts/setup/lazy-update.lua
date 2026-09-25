local lazy = require("lazy")
local updates = {}
local pinned = {}
local dirty = {}
local missing = {}

for _, plugin in ipairs(lazy.plugins()) do
  local name = plugin.name or "unknown"
  local dir = plugin.dir
  local is_pinned = plugin.pin == true
    or (plugin.version ~= nil and plugin.version ~= false)
    or (plugin.tag ~= nil and plugin.tag ~= false)
    or (plugin.commit ~= nil and plugin.commit ~= false)

  if is_pinned then
    table.insert(pinned, name)
  elseif not dir or vim.fn.isdirectory(dir) == 0 then
    table.insert(missing, name)
  elseif vim.fn.isdirectory(dir .. "/.git") == 0 and vim.fn.filereadable(dir .. "/.git") == 0 then
    table.insert(missing, name)
  else
    local result = vim.fn.systemlist({ "git", "-C", dir, "status", "--porcelain" })
    if vim.v.shell_error ~= 0 then
      table.insert(dirty, name .. " (git status failed)")
    elseif #result > 0 then
      table.insert(dirty, name)
    else
      table.insert(updates, name)
    end
  end
end

local function report(label, items)
  if #items > 0 then
    table.sort(items)
    print(label .. ": " .. table.concat(items, ", "))
  else
    print(label .. ": none")
  end
end

report("Pinned plugins kept", pinned)
report("Dirty plugins deferred", dirty)
report("Missing plugin checkouts deferred", missing)
report("Clean plugins selected for update", updates)

if #updates > 0 then
  print("Restart Neovim after updates if the active session needs the new plugin code.")
  local config = require("lazy.core.config")
  local previous = {}
  for _, plugin in ipairs(lazy.plugins()) do
    previous[plugin.name] = {}
    for _, task in ipairs(plugin._.tasks or {}) do
      previous[plugin.name][task] = true
    end
  end

  local ok, err = pcall(lazy.update, { plugins = updates, wait = true, show = false })
  if not ok then
    vim.api.nvim_err_writeln("Lazy update failed: " .. tostring(err))
    vim.cmd("cquit 1")
  end

  local failures = {}
  for _, name in ipairs(updates) do
    local plugin = config.plugins[name]
    for _, task in ipairs(plugin and plugin._.tasks or {}) do
      if not previous[name][task] and task:has_errors() then
        local detail = task:output(vim.log.levels.ERROR)
        table.insert(failures, name .. (detail ~= "" and (": " .. detail) or ": update task failed"))
      end
    end
  end
  if #failures > 0 then
    vim.api.nvim_err_writeln("Lazy plugin update failures:\n  " .. table.concat(failures, "\n  "))
    vim.cmd("cquit 1")
  end
end

vim.cmd("qa")
