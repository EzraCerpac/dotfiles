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

local function image_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
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
