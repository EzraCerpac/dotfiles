return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      keymap = {
        preset = "enter",
        -- Tab is reserved for sidekick NES + tabout.nvim; accept completions with <C-y>
        ["<Tab>"] = false,
        ["<S-Tab>"] = false,
      },
    },
  },
}
