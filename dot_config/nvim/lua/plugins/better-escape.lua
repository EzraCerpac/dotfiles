return {
  "max397574/better-escape.nvim",
  event = "InsertEnter",   -- load only when first entering Insert mode
  config = function()
    require("better_escape").setup({
      timeout = 300,             -- default timeout in ms
      default_mappings = false,  -- disable all default mappings
      mappings = {
        i = {  -- insert mode
          j = {
            k = "<Esc>",  -- jk to escape
            j = false,    -- disable jj
          },
          k = {
            j = "<Esc>",  -- kj to escape
          },
        },
        c = {  -- command mode
          j = {
            k = "<C-c>",  -- jk to escape
            j = false,    -- disable jj
          },
          k = {
            j = "<C-c>",  -- kj to escape
          },
        },
        t = {  -- terminal mode
          j = {
            k = "<C-\\><C-n>",  -- jk to escape
            j = false,          -- disable jj
          },
          k = {
            j = "<C-\\><C-n>",  -- kj to escape
          },
        },
        v = {  -- visual mode
          j = {
            k = "<Esc>",  -- jk to escape
            j = false,    -- disable jj
          },
          k = {
            j = "<Esc>",  -- kj to escape
          },
        },
        s = {  -- select mode
          j = {
            k = "<Esc>",  -- jk to escape
            j = false,    -- disable jj
          },
          k = {
            j = "<Esc>",  -- kj to escape
          },
        },
      },
    })
  end,
}
