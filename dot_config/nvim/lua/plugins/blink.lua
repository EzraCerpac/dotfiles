return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      keymap = {
        preset = "enter",
        -- Tab is reserved for tabout.nvim; accept completions with <C-y>
        ["<Tab>"] = "fallback",
        ["<S-Tab>"] = "fallback",
      },
    },
  },
}
