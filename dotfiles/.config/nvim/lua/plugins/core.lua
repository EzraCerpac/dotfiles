return {
  {
    "LazyVim/LazyVim",
    opts = {
      kind_filter = {
        typst = { "Namespace" },
      },
    },
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
