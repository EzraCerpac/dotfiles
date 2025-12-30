return {
  { "MunifTanjim/nui.nvim", lazy = true },
  {
    "j-hui/fidget.nvim",
    event = "LSPAttach",
    opts = {
      -- options
    },
  },
  {
    -- https://github.com/HiPhish/rainbow-delimiters.nvim
    "HiPhish/rainbow-delimiters.nvim",
    event = "VeryLazy",
  },
}
