local delftblue = require("config.delftblue")

if not delftblue.enabled() then
  return {}
end

return {
  { "olimorris/codecompanion.nvim", enabled = false },
  { "piersolenski/wtf.nvim", enabled = false },
  { "ThePrimeagen/99", enabled = false },
  { "folke/sidekick.nvim", enabled = false },
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "wakatime/vim-wakatime", enabled = false },
  { "3rd/image.nvim", enabled = false },
  { "toppair/peek.nvim", enabled = false },
  { "iamcco/markdown-preview.nvim", enabled = false },
  { "mfussenegger/nvim-dap", enabled = false },
  { "kdheepak/nvim-dap-julia", enabled = false },
  { "Civitasv/cmake-tools.nvim", enabled = false },
  { "stevearc/conform.nvim", dependencies = {} },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.auto_install = false
      opts.ensure_installed = {}
      return opts
    end,
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts = opts or {}
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters = opts.formatters or {}
      opts.formatters_by_ft.markdown = nil
      opts.formatters_by_ft["markdown.mdx"] = nil
      opts.formatters["markdownlint-cli2"] = nil
      opts.formatters["markdown-toc"] = nil
      return opts
    end,
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts = opts or {}
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.markdown = {}
      return opts
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
      opts.servers = opts.servers or {}
      opts.servers["*"] = vim.tbl_deep_extend("force", opts.servers["*"] or {}, {
        mason = false,
      })
      opts.servers.neocmake = { enabled = false, mason = false }
      if not delftblue.has("lua-language-server") then
        opts.servers.lua_ls = { enabled = false }
      end
      if not delftblue.has("texlab") then
        opts.servers.texlab = { enabled = false }
      end
      if not delftblue.has("tinymist") then
        opts.servers.tinymist = { enabled = false }
      end
      return opts
    end,
  },
}
