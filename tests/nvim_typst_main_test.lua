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
vim.fn.delete(project, "rf")
print("Typst chapter entrypoint tests passed")
