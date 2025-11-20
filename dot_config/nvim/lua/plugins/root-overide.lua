return {
  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      if vim.g.TEMP_DISABLE_ROOT then
        opts.root_spec = { "cwd" }
        vim.notify("LazyVim root detection disabled", vim.log.levels.WARN)
      end
    end,
  },
}
