-- WezTerm config with sensible defaults

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
bar.apply_to_config(config, {
  position = "bottom",
  hostname = { enabled = false },
  clock = { enabled = false },
})
config.hide_tab_bar_if_only_one_tab = true

local delftblue_domain_name = "SSH:delftblue"

config.ssh_domains = {}
for _, dom in ipairs(wezterm.default_ssh_domains()) do
  if dom.name and not dom.name:match("^SSHMUX:") then
    dom.assume_shell = "Posix"
    table.insert(config.ssh_domains, dom)
  end
end

local has_delftblue_domain = false
for _, dom in ipairs(config.ssh_domains) do
  if dom.name == delftblue_domain_name then
    has_delftblue_domain = true
    break
  end
end

config.launch_menu = config.launch_menu or {}
if has_delftblue_domain then
  table.insert(config.launch_menu, 1, {
    label = "DelftBlue",
    domain = { DomainName = delftblue_domain_name },
  })
end

local function spawn_delftblue_window()
  if not has_delftblue_domain then
    return
  end

  wezterm.mux.spawn_window({
    domain = { DomainName = delftblue_domain_name },
  })
end

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

  -- Split panes
  { key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "D", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

  -- Pane zoom
  { key = "Enter", mods = "CMD|SHIFT", action = act.TogglePaneZoomState },

  -- Tabs
  { key = "t", mods = "CMD", action = act.SpawnTab("CurrentPaneDomain") },
  has_delftblue_domain
      and {
        key = "T",
        mods = "CMD|SHIFT",
        action = act.SpawnTab({
          DomainName = delftblue_domain_name,
        }),
      }
    or nil,
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "LeftArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "RightArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },
  has_delftblue_domain
      and {
        key = "N",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(spawn_delftblue_window),
      }
    or nil,

  -- Copy/Paste like macOS
  { key = "c", mods = "CMD", action = act.CopyTo("Clipboard") },
  { key = "v", mods = "CMD", action = act.PasteFrom("Clipboard") },
}

local compact_keys = {}
for _, entry in ipairs(config.keys) do
  if entry ~= nil then
    table.insert(compact_keys, entry)
  end
end

for fn = 13, 24 do
  local key = "F" .. tostring(fn)
  table.insert(compact_keys, { key = key, mods = "", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "CTRL", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "ALT", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|CTRL", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|ALT", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "CTRL|ALT", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "CTRL|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "ALT|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|CTRL|ALT", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|CTRL|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|ALT|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "CTRL|ALT|CMD", action = act.Nop })
  table.insert(compact_keys, { key = key, mods = "SHIFT|CTRL|ALT|CMD", action = act.Nop })
end

config.keys = compact_keys

return config
