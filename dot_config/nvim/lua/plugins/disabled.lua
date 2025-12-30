return {
  { "akinsho/bufferline.nvim", enabled = false },
  { "ggandor/leap.nvim", enabled = false },
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        hijack_netrw_behavior = "disabled", -- prevent neo-tree from hijacking directory opens
      },
    },
  },
  -- Temporarily disable experimental Copilot LSP while debugging NVIM 0.12-dev LSP issues
  { "copilotlsp-nvim/copilot-lsp", enabled = false },
}
