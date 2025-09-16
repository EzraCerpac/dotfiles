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
    local function clear_lazyvim_move()
      for _, lhs in ipairs({ "<A-j>", "<A-k>" }) do
        for _, mode in ipairs({ "n", "i", "v", "x" }) do
          if vim.fn.maparg(lhs, mode) ~= "" then
            pcall(vim.keymap.del, mode, lhs)
          end
        end
      end
    end
    clear_lazyvim_move()
    vim.schedule(clear_lazyvim_move)
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyVimKeymaps",
      callback = clear_lazyvim_move,
    })
    local all_modes = { "n", "i", "v", "x", "s", "o", "t" }
    -- these keymaps will also accept a range,
    -- for example `10<A-h>` will `resize_left` by `(10 * config.default_amount)`
    vim.keymap.set(all_modes, "<C-A-h>", require("smart-splits").resize_left)
    vim.keymap.set(all_modes, "<C-A-j>", require("smart-splits").resize_down)
    vim.keymap.set(all_modes, "<C-A-k>", require("smart-splits").resize_up)
    vim.keymap.set(all_modes, "<C-A-l>", require("smart-splits").resize_right)
    -- moving between splits
    vim.keymap.set(all_modes, "<A-h>", require("smart-splits").move_cursor_left, { remap = true })
    vim.keymap.set(all_modes, "<A-j>", require("smart-splits").move_cursor_down, { remap = true })
    vim.keymap.set(all_modes, "<A-k>", require("smart-splits").move_cursor_up, { remap = true })
    vim.keymap.set(all_modes, "<A-l>", require("smart-splits").move_cursor_right, { remap = true })
    -- vim.keymap.set(all_modes, '<C-\\>', require('smart-splits').move_cursor_previous)
    -- swapping buffers between windows
    vim.keymap.set("n", "<leader><leader>h", require("smart-splits").swap_buf_left)
    vim.keymap.set("n", "<leader><leader>j", require("smart-splits").swap_buf_down)
    vim.keymap.set("n", "<leader><leader>k", require("smart-splits").swap_buf_up)
    vim.keymap.set("n", "<leader><leader>l", require("smart-splits").swap_buf_right)
  end,
}
