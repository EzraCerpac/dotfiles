---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  -- https://github.com/mrjones2014/smart-splits.nvim?tab=readme-ov-file
  lazy = false,
  opts = function()
    -- local wezterm_cli = vim.fn.exepath("wezterm")
    -- if wezterm_cli == "" then
    --   wezterm_cli = "wezterm"
    -- end
    return {
      multiplexer_integration = "wezterm",
      disable_multiplexer_nav_when_zoomed = true,
      -- wezterm_cli_path = wezterm_cli,
      default_amount = 5, -- default is 3
      float_win_behavior = "mux",
    }
  end,
  config = function(_, opts)
    local smart_splits = require("smart-splits")
    smart_splits.setup(opts)
    -- Ensure WezTerm user vars are kept in sync for smart navigation
    require("smart-splits.mux.utils").startup()

    local all_modes = { "n", "i", "v", "x", "s", "o", "t" }
    -- these keymaps will also accept a range,
    -- for example `10<A-h>` will `resize_left` by `(10 * config.default_amount)`
    vim.keymap.set(all_modes, "<C-M-h>", require("smart-splits").resize_left)
    vim.keymap.set(all_modes, "<C-M-j>", require("smart-splits").resize_down)
    vim.keymap.set(all_modes, "<C-M-k>", require("smart-splits").resize_up)
    vim.keymap.set(all_modes, "<C-M-l>", require("smart-splits").resize_right)
    -- moving between splits
    vim.keymap.set(all_modes, "<M-h>", require("smart-splits").move_cursor_left, { remap = true })
    vim.keymap.set(all_modes, "<M-j>", require("smart-splits").move_cursor_down, { remap = true })
    vim.keymap.set(all_modes, "<M-k>", require("smart-splits").move_cursor_up, { remap = true })
    vim.keymap.set(all_modes, "<M-l>", require("smart-splits").move_cursor_right, { remap = true })
    -- vim.keymap.set(all_modes, '<C-\\>', require('smart-splits').move_cursor_previous)
    -- swapping buffers between windows
    vim.keymap.set("n", "<leader><leader>h", require("smart-splits").swap_buf_left)
    vim.keymap.set("n", "<leader><leader>j", require("smart-splits").swap_buf_down)
    vim.keymap.set("n", "<leader><leader>k", require("smart-splits").swap_buf_up)
    vim.keymap.set("n", "<leader><leader>l", require("smart-splits").swap_buf_right)
  end,
}
