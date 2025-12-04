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
  -- Julia DAP configuration
  {
    "mfussenegger/nvim-dap",
    opts = function()
      local dap = require("dap")

      -- Julia debug adapter using DebugAdapter.jl
      -- Requires: Pkg.add("DebugAdapter") in Julia
      dap.adapters.julia = {
        type = "server",
        port = "${port}",
        executable = {
          command = "julia",
          args = {
            "--startup-file=no",
            "--history-file=no",
            "-e",
            [[
              using DebugAdapter
              DebugAdapter.run_debugger(; port=]] .. "${port}" .. [[)
            ]],
          },
        },
      }

      dap.configurations.julia = {
        {
          type = "julia",
          request = "launch",
          name = "Launch Julia file",
          program = "${file}",
          projectDir = "${workspaceFolder}",
          juliaEnv = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          type = "julia",
          request = "launch",
          name = "Launch Julia file (stop on entry)",
          program = "${file}",
          projectDir = "${workspaceFolder}",
          juliaEnv = "${workspaceFolder}",
          stopOnEntry = true,
        },
      }
    end,
  },
}
