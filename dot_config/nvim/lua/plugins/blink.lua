return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      keymap = {
        preset = "enter",
        -- Tab is reserved for sidekick NES + tabout.nvim; accept completions with <C-y>
        ["<Tab>"] = false,
        ["<S-Tab>"] = false,
      },
      completion = {
        trigger = {
          show_in_snippet = false,
          show_on_insert_on_trigger_character = function(ctx)
            local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
            -- In codecompanion buffers, don't trigger on backslash
            if bufname:match("%[CodeCompanion%]") and ctx.char == "\\" then
              return false
            end
            return true
          end,
        },
      },
    },
  },
}
