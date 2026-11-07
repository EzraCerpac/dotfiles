local lazy = require("lazy")
local config = require("lazy.core.config")
local plugin = require("lazy.core.plugin")

local function initialize()
  -- Imports from missing plugins can expose more plugins after installation.
  -- Match Lazy's bounded startup loop, but select only missing checkouts.
  for _ = 1, 6 do
    local missing = {}
    for _, item in pairs(config.plugins) do
      if item._.cond == false then
        -- Lazy marks disabled optional plugins with a false condition.
      elseif not item._.installed then
        table.insert(missing, item)
      elseif
        item.url
        and not item._.is_local
        and vim.fn.isdirectory(item.dir .. "/.git") == 0
        and vim.fn.filereadable(item.dir .. "/.git") == 0
      then
        error("incomplete plugin checkout: " .. item.name .. " (" .. item.dir .. ")")
      end
    end
    if #missing == 0 then
      if config.spec:report() > 0 then
        error("plugin specifications contain errors")
      end
      return
    end

    local previous = {}
    for _, item in pairs(config.plugins) do
      for _, task in ipairs(item._.tasks or {}) do
        previous[task] = true
      end
    end
    lazy.install({ plugins = missing, wait = true, show = false, clear = false, lockfile = true })
    for _, item in pairs(config.plugins) do
      for _, task in ipairs(item._.tasks or {}) do
        if not previous[task] and task:has_errors() then
          error(item.name .. ": " .. task:output(vim.log.levels.ERROR))
        end
      end
    end
    for _, item in ipairs(missing) do
      local current = config.plugins[item.name]
      if not current or not current._.installed then
        error("plugin checkout still missing: " .. item.name)
      end
    end
    plugin.load()
  end
  error("missing plugins remain after six installation rounds")
end

local ok, err = pcall(initialize)
if not ok then
  vim.api.nvim_err_writeln("Neovim plugin initialization failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
vim.cmd("qa")
