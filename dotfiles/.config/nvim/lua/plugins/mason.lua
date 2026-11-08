return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Source-built NAS Neovim needs host-built tools compatible with its libc.
      if vim.env.SETUP_NAS_NEOVIM_BUILD == "1" then
        opts.PATH = "append"
      end
    end,
  },
}
