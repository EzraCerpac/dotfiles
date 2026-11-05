return {
  { "MunifTanjim/nui.nvim", lazy = true },
  {
    "sphamba/smear-cursor.nvim",
    opts = {
      stiffness = 0.8,
      trailing_stiffness = 0.6,
      stiffness_insert_mode = 0.7,
      trailing_stiffness_insert_mode = 0.7,
      damping = 0.95,
      damping_insert_mode = 0.95,
      distance_stop_animating = 0.5,
    },
  },
  {
    "nvim-mini/mini.animate",
    opts = function(_, opts)
      opts.scroll.timing = require("mini.animate").gen_timing.linear({ duration = 75, unit = "total" })
    end,
  },
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
