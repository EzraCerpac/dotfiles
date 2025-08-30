return {
  { -- This plugin
    "Zeioth/compiler.nvim",
    cmd = { "CompilerOpen", "CompilerToggleResults", "CompilerRedo" },
    dependencies = { "stevearc/overseer.nvim", "nvim-telescope/telescope.nvim" },
    opts = {},
    keys = {
      { "<leader>ozo", "<cmd>CompilerOpen<cr>", desc = "Open Compiler" },
      { "<leader>ozr", "<cmd>CompilerRedo<cr>", desc = "Redo Compiler" },
      { "<leader>ozt", "<cmd>CompilerToggleResults<cr>", desc = "Toggle Compiler Results" },
    },
  },
  {
    "benomahony/uv.nvim",
    opts = {
      -- picker_integration = false, -- fails without picker
      keymaps = {
        prefix = "<leader>v",
      },
    },
  },
  -- { -- The task runner we use
  --   "stevearc/overseer.nvim",
  --   commit = "6271cab7ccc4ca840faa93f54440ffae3a3918bd",
  --   cmd = { "CompilerOpen", "CompilerToggleResults", "CompilerRedo" },
  --   opts = {
  --     task_list = {
  --       direction = "bottom",
  --       min_height = 25,
  --       max_height = 25,
  --       default_detail = 1
  --     },
  --   },
  -- },
}
