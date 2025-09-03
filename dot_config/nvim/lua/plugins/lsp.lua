local transparency = vim.g.neovide and 45 or 0

return {
  {
    "jinzhongjia/LspUI.nvim",
    branch = "main",
    -- Ensure LspUI registers its user commands by calling setup
    -- Lazy.nvim won't auto-call setup from just `opts`, so wire it explicitly.
    event = "VeryLazy",
    main = "LspUI",
    config = true,
    opts = {
      hover = {
        transparency = transparency,
      },
      rename = {
        transparency = transparency,
      },
      code_action = {
        transparency = transparency,
      },
      diagnostic = {
        transparency = transparency,
      },
      pos_keybind = {
        transparency = transparency,
      },
      signature = {
        enable = true,
      },
      inlay_hint = {
        enable = true,
      },
    },
    keys = {
      { "K", "<cmd>LspUI hover<CR>", desc = "LSP Hover" },
      { "gr", "<cmd>LspUI reference<CR>", desc = "LSP References" },
      { "gd", "<cmd>LspUI definition<CR>", desc = "LSP Definition" },
      -- { "gt", "<cmd>LspUI type_definition<CR>", desc = "LSP Type Definition" },  -- used for Treesj toggle
      { "gi", "<cmd>LspUI implementation<CR>", desc = "LSP Implementation" },
      { "<leader>rn", "<cmd>LspUI rename<CR>", desc = "LSP Rename" },
      { "<leader>ca", "<cmd>LspUI code_action<CR>", desc = "LSP Code Action" },
      { "[d", "<cmd>LspUI diagnostic prev<cr>", desc = "LspUI diagnostic prev" },
      { "]d", "<cmd>LspUI diagnostic next<cr>", desc = "LspUI diagnostic next" },
      { "<leader>ci", "<cmd>LspUI call_hierarchy incoming_calls<CR>", desc = "LSP Incoming Calls" },
      { "<leader>co", "<cmd>LspUI call_hierarchy outgoing_calls<CR>", desc = "LSP Outgoing Calls" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local keys = require("lazyvim.plugins.lsp.keymaps").get()
      local function map(lhs, rhs, desc)
        keys[#keys + 1] = { lhs, rhs, desc = desc }
      end

      -- Disable LazyVim's conflicting defaults
      for _, lhs in ipairs({ "K", "gd", "gr", "gi", "gt", "[d", "]d", "<leader>ca", "<leader>rn" }) do
        keys[#keys + 1] = { lhs, false }
      end

      -- -- Rebind to LspUI
      -- map("K", "<cmd>LspUI hover<CR>", "LSP Hover (LspUI)")
      -- map("gd", "<cmd>LspUI definition<CR>", "LSP Definition (LspUI)")
      -- map("gr", "<cmd>LspUI reference<CR>", "LSP References (LspUI)")
      -- map("gi", "<cmd>LspUI implementation<CR>", "LSP Implementation (LspUI)")
      -- map("[d", "<cmd>LspUI diagnostic prev<CR>", "Prev Diagnostic (LspUI)")
      -- map("]d", "<cmd>LspUI diagnostic next<CR>", "Next Diagnostic (LspUI)")
      -- map("<leader>rn", "<cmd>LspUI rename<CR>", "LSP Rename (LspUI)")
      -- map("<leader>ca", "<cmd>LspUI code_action<CR>", "LSP Code Action (LspUI)")
      --
      -- Prefer LspUI hints over core inlay_hints
      opts.inlay_hints = opts.inlay_hints or {}
      opts.inlay_hints.enabled = false
      -- Optional: prefer LspUI diagnostics popups over inline text
      opts.diagnostics = opts.diagnostics or {}
      opts.diagnostics.virtual_text = false

      return opts
    end,
  },
}
