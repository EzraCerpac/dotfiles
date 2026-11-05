local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local received
local specs = dofile(root .. "/dotfiles/.config/nvim/lua/plugins/lsp.lua")
local opts = {
  servers = {
    harper_ls = {
      handlers = {
        ["textDocument/publishDiagnostics"] = function(_, params) received = params end,
      },
    },
  },
}
specs[2].opts(nil, opts)
local handler = opts.servers.harper_ls.handlers["textDocument/publishDiagnostics"]
local client = { name = "harper_ls", offset_encoding = "utf-16" }
local get_client = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function() return client end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".typ")
vim.bo[bufnr].filetype = "typst"
local lines = {
  'É 😀 #percent(phase-outputs.all.bestShares.gd_wolfe, digits: 0) and mispeled prose.',
  '#num(phase-outputs.initial.models.at("3f").meanProbability.lbfgs_bt, digits: 2)',
  '#percent(phase-share(0, "3f", "lbfgs_bt"), digits: 0)',
  '#text("A mispeled title")[Nested mispeled prose and #emph[more mispeled prose].]',
  '#percent(',
  '  phase-outputs.all.choiceShares.gd_wolfe,',
  '  digits: 0,',
  ')',
  '#text("mispeled")',
  '#block(incompleteIdentifier',
}
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
local function diagnostic(line, word, occurrence)
  local text = lines[line]
  local from = 1
  local first, last
  for _ = 1, occurrence or 1 do
    first, last = assert(text:find(word, from, true))
    from = last + 1
  end
  return {
    message = word,
    range = {
      start = { line = line - 1, character = vim.str_utfindex(text, "utf-16", first - 1) },
      ["end"] = { line = line - 1, character = vim.str_utfindex(text, "utf-16", last) },
    },
  }
end
local all = {
  diagnostic(1, "bestShares"), diagnostic(1, "gd_wolfe"), diagnostic(1, "mispeled"),
  diagnostic(2, "3f"), diagnostic(2, "meanProbability"), diagnostic(2, "lbfgs_bt"),
  diagnostic(3, "3f"), diagnostic(3, "lbfgs_bt"),
  diagnostic(4, "mispeled", 1), diagnostic(4, "mispeled", 2), diagnostic(4, "mispeled", 3),
  diagnostic(6, "choiceShares"), diagnostic(6, "gd_wolfe"),
  diagnostic(9, "mispeled"), diagnostic(10, "incompleteIdentifier"),
}
local params = { uri = vim.uri_from_bufnr(bufnr), diagnostics = all }
local ctx = { client_id = 1 }
local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
handler(nil, params, ctx, {})
assert(#received.diagnostics == 6, vim.inspect(received.diagnostics))
for _, d in ipairs(received.diagnostics) do
  assert(d.message == "mispeled" or d.message == "incompleteIdentifier", vim.inspect(d))
end
assert(#params.diagnostics == #all, "Must not mutate the server's diagnostic list")
assert(vim.api.nvim_buf_get_changedtick(bufnr) == changedtick, "Must not edit the buffer")
local empty = vim.tbl_extend("force", params, { diagnostics = {} })
handler(nil, empty, ctx, {})
assert(#received.diagnostics == 0, "Empty updates must clear diagnostics")
handler({ message = "server error" }, params, ctx, {})
assert(received == params, "Errors must pass through")

vim.bo[bufnr].filetype = "markdown"
handler(nil, params, ctx, {})
assert(received == params, "Other filetypes must pass through")
vim.bo[bufnr].filetype = "typst"
client.name = "tinymist"
handler(nil, params, ctx, {})
assert(received == params, "Other language servers must pass through")
client.name = "harper_ls"
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function() error("parser unavailable") end
handler(nil, params, ctx, {})
assert(received == params, "Missing parser must pass diagnostics through")
vim.treesitter.get_parser = get_parser
local stale = vim.tbl_extend("force", params, { version = vim.lsp.util.buf_versions[bufnr] + 1 })
handler(nil, stale, ctx, {})
assert(received == stale, "Stale positions must pass diagnostics through")
vim.lsp.get_client_by_id = get_client
vim.api.nvim_buf_delete(bufnr, { force = true })
print("Harper Typst diagnostic filtering tests passed")
