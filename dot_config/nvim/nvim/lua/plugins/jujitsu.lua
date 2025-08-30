return {
  {
    "julienvincent/hunk.nvim",
    cmd = { "DiffEditor" }, -- lazy-load on first use
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      picker = "telescope", -- reasonable defaults
      signs = { add = "+", delete = "-", change = "~" },
    },
  },
  -- Use jjui.nvim to toggle jjui in a floating terminal
  {
    "ReKylee/jjui.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Ensure jjui is on PATH
      executable = "jjui",
      -- Faster startup by skipping shell profiles
      fast_shell = true,
      -- Editor used by jj for interactive commands
      editor = "nvim",
      -- Map <leader>gj to toggle JJUI
      keymaps = { toggle = "<leader>gj" },
      -- Delegate window look & feel to snacks.nvim (optional defaults)
      terminal_opts = {
        win = { title = "Jujutsu UI", border = "rounded", width = 0.9, height = 0.9 },
      },
    },
  },
}
