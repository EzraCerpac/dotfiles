local M = {}
local pending
local sequence = 0
local home = assert(os.getenv("HOME"))
local state_dir = home .. "/.local/state/rex/navigation"
local request_path = state_dir .. "/request"

local function prepare_state_dir()
  for _, path in ipairs({ home .. "/.local", home .. "/.local/state", home .. "/.local/state/rex", state_dir }) do
    if hs.fs.attributes(path, "mode") ~= "directory" and not hs.fs.mkdir(path) then return false end
  end
  local quoted = "'" .. state_dir:gsub("'", "'\\''") .. "'"
  local _, ok = hs.execute("/bin/chmod 700 " .. quoted, true)
  return ok
end
local wm_focus = os.getenv("HOME") .. "/.local/bin/wm-focus"
local keys = { left = "f13", down = "f14", up = "f15", right = "f16" }

local function focus_window_manager(direction)
  local task = hs.task.new(wm_focus, nil, { direction })
  if task then task:start() end
end

local function navigate(direction)
  if pending then return end
  local window = hs.window.focusedWindow()
  local app = window and window:application()
  if not app or app:bundleID() ~= "com.superlogical.rex" then
    focus_window_manager(direction)
    return
  end
  if not prepare_state_dir() then return end
  sequence = sequence + 1
  local id = string.format("%.0f", hs.timer.absoluteTime()) .. tostring(sequence)
  local request = io.open(request_path .. ".tmp", "w")
  if not request then return end
  request:write(id, "\n", direction, "\n")
  request:close()
  if not os.rename(request_path .. ".tmp", request_path) then return end
  pending = { id = id, direction = direction, window = window:id() }
  hs.timer.doAfter(5, function()
    if pending and pending.id == id then pending = nil end
  end)
  hs.eventtap.keyStroke({ "ctrl", "shift" }, keys[direction], 0, app)
end

function M.start()
  hs.urlevent.bind("rex-navigation", function(_, params)
    local request = pending
    if not request or params.request ~= request.id then return end
    pending = nil
    if params.state ~= "edge" then return end
    local window = hs.window.focusedWindow()
    if window and window:id() == request.window then
      focus_window_manager(request.direction)
    end
  end)
  local directions = { h = "left", j = "down", k = "up", l = "right", left = "left", down = "down", up = "up", right = "right" }
  for key, direction in pairs(directions) do
    hs.hotkey.bind({ "cmd", "ctrl", "alt" }, key, function() navigate(direction) end)
  end
end

return M
