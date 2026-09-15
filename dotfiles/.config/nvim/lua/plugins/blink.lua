return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      keymap = {
        preset = "enter",
        -- Tab is not used for completions; accept with <C-y>
        ["<Tab>"] = false,
        ["<S-Tab>"] = false,
      },
      sources = {
        per_filetype = {
          codecompanion = {
            "codecompanion",
            "buffer",
          },
        },
      },
    },
  },
}

