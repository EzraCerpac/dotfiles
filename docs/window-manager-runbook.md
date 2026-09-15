# Window-manager runbook

The daily window manager is AeroSpace, configured in `dotfiles/.config/aerospace/aerospace.toml`. Aegis supplies the workspace bar, app switcher, and command menu. BoringNotch owns the media, volume, brightness, and device HUDs. macOS owns notifications and native Mission Control.

Rift remains available as a rollback path. Its Homebrew formula, tracked config, and LaunchAgent remain managed; the cutover disabled the Rift LaunchAgent with `launchctl`, and routine package reconciliation no longer changes Rift service state. Do not enable the Rift agent during normal AeroSpace use. This keeps the fallback intact without running both managers.

## Workspaces and placement

AeroSpace keeps these workspaces persistent:

| Workspace | Purpose |
|---|---|
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

The built-in display uses a 10 px top gap; external displays reserve 45 px above windows for Aegis. Other outer and inner gaps are 10 px. App placement uses bundle and title rules, with no window-size matchers.

## Keyboard controls

Meh is Cmd+Ctrl+Alt. Hyper adds Shift. The approved config retains the current Meh/Hyper chord family and native macOS controls; it adds no swipe or replacement overview layer.

| Shortcut | Action |
|---|---|
| Meh+H/J/K/L or arrows | Focus through Neovim/Herdr when applicable, then AeroSpace across monitors |
| Hyper+H/J/K/L or arrows | Move the focused window |
| Meh+1–8, B, T, E, M | Switch workspace |
| Meh+9 | Open or reuse btop in Ops |
| Hyper+0 | Balance window sizes |
| Hyper+1–9, T | Move the focused window to that workspace and follow |
| Hyper+B | Switch to Browser Hub and open/reuse Orion |
| Hyper+E | Switch to Comms and open/reuse Apple Mail |
| Hyper+M | Switch to Media and open Music |
| Meh+Tab | Return to the previous workspace |
| Hyper+Tab | Move the current workspace to the next monitor |
| Meh+[ or Meh+] | Previous or next non-empty workspace on the focused monitor |
| Meh+F | Fullscreen within gaps |
| Cmd+Ctrl+F | Native macOS fullscreen |
| Meh+O | Open native macOS Mission Control |
| Meh+Space | Toggle floating and tiling |
| Meh+, or Meh+/ | Accordion layout or tiles |
| Meh+- or Meh+= | Smart-shrink or smart-grow by 50 px, following the parent layout orientation |
| Hyper+- or Hyper+= | Smart-shrink or smart-grow by 50 px, following the parent layout orientation |
| Hyper+F, A, W, Y, or Enter | Open Finder, Activity Monitor, WhatsApp, System Settings, or a new WezTerm shell |

The Corne's dedicated `+` key uses QMK's `KC_PLUS` (Shift+Equal), so Meh+`+` and Hyper+`+` both smart-grow by 50 px.

Enter service mode with Hyper+semicolon. It joins with a neighboring window using H/J/K/L, arrows, or their Hyper-modified forms; Shift+H/J/K/L and Shift+arrows swap with a neighbor. Each action exits service mode. `b` balances sizes, `r` flattens the workspace tree and selects tiles, and `f` toggles floating and tiling. Escape reloads the config and exits. Hyper+Space remains assigned to Homerow.

## Aegis, BoringNotch, and fullscreen

Aegis is configured for AeroSpace. Its menu provides Reload AeroSpace, Balance Windows, Reset Layout, Reapply App Rules, and native Mission Control. Its workspace order follows AeroSpace's `1–9, B, T, E, M` labels. Keep Aegis excluded from its own app switcher.

BoringNotch remains the only owner of media, volume, brightness, and device HUDs. Keep Aegis's corresponding HUDs disabled. macOS owns notification banners; Aegis's optional notification HUD stays disabled so it does not replace native banners.

Keep **Displays have separate Spaces** enabled in macOS. The AeroSpace config and mise setup do not set `com.apple.spaces spans-displays`; native fullscreen display separation remains a macOS preference. Aegis should hide its bar only on a display showing a native fullscreen window, leaving bars on other displays visible. No new swipe or custom overview integration is part of this configuration. Physical external-display acceptance has not been completed: verify native fullscreen on one display while checking that the other display remains usable and its Aegis bar stays visible.

If Aegis reports that Accessibility is required, grant access to the current signed Aegis app and relaunch it. Screen Recording is only needed for previews; denial should leave icons available. A replacement local signing identity may require renewing Aegis's own permission entry. Do not reset other apps' grants. The explicit Aegis installer retains the pinned, locally signed source build and its existing signing identity.

## Apply and rollback

Linked configuration edits change source directly. Review the source diff with JJ.
For rendered files, inspect `mise -C ~/.config/mise bootstrap dotfiles diff`
and its apply dry-run before deployment. Routine dotfile application does not
restart or switch window managers.

AeroSpace currently uses the local PR2245/Hyper build, not the upstream cask
release. Its explicit build task preserves that source revision; ordinary
package updates leave it alone. Aegis keeps its own launch-at-login setting.

Rift's configuration and explicit local installer remain available. The inactive,
malformed legacy LaunchAgent belongs in the protected rollback backup, not
normal bootstrap. Switching to Rift requires a deliberate manager handoff;
never enable it alongside AeroSpace.

After applying, check AeroSpace startup, the workspace map, app routing, Aegis's bar and switcher, and the Ops/Media placement with the actual external display. Confirm that native fullscreen affects only its own display. This runbook does not claim those live or physical checks have passed.

## References

- [AeroSpace](https://github.com/nikitabobko/AeroSpace)
- [Aegis](https://github.com/CCMurphy-dev/Aegis)
- [BoringNotch releases](https://github.com/TheBoredTeam/boring.notch/releases)
