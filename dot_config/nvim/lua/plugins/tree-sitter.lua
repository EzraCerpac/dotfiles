return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "latex",
        "typst",
        "python",
        "wgsl",
      })

      opts.textobjects = opts.textobjects or {}
      opts.textobjects.swap = {
        enable = true,
        swap_next = {
          ["ga"] = "@parameter.inner",
        },
        swap_previous = {
          ["gA"] = "@parameter.inner",
        },
      }
    end,
    init = function()
      require("vim.treesitter.query").add_predicate("is-mise?", function(_, _, bufnr, _)
        local filepath = vim.api.nvim_buf_get_name(tonumber(bufnr) or 0)
        local filename = vim.fn.fnamemodify(filepath, ":t")
        return string.match(filename, ".*mise.*%.toml$") ~= nil
      end, { force = true, all = false })
    end,
  },
}
