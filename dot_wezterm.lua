-- WezTerm config with sensible defaults and AeroSpace integration
-- Source of integration idea: see repo docs and AeroSpace issue #412

local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Appearance
config.color_scheme = "Catppuccin Mocha"
config.font_size = 14.0
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.7
config.macos_window_background_blur = 20
config.use_fancy_tab_bar = false
config.audible_bell = "Disabled"
config.scrollback_lines = 10000
config.hide_mouse_cursor_when_typing = true

-- Make Option behave like Alt/Meta (compose off) — similar to Ghostty
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Key helpers
local function to_wez_dir(dir)
  -- Map aerospace direction words to WezTerm expected values
  local m = {
    left = "Left",
    right = "Right",
    up = "Up",
    down = "Down",
    Left = "Left",
    Right = "Right",
    Up = "Up",
    Down = "Down",
    h = "Left",
    j = "Down",
    k = "Up",
    l = "Right",
  }
  return m[dir] or dir
end

local function is_vim(p)
  -- Prefer explicit user var if a plugin sets it (e.g., smart-splits.nvim)
  local ok_vars, vars = pcall(function()
    return p:get_user_vars()
  end)
  if ok_vars and vars and vars.IS_NVIM then
    local v = tostring(vars.IS_NVIM):lower()
    if v == "true" or v == "1" or v == "yes" then
      return true
    end
  end
  -- Fallback: foreground process name (works for local shells)
  local ok_name, name = pcall(function()
    return p:get_foreground_process_name()
  end)
  if not ok_name or not name then
    return false
  end
  name = tostring(name):lower()
  return name:find("nvim") or name:find(" vim$") or name:find("/n?vim$")
end

local function isViProcess(pane)
  -- get_foreground_process_name On Linux, macOS and Windows,
  -- the process can be queried to determine this path. Other operating systems
  -- (notably, FreeBSD and other unix systems) are not currently supported
  return pane:get_foreground_process_name():find("n?vim") ~= nil
    or pane:get_title():find("n?vim") ~= nil
end

local function conditionalActivatePane(window, pane, pane_direction, vim_direction)
  if isViProcess(pane) then
    window:perform_action(
      -- This should match the keybinds you set in Neovim.
      act.SendKey({ key = vim_direction, mods = "ALT" }),
      pane
    )
  else
    window:perform_action(act.ActivatePaneDirection(pane_direction), pane)
  end
end

-- Navigator.nvim WezTerm integration per wiki:
local function conditional_activate(window, pane, pane_dir, vim_key)
  if is_vim(pane) then
    window:perform_action(act.SendKey({ key = vim_key, mods = "ALT" }), pane)
    return
  end
  local tab = window:active_tab()
  if tab and tab:get_pane_direction(pane_dir) then
    window:perform_action(act.ActivatePaneDirection(pane_dir), pane)
    return
  end
  -- Fall back to AeroSpace window focus
  local ok = pcall(wezterm.run_child_process, { "aerospace", "focus", string.lower(pane_dir) })
  if not ok then
    wezterm.log_info("AeroSpace CLI not available for focus " .. pane_dir)
  end
end

-- wezterm.on("ActivatePaneDirection-left", function(window, pane)
--   conditional_activate(window, pane, "Left", "h")
-- end)
-- wezterm.on("ActivatePaneDirection-right", function(window, pane)
--   conditional_activate(window, pane, "Right", "l")
-- end)
-- wezterm.on("ActivatePaneDirection-up", function(window, pane)
--   conditional_activate(window, pane, "Up", "k")
-- end)
-- wezterm.on("ActivatePaneDirection-down", function(window, pane)
--   conditional_activate(window, pane, "Down", "j")
-- end)
wezterm.on("ActivatePaneDirection-right", function(window, pane)
  conditionalActivatePane(window, pane, "Right", "l")
end)
wezterm.on("ActivatePaneDirection-left", function(window, pane)
  conditionalActivatePane(window, pane, "Left", "h")
end)
wezterm.on("ActivatePaneDirection-up", function(window, pane)
  conditionalActivatePane(window, pane, "Up", "k")
end)
wezterm.on("ActivatePaneDirection-down", function(window, pane)
  conditionalActivatePane(window, pane, "Down", "j")
end)

-- Reasonable macOS-centric keys that avoid Alt-h/j/k/l conflicts (handled by AeroSpace)
config.keys = {
  -- Split panes
  { key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "D", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

  -- Pane zoom
  { key = "Enter", mods = "CMD|SHIFT", action = act.TogglePaneZoomState },

  -- Tabs
  { key = "t", mods = "CMD", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "LeftArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },

  -- Copy/Paste like macOS
  { key = "c", mods = "CMD", action = act.CopyTo("Clipboard") },
  { key = "v", mods = "CMD", action = act.PasteFrom("Clipboard") },
  -- Alt + h/j/k/l unified nav (WezTerm event approach)
  { key = "h", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-left") },
  { key = "j", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-down") },
  { key = "k", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-up") },
  { key = "l", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-right") },
}

return config
