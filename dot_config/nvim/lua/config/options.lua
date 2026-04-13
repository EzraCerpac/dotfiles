-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local delftblue = require("config.delftblue")

-- Prepend mise shims to PATH
if not delftblue.enabled() then
  vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH
end

-- Force transparent background after any colorscheme load or terminal background detection
-- Workaround for nvim 0.12 OSC 11 background detection resetting highlights
local force_transparent = vim.api.nvim_create_augroup("force_transparent_bg", { clear = true })
vim.api.nvim_create_autocmd({ "ColorScheme", "TermResponse", "UIEnter" }, {
  group = force_transparent,
  callback = function()
    vim.schedule(function()
      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
    end)
  end,
})

-- Disable automatic project root detection if the global variable is set
-- Read override if provided via --cmd
if vim.g.root_spec then
  vim.g.lazyvim_root_spec = vim.g.root_spec
else
  vim.g.lazyvim_root_spec = { "lsp", "cwd", "git" } -- default LazyVim spec
end
vim.g.root_spec = vim.g.lazyvim_root_spec

vim.opt.winbar = "%=%m %f"
vim.opt.wrap = true
vim.opt.formatoptions:remove({ "t" })  -- Disable auto-wrapping text at textwidth
if not delftblue.enabled() then
  vim.g.codeium_os = "Darwin"
  vim.g.codeium_arch = "arm64"
end

-- LazyVim picker to use.
-- Can be one of: telescope, fzf
-- Leave it to "auto" to automatically use the picker
-- enabled with `:LazyExtras`
vim.g.lazyvim_picker = delftblue.has("fzf") and "fzf" or "auto"

-- Temporarily prefer nvim-cmp to rule out blink.cmp issues on NVIM 0.12-dev.
-- Switch back to "blink.cmp" once LSP/completion is stable again.
vim.g.lazyvim_cmp = "blink.cmp"

-- Set XDG_CONFIG_HOME to ensure lazygit uses ~/.config/lazygit
vim.env.XDG_CONFIG_HOME = vim.fn.expand("~/.config")

-- Filetype detection for WGSL
vim.filetype.add({ extension = { wgsl = "wgsl" } })

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
-- vim.g.lazyvim_python_lsp = "pyright"
vim.g.lazyvim_python_ruff = "ruff"
if vim.fn.executable("ty") == 1 then
  vim.lsp.enable("ty")
end
