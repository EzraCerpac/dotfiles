rex.action{
  name = "project_picker_backend",
  title = "Open project picker on this host",
  args = { defer_selection = "boolean?" },
  run = function(ctx, args)
    if not ctx.session_id or not ctx.client_id then
      error("Open recent project requires an active Rex app session", 0)
    end
    local picker, err = rex.call("session.create", {
      label = "Choose project",
      initial_windows = {{
        window_label = "Choose project",
        layout = rex.layout.block{
          flavor = "com.superlogical.terminal.shell",
          options = {
            shell = "none",
            command = { "sh", "-lc", 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"; exec "$HOME/.local/bin/rex-project" --previous-session "$1"', "rex-project", ctx.session_id },
            exit = { on_completion = false },
          },
        },
      }},
    })
    if err then error(err, 0) end
    if args.defer_selection then
      return { session_id = picker.session_id, client_id = ctx.client_id }
    end
    rex.client.queue("session.select", { session_id = picker.session_id })
  end,
}
rex.action{
  name = "open_recent_project",
  title = "Open recent project",
  category = "Session",
  run = function(ctx)
    if not ctx.session_id or not ctx.client_id then
      error("Open recent project requires an active Rex app session", 0)
    end
    local result, err
    if ctx.server then
      result, err = rex.call("client.action", {
        action = "project_picker_backend",
        session_id = ctx.session_id,
        block_id = ctx.block_id,
        args = { defer_selection = true },
      })
      if err then error(err, 0) end
      local picker = result.result
      if not picker or not picker.client_id or not picker.session_id then
        error("Remote project picker did not return its client and session", 0)
      end
      result, err = rex.call("client.perform", {
        client_id = picker.client_id,
        action = "session.select",
        args = { session_id = picker.session_id },
        timeout_ms = 5000,
      })
    else
      result, err = rex.invoke("project_picker_backend")
    end
    if err then error(err, 0) end
    return result
  end,
}
rex.bind("shift+cmd+o", "open_recent_project")
