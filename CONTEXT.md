# Window manager context

This repository installs a Rift, Aegis, and BoringNotch trial on macOS. Rift manages windows and virtual workspaces. Aegis draws the workspace bar, replaces Cmd+Tab, shows status widgets, and owns notification banners. BoringNotch owns media, volume, brightness, and device HUDs.

The trial uses Rift 0.5.3-beta, Aegis 1.1.0, and BoringNotch 2.7.3. It does not run AeroSpace, SketchyBar, AltTab, or SVIM alongside them.

## Vocabulary

- A macOS Space is a native Mission Control desktop. Rift manages windows inside it.
- A virtual workspace is one of Rift's indexed window groups inside a macOS Space.
- A scrolling workspace arranges windows as a horizontal strip of columns. A column can contain a vertical stack.
- Flow is the mixed workspace for the current task.
- A flexible numbered workspace is an unassigned workspace for temporary or manual work.
- A special workspace is a shortcut-driven workspace with one focused job. Ops is special because Meh+9 creates or reuses temporary btop there.
- A hub is a stable home for a workbench that already switches projects internally, such as a browser or Herdr.
- An anchor is a dedicated destination for one application, such as ChatGPT.
- The preferred external display is the rightmost managed external display. When there is no external display, the current display is used.
- Laptop Scrolling and Docked Traditional are runtime layout profiles. They update all fourteen workspaces on every connected display without rewriting the tracked Rift config.

## Workspaces

Aegis hides empty workspaces. It shows the indices 0 through 9 and the configured B, T, E, and M labels.

| Index | Name | Select | Purpose |
|---:|---|---|---|
| 0 | Flow | Meh+0 | Mixed windows for the current task |
| 1 | Thesis | Meh+1 | Thesis work only |
| 2 | ChatGPT | Meh+2 | ChatGPT desktop app |
| 3-8 | 3-8 | Meh+3 through Meh+8 | Flexible numbered workspaces |
| 9 | Ops | Meh+9 | Temporary btop and operations |
| 10 | Browser Hub | Meh+B | Manually anchored browser workbench |
| 11 | Terminal Hub | Meh+T | Persistent default Herdr session |
| 12 | Comms | Meh+E | Mail and WhatsApp |
| 13 | Media | Meh+M | Music |

Thesis and flexible numbered workspaces have no automatic app rule. Move only thesis-related windows to Thesis. Atlas and other browsers stay in the workspace where they were opened. An ordinary Herdr-titled WezTerm window goes to Terminal Hub. A raw shell, btop, and the Gitlogue screensaver do not.

Hyper+0 through Hyper+8 moves the focused window and follows it. Hyper+B, Hyper+T, and Hyper+E move it to Browser Hub, Terminal Hub, and Comms. Hyper+9 moves it to Ops on the preferred external display when one exists. Meh+M selects Media there; Hyper+M opens or reuses Music there. On a laptop, both use the current display.

## Transient windows

Rift floats dialogs, system dialogs, sheets, and floating utility windows. They stay usable without taking a column from the scrolling layout. Rift ignores Raycast's launcher windows and Orion's exact `Orion Preview` helper. Normal Orion browser windows remain managed and stay wherever they were placed.

The transient rules come before workspace routes because Rift uses the earlier rule when two matches have equal specificity. If Raycast returns as a blank item in native Mission Control, quit and reopen Raycast. Restart Dock once only if Mission Control kept a stale item after that restart.

## Window controls

Meh means Cmd+Ctrl+Alt. Hyper adds Shift.

| Shortcut | Action |
|---|---|
| Meh+H/J/K/L or arrows | Focus through Neovim, Herdr, then Rift |
| Hyper+H/J/K/L or arrows | Move the focused Rift node |
| Meh+Tab | Return to the last virtual workspace |
| Meh+[ or Meh+] | Previous or next non-empty workspace |
| F3 or Meh+O | Show every non-empty Rift workspace |
| Shift+F3 | Show windows in the current Rift workspace |
| Meh+F | Fullscreen within gaps |
| Cmd+Ctrl+F | Native macOS fullscreen |
| Meh+C | Center the selected column |
| Meh+S | Snap the strip to a column |
| Hyper+, or Hyper+. | Consume or expel left or right |
| Meh+/ | Pull the focused window out of a stack |
| Meh+, | Toggle a whole stack |
| Hyper+Space | Toggle floating |
| Hyper+Tab | Move the window to the display on the right |
| Meh+- or Meh+= | Shrink or grow horizontally |
| Hyper+- or Hyper+= | Shrink or grow vertically |

Rift's overview is the primary Mission Control interface. Use arrows or Tab to select, Enter or a click to activate, and Escape or a click outside to dismiss. Empty workspaces do not appear. Four-finger swipe up still opens native Mission Control as a fallback, where Raycast's blank helper tile may still appear.

The S, C, E, and T keys also have tap-hold behavior in the keyboard configuration. Tap them promptly when they are part of a global shortcut. On the internal keyboard, the bottom-left Option key remains the ordinary @meh modifier; the Corne no longer translates Tab into private function-key signals. Rift handles Meh+Tab directly as `switch_to_last_workspace` and Hyper+Tab directly as moving the focused window to the display on the right. Aegis captures bare Cmd+Tab and Cmd+Shift+Tab while modified Cmd+Tab combinations containing Option or Control pass through to Rift.

Hyper+A, Hyper+F, Hyper+W, Hyper+Y, and Hyper+M open Activity Monitor, Finder, WhatsApp, System Settings, and Music. Hyper+Enter opens a raw fish login shell in a new WezTerm window. Ordinary WezTerm launches still enter Herdr.

## Layout profiles

Laptop Scrolling is the tracked default. It uses 70 percent columns, 180 ms animations, and mouse hover focus. Four-finger horizontal swipes switch directly between non-empty workspaces and give one haptic when the switch commits. Trackpad swipes do not scroll the column strip; use the focus keys, mouse, and strip commands for columns. All outer gaps are 10 px; macOS already removes the menu-bar area before Rift lays out windows.

Rift 0.5.3 does not natively expand a workspace's sole column. Use Meh+F when one window should fill the tiling area inside the gaps; automatic expansion would require a background window-event subscriber.

Rift 0.5.3 can leak scrolling windows across side-by-side displays. Before using that arrangement, open Aegis's Cmd+Tab command palette and run `Docked Traditional`. Run `Laptop Scrolling` after returning to the laptop display. Restarting Rift restores Laptop Scrolling.

The profile helper briefly focuses each connected display while it updates all fourteen workspaces, then restores the original display. The command palette also has `All Workspaces`, `Current Workspace`, `Reload Rift`, and `Restart Rift`. Open it from Aegis's Cmd+Tab switcher by starting the search with `:`.

## Configuration lifecycle

The first plain `chezmoi apply` installs the tracked files, Rift, and Aegis, but leaves Rift staged and keeps the old desktop stack in place. After granting Accessibility access and checking Aegis, start Rift with:

```sh
RIFT_SERVICE_ACTIVATE=1 chezmoi apply
```

Only after Rift and Aegis are live and verified, perform the one-time cutover:

```sh
RIFT_SERVICE_ACTIVATE=1 WINDOW_MANAGER_MIGRATION_APPROVED=1 chezmoi apply
```

That second gate removes the old Brew-managed stack but preserves BoringNotch. Aegis writes UI changes back to `~/.config/aegis/config.json`. The `ca` command re-adds that allowlisted file before applying, so intentional Aegis changes enter the JJ working copy.

The normal Chezmoi adapter installs the official Aegis 1.1.0 bundle. This machine can instead build twelve stacked changes from the exact pinned revision of `~/Projects/Tools/Aegis`: modified Cmd+Tab handling, a menu-only context button, configurable workspace labels, native-fullscreen bar hiding, empty-workspace filtering, readable system-native settings, app-switcher event-tap recovery, bounded Rift subscription reconnection, Screen Recording-aware window previews, pill-scoped native Liquid Glass, a theme-aware Cmd+Tab surface, and silent-first Accessibility checks.

```sh
chezmoi apply ~/.local/bin/aegis-local-install
aegis-local-install
```

The helper refuses a dirty checkout or a different revision. It requires exactly one `Aegis Local Code Signing` identity from the login keychain, signs the Release app and nested code by that identity hash (never ad hoc), verifies each signature and rejects CDHash-only designated requirements before and after an atomic replacement, then evaluates each certificate requirement with `codesign -R` before replacing the existing app. An untrusted self-signed certificate fails with a clear trust error and no replacement. It disables automatic Sparkle updates, and records the identity hash plus normalized designated-requirement digest under `~/.local/state/aegis-local-install/`. Run `aegis-local-signing-setup` once to create and validate the ten-year self-signed identity in Keychain Access; set its Trust section to Always Trust (or Code Signing trust) and verify the wizard's temporary signed probe. The wizard never exports or records the private key. Renewing or replacing that certificate changes the app identity and needs one fresh Aegis Accessibility and Screen Recording approval. Aegis checks Accessibility silently first and requests the pane only once when access is genuinely absent. It requests Screen Recording at most once per launch when previews are enabled; denial or capture failure falls back to icons until activation or an explicit Retry rechecks the grant. A manual Aegis "Check for Updates" can still replace the local build. `wip/aegis-cmd-tab-modifiers` keeps the first upstream-ready commit; `wip/aegis-context-button-menu` adds the second; `wip/aegis-workspace-name-labels` adds the third; `wip/aegis-native-fullscreen-bar` adds the fourth; `wip/aegis-hide-empty-workspaces` adds the fifth; `wip/aegis-settings-system-appearance` adds the sixth; `wip/aegis-switcher-event-tap-recovery` adds the seventh; `wip/aegis-rift-subscription-reconnect` adds the eighth; `wip/aegis-screen-recording-permission` adds the ninth; `wip/aegis-native-liquid-glass` adds the tenth; `wip/aegis-themed-switcher` adds the eleventh; `wip/aegis-accessibility-silent-first` adds the twelfth. The app binary is not stored in Chezmoi or GitHub.

The app switcher reports `Active`, `Accessibility required`, `Recovering`, or `Failed` in General settings. It prompts once, watches for a newly granted permission, and recreates a disabled or silently dead event tap with bounded retries. If a certificate is replaced, remove only the stale Aegis entry from Privacy & Security → Accessibility, add `/Applications/Aegis.app`, and enable it again. Do not reset other applications' grants.

With `contextButtonMenuOnly` enabled, the far-left `≡` button opens the full menu on either primary or secondary click. Scrolling over it does nothing. Layout and workspace actions remain available inside the menu.

The tracked Aegis config uses index labels with four overrides, so the bar shows `0 1 2 3 4 5 6 7 8 9 B T E M`. Overrides change only the bar text; Rift still uses indices 0 through 13. Aegis keeps `Auto` multi-monitor mode.

The Aegis settings window follows macOS light or dark appearance independently of the configured bar theme. It uses an opaque native window background and semantic system colors, so desktop content cannot bleed through and controls remain readable. The tracked `custom` bar theme remains unchanged.

The Cmd+Tab surface follows the selected Aegis theme. Dark, light, system, and custom themes use solid matching surfaces; the current custom theme has no explicit colors and therefore uses Aegis's dark fallback. On macOS 26 and later, the Liquid Glass theme applies native regular glass only to workspace pills, the system-status pill, and Cmd+Tab. The full-width menu-bar background stays unchanged. Older macOS versions keep the simulated pill and Cmd+Tab material fallback. Reduce Transparency replaces those glass surfaces with solid themed backgrounds. Notification and notch HUD surfaces are unchanged.

Empty inactive workspaces are hidden from the Aegis bar. The focused workspace stays visible even when it has no windows. Occupancy comes from managed windows, so minimized, hidden, Finder, and icon-excluded windows still keep their workspace visible. The filter changes only the bar: every workspace remains available through shortcuts, Cmd+Tab, context menus, window moves, and app routing. Labels are resolved before filtering, so abbreviations and shortcut overrides do not change as workspaces appear or disappear.

Aegis hides its bar on the display showing a native macOS fullscreen or another Rift-unmanaged Space, then restores it after returning to a managed Space. Other displays keep their bars. Meh+F fullscreen-within-gaps remains managed by Rift and deliberately keeps the bar visible.

Rift and Aegis both need Accessibility access. Aegis and BoringNotch also need login-item approval. Aegis's master HUD path stays enabled only because its notification service closes the native banner before drawing its replacement; disabling the notification HUD would make banners invisible. Its music, media, volume/brightness, device, focus, and virtual-notch HUDs stay off so BoringNotch is their sole owner. Test a harmless notification after each macOS or Aegis update.

Dragging a window to the top edge does not enter Mission Control. Rift consumes four-finger horizontal swipes, while vertical Mission Control gestures, shortcuts, and Hot Corners remain available. This avoids accidental Mission Control activation while dragging Aegis items.

Rift 0.5.3 is ad-hoc signed, and macOS 27 beta has turned its Accessibility grant off after a reboot. The repository therefore replaces Rift's stock `KeepAlive` service with a one-shot login agent. If permission is missing, Rift prompts once and exits instead of restarting every 30 seconds. Turn its switch back on, then run the activation apply again. Do not reinstall the stock Rift service.

Useful checks:

```sh
/bin/launchctl print "gui/$(id -u)/git.acsandmann.rift"
RIFT_CLI_PRETTY=1 rift-cli execute config get
rift-cli query workspaces
rift-cli query windows
rift-cli query displays
```

Rift has no pure config lint command. `rift-cli execute config reload` validates and applies a config against the running service. `rift --validate` mainly checks the saved layout, not the full config.

## btop

Meh+9 opens or reuses a raw WezTerm btop window in Ops on the preferred external display. With no external display, it uses the invoking display. Each press resets its one-minute deadline. Reuse needs Rift's `{pid, idx}` identity, including the brief post-restart state where WezTerm's bundle ID or WindowServer ID can be absent. Closing is stricter: the helper schedules it only after obtaining a fresh WindowServer ID, and closes only if every identity value and timer generation still match. A Rift restart or mismatch leaves the window open.

## Stop and rollback

To stop the trial without changing repository history:

```sh
/bin/launchctl bootout "gui/$(id -u)/git.acsandmann.rift"
osascript -e 'tell application id "Aegis.Aegis" to quit'
osascript -e 'tell application id "theboringteam.boringnotch" to quit'
```

Disable Aegis Launch at Login before removing the app. Then create a new JJ working commit from the migration commit's parent and apply that older Chezmoi state:

```sh
jj log -r 'all()' -n 12
jj new <migration-parent-change-id>
chezmoi apply
brew services start sketchybar
open -a AeroSpace
open -a AltTab
```

BoringNotch can remain installed but inactive during rollback. Its settings remain in the application container. The rollback keeps the migration commit intact, so a new working commit from that change ID restores the trial.

To restore the official Aegis build without changing JJ history, quit Aegis, move the local `/Applications/Aegis.app` aside, and apply Chezmoi. The managed adapter installs the pinned official 1.1.0 bundle again.
