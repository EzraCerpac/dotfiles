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
            name = "copilot",
            model = "gpt-5",
          },
        },
        completion = {
          adapter = {
            name = "copilot",
            model = "gpt-5-mini",
          },
        },
        inline = {
          adapter = {
            name = "copilot",
            model = "gpt-5",
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
      vim.keymap.set("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })
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
  -- {
  --   -- https://github.com/aweis89/ai-terminals.nvim
  --   "aweis89/ai-terminals.nvim",
  --   dependencies = { "folke/snacks.nvim" },
  --   opts = {
  --     auto_terminal_keymaps = {
  --       prefix = "<leader>at",
  --       terminals = {
  --         { name = "claude", key = "a" },
  --         { name = "opencode", key = "o" },
  --         { name = "codex", key = "c" },
  --       },
  --     },
  --     terminals = {
  --       codex = {
  --         cmd = function()
  --           return "codex --search --full-auto"
  --         end,
  --         path_header_template = "@%s", -- Default: @ prefix
  --       },
  --     },
  --     watch_cwd = {
  --       enabled = false, -- Gives buff changed messages all the time
  --       ignore = {
  --         "**/.git/**",
  --         "**/node_modules/**",
  --         "**/.venv/**",
  --         "**/*.log",
  --       },
  --       -- Also merge ignore rules from <git root>/.gitignore
  --       -- Negations (!) are supported; patterns are evaluated relative to repo root
  --       gitignore = true,
  --     },
  --     trigger_formatting = { enabled = true },
  --   },
  -- },
  -- {
  --   "NickvanDyke/opencode.nvim",
  --   dependencies = {
  --     "folke/snacks.nvim",
  --   },
  --   ---@type opencode.Config
  --   opts = {
  --     -- You can add custom prompts or contexts here later, e.g.:
  --     -- prompts = { },
  --     -- contexts = { },
  --   },
  -- -- stylua: ignore
  -- keys = {
  --   { "<leader>Ot", function() require("opencode").toggle() end, desc = "Toggle embedded opencode" },
  --   { "<leader>Oa", function() require("opencode").ask("@cursor: ") end, desc = "Ask opencode", mode = "n" },
  --   { "<leader>Oa", function() require("opencode").ask("@selection: ") end, desc = "Ask opencode about selection", mode = "v" },
  --   { "<leader>Op", function() require("opencode").select_prompt() end, desc = "Select prompt", mode = { "n", "v" } },
  --   { "<leader>On", function() require("opencode").command("session_new") end, desc = "New session" },
  --   { "<leader>Oy", function() require("opencode").command("messages_copy") end, desc = "Copy last message" },
  --   { "<S-C-u>",    function() require("opencode").command("messages_half_page_up") end,   desc = "Scroll messages up" },
  --   { "<S-C-d>",    function() require("opencode").command("messages_half_page_down") end, desc = "Scroll messages down" },
  -- },
  -- },
}
