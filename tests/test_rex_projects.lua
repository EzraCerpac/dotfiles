local definitions, calls, queued = {}, {}, {}
rex = {
  action = function(def) definitions[def.name] = def.run end,
  bind = function(key, action) assert(key == "shift+cmd+o" and action == "open_recent_project") end,
  layout = { block = function(spec) return spec end },
  client = { queue = function(action, args) table.insert(queued, {action, args}) end },
  call = function(method, args)
    table.insert(calls, {method, args})
    if method == "session.create" then return {session_id = "session:picker"} end
    if method == "client.action" then return {result = {session_id = "session:picker", client_id = "client:remote"}} end
    return {}
  end,
  invoke = function(name) return definitions[name]({session_id = "session:original", client_id = "client:app"}, {}) end,
}
local root = os.getenv("NVIM_TYPST_TEST_ROOT")
dofile(root and (root .. "/dotfiles/.config/rex/projects.lua") or assert(arg[1]))
definitions.open_recent_project({session_id = "session:original", client_id = "client:app"})
assert(calls[1][1] == "session.create")
assert(queued[1][1] == "session.select" and queued[1][2].session_id == "session:picker")
assert(calls[1][2].initial_windows[1].layout.options.command[5] == "session:original")
calls, queued = {}, {}
definitions.open_recent_project({session_id = "session:remote", block_id = "block:remote", client_id = "client:home", server = "nas"})
assert(#calls == 2 and calls[1][1] == "client.action")
assert(calls[1][2].action == "project_picker_backend" and calls[1][2].session_id == "session:remote" and calls[1][2].block_id == "block:remote")
assert(calls[2][1] == "client.perform" and calls[2][2].client_id == "client:remote")
assert(calls[2][2].args.session_id == "session:picker")
assert(#queued == 0)
print("project action dispatch checks passed")
