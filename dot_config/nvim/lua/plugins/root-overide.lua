return {
  {
    "LazyVim/LazyVim",
    init = function()
      if vim.g.TEMP_DISABLE_ROOT then
        -- Make root() identical to cwd when override is active
        local Util = require("lazyvim.util")
        Util.root = function()
          return vim.loop.cwd()
        end
      end
    end,
  },
}
