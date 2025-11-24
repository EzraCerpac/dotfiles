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
  -- { "rafikdraoui/jj-diffconflicts" },
  -- Use jjui.nvim to toggle jjui in a floating terminal
  {
    "ReKylee/jjui.nvim",
    cmd = { "JJUI" },
    keys = {
      { "<leader>jj", "<cmd>JJUI<cr>", desc = "Toggle JJUI" },
    },
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Ensure jjui is on PATH
      executable = "jjui",
      -- Faster startup by skipping shell profiles
      fast_shell = true,
      -- Editor used by jj for interactive commands
      editor = "nvim",
      -- Map <leader>jj to toggle JJUI
      keymaps = { toggle = "<leader>jj" },
      -- Delegate window look & feel to snacks.nvim (optional defaults)
      terminal_opts = {
        win = { title = "Jujutsu UI", border = "rounded", width = 0.9, height = 0.9 },
      },
    },
  },
  {
    -- https://github.com/NicolasGB/jj.nvim
    "nicolasgb/jj.nvim",
    dependencies = {
      "folke/snacks.nvim", -- Optional only if you use picker's
    },

    config = function()
      local jj = require("jj")
      local jj_cmd = require("jj.cmd")
      local jj_diff = require("jj.diff")
      local jj_picker = require("jj.picker")

      jj.setup({
        cmd = {
          describe = {
            editor = {
              type = "buffer",
              keymaps = {
                close = { "q", "<Esc>", "<C-c>" },
              },
            },
          },
          keymaps = {
            log = {
              checkout = "<CR>",
              describe = "d",
              diff = "<S-d>",
            },
            status = {
              open_file = "<CR>",
              restore_file = "<S-x>",
            },
            close = { "q", "<Esc>" },
          },
        },
      })

      -- Core commands
      vim.keymap.set("n", "<leader>jd", jj_cmd.describe, { desc = "JJ describe" })
      vim.keymap.set("n", "<leader>jl", jj_cmd.log, { desc = "JJ log" })
      vim.keymap.set("n", "<leader>je", jj_cmd.edit, { desc = "JJ edit" })
      vim.keymap.set("n", "<leader>jn", jj_cmd.new, { desc = "JJ new" })
      vim.keymap.set("n", "<leader>js", jj_cmd.status, { desc = "JJ status" })
      vim.keymap.set("n", "<leader>jS", jj_cmd.squash, { desc = "JJ squash" })
      vim.keymap.set("n", "<leader>ju", jj_cmd.undo, { desc = "JJ undo" })
      vim.keymap.set("n", "<leader>jy", jj_cmd.redo, { desc = "JJ redo" })
      vim.keymap.set("n", "<leader>jr", jj_cmd.rebase, { desc = "JJ rebase" })
      vim.keymap.set("n", "<leader>jb", jj_cmd.bookmark_create, { desc = "JJ bookmark create" })
      vim.keymap.set("n", "<leader>jB", jj_cmd.bookmark_delete, { desc = "JJ bookmark delete" })

      -- Diff commands
      vim.keymap.set("n", "<leader>jv", jj_diff.open_vdiff, { desc = "JJ diff vertical" })
      vim.keymap.set("n", "<leader>jh", jj_diff.open_hdiff, { desc = "JJ diff horizontal" })

      -- Pickers
      vim.keymap.set("n", "<leader>jp", jj_picker.status, { desc = "JJ Picker status" })
      vim.keymap.set("n", "<leader>jH", jj_picker.file_history, { desc = "JJ Picker file history" })

      -- Some functions like `log` can take parameters
      vim.keymap.set("n", "<leader>jL", function()
        jj_cmd.log({
          revisions = "'all()'", -- equivalent to jj log -r ::
        })
      end, { desc = "JJ log all" })

      -- This is an alias i use for moving bookmarks its so good
      vim.keymap.set("n", "<leader>jt", function()
        jj_cmd.j("tug")
        jj_cmd.log({})
      end, { desc = "JJ tug" })
    end,
  },
}
