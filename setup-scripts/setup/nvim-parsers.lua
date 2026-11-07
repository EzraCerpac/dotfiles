return function()
  local lazy = require("lazy")
  -- LazyVim starts missing parser installs asynchronously at startup. Wait for
  -- those installs explicitly so parser build failures make this stage fail.
  for _, plugin in ipairs(lazy.plugins()) do
    if plugin.name == "nvim-treesitter" and plugin._.loaded then
      local ok, err = pcall(function()
        local opts = require("lazy.core.plugin").values(plugin, "opts", false)
        local ts = require("nvim-treesitter")
        local available = ts.get_available()
        local installed = ts.get_installed("parsers")
        local missing_parsers = {}
        for _, lang in ipairs(opts.ensure_installed or {}) do
          if vim.tbl_contains(available, lang) and not vim.tbl_contains(installed, lang) then
            table.insert(missing_parsers, lang)
          end
        end
        if #missing_parsers > 0 then
          if not ts.install(missing_parsers, { force = true, summary = true }):wait(300000) then
            error("parser installation failed: " .. table.concat(missing_parsers, ", "))
          end
          installed = ts.get_installed("parsers")
          local still_missing = vim.tbl_filter(function(lang)
            return not vim.tbl_contains(installed, lang)
          end, missing_parsers)
          if #still_missing > 0 then
            error("parser binaries still missing: " .. table.concat(still_missing, ", "))
          end
        end
      end)
      if not ok then
        error("Tree-sitter parser update failed: " .. tostring(err))
      end
      break
    end
  end
end
