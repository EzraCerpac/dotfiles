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
  end,
}
