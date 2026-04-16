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
    build = function() end,
    opts = function(_, opts)
      opts.auto_install = false
      opts.ensure_installed = {}
      return opts
    end,
    config = function(_, opts)
      local TS = require("nvim-treesitter")

      setmetatable(require("nvim-treesitter.install"), {
        __newindex = function(_, k)
          if k == "compilers" then
            vim.schedule(function()
              LazyVim.error({
                "Setting custom compilers for `nvim-treesitter` is no longer supported.",
                "",
                "For more info, see:",
                "- [compilers](https://docs.rs/cc/latest/cc/#compile-time-requirements)",
              })
            end)
          end
        end,
      })

      if not TS.get_installed then
        return LazyVim.error("Please use `:Lazy` and update `nvim-treesitter`")
      end

      TS.setup(opts)
      LazyVim.treesitter.get_installed(true)

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lazyvim_treesitter", { clear = true }),
        callback = function(ev)
          local ft, lang = ev.match, vim.treesitter.language.get_lang(ev.match)
          if not LazyVim.treesitter.have(ft) then
            return
          end

          local function enabled(feat, query)
            local f = opts[feat] or {}
            return f.enable ~= false
              and not (type(f.disable) == "table" and vim.tbl_contains(f.disable, lang))
              and LazyVim.treesitter.have(ft, query)
          end

          if enabled("highlight", "highlights") then
            pcall(vim.treesitter.start, ev.buf)
          end

          if enabled("indent", "indents") then
            LazyVim.set_default("indentexpr", "v:lua.LazyVim.treesitter.indentexpr()")
          end

          if enabled("folds", "folds") then
            if LazyVim.set_default("foldmethod", "expr") then
              LazyVim.set_default("foldexpr", "v:lua.LazyVim.treesitter.foldexpr()")
            end
          end
        end,
      })
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
