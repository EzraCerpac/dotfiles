return {
  {
    "copilotlsp-nvim/copilot-lsp",
    init = function()
      vim.g.copilot_nes_debounce = 500
      vim.lsp.enable("copilot_ls")
      vim.keymap.set("n", "<tab>", function()
        -- Try to jump to the start of the suggestion edit.
        -- If already at the start, then apply the pending suggestion and jump to the end of the edit.
        local _ = require("copilot-lsp.nes").walk_cursor_start_edit()
          or (require("copilot-lsp.nes").apply_pending_nes() and require("copilot-lsp.nes").walk_cursor_end_edit())
      end)
    end,
    vim.keymap.set("n", "<esc>", function()
      if not require("copilot-lsp.nes").clear() then
        -- fallback to other functionality
      end
    end, { desc = "Clear Copilot suggestion or fallback" }),
  },
  {
    -- https://github.com/aweis89/ai-terminals.nvim
    "aweis89/ai-terminals.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      auto_terminal_keymaps = {
        prefix = "<leader>a",
        terminals = {
          { name = "claude", key = "a" },
          { name = "opencode", key = "o" },
          { name = "codex", key = "c" },
        },
      },
    },
  },
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
