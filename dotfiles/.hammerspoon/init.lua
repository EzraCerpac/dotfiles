local home = os.getenv("HOME")
local image_dir = home .. "/.config/keyboard/corne-qmk/images/generated"

local layer_images = {
    [0] = image_dir .. "/layer0.png",
    [1] = image_dir .. "/layer1.png",
    [2] = image_dir .. "/layer2.png",
    [3] = image_dir .. "/layer3.png",
}

local layer_names = {
    [0] = "Base",
    [1] = "NumSym",
    [2] = "NavFn",
    [3] = "Game",
}

local signal_to_layer = {
    ["f17"] = 0,
    ["f18"] = 1,
    ["f19"] = 2,
    ["f23"] = 3,
}

local current_layer = 0
local overlay = nil
local overlay_visible = false
local signal_tap = nil
local signal_hotkeys = {}
local enable_gitlogue_idle = false
local gitlogue_idle_timer = nil
local gitlogue_focus_timer = nil
local gitlogue_screen_watcher = nil
local gitlogue_has_launched = false
local gitlogue_has_locked = false
local gitlogue_screen_locked = false
local gitlogue_task = nil
local gitlogue_target = nil
local gitlogue_stop_pending = false

local gitlogue_config = {
    launcher = home .. "/.local/bin/gitlogue-screensaver",
    rex = home .. "/.local/bin/rex",
    window_title = "gitlogue-screensaver",
    idle_start_seconds = 300,
    lock_after_seconds = 900,
    reset_threshold_seconds = 5,
    poll_interval_seconds = 5,
}

local function image_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_output(command)
    local output, ok, _, rc = hs.execute(command, true)
    if ok and rc == 0 then
        return output
    end
    return nil
end

-- Only act on the exact window and session returned by our launcher.
local function gitlogue_window()
    local target = gitlogue_target
    if not target then return nil end
    local window = hs.window.get(target.window_id)
    if not window then return nil end
    local app = window:application()
    if not app or app:bundleID() ~= "com.superlogical.rex" or app:pid() ~= target.pid then return nil end
    if not window:title():match(" %- gitlogue%-screensaver$") then return nil end
    return window
end

local function gitlogue_session_is_ours()
    local target = gitlogue_target
    if not target then return false end
    local output = command_output(shell_quote(gitlogue_config.rex)
        .. " --autostart=false session inspect " .. shell_quote(target.session) .. " --json")
    if not output then return false end
    local ok, data = pcall(hs.json.decode, output)
    if not ok or type(data) ~= "table" or type(data.windows) ~= "table" or #data.windows ~= 1 then return false end
    local blocks = {}
    for _, layer in ipairs(data.windows[1].layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do blocks[#blocks + 1] = block end
    end
    return #blocks == 1 and blocks[1].block_id == target.block
end

local function matching_gitlogue_windows()
    local target = gitlogue_target
    local app = target and hs.application.get("com.superlogical.rex")
    if not app or app:pid() ~= target.pid then return nil end
    local count = 0
    for _, window in ipairs(app:allWindows()) do
        if window:title():match(" %- gitlogue%-screensaver$") then count = count + 1 end
    end
    return count
end

local function focus_gitlogue_window(attempt)
    local window = gitlogue_window()
    if window then
        window:focus()
        window:setFullScreen(true)
    elseif attempt < 8 and gitlogue_target then
        gitlogue_focus_timer = hs.timer.doAfter(0.5, function() focus_gitlogue_window(attempt + 1) end)
    end
end

local function stop_gitlogue(attempt)
    attempt = attempt or 0
    gitlogue_stop_pending = true
    if gitlogue_focus_timer then gitlogue_focus_timer:stop(); gitlogue_focus_timer = nil end
    local target = gitlogue_target
    local window = gitlogue_window()
    if target and not window and attempt < 8 then
        gitlogue_focus_timer = hs.timer.doAfter(0.5, function() stop_gitlogue(attempt + 1) end)
        return
    end
    if not target or not window or matching_gitlogue_windows() ~= 1 or not gitlogue_session_is_ours() then
        gitlogue_target = nil
        return
    end
    -- Closing a Rex window detaches its session. Kill only our still-unchanged
    -- one-block session, after confirming no matching window remains.
    if window:close() and matching_gitlogue_windows() == 0 and gitlogue_session_is_ours() then
        hs.execute(shell_quote(gitlogue_config.rex) .. " --autostart=false kill " .. shell_quote(target.session), true)
    end
    gitlogue_target = nil
end

local function launch_gitlogue()
    if not image_exists(gitlogue_config.launcher) then
        hs.notify.new({ title = "Gitlogue Screensaver", informativeText = "Missing launcher: " .. gitlogue_config.launcher }):send()
        return false
    end
    if gitlogue_task then return true end
    if gitlogue_window() then focus_gitlogue_window(0); return true end
    gitlogue_stop_pending = false
    gitlogue_task = hs.task.new(gitlogue_config.launcher, function(code, output)
        gitlogue_task = nil
        local window_id, pid, session, block = (output or ""):match("^(%d+)\t(%d+)\t(session:[%w%-]+)\t(block:[%w%-]+)%s*$")
        if code ~= 0 or not window_id then
            gitlogue_has_launched = false
            return
        end
        gitlogue_target = { window_id = tonumber(window_id), pid = tonumber(pid), session = session, block = block }
        if gitlogue_stop_pending then stop_gitlogue() else focus_gitlogue_window(0) end
    end, {})
    if not gitlogue_task then return false end
    gitlogue_task:start()
    return true
end

local function handle_gitlogue_idle()
    local idle_seconds = hs.host.idleTime()

    if gitlogue_screen_locked then
        return
    end

    if idle_seconds < gitlogue_config.reset_threshold_seconds then
        if gitlogue_has_launched then
            stop_gitlogue()
        end
        gitlogue_has_launched = false
        gitlogue_has_locked = false
        return
    end

    if idle_seconds >= gitlogue_config.lock_after_seconds then
        if not gitlogue_has_locked then
            stop_gitlogue()
            gitlogue_has_locked = true
            hs.caffeinate.lockScreen()
        end
        return
    end

    if idle_seconds >= gitlogue_config.idle_start_seconds then
        if not gitlogue_has_launched then
            gitlogue_has_launched = launch_gitlogue()
        elseif not gitlogue_task and not gitlogue_window() then
            gitlogue_has_launched = false
        end
    end
end

local function remove_overlay()
    if overlay then
        overlay:delete()
        overlay = nil
    end
end

local function ensure_overlay(layer)
    remove_overlay()

    local image_path = layer_images[layer]
    if not image_exists(image_path) then
        hs.notify.new({
            title = "Corne HUD",
            informativeText = "Missing image for " .. (layer_names[layer] or tostring(layer)) .. ": " .. image_path,
        }):send()
        return false
    end

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    overlay = hs.canvas.new({
        x = frame.x + frame.w - 520,
        y = frame.y + frame.h - 340,
        w = 500,
        h = 300,
    })

    overlay:appendElements({
        {
            type = "image",
            image = hs.image.imageFromPath(image_path),
            imageScaling = "scaleToFit",
        },
    })

    overlay:level(hs.canvas.windowLevels.floating)
    overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    overlay:alpha(0.92)
    overlay:show()

    current_layer = layer
    return true
end

local function update_layer(layer)
    current_layer = layer
    if overlay_visible then
        ensure_overlay(layer)
    end
end

local function toggle_overlay()
    overlay_visible = not overlay_visible
    if overlay_visible then
        ensure_overlay(current_layer)
    else
        remove_overlay()
    end
end

hs.hotkey.bind({"cmd", "ctrl"}, "O", toggle_overlay)

for key, layer in pairs(signal_to_layer) do
    if hs.keycodes.map[key] ~= nil then
        local hotkey = hs.hotkey.bind({}, key, function()
            update_layer(layer)
        end)
        if hotkey then
            table.insert(signal_hotkeys, hotkey)
        end
    end
end

local signal_keycodes = {}
for key, layer in pairs(signal_to_layer) do
    local keycode = hs.keycodes.map[key]
    if keycode ~= nil then
        signal_keycodes[keycode] = layer
    end
end

signal_tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local keycode = event:getKeyCode()
    local layer = signal_keycodes[keycode]
    if layer ~= nil then
        update_layer(layer)
        return true
    end
    return false
end)
signal_tap:start()

if enable_gitlogue_idle then
    gitlogue_screen_watcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.screensDidLock then
            gitlogue_screen_locked = true
            stop_gitlogue()
        elseif event == hs.caffeinate.watcher.screensDidUnlock then
            gitlogue_screen_locked = false
            gitlogue_has_launched = false
            gitlogue_has_locked = false
        elseif event == hs.caffeinate.watcher.screensDidSleep then
            stop_gitlogue()
        end
    end)
    gitlogue_screen_watcher:start()

    gitlogue_idle_timer = hs.timer.doEvery(gitlogue_config.poll_interval_seconds, handle_gitlogue_idle)
    handle_gitlogue_idle()
end

aerospace_workspaces = require("aerospace_workspaces").new():start()
rex_navigation = require("rex_navigation").start()

local registered = {}
for _, key in ipairs({"f17", "f18", "f19", "f23"}) do
    if hs.keycodes.map[key] ~= nil then
        table.insert(registered, key)
    end
end

hs.notify.new({
    title = "Corne HUD",
    informativeText = "Loaded. Toggle Cmd+Ctrl+O. Layers: Base/NumSym/NavFn/Game. Signals: F17/F18/F19/F23. Registered: " .. table.concat(registered, ", "),
}):send()
