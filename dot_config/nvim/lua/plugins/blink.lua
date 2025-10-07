return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      keymap = {
        preset = "enter",
        -- Explicitly configure Tab to accept Copilot native suggestions
        -- This ensures ai_accept is properly prioritized
        ["<Tab>"] = {
          LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" }),
          "fallback",
        },
        ["<S-Tab>"] = {
          LazyVim.cmp.map({ "snippet_backward" }),
          "fallback",
        },
      },
    },
  },
}
