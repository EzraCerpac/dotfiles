return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    dependencies = {
      { "DrKJeff16/wezterm-types", lazy = true },
    },
    opts = {
      library = {
        -- Other library configs...
        { path = "wezterm-types", mods = { "wezterm" } },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          enabled = false, -- using ty instead
        },
        julials = {
          -- critical: do NOT let Mason manage Julia LS
          mason = false,
          cmd = vim.list_extend({
            "julia",
            "--startup-file=no",
            "--history-file=no",
          }, { vim.fn.stdpath("config") .. "/lua/helpers/julials.jl" }),
          -- keep the same settings as the LazyVim Julia extra
          settings = {
            julia = {
              completionmode = "qualify",
              -- lint = { missingrefs = "none" },
            },
          },
        },
      },
    },
  },
  -- Julia DAP configuration via nvim-dap-julia
  {
    -- https://github.com/kdheepak/nvim-dap-julia/
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "kdheepak/nvim-dap-julia",
        config = function()
          require("nvim-dap-julia").setup()
        end,
      },
    },
  },
  {
    "jmbuhr/otter.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      vim.api.nvim_create_autocmd({ "FileType" }, {
        pattern = { "toml" },
        group = vim.api.nvim_create_augroup("EmbedToml", {}),
        callback = function()
          require("otter").activate()
        end,
      })
    end,
  },
}
