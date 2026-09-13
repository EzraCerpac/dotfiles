local root = assert(os.getenv("AEROSPACE_DEFAULTS_TEST_ROOT"))
local module = dofile(root .. "/dot_hammerspoon/aerospace_workspaces.lua")

local function screen(uuid, name, x)
  return {
    getUUID = function() return uuid end,
    name = function() return name end,
    fullFrame = function() return { x = x, y = 0, w = 1200, h = 800 } end,
  }
end

local function make_runtime(initial_screens, options)
  options = options or {}
  local runtime = { calls = {}, timers = {}, settings_values = options.settings or {}, screens = initial_screens }
  local app_pid = options.pid

  runtime.settings = {
    get = function(key) return runtime.settings_values[key] end,
    set = function(key, value) runtime.settings_values[key] = value end,
  }
  runtime.fs = { attributes = function() return { mode = "file" } end }
  runtime.json = {
    decode = function(value)
      if value == "MONITORS" then
        return options.monitor_records or {
          { ["monitor-id"] = "1", ["monitor-appkit-nsscreen-screens-id"] = "1", ["monitor-name"] = "Built-in Retina Display" },
          { ["monitor-id"] = "3", ["monitor-appkit-nsscreen-screens-id"] = "2", ["monitor-name"] = "External Left" },
          { ["monitor-id"] = "2", ["monitor-appkit-nsscreen-screens-id"] = "3", ["monitor-name"] = "External Right" },
        }
      end
      if value == "FOCUSED" then
        return { { workspace = "4" } }
      end
      if value == "FOCUSED_WINDOW" then
        return { { ["window-id"] = 4242 } }
      end
      error("unexpected JSON fixture: " .. tostring(value))
    end,
  }
  runtime.screen = {
    allScreens = function() return runtime.screens end,
    watcher = {
      new = function(callback)
        runtime.screen_callback = callback
        return { start = function() runtime.watcher_started = true end }
      end,
    },
  }
  runtime.timer = {
    doAfter = function(delay, callback)
      local timer = { delay = delay, callback = callback, stopped = false }
      function timer:stop() self.stopped = true end
      table.insert(runtime.timers, timer)
      return timer
    end,
  }
  runtime.urlevent = { bind = function(name, callback) runtime.url_callback = callback end }
  runtime.application = {
    get = function(name)
      assert(name == "AeroSpace")
      if app_pid == nil then return nil end
      return { pid = function() return app_pid end }
    end,
  }
  runtime.task = {
    new = function(path, callback, stream_callback, args)
      assert(stream_callback == nil, "test tasks should not use streaming callbacks")
      local task = { path = path, args = args }
      function task:start()
        table.insert(runtime.calls, table.concat(args, " "))
        local output = ""
        if args[1] == "list-monitors" then output = "MONITORS" end
        if args[1] == "list-workspaces" then output = "FOCUSED" end
        if args[1] == "list-windows" then output = "FOCUSED_WINDOW" end
        local exit_code = options.fail_focus and args[1] == "focus" and 1 or 0
        callback(exit_code, output, "")
        return true
      end
      return task
    end,
  }

  function runtime:flush_timers()
    local timers = self.timers
    self.timers = {}
    for _, timer in ipairs(timers) do
      if not timer.stopped then
        assert(timer.delay == 0.5, "checks must be debounced for 0.5 seconds")
        timer.callback()
      end
    end
  end

  return runtime
end

local function placement_calls(runtime)
  local result = {}
  for _, call in ipairs(runtime.calls) do
    if call:match("^move%-workspace%-to%-monitor") then
      table.insert(result, call)
    end
  end
  return result
end

local built_in = screen("37D8832A-2D66-02CA-B9F7-8F30A301B230", "Built-in Retina Display", 0)
local left = screen("external-left", "External Left", -1200)
local right = screen("external-right", "External Right", 1200)

-- Startup maps the rightmost NSScreen index to AeroSpace's monitor ID and restores the old workspace.
local persistent = {}
local runtime = make_runtime({ built_in, left, right }, { pid = 101, settings = persistent })
module.new({ hs = runtime, home = "/test", aerospacePath = "/test/aerospace" }):start()
runtime:flush_timers()
local moved = placement_calls(runtime)
assert(#moved == 2, "startup should place both default workspaces")
assert(moved[1] == "move-workspace-to-monitor --workspace 9 -- 2", "Ops must use the monitor mapped from rightmost NSScreen")
assert(moved[2] == "move-workspace-to-monitor --workspace M -- 2", "Media must use the monitor mapped from rightmost NSScreen")
assert(runtime.calls[#runtime.calls] == "focus --window-id 4242", "focused window must be restored after placement")

-- Duplicate watcher events and display rearrangement do not reclaim a manual override.
local moved_before = #placement_calls(runtime)
right.fullFrame = function() return { x = 1400, y = 80, w = 1200, h = 800 } end
runtime.screen_callback()
runtime.screen_callback()
runtime:flush_timers()
assert(#placement_calls(runtime) == moved_before, "same external UUID set must not move workspaces")

-- Reloading Hammerspoon with the same AeroSpace process must leave manual placement alone.
local reloaded = make_runtime({ built_in, left, right }, { pid = 101, settings = persistent })
module.new({ hs = reloaded, home = "/test", aerospacePath = "/test/aerospace" }):start()
reloaded:flush_timers()
assert(#placement_calls(reloaded) == 0, "config reload must not replay startup defaults")

-- A new external display connection applies defaults once; disconnect alone does nothing; reconnect applies again.
local attach_settings = {}
local attach = make_runtime({ built_in }, { pid = 202, settings = attach_settings })
module.new({ hs = attach, home = "/test", aerospacePath = "/test/aerospace" }):start()
attach:flush_timers()
assert(#placement_calls(attach) == 0, "no external display must be a no-op")
attach.screens = { built_in, right }
attach.screen_callback()
attach.screen_callback()
attach:flush_timers()
assert(#placement_calls(attach) == 2, "external attach must place both defaults once")
attach.screens = { built_in }
attach.screen_callback()
attach:flush_timers()
assert(#placement_calls(attach) == 2, "disconnect must not move workspaces")
attach.screens = { built_in, right }
attach.screen_callback()
attach:flush_timers()
assert(#placement_calls(attach) == 4, "reconnect must apply defaults again")

-- Tied rightmost external frames are ambiguous, so fail closed without moving.
local ambiguous = make_runtime({
  built_in,
  left,
  screen("external-right-ambiguous", "External Right", 1200),
  screen("external-east", "External East", 1200),
}, { pid = 303 })
module.new({ hs = ambiguous, home = "/test", aerospacePath = "/test/aerospace" }):start()
ambiguous:flush_timers()
assert(#placement_calls(ambiguous) == 0, "ambiguous rightmost display must be a no-op")

-- Missing or duplicate NSScreen-to-monitor matches are also ambiguous and fail closed.
local duplicate_mapping = make_runtime({ built_in, right }, {
  pid = 304,
  monitor_records = {
    { ["monitor-id"] = "2", ["monitor-appkit-nsscreen-screens-id"] = "2", ["monitor-name"] = "External Right" },
    { ["monitor-id"] = "3", ["monitor-appkit-nsscreen-screens-id"] = "2", ["monitor-name"] = "External Duplicate" },
  },
})
module.new({ hs = duplicate_mapping, home = "/test", aerospacePath = "/test/aerospace" }):start()
duplicate_mapping:flush_timers()
assert(#placement_calls(duplicate_mapping) == 0, "duplicate screen mapping must be a no-op")

-- If the original window closes during placement, restore its prior workspace instead.
local fallback = make_runtime({ built_in, right }, { pid = 404, fail_focus = true })
module.new({ hs = fallback, home = "/test", aerospacePath = "/test/aerospace" }):start()
fallback:flush_timers()
assert(fallback.calls[#fallback.calls] == "workspace 4", "missing focused window should fall back to its workspace")

-- External connection notifications are ignored when AeroSpace itself is not running.
local stopped = make_runtime({ built_in }, { pid = nil })
module.new({ hs = stopped, home = "/test", aerospacePath = "/test/aerospace" }):start()
stopped:flush_timers()
stopped.screens = { built_in, right }
stopped.screen_callback()
stopped:flush_timers()
assert(#stopped.calls == 0, "missing AeroSpace must be a no-op")

print("AeroSpace display defaults tests passed")
