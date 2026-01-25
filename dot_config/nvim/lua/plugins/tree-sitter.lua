return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "latex",
        "typst",
        "python",
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
