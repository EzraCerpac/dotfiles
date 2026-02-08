return {
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 500, -- ms before showing blame
        virt_text = true,
        virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
      },
      current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> • <summary>",
    },
  },
  {
    "kdheepak/lazygit.nvim",
    enabled = false,
  },
  {
    "NeogitOrg/neogit",
    enabled = false,
    dependencies = {
      "nvim-lua/plenary.nvim", -- required
      "sindrets/diffview.nvim", -- optional - Diff integration
    },
    opts = {
      -- process_spinner = true,
      graph_style = "kitty",
      signs = {
        -- { CLOSED, OPENED }
        hunk = { "", "" },
        item = { "+", "-" },
        section = { "+", "-" },
      },
    },
    keys = {
      {
        "<leader>gg",
        function()
          local neogit = require("neogit")
          neogit.open({ kind = "tab" })
        end,
        desc = "neogit open",
      },
    },
  },
}
