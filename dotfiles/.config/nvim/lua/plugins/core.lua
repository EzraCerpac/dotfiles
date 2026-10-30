return {
  {
    "LazyVim/LazyVim",
    -- opts = {
    -- },
  },
  {
    "nvim-mini/mini.ai",
    opts = {
      custom_textobjects = {
        b = { { "%b()", "%b[]", "%b{}", "%b<>" }, "^.().*().$" },
      },
    },
  },
}
