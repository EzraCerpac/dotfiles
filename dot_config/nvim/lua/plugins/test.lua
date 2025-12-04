return {
  {
    -- https://github.com/andythigpen/nvim-coverage
    "andythigpen/nvim-coverage",
    version = "*",
    config = function()
      require("coverage").setup({
        auto_reload = true,
      })
    end,
    keys = {
      {
        "<leader>tc",
        function()
          require("coverage").load(true)
        end,
        desc = "Run Coverage",
      },
      {
        "<leader>uc",
        function()
          require("coverage").toggle()
        end,
        desc = "Toggle Coverage",
      },
      {
        "<leader>tC",
        function()
          require("coverage").load()
          require("coverage").summary()
        end,
        desc = "Coverage Summary",
      },
    },
  },
}
