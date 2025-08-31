local HOME = os.getenv("HOME")
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
        tex = { "latexindent" },
        typescriptreact = { "biome", stop_after_first = true },
        typescript = { "biome", stop_after_first = true },
        ["_"] = { "trim_whitespace" },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = {
            "--config",
            HOME .. "/.markdownlint.toml",
            "--rules",
            "sentences-per-line",
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
