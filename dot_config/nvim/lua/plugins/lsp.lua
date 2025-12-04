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
        julials = {
          -- critical: do NOT let Mason manage Julia LS
          mason = false,
          -- keep the same settings as the LazyVim Julia extra
          settings = {
            julia = {
              completionmode = "qualify",
              lint = { missingrefs = "none" },
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
}
