---@type LazySpec
return {
  "numToStr/Navigator.nvim",
  lazy = false,
  config = function()
    require("Navigator").setup({
      mux = "wezterm",
      auto_save = "current",
      disable_on_zoom = false,
    })
    -- Keymaps are centralized in lua/config/keymaps.lua
  end,
}
