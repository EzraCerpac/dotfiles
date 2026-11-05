local terminal = "com.superlogical.terminal"
local directions = { left = true, right = true, up = true, down = true }

local function focused(view)
  for _, window in ipairs(view.windows or {}) do
    if window.window_id == view.active_window_id then
      return window.focused_block_id, window.window_id
    end
  end
end

-- Runs on the server that owns the pane, including remote servers.
rex.action {
  name = "rex_nvim_probe",
  title = "Move within Neovim",
  args = { direction = "string" },
  run = function(ctx, args)
    assert(directions[args.direction], "invalid direction")
    local process, err = rex.block.call(terminal, "process", { block_id = ctx.block_id })
    assert(process, err)
    local foreground = process.foreground
    if not foreground or foreground.name ~= "nvim" then return { state = "not_editor" } end
    assert(foreground.path and foreground.pid and foreground.user_id, "incomplete Neovim process information")
    local socket = string.format("%s/.local/state/rex/nvim/%d-%d", assert(os.getenv("HOME")), foreground.user_id, foreground.pid)
    local expression = "luaeval(\"require('config.modules.rex-navigation').move('" .. args.direction .. "')\")"
    local result, exec_err = rex.exec({ foreground.path, "--clean", "--headless", "--server", socket, "--remote-expr", expression }, { timeout = 1 })
    assert(result and result.ok, exec_err or (result and result.stderr) or "Neovim probe failed")
    local state = result.stdout:match("^%s*(%a+)%s*$")
    assert(state == "moved" or state == "edge", "invalid Neovim response")
    return { state = state }
  end,
}

rex.action {
  name = "rex_navigate",
  title = "Navigate across editor, panes, and windows",
  args = { direction = "string" },
  run = function(ctx, args)
    -- Hammerspoon supplies a single-use request ID; without it never fall back.
    local request = io.open(assert(os.getenv("HOME")) .. "/.local/state/rex/navigation/request", "r")
    if not request then return end
    local id, requested_direction = request:read("*l"), request:read("*l")
    request:close()
    if not id or not id:match("^%d+$") or args.direction ~= requested_direction or not directions[args.direction] then return end
    local function reply(state)
      local url = "hammerspoon://rex-navigation?request=" .. id .. "&state=" .. state
      rex.exec({ "/usr/bin/open", "-g", url }, { timeout = 1 })
    end
    local ok, state = pcall(function()
      assert(ctx.session_id and ctx.block_id, "missing context")
      local before = assert(rex.session.view {})
      local block, window = focused(before)
      assert(block == ctx.block_id, "focus changed")
      local creator
      for _, w in ipairs(before.windows or {}) do
        if w.window_id == window then
          for _, layer in ipairs(w.layers or {}) do
            for _, b in ipairs(layer.blocks or {}) do
              if b.block_id == block then creator = b.creator_name end
            end
          end
        end
      end
      assert(creator, "focused block missing")
      if creator == terminal then
        local probe, err
        if ctx.server then
          probe, err = rex.call("client.action", { action = "rex_nvim_probe", session_id = ctx.session_id, block_id = ctx.block_id, args = { direction = args.direction } })
          if probe then probe = probe.result end
        else
          probe, err = rex.invoke("rex_nvim_probe", { direction = args.direction })
        end
        assert(probe, err)
        if probe.state == "moved" then return "handled" end
        assert(probe.state == "edge" or probe.state == "not_editor", "invalid probe result")
      end
      local current = assert(rex.session.view {})
      local current_block, current_window = focused(current)
      assert(current_block == block and current_window == window, "focus changed")
      assert(rex.session.focus_direction { direction = args.direction, wrap = false })
      local after = assert(rex.session.view {})
      local next_block, next_window = focused(after)
      assert(next_block and next_window == window, "focus changed unexpectedly")
      return next_block == block and "edge" or "handled"
    end)
    reply(ok and state or "error")
  end,
}
