---@type LazySpec
return {
  "numToStr/Navigator.nvim",
  lazy = false,
  config = function()
    require("Navigator").setup({
      mux = "auto",
      auto_save = "current",
      disable_on_zoom = false,
    })
    -- Keymaps are centralized in lua/config/keymaps.lua
  end,
}
