return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    opts = {
      ensure_installed = {
        "latex",
        "typst",
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    config = function()
      require("nvim-treesitter.configs").setup({
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
      })
    end,
  },
}
