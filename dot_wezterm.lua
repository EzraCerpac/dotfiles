-- WezTerm config with sensible defaults

---@type Wezterm
local wezterm = require("wezterm")
local act = wezterm.action

---@type Config
local config = (wezterm.config_builder and wezterm.config_builder()) or {}

-- Appearance
config.color_scheme = "Catppuccin Mocha"
config.font_size = 14.0
config.default_prog = { wezterm.home_dir .. "/.local/bin/herdr" }
config.disable_default_key_bindings = true
config.enable_tab_bar = false
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.7
config.macos_window_background_blur = 20
config.audible_bell = "Disabled"
config.scrollback_lines = 10000
config.hide_mouse_cursor_when_typing = true

-- Make Option behave like Alt/Meta (compose off) — similar to Ghostty
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Reasonable macOS-centric keys
config.keys = {
  -- Pass Ctrl+Arrow through to terminal apps (e.g. Neovim mini.move).
  { key = "UpArrow", mods = "CTRL", action = act.SendKey({ key = "UpArrow", mods = "CTRL" }) },
  { key = "DownArrow", mods = "CTRL", action = act.SendKey({ key = "DownArrow", mods = "CTRL" }) },
  { key = "LeftArrow", mods = "CTRL", action = act.SendKey({ key = "LeftArrow", mods = "CTRL" }) },
  { key = "RightArrow", mods = "CTRL", action = act.SendKey({ key = "RightArrow", mods = "CTRL" }) },

  -- Pass Ctrl+V through for terminal apps (e.g. Neovim block select).
  { key = "v", mods = "CTRL", action = act.SendKey({ key = "v", mods = "CTRL" }) },
  { key = "V", mods = "CTRL", action = act.SendKey({ key = "v", mods = "CTRL" }) },

  -- macOS-style line navigation for shells that bind these private CSI sequences.
  { key = "LeftArrow", mods = "CMD", action = act.SendString("\x1b[1;13D") },
  { key = "RightArrow", mods = "CMD", action = act.SendString("\x1b[1;13C") },
  { key = "Backspace", mods = "CMD", action = act.SendString("\x1b[1;13~") },
  { key = "Tab", mods = "SHIFT", action = act.SendString("\x1b[Z") },

  -- Font size: support both Cmd+= and Cmd++ on macOS keyboards.
  { key = "=", mods = "CMD", action = act.IncreaseFontSize },
  { key = "+", mods = "CMD", action = act.IncreaseFontSize },
  { key = "=", mods = "CMD|SHIFT", action = act.IncreaseFontSize },
  { key = "-", mods = "CMD", action = act.DecreaseFontSize },
  { key = "0", mods = "CMD", action = act.ResetFontSize },

  -- Close the outer terminal window. Herdr owns terminal tabs and panes.
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = false }) },

  -- Copy/Paste like macOS
  { key = "c", mods = "CMD", action = act.CopyTo("Clipboard") },
  { key = "v", mods = "CMD", action = act.PasteFrom("Clipboard") },
}

for fn = 13, 24 do
  local key = "F" .. tostring(fn)
  table.insert(config.keys, { key = key, mods = "", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "CTRL", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "ALT", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|CTRL", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|ALT", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "CTRL|ALT", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "CTRL|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "ALT|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|CTRL|ALT", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|CTRL|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|ALT|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "CTRL|ALT|CMD", action = act.Nop })
  table.insert(config.keys, { key = key, mods = "SHIFT|CTRL|ALT|CMD", action = act.Nop })
end

return config
