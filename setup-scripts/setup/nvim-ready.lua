local lazy = require("lazy")
local config = require("lazy.core.config")
local plugin = require("lazy.core.plugin")

local function load(name)
  local item = config.plugins[name]
  if item and item._.installed and item._.cond ~= false then
    lazy.load({ plugins = { name } })
  end
  return item and item._.cond ~= false and item._.loaded and item or nil
end

local function initialize()
  local mason = load("mason.nvim")
  if mason then
    local registry = require("mason-registry")
    local refreshed, detail = registry.refresh()
    if not refreshed then
      error("Mason registry refresh failed: " .. tostring(detail))
    end
    -- LazyVim computes the Mason-managed server set when configuring lspconfig.
    local lsp = load("nvim-lspconfig")
    local requested = {}
    local function add(name)
      if not vim.tbl_contains(requested, name) then
        table.insert(requested, name)
      end
    end
    local opts = plugin.values(mason, "opts", false)
    for _, name in ipairs(opts.ensure_installed or {}) do
      add(name)
    end
    if lsp and config.plugins["mason-lspconfig.nvim"] then
      local settings = require("mason-lspconfig.settings").current
      local mapping = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
      for _, server in ipairs(settings.ensure_installed or {}) do
        local name = mapping[server]
        if not name then
          error("Mason has no package for configured server: " .. server)
        end
        add(name)
      end
    end
    local treesitter = config.plugins["nvim-treesitter"]
    if
      treesitter
      and treesitter._.installed
      and treesitter._.cond ~= false
      and vim.fn.executable("tree-sitter") == 0
    then
      add("tree-sitter-cli")
    end
    local packages = {}
    for _, name in ipairs(requested) do
      packages[#packages + 1] = registry.get_package(name)
    end
    local function settled()
      for _, package in ipairs(packages) do
        if package:is_installing() then
          return false
        end
      end
      return true
    end
    vim.wait(10)
    if not vim.wait(300000, settled, 100) then
      error("timed out waiting for Mason installs")
    end
    local pending, failures = 0, {}
    for _, package in ipairs(packages) do
      if not package:is_installed() then
        pending = pending + 1
        local handle = package:install(nil, function(success, err)
          if not success then
            table.insert(failures, package.name .. ": " .. tostring(err))
          end
          pending = pending - 1
        end)
        -- Archive tools print normal progress on stderr. Treat it as output;
        -- Mason's callback, not the output stream, reports install failure.
        handle:on("stdout", vim.schedule_wrap(vim.api.nvim_out_write))
        handle:on("stderr", vim.schedule_wrap(vim.api.nvim_out_write))
      end
    end
    if not vim.wait(300000, function()
      return pending == 0
    end, 100) then
      error("timed out waiting for Mason installs")
    end
    if #failures > 0 then
      error("Mason install failed: " .. table.concat(failures, "; "))
    end
    for _, package in ipairs(packages) do
      if not package:is_installed() then
        error("Mason package still missing: " .. package.name)
      end
    end
  end
  local treesitter = load("nvim-treesitter")
  if treesitter and vim.fn.executable("tree-sitter") == 0 then
    error("tree-sitter CLI is required for configured parsers")
  end
  local parser_script = debug.getinfo(1, "S").source:sub(2):gsub("[^/]+$", "nvim-parsers.lua")
  dofile(parser_script)()
end

local ok, err = pcall(initialize)
if not ok then
  vim.api.nvim_err_writeln("Neovim tool initialization failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
vim.cmd("qa")
