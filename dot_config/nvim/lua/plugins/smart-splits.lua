---@type LazySpec
return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  opts = function()
    local wezterm_cli = vim.fn.exepath("wezterm")
    if wezterm_cli == "" then
      wezterm_cli = "wezterm"
    end
    return {
      log_level = "warn",
      multiplexer_integration = "wezterm",
      disable_multiplexer_nav_when_zoomed = true,
      wezterm_cli_path = wezterm_cli,
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
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<C-A-h>", require("smart-splits").resize_left)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<C-A-j>", require("smart-splits").resize_down)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<C-A-k>", require("smart-splits").resize_up)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<C-A-l>", require("smart-splits").resize_right)
    -- moving between splits
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<A-h>", require("smart-splits").move_cursor_left)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<A-j>", require("smart-splits").move_cursor_down)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<A-k>", require("smart-splits").move_cursor_up)
    vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, "<A-l>", require("smart-splits").move_cursor_right)
    -- vim.keymap.set({ "n", "i", "v", "x", "s", "o", "t" }, '<C-\\>', require('smart-splits').move_cursor_previous)
    -- swapping buffers between windows
    vim.keymap.set("n", "<leader><leader>h", require("smart-splits").swap_buf_left)
    vim.keymap.set("n", "<leader><leader>j", require("smart-splits").swap_buf_down)
    vim.keymap.set("n", "<leader><leader>k", require("smart-splits").swap_buf_up)
    vim.keymap.set("n", "<leader><leader>l", require("smart-splits").swap_buf_right)
  end,
}
