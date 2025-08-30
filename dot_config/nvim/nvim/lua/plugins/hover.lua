return {
  {
    "Fildo7525/pretty_hover",
    event = "LspAttach",
    opts = {
      -- completion = {
      --   documentation = {
      --     draw = function(opts)
      --       if opts.item and opts.item.documentation then
      --         local out = require("pretty_hover.parser").parse(opts.item.documentation.value)
      --         opts.item.documentation.value = out:string()
      --       end
      --
      --       opts.default_implementation(opts)
      --     end,
      --   },
      -- },
    },
  },
}
