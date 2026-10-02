local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local module_path = root .. "/dotfiles/.config/nvim/lua/custom/typst_references.lua"
local state = vim.fn.tempname()
local stdpath = vim.fn.stdpath
vim.fn.stdpath = function(kind)
  return kind == "state" and state or stdpath(kind)
end
local clients = { { id = 5, name = "tinymist", root_dir = "/project-a" } }
vim.lsp.get_clients = function(opts)
  if not opts then
    return {}
  end
  return clients
end
local node_kind
vim.treesitter.get_node = function()
  if not node_kind then
    error("parser unavailable")
  end
  return {
    type = function()
      return node_kind
    end,
    parent = function()
      return nil
    end,
  }
end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.opt.virtualedit = "onemore"
vim.bo[buf].filetype = "typst"
vim.api.nvim_buf_set_name(buf, "/project-a/main.typ")
local function context(line, column)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, column or #line })
  return { bufnr = buf, line = line, cursor = { 1, column or #line } }
end
local m = dofile(module_path)
local source = m.new()
local function complete(ctx)
  local response
  source:get_completions(ctx, function(result)
    response = result
  end)
  assert(response and not response.is_incomplete_forward)
  return response.items
end
local ctx = context("See @")
assert(#complete(ctx) == 0, "A cold cache should be empty")
local original = {
  {
    label = "ch:results",
    kind = 18,
    client_id = 5,
    textEdit = { newText = "stale" },
    data = { stale = true },
  },
  { label = "fig:solver", kind = 18, client_id = 5 },
  { label = "fig:solver", kind = 18, client_id = 5 },
  { label = "not-a-reference", kind = 6, client_id = 5 },
  { label = "malicious\nlabel", kind = 18, client_id = 5 },
  { label = "another-client", kind = 18, client_id = 6 },
}
assert(m.record(ctx, original) == original, "The LSP transform must preserve its items")
local items = complete(ctx)
assert(#items == 2 and items[1].label == "ch:results")
assert(items[1].kind == 18 and items[1].insertText == "ch:results")
assert(not items[1].data and not items[1].client_id, "Cached items must not resolve through LSP")
assert(items[1].textEdit.newText == "ch:results", "Never reuse the LSP edit")
m.record(ctx, {})
m.record(ctx, { { kind = 18, label = "", client_id = 5 } })
assert(#complete(ctx) == 2, "Empty/error replies must preserve the previous successful list")
m.seed(
  clients[1],
  { { kind = 18, label = "ch:results" }, { kind = 18, label = "fig:solver" } },
  "/project-a/main.typ"
)
m.record(context("See @ch:"), { { kind = 18, label = "ch:results", client_id = 5 } })
local other_prefix = complete(context("See @fig:"))
assert(
  #other_prefix == 2 and other_prefix[2].label == "fig:solver",
  "A narrow prefix reply must retain other known references"
)
ctx = context("See @ch:resOLD.", 11)
items = complete(ctx)
assert(
  items[1].textEdit.range.start.character == 5 and items[1].textEdit.range["end"].character == 14
)
vim.lsp.util.apply_text_edits({ items[1].textEdit }, buf, "utf-8")
assert(
  vim.api.nvim_get_current_line() == "See @ch:results.",
  "Colon labels must replace the whole current reference"
)

local path = state
  .. "/typst-references/"
  .. vim.fn.sha256("/project-a\0/project-a/main.typ")
  .. ".json"
assert(vim.uv.fs_stat(path).mode % 512 == 384, "Persistent labels must have mode 0600")
local saved = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
assert(#saved.labels == 2 and saved.labels[1] == "ch:results" and saved.items == nil)
m = dofile(module_path)
source = m.new()
ctx = context("@")
assert(#complete(ctx) == 2, "A restart should load the matching main-file cache")
m.set_main(5, "/project-a", "/project-a/other.typ")
assert(#complete(ctx) == 0, "Switching main files must not leak references")
m.seed(clients[1], { { kind = 18, label = "other:main" } }, "/project-a/other.typ")
assert(complete(ctx)[1].label == "other:main")
m.set_main(5, "/project-a", "/project-a/main.typ")
assert(#complete(ctx) == 2, "Switching back should restore that main's labels")
m.seed(clients[1], { { kind = 18, label = "ch:über" } }, "/manuscript/main.typ")
assert(complete(ctx)[1].label == "ch:über", "Virtual main paths must be rooted in the project")
assert(
  vim.uv.fs_stat(
    state
      .. "/typst-references/"
      .. vim.fn.sha256("/project-a\0/project-a/manuscript/main.typ")
      .. ".json"
  )
)
m.set_main(5, "/project-a", "/project-a/main.typ")
clients = { { id = 5, name = "tinymist", root_dir = "/project-b" } }
assert(#complete(ctx) == 0, "Reused client IDs must not cross project roots")
clients = {}
assert(#complete(ctx) == 0, "A detached buffer must not use the old project's cache")
clients = { { id = 5, name = "tinymist", root_dir = "/project-a" } }

for _, line in ipairs({ "// @", '#import "@', '#let x = "@', "/* @", "ordinary text", "\\@" }) do
  assert(not m.is_reference(context(line)), "Reject non-reference context: " .. line)
end
for _, kind in ipairs({ "line_comment", "block_comment", "string", "import", "code", "math" }) do
  node_kind = kind
  assert(not m.is_reference(context("@ch:")), "Reject Tree-sitter context: " .. kind)
end
node_kind = "reference"
assert(m.is_reference(context("@ch:")))
vim.bo[buf].filetype = "lua"
assert(not m.is_reference(context("@")))
vim.bo[buf].filetype = "typst"

vim.fn.writefile(
  { '{"version":1,"root":"/project-a","main":"/project-a/main.typ","labels":{"bad":"ch:bad"}}' },
  path
)
m = dofile(module_path)
source = m.new()
assert(#complete(context("@")) == 0, "Malformed persisted schemas must be rejected")
vim.fn.writefile({ "not json" }, path)
m = dofile(module_path)
source = m.new()
assert(#complete(context("@")) == 0, "Invalid JSON must be rejected")
local many = {}
for i = 1, 2005 do
  many[#many + 1] = { kind = 18, label = "ref:" .. i }
end
m.seed(clients[1], many, "/project-a/main.typ")
assert(#complete(context("@")) == 2000, "The persistent cache must stay bounded")

-- Exercise the real Blink provider/queue/tree rather than emulating its timeout behavior.
local plugins = os.getenv("NVIM_TEST_PLUGIN_ROOT") or stdpath("data") .. "/lazy"
vim.opt.rtp:prepend(plugins .. "/blink.cmp")
vim.opt.rtp:prepend(root .. "/dotfiles/.config/nvim")
package.loaded["custom.typst_references"] = m
local opts = dofile(root .. "/dotfiles/.config/nvim/lua/plugins/blink.lua")[1].opts(nil, {
  sources = {
    default = { "lsp", "buffer" },
    providers = {
      buffer = {
        opts = {
          get_bufnrs = function()
            return { buf }
          end,
        },
      },
    },
  },
})
require("blink.cmp.config").merge_with(opts)
local lsp_requests, replied, release_reply = 0, false, nil
clients[1].offset_encoding = "utf-16"
clients[1].server_capabilities = { completionProvider = { triggerCharacters = { "@", ":" } } }
clients[1].request = function(_, method, _, callback)
  assert(method == "textDocument/completion")
  lsp_requests = lsp_requests + 1
  release_reply = function()
    replied = true
    callback(nil, {})
  end
  return true, 1
end
clients[1].cancel_request = function() end
m.seed(clients[1], { { kind = 18, label = "ch:über" } }, "/project-a/pipeline.typ")
local sources = require("blink.cmp.sources.lib")
local emitted
sources.completions_emitter:on(function(event)
  emitted = event.items
end)
ctx = context("bufferword See @ch:ü")
ctx.id, ctx.mode = 100, "default"
ctx.bounds = { start_col = 16, length = 5, line_number = 1 }
ctx.trigger = { kind = "trigger_character", initial_kind = "trigger_character", character = ":" }
ctx.providers = opts.sources.default(ctx)
local started = vim.uv.hrtime()
sources.request_completions(ctx)
assert(
  vim.wait(300, function()
    return emitted and emitted.typst_references ~= nil
  end, 5),
  "Blink never reached the fallback"
)
local elapsed = (vim.uv.hrtime() - started) / 1000000
assert(
  elapsed >= 100 and not replied and lsp_requests == 1,
  "The cached fallback must arrive after timeout, before the stalled reply"
)
assert(
  not emitted.buffer and not emitted.lsp,
  "Reference completions must not expose ordinary buffer words"
)
local accepted = emitted.typst_references[1]
assert(accepted.label == "ch:über" and not accepted.client_id)
local edit = require("blink.cmp.lib.text_edits").get_from_item(accepted)
vim.lsp.util.apply_text_edits({ edit }, buf, "utf-8")
assert(
  vim.api.nvim_get_current_line() == "bufferword See @ch:über",
  "Blink must apply fresh UTF-8 reference edits"
)
sources.cancel_completions()
assert(release_reply, "The stalled LSP request should provide a late reply")
release_reply()
assert(replied, "The simulated LSP reply should arrive after the fallback")
vim.fn.delete(state, "rf")
print("Typst reference fallback tests passed")
