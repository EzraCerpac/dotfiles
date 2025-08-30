return {
  "doctorfree/cheatsheet.nvim",
  event = "VeryLazy",
  dependencies = {
    { "nvim-telescope/telescope.nvim" },
    { "nvim-lua/popup.nvim" },
    { "nvim-lua/plenary.nvim" },
  },
  config = function()
    local ctactions = require("cheatsheet.telescope.actions")
    require("cheatsheet").setup({
      -- Enable bundled cheatsheets for general use
      bundled_cheatsheets = {
        enabled = { 
          "default", 
          "lua", 
          "markdown", 
          "regex", 
          "netrw", 
          "unicode", 
          "python",
          "rust",
          "javascript",
          "typescript",
          "css",
          "html",
          "json",
          "yaml",
          "sql",
          "bash",
          "git",
          "tmux",
          "vim"
        },
        disabled = { "nerd-fonts" }, -- Disable nerd-fonts as it's very large
      },
      -- Enable plugin-specific cheatsheets for installed plugins
      bundled_plugin_cheatsheets = {
        enabled = {
          "gitsigns.nvim",
          "telescope.nvim",
          "nvim-treesitter",
          "bufferline.nvim",
          "mason.nvim",
          "conform.nvim",
          "trouble.nvim",
          "flash.nvim",
          "yanky.nvim",
          "todo-comments.nvim",
          "persistence.nvim",
          "neotest",
          "which-key.nvim",
          "render-markdown.nvim",
          "vimtex",
        },
        disabled = {},
      },
      -- Only show cheatsheets for plugins that are actually installed
      include_only_installed_plugins = true,
      -- Telescope key mappings
      telescope_mappings = {
        ["<CR>"] = ctactions.select_or_fill_commandline, -- Fill command line on Enter
        ["<A-CR>"] = ctactions.select_or_execute,        -- Execute directly with Alt-Enter
        ["<C-Y>"] = ctactions.copy_cheat_value,          -- Copy cheat value
        ["<C-E>"] = ctactions.edit_user_cheatsheet,      -- Edit user cheatsheet
      },
    })
  end,
  keys = {
    { "<leader>?", "<cmd>Cheatsheet<CR>", desc = "Open cheatsheet" },
    { "<leader>ce", "<cmd>CheatsheetEdit<CR>", desc = "Edit user cheatsheet" },
  },
}
