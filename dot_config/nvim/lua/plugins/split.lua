return {
  "Wansmer/treesj",
  event = "VeryLazy",
  dependencies = { "nvim-treesitter/nvim-treesitter" }, -- if you install parsers with `nvim-treesitter`

  config = function()
    require("treesj").setup({
      use_default_keymaps = false,
    })

    local langs = require("treesj.langs")["presets"]

    vim.api.nvim_create_autocmd({ "FileType" }, {
      pattern = "*",
      callback = function()
        local opts = { buffer = true }
        if langs[vim.bo.filetype] then
          vim.keymap.set("n", "gt", require("treesj").toggle)
          vim.keymap.set("n", "gT", function()
            require("treesj").toggle({ split = { recursive = true } })
          end)
          vim.keymap.set("n", "gS", require("treesj").split)
          vim.keymap.set("n", "gJ", require("treesj").join)
        else
          vim.keymap.set("n", "gS", "<Cmd>SplitjoinSplit<CR>", opts)
          vim.keymap.set("n", "gJ", "<Cmd>SplitjoinJoin<CR>", opts)
        end
      end,
    })
  end,
}
