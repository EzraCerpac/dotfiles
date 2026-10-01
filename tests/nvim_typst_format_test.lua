local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local plugins = (os.getenv("NVIM_TEST_PLUGIN_ROOT") or vim.fn.stdpath("data") .. "/lazy") .. "/"
assert(vim.fn.executable("typstyle") == 1, "Typst format tests require typstyle on PATH")
vim.opt.rtp:prepend(plugins .. "conform.nvim")

local defaults = dofile(plugins .. "LazyVim/lua/lazyvim/plugins/extras/lang/typst.lua")
local opts
for _, spec in ipairs(defaults) do
  if spec[1] == "stevearc/conform.nvim" then
    opts = spec.opts
  end
end
local overrides = dofile(root .. "/dotfiles/.config/nvim/lua/plugins/conform.lua")[1].opts
local conform = require("conform")
conform.setup(vim.tbl_deep_extend("force", opts, overrides))

local bufnr = vim.api.nvim_create_buf(false, true)
vim.bo[bufnr].filetype = "typst"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "#let value=1" })
local before = vim.api.nvim_buf_get_changedtick(bufnr)
local requests = 0
local original = vim.lsp.get_clients
vim.lsp.get_clients = function()
  return {
    {
      id = 1,
      name = "tinymist",
      offset_encoding = "utf-16",
      supports_method = function()
        return true
      end,
      request_sync = function()
        requests = requests + 1
        return nil, "timeout"
      end,
    },
  }
end
local err, changed
conform.format({ bufnr = bufnr, dry_run = true, quiet = true }, function(e, c)
  err, changed = e, c
end)
vim.lsp.get_clients = original

assert(requests == 0, "Formatting waited for a stalled Tinymist server")
assert(err == nil, tostring(err))
assert(changed, "Standalone typstyle did not format the Typst buffer")
assert(before == vim.api.nvim_buf_get_changedtick(bufnr), "Dry run changed the buffer")
print("Typst formatting stays independent of a stalled Tinymist server")
