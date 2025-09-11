return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "latex",
        "typst",
      },
      textobjects = {
        swap = {
          enable = true,
          swap_next = {
            ["ga"] = "@parameter.inner",
          },
          swap_previous = {
            ["gA"] = "@parameter.inner",
          },
        },
      },
    },
  },
}
