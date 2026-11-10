local guard_path = os.getenv("HUMANIZE_TYPST_GUARD_PATH")
  or vim.fn.expand("~/.config/nvim/lua/custom/typst_guard.lua")
local guard = dofile(guard_path)
local command = arg and arg[1]
local input = vim.fn.json_decode(io.read("*a") or "")
local function emit(value)
  io.write(vim.fn.json_encode(value), "\n")
end
if command == "prepare" then
  local plan, chunks = guard.prepare(input.source or "", input.paragraph_mode ~= false)
  if not plan then emit({ error = chunks }); vim.cmd("cquit 1") end
  emit({ plan = plan, chunks = chunks })
elseif command == "restore" then
  local source, err = guard.restore(input.plan, input.outputs)
  if not source then emit({ error = err }); vim.cmd("cquit 1") end
  emit({ source = source })
else
  emit({ error = "usage: prepare or restore" }); vim.cmd("cquit 2")
end
