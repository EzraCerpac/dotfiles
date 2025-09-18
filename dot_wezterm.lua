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

-- tab bar
local bar = wezterm.plugin.require("https://github.com/adriankarlen/bar.wezterm")
bar.apply_to_config(config)
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

-- wezterm.on("update-right-status", function(window, _)
--   local SOLID_LEFT_ARROW = ""
--   local ARROW_FOREGROUND = { Foreground = { Color = "#c6a0f6" } }
--   local prefix = ""
--
--   -- if window:leader_is_active() then
--   --   prefix = " " .. utf8.char(0x1f30a) -- ocean wave
--   --   SOLID_LEFT_ARROW = utf8.char(0xe0b2)
--   -- end
--
--   if window:active_tab():tab_id() ~= 0 then
--     ARROW_FOREGROUND = { Foreground = { Color = "#1e2030" } }
--   end -- arrow color based on if tab is first pane
--
--   window:set_left_status(wezterm.format({
--     { Background = { Color = "#b7bdf8" } },
--     { Text = prefix },
--     ARROW_FOREGROUND,
--     { Text = SOLID_LEFT_ARROW },
--   }))
-- end)

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
local aerospace_user_var = "ActivatePaneFromAerospace"
local inverse_direction_keys = {
  left = "h",
  down = "j",
  up = "k",
  right = "l",
}
local resize_mod = "CTRL|ALT"
local move_mod = "META"

local aerospace_cli_candidates = {}
do
  local env_cli = os.getenv("AEROSPACE_CLI")
  if env_cli and env_cli ~= "" then
    table.insert(aerospace_cli_candidates, env_cli)
  end
  table.insert(aerospace_cli_candidates, "aerospace")
  table.insert(aerospace_cli_candidates, "/opt/homebrew/bin/aerospace")
end

local function focus_aerospace(direction)
  local dir = string.lower(direction)
  for _, cli in ipairs(aerospace_cli_candidates) do
    if cli and cli ~= "" then
      local ok, result = pcall(wezterm.run_child_process, {
        cli,
        "focus",
        "--boundaries",
        "all-monitors-outer-frame",
        dir,
      })
      if ok and result then
        return true
      end
    end
  end
  return false
end

local function split_nav_callback(resize_or_move, key)
  return function(win, pane)
    if is_vim(pane) then
      win:perform_action({
        SendKey = { key = key, mods = resize_or_move == "resize" and resize_mod or move_mod },
      }, pane)
    else
      local pane_dir = direction_keys[key]
      if resize_or_move == "resize" then
        win:perform_action({ AdjustPaneSize = { pane_dir, 3 } }, pane)
      else
        local tab = win:active_tab()
        if tab and tab:get_pane_direction(pane_dir) then
          win:perform_action(act.ActivatePaneDirection(pane_dir), pane)
          return
        end
        if not focus_aerospace(pane_dir) then
          wezterm.log_info("AeroSpace CLI not available for focus " .. pane_dir)
        end
      end
    end
  end
end

local function split_nav(resize_or_move, key)
  return {
    key = key,
    mods = resize_or_move == "resize" and resize_mod or move_mod,
    action = wezterm.action_callback(split_nav_callback(resize_or_move, key)),
  }
end

-- Register pane navigation events with minimal duplication
for dir, key in pairs({ left = "h", right = "l", up = "k", down = "j" }) do
  wezterm.on("ActivatePaneDirection-" .. dir, split_nav_callback("move", key))
end

wezterm.on("user-var-changed", function(window, pane, name, value)
  if name ~= aerospace_user_var then
    return
  end
  if not value or value == "" then
    return
  end
  local key = inverse_direction_keys[string.lower(value)]
  if not key then
    wezterm.log_info("Unknown AeroSpace direction: " .. tostring(value))
    return
  end
  split_nav_callback("move", key)(window, pane)
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
