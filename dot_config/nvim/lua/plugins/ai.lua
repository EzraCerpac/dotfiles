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
    opts = {
      adapters = {
        acp = {
          codex = function()
            local cfg = require("codecompanion.adapters").extend("codex")
            -- Use ChatGPT login (requires paid subscription)
            cfg.defaults.auth_method = "chatgpt"
            -- If you don’t have the codex-acp binary installed globally, use npm:
            -- cfg.commands.default = { "npx", "@zed-industries/codex-acp" }
            return cfg
          end,
        },
        copilot = function()
          return require("codecompanion.adapters").extend("copilot", {
            schema = {
              model = {
                default = "gpt-5",
              },
            },
          })
        end,
      },
      strategies = {
        chat = {
          adapter = {
            type = "acp",
            name = "codex",
          },
        },
      },
    },
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "ravitemer/mcphub.nvim" },
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
    config = function()
      require("goose").setup({
        keymap = {
    global = {
      toggle = '<leader>gg',                 -- Open goose. Close if opened
      open_input = '<leader>gi',             -- Opens and focuses on input window on insert mode
      open_input_new_session = '<leader>gI', -- Opens and focuses on input window on insert mode. Creates a new session
      open_output = '<leader>go',            -- Opens and focuses on output window
      toggle_focus = '<leader>gt',           -- Toggle focus between goose and last window
      close = '<leader>gq',                  -- Close UI windows
      toggle_fullscreen = '<leader>gf',      -- Toggle between normal and fullscreen mode
      select_session = '<leader>gs',         -- Select and load a goose session
      goose_mode_chat = '<leader>gmc',       -- Set goose mode to `chat`. (Tool calling disabled. No editor context besides selections)
      goose_mode_auto = '<leader>gma',       -- Set goose mode to `auto`. (Default mode with full agent capabilities)
      configure_provider = '<leader>gp',     -- Quick provider and model switch from predefined list
      diff_open = '<leader>gd',              -- Opens a diff tab of a modified file since the last goose prompt
      diff_next = '<leader>g]',              -- Navigate to next file diff
      diff_prev = '<leader>g[',              -- Navigate to previous file diff
      diff_close = '<leader>gc',             -- Close diff view tab and return to normal editing
      diff_revert_all = '<leader>gra',       -- Revert all file changes since the last goose prompt
      diff_revert_this = '<leader>grt',      -- Revert current file changes since the last goose prompt
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
}
