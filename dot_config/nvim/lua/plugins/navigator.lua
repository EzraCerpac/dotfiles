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

    local map = vim.keymap.set
    local opts = { silent = true, noremap = true }

    -- Alt/meta hjkl in normal and terminal modes
    map({ "n", "t" }, "<A-h>", require("Navigator").left, vim.tbl_extend("force", opts, { desc = "Navigator left" }))
    map({ "n", "t" }, "<A-j>", require("Navigator").down, vim.tbl_extend("force", opts, { desc = "Navigator down" }))
    map({ "n", "t" }, "<A-k>", require("Navigator").up, vim.tbl_extend("force", opts, { desc = "Navigator up" }))
    map({ "n", "t" }, "<A-l>", require("Navigator").right, vim.tbl_extend("force", opts, { desc = "Navigator right" }))
  end,
}

