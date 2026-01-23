return {
  {
    "stevearc/conform.nvim",
    optional = true,
    dependencies = { "mason.nvim" },
    opts = {
      formatters_by_ft = {
        python = { "ruff_format" },
        json = { "biome" },
        javascript = { "biome", stop_after_first = true },
        julia = { "runic" },
        tex = { "latexindent" },
        typescriptreact = { "biome", stop_after_first = true },
        typescript = { "biome", stop_after_first = true },
        typst = { "typstyle" },
        rust = { "rustfmt" },
        ["_"] = { "trim_whitespace" },
      },
      formatters = {
        runic = {
          command = "julia",
          args = {
            "--project=@runic",
            "-e",
            [[
          using Runic
          exit(Runic.main(ARGS))
        ]],
            "--",
            "--check",
            "--diff",
            "$FILENAME",
          },
          stdin = false,
        },
        ["markdownlint-cli2"] = {
          args = {
            "--config",
            vim.fn.expand("$HOME/.markdownlint-cli2.yaml"),
            "--fix",
            "$FILENAME",
          },
        },
      },
    },
  },
  {
    -- BUG: Not working I believe
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = {
            "--config",
            vim.fn.expand("$HOME/.markdownlint-cli2.yaml"),
            -- "--rules",
            -- "sentences-per-line",
            "--",
          },
        },
      },
    },
  },
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        "luvit-meta/library",
      },
    },
  },
}
