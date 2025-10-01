-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.winbar = "%=%m %f"
vim.opt.wrap = true
vim.g.codeium_os = "Darwin"
vim.g.codeium_arch = "arm64"

-- LazyVim picker to use.
-- Can be one of: telescope, fzf
-- Leave it to "auto" to automatically use the picker
-- enabled with `:LazyExtras`
vim.g.lazyvim_picker = "fzf"

-- Temporarily prefer nvim-cmp to rule out blink.cmp issues on NVIM 0.12-dev.
-- Switch back to "blink.cmp" once LSP/completion is stable again.
vim.g.lazyvim_cmp = "blink.cmp"

-- Set XDG_CONFIG_HOME to ensure lazygit uses ~/.config/lazygit
vim.env.XDG_CONFIG_HOME = vim.fn.expand("~/.config")

-- LSP Server configurations
-- require("lspconfig").harper_ls.setup({
--   settings = {
--     ["harper-ls"] = {
--       userDictPath = "",
--       workspaceDictPath = "",
--       fileDictPath = "",
--       linters = {
--         SpellCheck = true,
--         SpelledNumbers = true,
--         AnA = true,
--         SentenceCapitalization = false,
--         UnclosedQuotes = true,
--         WrongQuotes = false,
--         LongSentences = true,
--         RepeatedWords = true,
--         Spaces = true,
--         Matcher = true,
--         CorrectNumberSuffix = true,
--       },
--       codeActions = {
--         ForceStable = false,
--       },
--       markdown = {
--         IgnoreLinkTitle = false,
--       },
--       diagnosticSeverity = "hint",
--       isolateEnglish = false,
--       dialect = "American",
--       maxFileLength = 120000,
--       ignoredLintsPath = {},
--     },
--   },
-- })

-- LSP Server to use for Python.
vim.g.lazyvim_python_lsp = "pyright"
vim.g.lazyvim_python_ruff = "ruff"
-- vim.lsp.enable("ty")

require("lspconfig")["tinymist"].setup({ -- Alternatively, can be used `vim.lsp.config["tinymist"]`
  -- ...
  on_attach = function(client, bufnr)
    vim.keymap.set("n", "<local_leader>tp", function()
      client:exec_cmd({
        title = "pin",
        command = "tinymist.pinMain",
        arguments = { vim.api.nvim_buf_get_name(0) },
      }, { bufnr = bufnr })
    end, { desc = "[T]inymist [P]in", noremap = true })

    vim.keymap.set("n", "<local_leader>tu", function()
      client:exec_cmd({
        title = "unpin",
        command = "tinymist.pinMain",
        arguments = { vim.v.null },
      }, { bufnr = bufnr })
    end, { desc = "[T]inymist [U]npin", noremap = true })
  end,
})
