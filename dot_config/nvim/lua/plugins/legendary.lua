return {
  -- https://github.com/mrjones2014/legendary.nvim
  "mrjones2014/legendary.nvim",
  lazy = true,
  cmd = {
    "Legendary",
    "LegendaryRepeat",
    "LegendaryScratch",
    "LegendaryScratchToggle",
    "LegendaryEvalLine",
    "LegendaryEvalLines",
    "LegendaryEvalBuf",
    "LegendaryApi",
    "LegendaryDeprecated",
    "LegendaryLog",
    "LegendaryFrecencyReset",
    "LegendaryLogLevel",
  },
  -- sqlite is only needed if you want to use frecency sorting
  dependencies = { "kkharji/sqlite.lua" },
  keys = {
    { "<C-p>", "<cmd>Legendary<cr>", desc = "Legendary Keymaps" },
  },
  config = function()
    require("legendary").setup({
      extensions = {
        lazy_nvim = true,
        which_key = {
          auto_register = true,
        },
        smart_splits = {
          directions = { "h", "j", "k", "l" },
          mods = {
            move = "<M>",
            resize = "<C-M>",
          },
        },
      },
    })
  end,
}
