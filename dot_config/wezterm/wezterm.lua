-- WezTerm config with sensible defaults and AeroSpace integration
-- Source of integration idea: see repo docs and AeroSpace issue #412

local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Appearance
config.color_scheme = 'Catppuccin Mocha'
config.font_size = 14.0
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = 'RESIZE'
config.window_background_opacity = 0.7
config.macos_window_background_blur = 20
config.use_fancy_tab_bar = false
config.audible_bell = 'Disabled'
config.scrollback_lines = 10000
config.hide_mouse_cursor_when_typing = true

-- Make Option behave like Alt/Meta (compose off) — similar to Ghostty
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Key helpers
local function to_wez_dir(dir)
  -- Map aerospace direction words to WezTerm expected values
  local m = {
    left = 'Left', right = 'Right', up = 'Up', down = 'Down',
    Left = 'Left', Right = 'Right', Up = 'Up', Down = 'Down',
    h = 'Left', j = 'Down', k = 'Up', l = 'Right',
  }
  return m[dir] or dir
end

local function is_vim(p)
  local ok, vars = pcall(function()
    return p:get_user_vars()
  end)
  if not ok or not vars then
    return false
  end
  local v = vars.IS_NVIM
  if not v then
    return false
  end
  v = tostring(v):lower()
  return v == 'true' or v == '1' or v == 'yes'
end

--
-- AeroSpace integration
--
-- A tiny wrapper script in ~/.config/aerospace/bin sends a user var into WezTerm:
--   wezterm cli set-user-var AEROSPACE_FOCUS <dir>
-- We handle it here: if a pane exists in that direction, navigate inside WezTerm;
-- otherwise, fall back to AeroSpace focus in the same direction.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'AEROSPACE_FOCUS' or not value or value == '' then
    return
  end

  local dir = to_wez_dir(value)
  local tab = window:active_tab()
  if not tab then
    return
  end

  -- If Neovim is running in the active pane, forward Alt-h/j/k/l into it.
  if is_vim(pane) then
    local key_from_dir = { Left = 'h', Down = 'j', Up = 'k', Right = 'l' }
    local key = key_from_dir[dir]
    if key then
      window:perform_action(act.SendKey({ key = key, mods = 'ALT' }), pane)
      return
    end
  end

  -- If a pane exists in that direction, move within WezTerm.
  if tab:get_pane_direction(dir) then
    window:perform_action(act.ActivatePaneDirection(dir), pane)
    return
  end

  -- Otherwise, delegate back to AeroSpace to move between windows.
  wezterm.log_info('No pane ' .. dir .. ' — delegating to AeroSpace')
  -- Best-effort: ignore failures if aerospace is not available.
  wezterm.run_child_process({ 'aerospace', 'focus', string.lower(dir) })
end)

-- Reasonable macOS-centric keys that avoid Alt-h/j/k/l conflicts (handled by AeroSpace)
config.keys = {
  -- Split panes
  { key = 'd', mods = 'CMD', action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
  { key = 'D', mods = 'CMD|SHIFT', action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) },

  -- Pane zoom
  { key = 'Enter', mods = 'CMD|SHIFT', action = act.TogglePaneZoomState },

  -- Tabs
  { key = 't', mods = 'CMD', action = act.SpawnTab('CurrentPaneDomain') },
  { key = 'w', mods = 'CMD', action = act.CloseCurrentTab({ confirm = true }) },
  { key = 'LeftArrow', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(1) },

  -- Copy/Paste like macOS
  { key = 'c', mods = 'CMD', action = act.CopyTo('Clipboard') },
  { key = 'v', mods = 'CMD', action = act.PasteFrom('Clipboard') },
}

return config
