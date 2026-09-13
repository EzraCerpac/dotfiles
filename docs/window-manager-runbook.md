# Window-manager runbook

The daily window manager is AeroSpace, configured in `dot_config/aerospace/aerospace.toml`. Aegis supplies the workspace bar, app switcher, and command menu. BoringNotch owns the media, volume, brightness, and device HUDs. macOS owns notifications and native Mission Control.

Rift remains available as a rollback path. Its Homebrew formula, tracked config, and LaunchAgent remain managed; the cutover disabled the Rift LaunchAgent with `launchctl`, and routine package reconciliation no longer changes Rift service state. Do not enable the Rift agent during normal AeroSpace use. This keeps the fallback intact without running both managers.

## Workspaces and placement

AeroSpace keeps these workspaces persistent:

| Workspace | Purpose |
|---|---|
| 0 | Flow |
| 1 | Thesis |
| 2 | Codex |
| 3–8 | Flexible |
| 9 | Ops and temporary btop |
| B | Browser Hub |
| T | Terminal Hub and Herdr |
| E | Comms |
| M | Media and Music |

Codex routes to 2, Orion to B, Herdr-titled WezTerm windows to T, btop to 9, Mail and WhatsApp to E, and Music to M. Raycast, Antinote, Weather, Contacts, and matching Orion Preview windows have floating rules. The config does not route other browsers. App and title rules run when AeroSpace detects a window; title changes do not trigger a second routing pass.

At AeroSpace startup and when a new external display is connected, the Hammerspoon workspace helper places Ops (9) and Media (M) on the rightmost external display. It leaves them where they are when there is no external display or the screen-to-monitor mapping is ambiguous, then restores the previously focused workspace. These are connection-time defaults, not forced monitor assignments.

Focus follows the pointer. To disable hover focus, change `focus-follows-mouse.enabled` to `false` in the tracked AeroSpace config and apply that file. AeroSpace does not move the pointer when the focused monitor changes. The focus helper sends directional focus through Neovim and Herdr when applicable, then AeroSpace. `start-btop` reuses the matching WezTerm btop window, moves it to Ops, and fills the display within the configured gaps. It checks every minute and leaves btop open while Ops is visible; after Ops is no longer visible, the next timer check closes it only if the saved window and AeroSpace process identities still match.

The built-in display uses a 10 px top gap; external displays use 58 px total (48 px for Aegis plus 10 px breathing room). Other outer and inner gaps are 10 px. App placement uses bundle and title rules, with no window-size matchers.

## Keyboard controls

Meh is Cmd+Ctrl+Alt. Hyper adds Shift. The approved config retains the current Meh/Hyper chord family and native macOS controls; it adds no swipe or replacement overview layer.

| Shortcut | Action |
|---|---|
| Meh+H/J/K/L or arrows | Focus through Herdr/Neovim when applicable, otherwise AeroSpace |
| Hyper+H/J/K/L or arrows | Move the focused window |
| Meh+0–8, B, T, E, M | Switch workspace |
| Meh+9 | Open or reuse btop in Ops |
| Hyper+0–9, B, T, E | Move the focused window to that workspace and follow |
| Hyper+M | Switch to Media and open Music |
| Meh+Tab | Return to the previous workspace |
| Hyper+Tab | Move the current workspace to the next monitor |
| Meh+[ or Meh+] | Previous or next non-empty workspace on the focused monitor |
| Meh+F | Fullscreen within gaps |
| Cmd+Ctrl+F | Native macOS fullscreen |
| Meh+O | Open native macOS Mission Control |
| Meh+Space | Toggle floating and tiling |
| Meh+, or Meh+/ | Accordion layout or tiles |
| Meh+- or Meh+= | Shrink or grow window width |
| Hyper+- or Hyper+= | Shrink or grow window height |
| Hyper+F, A, W, Y, or Enter | Open Finder, Activity Monitor, WhatsApp, System Settings, or a new WezTerm shell |

The service mode provides join and swap actions; `b` balances sizes and `r` flattens the workspace tree. `f` toggles floating and tiling. The Aegis Reset Layout command separately flattens the tree and selects tiles. Hyper+Space remains assigned to Homerow.

## Aegis, BoringNotch, and fullscreen

Aegis is configured for AeroSpace. Its menu provides Reload AeroSpace, Balance Windows, Reset Layout, Reapply App Rules, and native Mission Control. Its workspace order follows AeroSpace's `0–9, B, T, E, M` labels. Keep Aegis excluded from its own app switcher.

BoringNotch remains the only owner of media, volume, brightness, and device HUDs. Keep Aegis's corresponding HUDs disabled. macOS owns notification banners; Aegis's optional notification HUD stays disabled so it does not replace native banners.

Keep **Displays have separate Spaces** enabled in macOS. The AeroSpace config and Chezmoi setup do not set `com.apple.spaces spans-displays`; native fullscreen display separation remains a macOS preference. Aegis should hide its bar only on a display showing a native fullscreen window, leaving bars on other displays visible. No new swipe or custom overview integration is part of this configuration. Physical external-display acceptance has not been completed: verify native fullscreen on one display while checking that the other display remains usable and its Aegis bar stays visible.

If Aegis reports that Accessibility is required, grant access to the current signed Aegis app and relaunch it. Screen Recording is only needed for previews; denial should leave icons available. A replacement local signing identity may require renewing Aegis's own permission entry. Do not reset other apps' grants. The managed app reconciliation installs the pinned official Aegis bundle; `aegis-local-install` is an explicit opt-in for the pinned, locally signed source build.

## Apply and rollback

Review `chezmoi diff` and `chezmoi apply --dry-run` before applying config changes. The package reconciler installs AeroSpace from `nikitabobko/tap/aerospace`; the config starts AeroSpace at login, and Aegis has its own launch-at-login setting. Aegis's custom commands can reload AeroSpace and reapply window rules after a config change.

Rift's Homebrew package, tracked config, local installer commands, and LaunchAgent remain available and managed. The cutover disabled the Rift agent with `launchctl`; routine package reconciliation does not re-enable it. A rollback requires an explicit manager handoff and launchctl action. Do not remove the retained Rift setup or enable it alongside AeroSpace.

After applying, check AeroSpace startup, the workspace map, app routing, Aegis's bar and switcher, and the Ops/Media placement with the actual external display. Confirm that native fullscreen affects only its own display. This runbook does not claim those live or physical checks have passed.

## References

- [AeroSpace](https://github.com/nikitabobko/AeroSpace)
- [Aegis](https://github.com/CCMurphy-dev/Aegis)
- [BoringNotch releases](https://github.com/TheBoredTeam/boring.notch/releases)
