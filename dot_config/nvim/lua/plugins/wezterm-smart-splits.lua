---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false, -- ensure user-var is set for WezTerm immediately
  config = function()
    require("smart-splits").setup({
      log_level = "warn",
      multiplexer_integration = "wezterm",
      at_edge = "wrap", -- or "stop" if you prefer no wrap-around
    })

    local ss = require("smart-splits")
    local map = vim.keymap.set
    local opts = { silent = true, noremap = true }

    -- Alt/meta + hjkl to move between splits; at edge, fall through to WezTerm pane
    map("n", "<M-h>", ss.move_cursor_left, vim.tbl_extend("force", opts, { desc = "Move left (smart-splits)" }))
    map("n", "<M-j>", ss.move_cursor_down, vim.tbl_extend("force", opts, { desc = "Move down (smart-splits)" }))
    map("n", "<M-k>", ss.move_cursor_up, vim.tbl_extend("force", opts, { desc = "Move up (smart-splits)" }))
    map("n", "<M-l>", ss.move_cursor_right, vim.tbl_extend("force", opts, { desc = "Move right (smart-splits)" }))
  end,
}
