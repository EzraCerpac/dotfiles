local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local m = dofile(root .. "/dotfiles/.config/nvim/lua/custom/typst_definition.lua")
local b = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(b)
vim.api.nvim_buf_set_lines(b, 0, -1, false, {
  "See @eq:score and @eq:über.",
  "$ x = 1 $ <eq:score>",
  "$ y = 2 $ <eq:über>",
  "// <eq:score>",
})
assert(vim.deep_equal(m.local_target(b, 0, 8), { 2, 10 }), "Resolve literal label, excluding comment")
assert(vim.deep_equal(m.local_target(b, 0, 23), { 3, 10 }), "Resolve UTF-8 labels")
assert(not m.local_target(b, 3, 8), "Comments are not references")
vim.api.nvim_win_set_cursor(0, { 1, 8 })
m.goto_definition()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 10 }), "Jump directly without LSP")
vim.api.nvim_buf_set_lines(b, 4, 4, false, { "$ z = 3 $ <eq:score>" })
assert(not m.local_target(b, 0, 8), "Do not guess when labels are ambiguous")
local ambiguous_lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
for _, line in ipairs({
  "#show <intro>: set text(blue)",
  "#let selected = <intro>",
  "#context query(<intro>)",
  "#{ let selected = <intro> }",
  "#[<intro>]",
  "Hello #[<intro>]",
  "Hello *<intro>*",
  "Hello _<intro>_",
}) do
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { line, "See @intro." })
  assert(not m.local_target(b, 1, 6), "Do not treat code values or empty content scopes as attachments: " .. line)
end
for _, line in ipairs({
  "= Intro <intro>",
  "#[= Intro <intro>]",
  "#block[Heading <intro>]",
  "Hello *World <intro>*",
  "Hello _World <intro>_",
}) do
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { line, "See @intro." })
  local column = assert(line:find("<intro>", 1, true)) - 1
  assert(vim.deep_equal(m.local_target(b, 1, 6), { 1, column }), "Resolve genuine markup attachment: " .. line)
end
vim.api.nvim_buf_set_lines(b, 0, -1, false, {
  "#show <intro>: set text(blue)",
  "= Intro <intro>",
  "See @intro.",
})
assert(vim.deep_equal(m.local_target(b, 2, 6), { 2, 8 }), "A selector must not make a real attachment ambiguous")
vim.api.nvim_buf_set_lines(b, 0, -1, false, ambiguous_lines)
print("Typst local definition tests passed")
local original_get_clients = vim.lsp.get_clients
local callback, timeout, cancelled, message
vim.lsp.get_clients = function()
  return {
    {
      offset_encoding = "utf-16",
      is_stopped = function()
        return false
      end,
      request = function(_, method, params, cb)
        assert(method == "textDocument/definition")
        callback = cb
        return true, 123
      end,
      cancel_request = function(_, id)
        cancelled = id
      end,
    },
  }
end
vim.defer_fn = function(fn, ms)
  assert(ms == 5000)
  timeout = fn
end
vim.notify = function(msg)
  message = msg
end
local original_get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function()
  return nil, "No parser available"
end
vim.api.nvim_win_set_cursor(0, { 1, 8 })
m.goto_definition()
assert(callback and timeout, "A missing parser must fall back to the Tinymist request")
callback(nil, nil)
vim.treesitter.get_parser = original_get_parser
callback, timeout = nil, nil
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "#show <intro>: set text(blue)", "See @intro." })
vim.api.nvim_win_set_cursor(0, { 2, 6 })
m.goto_definition()
assert(callback and timeout, "A selector-only label must fall back to Tinymist")
callback(nil, nil)
vim.api.nvim_buf_set_lines(b, 0, -1, false, ambiguous_lines)
callback, timeout = nil, nil
vim.api.nvim_win_set_cursor(0, { 1, 8 })
m.goto_definition()
assert(callback and timeout, "Use a bounded server request for ambiguous or external targets")
timeout()
assert(cancelled == 123 and message:find("timed out"), "Cancel and report stalled request")
callback(nil, {
  uri = "file:///should-not-open.typ",
  range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
})
assert(vim.api.nvim_get_current_buf() == b, "Ignore results arriving after timeout")
print("Typst server timeout tests passed")

local shown
vim.lsp.util.show_document = function(location, encoding, options)
  shown = location
  assert(encoding == "utf-16" and options.focus)
end
m.goto_definition()
local external = {
  uri = "file:///background.typ",
  range = { start = { line = 10, character = 0 }, ["end"] = { line = 10, character = 5 } },
}
callback(nil, { external })
assert(shown == external, "Jump to a server-resolved definition outside the buffer")
timeout()
assert(shown == external, "Completed requests do not time out")
print("Typst external definition tests passed")
shown = nil
m.goto_definition()
vim.api.nvim_buf_set_text(b, 0, 0, 0, 0, { "Changed " })
callback(nil, { external })
assert(not shown, "Ignore definitions for buffer contents edited during the request")
print("Typst stale response test passed")
vim.lsp.get_clients = original_get_clients
