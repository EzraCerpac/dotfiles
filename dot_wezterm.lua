-- WezTerm config with sensible defaults and AeroSpace integration
-- Source of integration idea: see repo docs and AeroSpace issue #412

---@type Wezterm
local wezterm = require("wezterm")
local act = wezterm.action

---@type Config
local config = (wezterm.config_builder and wezterm.config_builder()) or {}

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

local function is_vim(pane)
  -- this is set by the plugin, and unset on ExitPre in Neovim
  return pane:get_user_vars().IS_NVIM == "true"
end
--   -- Prefer explicit user var if a plugin sets it (e.g., smart-splits.nvim)
--   local ok_vars, vars = pcall(function()
--     return pane:get_user_vars()
--   end)
--   if ok_vars and vars and vars.IS_NVIM then
--     local v = tostring(vars.IS_NVIM):lower()
--     if v == "true" or v == "1" or v == "yes" then
--       return true
--     end
--   end
--   -- Fallback: foreground process name (works for local shells)
--   local ok_name, name = pcall(function()
--     return pane:get_foreground_process_name()
--   end)
--   if not ok_name or not name then
--     return false
--   end
--   name = tostring(name):lower()
--   return name:find("nvim") or name:find(" vim$") or name:find("/n?vim$")
-- end

local direction_keys = {
  h = "Left",
  j = "Down",
  k = "Up",
  l = "Right",
}
local resize_mod = "CTRL|META"
local move_mod = "META"

local function split_nav(resize_or_move, key)
  return {
    key = key,
    mods = resize_or_move == "resize" and resize_mod or move_mod,
    action = wezterm.action_callback(function(win, pane)
      if is_vim(pane) then
        -- pass the keys through to vim/nvim
        win:perform_action({
          SendKey = { key = key, mods = resize_or_move == "resize" and resize_mod or move_mod },
        }, pane)
      else
        local pane_dir = direction_keys[key]
        if resize_or_move == "resize" then
          win:perform_action({ AdjustPaneSize = { pane_dir, 3 } }, pane)
        else
          -- win:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)
          local tab = win:active_tab()
          if tab and tab:get_pane_direction(pane_dir) then
            win:perform_action(act.ActivatePaneDirection(pane_dir), pane)
            return
          end
          -- Fall back to AeroSpace window focus
          local ok =
            pcall(wezterm.run_child_process, { "aerospace", "focus", string.lower(pane_dir) })
          if not ok then
            wezterm.log_info("AeroSpace CLI not available for focus " .. pane_dir)
          end
        end
      end
    end),
  }
end

wezterm.on("ActivatePaneDirection-left", split_nav("move", "h"))
wezterm.on("ActivatePaneDirection-right", split_nav("move", "l"))
wezterm.on("ActivatePaneDirection-up", split_nav("move", "k"))
wezterm.on("ActivatePaneDirection-down", split_nav("move", "j"))

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
  -- { key = "h", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-left") },
  -- { key = "j", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-down") },
  -- { key = "k", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-up") },
  -- { key = "l", mods = "ALT", action = act.EmitEvent("ActivatePaneDirection-right") },
  -- move between split panes
  split_nav("move", "h"),
  split_nav("move", "j"),
  split_nav("move", "k"),
  split_nav("move", "l"),
  -- resize panes
  split_nav("resize", "h"),
  split_nav("resize", "j"),
  split_nav("resize", "k"),
  split_nav("resize", "l"),
}

return config
