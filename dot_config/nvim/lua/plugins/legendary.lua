return {
  -- https://github.com/mrjones2014/legendary.nvim
  "mrjones2014/legendary.nvim",
  -- since legendary.nvim handles all your keymaps/commands,
  -- its recommended to load legendary.nvim before other plugins
  priority = 10000,
  lazy = false,
  -- sqlite is only needed if you want to use frecency sorting
  dependencies = { "kkharji/sqlite.lua" },
  keys = {
    { "<C-p>", "<cmd>Legendary<cr>", desc = "Legendary Keymaps" },
  },
  config = function()
    require("legendary").setup({
      extensions = {
        lazy_nvim = true,
        smart_splits = {
          directions = { "h", "j", "k", "l" },
          mods = {
            move = "<M>",
            resize = "<C-M>",
          },
        },
      },
      which_key = {
        auto_register = true,
      },
    })
  end,
}
