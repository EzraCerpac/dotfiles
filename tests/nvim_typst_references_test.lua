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
vim.uv.update_time()
local started = vim.uv.hrtime()
sources.request_completions(ctx)
assert(
  vim.wait(300, function()
    return emitted and emitted.typst_references ~= nil
  end, 5),
  "Blink never reached the fallback"
)
local elapsed = (vim.uv.hrtime() - started) / 1000000
assert(elapsed >= 100, ("The cached fallback arrived before the timeout (%.1fms)"):format(elapsed))
assert(not replied, "The cached fallback must arrive before the stalled LSP reply")
assert(lsp_requests == 1, ("Expected one stalled LSP request, got %d"):format(lsp_requests))
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
-- A new workspace has no manually seeded fallback. The first compile may still
-- be pending when Blink asks for '@'; the next prefix must query Tinymist again.
clients[1].root_dir = "/cold-start"
vim.api.nvim_buf_set_name(buf, "/cold-start/main.typ")
local cold_requests = 0
clients[1].request = function(_, _, _, callback)
  cold_requests = cold_requests + 1
  callback(nil, cold_requests == 1 and { items = {}, isIncomplete = false } or {
    items = { { kind = 18, label = "ch:results" } },
    isIncomplete = false,
  })
  return true, cold_requests
end
m.attach(clients[1])
local wrapped = clients[1].request
m.attach(clients[1])
assert(clients[1].request == wrapped, "Attaching twice must not wrap twice")
ctx = context("See @")
assert(#complete(ctx) == 0, "The new workspace must begin with an empty cache")
ctx.id, ctx.mode = 200, "default"
ctx.bounds = { start_col = 6, length = 0, line_number = 1 }
ctx.trigger = { kind = "trigger_character", initial_kind = "trigger_character", character = "@" }
ctx.providers = opts.sources.default(ctx)
emitted = nil
sources.request_completions(ctx)
assert(vim.wait(300, function()
  return emitted ~= nil
end, 5))
local lsp_cache = require("blink.cmp.sources.lsp.cache")
assert(lsp_cache.entries[5].response.is_incomplete_forward, "Empty reference replies must remain retryable")
sources.cancel_completions()
ctx = vim.tbl_extend("force", ctx, context("See @ch:"))
ctx.bounds = { start_col = 6, length = 3, line_number = 1 }
ctx.trigger = { kind = "trigger_character", initial_kind = "trigger_character", character = ":" }
emitted = nil
sources.request_completions(ctx)
assert(vim.wait(300, function()
  return emitted and emitted.lsp and #emitted.lsp > 0
end, 5))
assert(cold_requests == 2, "Blink must retry the empty complete response on the next reference prefix")
assert(emitted.lsp[1].label == "ch:results")
assert(complete(ctx)[1].label == "ch:results", "A real successful reply must populate the cold fallback")
sources.cancel_completions()
m = dofile(module_path)
source = m.new()
assert(complete(ctx)[1].label == "ch:results", "Cold-start recovery must survive module restart")

local original_result = { items = {}, isIncomplete = false }
node_kind = nil
local handler
local passthrough = {
  id = 9,
  root_dir = "/cold-start",
  offset_encoding = "utf-16",
  request = function(_, _, _, cb)
    handler = cb
    return true, 99
  end,
}
m.attach(passthrough)
local function request(line, reply, err)
  context(line)
  local received, received_error
  passthrough:request(
    "textDocument/completion",
    { position = { line = 0, character = vim.str_utfindex(line, "utf-16") } },
    function(e, r)
      received_error, received = e, r
    end,
    buf
  )
  handler(err, reply)
  return received, received_error
end
assert(request("ordinary", original_result) == original_result, "Ordinary completion must stay unchanged")
assert(request("// @", original_result) == original_result, "Comments must stay unchanged")
local err = { code = -1, message = "failed" }
local received, received_error = request("See @", nil, err)
assert(received == nil and received_error == err, "LSP errors must remain errors")
assert(request("über @", nil).isIncomplete, "UTF-16 positions must recognize references after Unicode")

clients = { passthrough }
ctx = context("See @")
passthrough:request("textDocument/completion", {position = {line = 0, character = 5}}, function() end, buf)
m.set_main(9, "/cold-start", "/cold-start/other.typ")
local late = { { kind = 18, label = "old:main", client_id = 9 } }
handler(nil, {items = late, isIncomplete = false})
m.record(ctx, late)
assert(#complete(ctx) == 0, "Neither raw recording nor Blink transforms may cache a late old-main reply")

local warm_requests, warm_reply, warm_params = 0
local warm = {
  id = 12, root_dir = "/warm-start", offset_encoding = "utf-16", attached_buffers = { [buf] = true },
  request = function(_, _, params, cb)
    warm_requests, warm_params, warm_reply = warm_requests + 1, params, cb
    return true, warm_requests
  end,
}
clients = { warm }
vim.api.nvim_buf_set_name(buf, "/warm-start/main.typ")
m.set_main(12, "/warm-start", "/warm-start/main.typ")
node_kind = "label"
context("über <known:label>")
local before_tick, before_cursor = vim.api.nvim_buf_get_changedtick(buf), vim.api.nvim_win_get_cursor(0)
m.warm(warm)
m.warm(warm)
assert(warm_requests == 1, "Duplicate compile notifications must coalesce warming requests")
assert(warm_params.context.triggerKind == 1 and warm_params.position.character == 6, "Warm at existing UTF-16 label syntax")
assert(vim.api.nvim_buf_get_changedtick(buf) == before_tick and vim.deep_equal(before_cursor, vim.api.nvim_win_get_cursor(0)), "Warming must not edit or move the author's buffer")
warm_reply(nil, { items = {}, isIncomplete = false })
m.warm(warm)
assert(warm_requests == 2, "An empty warm reply must allow retry on the next successful compile")
warm_reply(nil, { items = { { kind = 18, label = "ch:warmed" } } })
m.warm(warm)
assert(warm_requests == 2, "A populated cache must not issue repeated background queries")
node_kind = "reference"
assert(complete(context("See @"))[1].label == "ch:warmed", "Cold warming must supply references during invalid edits")

m.set_main(12, "/warm-start", "/warm-start/other.typ")
vim.api.nvim_buf_set_name(buf, "/warm-start/other.typ")
node_kind = "label"
context("<other:label>")
m.warm(warm)
m.set_main(12, "/warm-start", "/warm-start/third.typ")
warm_reply(nil, { items = { { kind = 18, label = "old:warm" } } })
node_kind = "reference"
assert(#complete(context("See @")) == 0, "A late warm reply must not cross main files")
m.warm(warm)
assert(warm_requests == 3, "A sibling file's reference must not be used to warm the selected main")
local sibling = vim.api.nvim_create_buf(false, true)
vim.bo[sibling].filetype = "typst"
vim.api.nvim_buf_set_name(sibling, "/warm-start/sibling.typ")
vim.api.nvim_buf_set_lines(sibling, 0, -1, false, { "See @sibling" })
warm.attached_buffers[sibling] = true
vim.api.nvim_buf_set_name(buf, "/warm-start/third.typ")
node_kind = "label"
context("<third:label>")
m.warm(warm)
assert(warm_params.textDocument.uri == vim.uri_from_bufnr(buf), "Warming must query the selected main, never an attached sibling")
warm_reply(nil, { items = { { kind = 18, label = "third:label" } } })

local lsp_opts = dofile(root .. "/dotfiles/.config/nvim/lua/plugins/lsp.lua")[2].opts(nil, {
  servers = { tinymist = { settings = { completion = { postfix = false } } } },
})
assert(lsp_opts.servers.tinymist.settings.completion.triggerOnSnippetPlaceholders)
assert(lsp_opts.servers.tinymist.settings.completion.postfix == false, "Preserve neighboring completion settings")
vim.fn.delete(state, "rf")
print("Typst reference fallback tests passed")
