local home = os.getenv("HOME")
local image_dir = home .. "/.config/keyboard/corne-qmk/images/generated"

local layer_images = {
    [0] = image_dir .. "/layer0.png",
    [1] = image_dir .. "/layer1.png",
    [2] = image_dir .. "/layer2.png",
    [3] = image_dir .. "/layer3.png",
}

local signal_to_layer = {
    ["f17"] = 0,
    ["f18"] = 1,
    ["f19"] = 2,
    ["f23"] = 3,
    ["f20"] = 0,
    ["f21"] = 1,
    ["f22"] = 2,
    ["f14"] = 0,
    ["f15"] = 1,
    ["f16"] = 2,
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

local gitlogue_config = {
    launcher = home .. "/.local/bin/gitlogue-screensaver",
    wezterm = "/opt/homebrew/bin/wezterm",
    workspace = "gitlogue-screensaver",
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

local function gitlogue_targets()
    if not image_exists(gitlogue_config.wezterm) then
        return {}
    end

    local list_command = shell_quote(gitlogue_config.wezterm) .. " cli list --format json"
    local output = command_output(list_command)
    if not output or output == "" then
        return {}
    end

    local decoded = hs.json.decode(output)
    if type(decoded) ~= "table" then
        return {}
    end

    local targets = {}
    for _, entry in ipairs(decoded) do
        if entry.workspace == gitlogue_config.workspace
            or entry.window_title == gitlogue_config.window_title
            or entry.title == gitlogue_config.window_title then
            table.insert(targets, entry)
        end
    end

    return targets
end

local function gitlogue_window()
    local app = hs.application.get("WezTerm")
    if not app then
        return nil
    end

    for _, window in ipairs(app:allWindows()) do
        if window:title() == gitlogue_config.window_title then
            return window
        end
    end

    return nil
end

local function focus_gitlogue_window(attempt)
    local window = gitlogue_window()
    if window then
        window:focus()
        window:setFullScreen(true)
        return
    end

    if attempt >= 8 then
        return
    end

    gitlogue_focus_timer = hs.timer.doAfter(0.5, function()
        focus_gitlogue_window(attempt + 1)
    end)
end

local function stop_gitlogue()
    local targets = gitlogue_targets()
    for _, entry in ipairs(targets) do
        local kill_command = string.format(
            "%s cli kill-pane --pane-id %s",
            shell_quote(gitlogue_config.wezterm),
            tostring(entry.pane_id)
        )
        hs.execute(kill_command, true)
    end
end

local function launch_gitlogue()
    if not image_exists(gitlogue_config.launcher) then
        hs.notify.new({
            title = "Gitlogue Screensaver",
            informativeText = "Missing launcher: " .. gitlogue_config.launcher,
        }):send()
        return false
    end

    if #gitlogue_targets() > 0 then
        focus_gitlogue_window(0)
        return true
    end

    local task = hs.task.new(gitlogue_config.launcher, nil, {})
    if not task then
        hs.notify.new({
            title = "Gitlogue Screensaver",
            informativeText = "Could not create launcher task.",
        }):send()
        return false
    end

    task:start()
    focus_gitlogue_window(0)
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
        elseif #gitlogue_targets() == 0 then
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
            informativeText = "Missing image: " .. image_path,
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

local registered = {}
for _, key in ipairs({"f17", "f18", "f19", "f23", "f20", "f21", "f22", "f14", "f15", "f16"}) do
    if hs.keycodes.map[key] ~= nil then
        table.insert(registered, key)
    end
end

hs.notify.new({
    title = "Corne HUD",
    informativeText = "Loaded. Toggle Cmd+Ctrl+O. Signals: F17/F18/F19/F23 (compat F20/F21/F22 + F14/F15/F16). Registered: " .. table.concat(registered, ", "),
}):send()
