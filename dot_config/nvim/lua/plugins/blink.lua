return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      enabled = function()
        local bufname = vim.api.nvim_buf_get_name(0)
        -- Disable in codecompanion buffers to allow slash commands
        if bufname:match("%[CodeCompanion%]") then
          return false
        end
        return vim.bo.buftype ~= "prompt" and vim.b.completion ~= false
      end,
      keymap = {
        preset = "enter",
        -- Tab is reserved for sidekick NES + tabout.nvim; accept completions with <C-y>
        ["<Tab>"] = false,
        ["<S-Tab>"] = false,
      },
    },
  },
}
