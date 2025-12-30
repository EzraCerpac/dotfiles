-- I migrated my custom keymaps config and also the git status config to
-- separate files, as this file was growing too big
-- I also use this file as a centralized place for all the different keymaps,
-- including my custom ones
--
-- Load external modules first
local mini_files_km = require("config.modules.mini-files-km")

-- -- git config is slowing mini.files too much, so disabling it
local mini_files_git = require("config.modules.mini-files-git")

-- for oil.nvim detail toggle
local detail = false

return {
  {
    "nvim-mini/mini.files",
    lazy = false,
    opts = function(_, opts)
      -- I didn't like the default mappings, so I modified them
      -- Module mappings created only inside explorer.
      -- Use `''` (empty string) to not create one.
      opts.mappings = vim.tbl_deep_extend("force", opts.mappings or {}, {
        close = "<esc>",
        -- Use this if you want to open several files
        go_in = "l",
        -- This opens the file, but quits out of mini.files (default L)
        go_in_plus = "<CR>",
        -- I swapped the following 2 (default go_out: h)
        -- go_out_plus: when you go out, it shows you only 1 item to the right
        -- go_out: shows you all the items to the right
        go_out = "H",
        go_out_plus = "h",
        -- Default <BS>
        reset = "<BS>",
        -- Default @
        reveal_cwd = ".",
        show_help = "g?",
        -- Default =
        synchronize = "=",
        trim_left = "<",
        trim_right = ">",

        -- Below, custom mapping opens the highlighted directory in a right-hand
        -- Vim vertical split (no tmux dependency)
      })

      -- Here I define my custom keymaps in a centralized place
      opts.custom_keymaps = {
        -- Open the highlighted directory in a vertical split using Vim windows (no tmux)
        open_split_right = "L",
        copy_to_clipboard = "<space>yy",
        zip_and_copy = "<space>yz",
        paste_from_clipboard = "<space>p",
        copy_path = "<M-c>",
        -- Don't use "i" as it conflicts wit insert mode
        preview_image = "<space>i",
        preview_image_popup = "<M-i>",
      }

      opts.windows = vim.tbl_deep_extend("force", opts.windows or {}, {
        preview = true,
        width_focus = 30,
        width_preview = 80,
      })

      opts.options = vim.tbl_deep_extend("force", opts.options or {}, {
        -- Whether to use for editing directories
        -- Disabled by default in LazyVim because neo-tree is used for that
        use_as_default_explorer = false,
        -- If set to false, files are moved to the trash directory
        -- To get this dir run :echo stdpath('data')
        -- ~/.local/share/neobean/mini.files/trash
        permanent_delete = false,
      })
      return opts
    end,

    keys = {
      {
        -- Open the directory of the file currently being edited
        -- If the file doesn't exist because you maybe switched to a new git branch
        -- open the current working directory
        "<leader>e",
        function()
          local buf_name = vim.api.nvim_buf_get_name(0)
          local dir_name = vim.fn.fnamemodify(buf_name, ":p:h")
          if vim.fn.filereadable(buf_name) == 1 then
            -- Pass the full file path to highlight the file
            require("mini.files").open(buf_name, true)
          elseif vim.fn.isdirectory(dir_name) == 1 then
            -- If the directory exists but the file doesn't, open the directory
            require("mini.files").open(dir_name, true)
          else
            -- If neither exists, fallback to the current working directory
            require("mini.files").open(vim.uv.cwd(), true)
          end
        end,
        desc = "Open mini.files (Directory of Current File or CWD if not exists)",
      },
      -- Open the current working directory
      {
        "<leader>E",
        function()
          require("mini.files").open(vim.uv.cwd(), true)
        end,
        desc = "Open mini.files (cwd)",
      },
    },

    config = function(_, opts)
      -- Set up mini.files
      require("mini.files").setup(opts)
      -- Load custom keymaps
      mini_files_km.setup(opts)

      -- Load Git integration
      -- git config is slowing mini.files too much, so disabling it
      mini_files_git.setup()
    end,
  },
  {
    "stevearc/oil.nvim",
    lazy = false, -- correct
    dependencies = {
      { "nvim-mini/mini.icons", opts = {} },
    },
    ---@module 'oil'
    ---@type oil.SetupOpts
    opts = {
      default_file_explorer = true, -- THIS is the key
      columns = {
        "icon",
        -- "permissions",
        -- "size",
        -- "mtime",
      },
      delete_to_trash = true,
      skip_confirm_for_simple_edits = true,
      view_options = {
        show_hidden = true,
      },
      keymaps = {
        ["H"] = { "actions.parent", mode = "n" },
        ["L"] = { "actions.select", mode = "n" },
        ["<C-v>"] = { "actions.select", opts = { vertical = true } },
        ["gd"] = {
          desc = "Toggle file detail view",
          callback = function()
            detail = not detail
            if detail then
              require("oil").set_columns({ "icon", "permissions", "size", "mtime" })
            else
              require("oil").set_columns({ "icon" })
            end
          end,
        },
      },
    },
    keys = {
      { "-", "<CMD>Oil<CR>", desc = "Open parent directory" },
    },
  },
  {
    -- https://github.com/JezerM/oil-lsp-diagnostics.nvim
    "JezerM/oil-lsp-diagnostics.nvim",
    dependencies = { "stevearc/oil.nvim" },
    opts = {},
  },
  {
    -- https://github.com/benomahony/oil-git.nvim
    "benomahony/oil-git.nvim",
    dependencies = { "stevearc/oil.nvim" },
  },
}
