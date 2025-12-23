return {
  -- {
  --   "copilotlsp-nvim/copilot-lsp",
  --   init = function()
  --     vim.g.copilot_nes_debounce = 500
  --     vim.lsp.enable("copilot_ls")
  --     vim.keymap.set("n", "<tab>", function()
  --       local bufnr = vim.api.nvim_get_current_buf()
  --       local state = vim.b[bufnr].nes_state
  --       if state then
  --         -- Try to jump to the start of the suggestion edit.
  --         -- If already at the start, then apply the pending suggestion and jump to the end of the edit.
  --         local _ = require("copilot-lsp.nes").walk_cursor_start_edit()
  --           or (require("copilot-lsp.nes").apply_pending_nes() and require("copilot-lsp.nes").walk_cursor_end_edit())
  --         return nil
  --       else
  --         -- Resolving the terminal's inability to distinguish between `TAB` and `<C-i>` in normal mode
  --         return "<C-i>"
  --       end
  --     end, { desc = "Accept Copilot NES suggestion", expr = true })
  --     -- Clear copilot suggestion with Esc if visible, otherwise preserve default Esc behavior
  --     vim.keymap.set("n", "<esc>", function()
  --       ---@diagnostic disable-next-line: empty-block
  --       if not require("copilot-lsp.nes").clear() then
  --         -- fallback to other functionality
  --       end
  --     end, { desc = "Clear Copilot suggestion or fallback" })
  --   end,
  -- },
  {
    "olimorris/codecompanion.nvim",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "ravitemer/mcphub.nvim" },
    },
    opts = {
      adapters = {
        acp = {
opencode = function()
                return require("codecompanion.adapters").extend("opencode", {
                    commands = {
                        default = {
                            "opencode", "acp"
                        },
                        sonnet_4_5 = {
                            "opencode", "acp", "-m", "github-copilot/claude-sonnet-4.5"
                        },
                        opus_4_5 = {
                            "opencode", "acp", "-m", "github-copilot/claude-opus-4.5"
                        },
                        gpt_5_2 = {
                            "opencode", "acp", "-m", "github-copilot/gpt-5.2"
                        }
                    },
                })
            end,
      --     codex = function()
      --       local cfg = require("codecompanion.adapters").extend("codex")
      --       -- Use ChatGPT login (requires paid subscription)
      --       cfg.defaults.auth_method = "chatgpt"
      --       -- If you don’t have the codex-acp binary installed globally, use npm:
      --       -- cfg.commands.default = { "npx", "@zed-industries/codex-acp" }
      --       return cfg
      --     end,
      --   },
      --   copilot = function()
      --     return require("codecompanion.adapters").extend("copilot", {
      --       schema = {
      --         model = {
      --           default = "gpt-5.1-codex",
      --         },
      --       },
      --     })
      --   end,
      -- },
      strategies = {
        chat = {
          adapter = {
            name = "opencode",
          },
          -- adapter = {
          --   type = "acp",
          --   name = "codex",
          -- },
        },
      },
    },
    config = function()
      require("codecompanion").setup({
        extensions = {
          mcphub = {
            callback = "mcphub.extensions.codecompanion",
            opts = {
              make_vars = true,
              make_slash_commands = true,
              show_result_in_chat = true,
            },
          },
        },
      })
      vim.keymap.set(
        { "n", "v" },
        "<LocalLeader>a",
        "<cmd>CodeCompanionChat Toggle<cr>",
        { noremap = true, silent = true }
      )
      vim.keymap.set("v", "<LocalLeader>ca", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })
      vim.cmd([[cab cc CodeCompanion]])
      vim.g.codecompanion_yolo_mode = true
      local progress = require("fidget.progress")
      local handles = {}
      local group = vim.api.nvim_create_augroup("CodeCompanionFidget", {})
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeCompanionRequestStarted",
        callback = function(e)
          handles[e.data.id] = progress.handle.create({
            title = "CodeCompanion",
            message = "Thinking...",
            lsp_client = { name = e.data.adapter.formatted_name },
          })
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeCompanionRequestFinished",
        callback = function(e)
          local h = handles[e.data.id]
          if h then
            h.message = e.data.status == "success" and "Done" or "Failed"
            h:finish()
            handles[e.data.id] = nil
          end
        end,
      })
    end,
  },
  {
    "ravitemer/mcphub.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    build = "npm install -g mcp-hub@latest", -- Installs `mcp-hub` node binary globally
    config = function()
      require("mcphub").setup()
    end,
  },
  {
    "azorng/goose.nvim",
    event = "VeryLazy",
    config = function()
      require("goose").setup({
        keymap = {
          global = {
            toggle = "<leader>ag", -- Open goose. Close if opened
            open_input = "<leader>ai", -- Opens and focuses on input window on insert mode
            open_input_new_session = "<leader>aI", -- Opens and focuses on input window on insert mode. Creates a new session
            open_output = "<leader>ao", -- Opens and focuses on output window
            toggle_focus = "<leader>at", -- Toggle focus between goose and last window
            close = "<leader>aq", -- Close UI windows
            toggle_fullscreen = "<leader>af", -- Toggle between normal and fullscreen mode
            select_session = "<leader>as", -- Select and load a goose session
            goose_mode_chat = "<leader>amc", -- Set goose mode to `chat`. (Tool calling disabled. No editor context besides selections)
            goose_mode_auto = "<leader>ama", -- Set goose mode to `auto`. (Default mode with full agent capabilities)
            configure_provider = "<leader>ap", -- Quick provider and model switch from predefined list
            diff_open = "<leader>ad", -- Opens a diff tab of a modified file since the last goose prompt
            diff_next = "<leader>a]", -- Navigate to next file diff
            diff_prev = "<leader>a[", -- Navigate to previous file diff
            diff_close = "<leader>ac", -- Close diff view tab and return to normal editing
            diff_revert_all = "<leader>ara", -- Revert all file changes since the last goose prompt
            diff_revert_this = "<leader>art", -- Revert current file changes since the last goose prompt
          },
        },
      })
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          anti_conceal = { enabled = false },
        },
      },
    },
  },
  {
    -- https://github.com/piersolenski/wtf.nvim
    "piersolenski/wtf.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      -- Optional: For WtfGrepHistory (pick one)
      -- "nvim-telescope/telescope.nvim",
      -- "folke/snacks.nvim",
      "ibhagwan/fzf-lua",
    },
    opts = {
      provider = "copilot",
      providers = {
        copilot = {
          model_id = "claude-sonnet-4.5",
        },
      },
    },
    keys = {
      {
        "<localLeader>wd",
        mode = { "n", "x" },
        function()
          require("wtf").diagnose()
        end,
        desc = "Debug diagnostic with AI",
      },
      {
        "<localLeader>wf",
        mode = { "n", "x" },
        function()
          require("wtf").fix()
        end,
        desc = "Fix diagnostic with AI",
      },
      {
        mode = { "n" },
        "<localLeader>ws",
        function()
          require("wtf").search()
        end,
        desc = "Search diagnostic with Google",
      },
      {
        mode = { "n" },
        "<localLeader>wp",
        function()
          require("wtf").pick_provider()
        end,
        desc = "Pick provider",
      },
      {
        mode = { "n" },
        "<localLeader>wh",
        function()
          require("wtf").history()
        end,
        desc = "Populate the quickfix list with previous chat history",
      },
      {
        mode = { "n" },
        "<localLeader>wg",
        function()
          require("wtf").grep_history()
        end,
        desc = "Grep previous chat history with fzf-lua",
      },
    },
  },
}
