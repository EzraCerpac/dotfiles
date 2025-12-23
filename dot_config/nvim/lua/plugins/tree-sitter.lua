return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",

      -- Provides `queries/wgsl/*` for highlighting, etc.
      "szebniok/tree-sitter-wgsl",
    },
    opts = function(_, opts)
      local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
      parser_config.wgsl = vim.tbl_deep_extend("force", parser_config.wgsl or {}, {
        install_info = {
          url = "https://github.com/szebniok/tree-sitter-wgsl",
          files = { "src/parser.c", "src/scanner.c" },
        },
        filetype = "wgsl",
      })

      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "latex",
        "typst",
        "wgsl",
      })

      opts.textobjects = opts.textobjects or {}
      opts.textobjects.swap = {
        enable = true,
        swap_next = {
          ["ga"] = "@parameter.inner",
        },
        swap_previous = {
          ["gA"] = "@parameter.inner",
        },
      }
    end,
  },
}
