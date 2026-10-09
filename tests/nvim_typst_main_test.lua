local root = assert(os.getenv("NVIM_TYPST_TEST_ROOT"))
local m = dofile(root .. "/dotfiles/.config/nvim/lua/custom/typst_main.lua")
local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/manuscript/chapters", "p")
project = vim.uv.fs_realpath(project)
vim.fn.writefile({ "= Main" }, project .. "/main.typ")
vim.fn.writefile({ "= Manuscript" }, project .. "/manuscript/main.typ")
local chapter = project .. "/manuscript/chapters/results.typ"
assert(m.resolve(chapter, project) == project .. "/manuscript/main.typ", "Resolve the closest entrypoint")
assert(m.resolve(project .. "/main.typ", project) == project .. "/main.typ")
assert(not m.resolve(chapter, project .. "/manuscript/chapters"), "Do not cross the project boundary")
assert(not m.resolve(chapter, project .. "-other"), "Do not confuse root prefixes")
assert(not m.resolve(chapter, nil), "Single files without a root need no pin")
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, chapter)
local count = 0
local client = {
  id = 1,
  root_dir = project,
  exec_cmd = function(_, command, ctx)
    count = count + 1
    assert(command.command == "tinymist.pinMain" and command.arguments[1] == project .. "/manuscript/main.typ")
    assert(ctx.bufnr == buf)
  end,
}
local before = vim.api.nvim_buf_get_changedtick(buf)
m.attach(client, buf)
assert(count == 1)
m.attach(client, buf)
assert(count == 1, "Later file attachment must preserve manual main pins")
assert(vim.api.nvim_buf_get_changedtick(buf) == before, "Pinning must not edit author text")
client._typst_main_selected = nil
client.settings = { typstExtraArgs = { "explicit.typ" } }
m.attach(client, buf)
assert(count == 1, "Explicit project configuration takes precedence")
-- A reused client must recover after its first buffer has no entrypoint.
local recovery = project .. "/recovery"
vim.fn.mkdir(recovery .. "/book/chapters", "p")
vim.fn.writefile({ "= Book" }, recovery .. "/book/main.typ")
local standalone_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(standalone_buf, recovery .. "/standalone.typ")
local chapter_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(chapter_buf, recovery .. "/book/chapters/results.typ")
local recovered_pins = 0
local reused = {
  id = 2,
  root_dir = recovery,
  exec_cmd = function(_, command, ctx)
    recovered_pins = recovered_pins + 1
    assert(command.command == "tinymist.pinMain" and command.arguments[1] == recovery .. "/book/main.typ")
    assert(ctx.bufnr == chapter_buf)
  end,
}
local standalone_tick = vim.api.nvim_buf_get_changedtick(standalone_buf)
local chapter_tick = vim.api.nvim_buf_get_changedtick(chapter_buf)
m.attach(reused, standalone_buf)
assert(
  recovered_pins == 0 and not reused._typst_main_selected,
  "An unresolved first buffer must leave project selection open"
)
m.attach(reused, chapter_buf)
assert(recovered_pins == 1 and reused._typst_main_selected, "The reused client must select a later chapter's main")
m.attach(reused, standalone_buf)
m.attach(reused, chapter_buf)
assert(recovered_pins == 1, "Once selected, further attachments must preserve later manual pins")
assert(vim.api.nvim_buf_get_changedtick(standalone_buf) == standalone_tick)
assert(vim.api.nvim_buf_get_changedtick(chapter_buf) == chapter_tick)

-- A manual pin (or unpin) after the unresolved file owns later selection.
for _, manual_main in ipairs({ recovery .. "/chosen.typ", vim.v.null }) do
  local requests = {}
  local manual = {
    id = 3,
    root_dir = recovery,
    request = function(_, method, params, callback, bufnr)
      requests[#requests + 1] = { method = method, params = params, bufnr = bufnr }
      if callback then
        callback(nil, { ok = true })
      end
      return true, 91
    end,
    exec_cmd = function(self, command, ctx)
      return self:request("workspace/executeCommand", command, nil, ctx.bufnr)
    end,
  }
  m.attach(manual, standalone_buf)
  local wrapped_request = manual.request
  m.attach(manual, standalone_buf)
  assert(manual.request == wrapped_request, "Request observation must be idempotent")
  local callback_result
  local sent, request_id = manual:request("textDocument/completion", {}, function(_, result)
    callback_result = result
  end, standalone_buf)
  assert(sent and request_id == 91 and callback_result.ok, "Preserve request returns and callback arguments")
  assert(not manual._typst_main_selected, "Unrelated requests must not select a main")
  manual:exec_cmd({ command = "tinymist.pinMain", arguments = { manual_main } }, { bufnr = standalone_buf })
  m.attach(manual, chapter_buf)
  assert(#requests == 2, "A later chapter must not replace an earlier manual pin or unpin")
  assert(requests[2].params.arguments[1] == manual_main and requests[2].bufnr == standalone_buf)
end

vim.fn.delete(project, "rf")
print("Typst chapter entrypoint tests passed")
