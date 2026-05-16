return {
  {
    "folke/sidekick.nvim",
    optional = true,
    opts = {
      cli = {
        tools = {
          codex = {},
        },
      },
    },
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
      {
        "<leader>aa",
        function()
          require("sidekick.cli").toggle("codex")
        end,
        desc = "Sidekick Toggle Codex",
      },
      {
        "<leader>at",
        function()
          require("sidekick.cli").send({ name = "codex", msg = "{this}" })
        end,
        mode = { "x", "n" },
        desc = "Send This to Codex",
      },
      {
        "<leader>af",
        function()
          require("sidekick.cli").send({ name = "codex", msg = "{file}" })
        end,
        desc = "Send File to Codex",
      },
      {
        "<leader>av",
        function()
          require("sidekick.cli").send({ name = "codex", msg = "{selection}" })
        end,
        mode = { "x" },
        desc = "Send Selection to Codex",
      },
      {
        "<leader>ap",
        function()
          require("sidekick.cli").prompt({
            cb = function(_, text)
              if text then
                require("sidekick.cli").send({ name = "codex", msg = text })
              end
            end,
          })
        end,
        mode = { "n", "x" },
        desc = "Sidekick Codex Prompt",
      },
    },
  },
}
