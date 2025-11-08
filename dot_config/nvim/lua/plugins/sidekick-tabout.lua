return {
  {
    "folke/sidekick.nvim",
    optional = true,
    keys = {
      {
        "<Tab>",
        function()
          local ok, Nes = pcall(require, "sidekick.nes")
          if ok and Nes.have() and (Nes.jump() or Nes.apply()) then
            return ""
          end
          return vim.api.nvim_replace_termcodes("<Plug>(Tabout)", true, true, true)
        end,
        mode = "i",
        expr = true,
        silent = true,
        desc = "NES accept or Tabout",
      },
      {
        "<S-Tab>",
        function()
          return vim.api.nvim_replace_termcodes("<Plug>(TaboutBack)", true, true, true)
        end,
        mode = "i",
        expr = true,
        silent = true,
        desc = "TaboutBack",
      },
    },
  },
}
