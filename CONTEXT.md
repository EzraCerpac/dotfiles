# Window manager context

This repository installs a Rift, Aegis, and BoringNotch trial on macOS. Rift manages windows and virtual workspaces. Aegis draws the workspace bar, replaces Cmd+Tab, shows status widgets, and owns notification banners. BoringNotch owns media, volume, brightness, and device HUDs.

The trial uses Rift 0.5.3-beta, Aegis 1.1.0, and BoringNotch 2.7.3. It does not run AeroSpace, SketchyBar, AltTab, or SVIM alongside them.

## Vocabulary

- A macOS Space is a native Mission Control desktop. Rift manages windows inside it.
- A virtual workspace is one of Rift's indexed window groups inside a macOS Space.
- A scrolling workspace arranges windows as a horizontal strip of columns. A column can contain a vertical stack.
- Flow is the mixed workspace for the current task.
- A hub is a stable home for a workbench that already switches projects internally, such as a browser or Herdr.
- An anchor is a dedicated destination for one application, such as ChatGPT.
- Laptop Scrolling and Docked Traditional are runtime layout profiles. They update all eight workspaces on every connected display without rewriting the tracked Rift config.

## Workspaces

Aegis 1.1.0 shows the numeric index, not Rift's name.

| Index | Name | Select | Purpose |
|---:|---|---|---|
| 0 | Flow | Meh+0 | Mixed windows for the current task |
| 1 | Thesis | Meh+1 | Thesis work only |
| 2 | ChatGPT | Meh+2 | ChatGPT desktop app |
| 3 | Comms | Meh+3 or Meh+E | Mail and WhatsApp |
| 4 | Media | Meh+4 or Meh+M | Music |
| 5 | Ops | Meh+5 or Meh+9 | Temporary btop and operations |
| 6 | Browser Hub | Meh+6 or Meh+B | Manually anchored browser workbench |
| 7 | Terminal Hub | Meh+7 or Meh+T | Persistent default Herdr session |

Thesis has no automatic app rule. Move only thesis-related windows there. Atlas and other browsers stay in the workspace where they were opened. An ordinary Herdr-titled WezTerm window goes to Terminal Hub. A raw shell, btop, and the Gitlogue screensaver do not.

Hyper+0 through Hyper+7 moves the focused window and follows it. Hyper+E, Hyper+B, Hyper+T, and Hyper+9 are aliases for Comms, Browser Hub, Terminal Hub, and Ops. Hyper+M opens Music, so use Hyper+4 to move a window to Media.

## Window controls

Meh means Cmd+Ctrl+Alt. Hyper adds Shift.

| Shortcut | Action |
|---|---|
| Meh+H/J/K/L or arrows | Focus through Neovim, Herdr, then Rift |
| Hyper+H/J/K/L or arrows | Move the focused Rift node |
| Meh+Tab | Return to the last virtual workspace |
| Meh+[ or Meh+] | Previous or next non-empty workspace |
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

The S, C, E, and T keys also have tap-hold behavior in the keyboard configuration. Tap them promptly when they are part of a global shortcut. On the internal keyboard, the bottom-left Option key remains the ordinary @meh modifier; the Corne no longer translates Tab into private function-key signals. Rift handles Meh+Tab directly as `switch_to_last_workspace` and Hyper+Tab directly as moving the focused window to the display on the right. Aegis captures bare Cmd+Tab and Cmd+Shift+Tab while modified Cmd+Tab combinations containing Option or Control pass through to Rift.

Hyper+A, Hyper+F, Hyper+W, Hyper+Y, and Hyper+M open Atlas, Finder, WhatsApp, System Settings, and Music. Hyper+Enter opens a raw fish login shell in a new WezTerm window. Ordinary WezTerm launches still enter Herdr.

## Layout profiles

Laptop Scrolling is the tracked default. It uses 70 percent columns, 180 ms animations, mouse hover focus, and a three-finger horizontal gesture. Scrolling past the end of a strip switches virtual workspace. All outer gaps are 10 px; macOS already removes the menu-bar area before Rift lays out windows.

Rift 0.5.3 does not natively expand a workspace's sole column. Use Meh+F when one window should fill the tiling area inside the gaps; automatic expansion would require a background window-event subscriber.

Rift 0.5.3 can leak scrolling windows across side-by-side displays. Before using that arrangement, open Aegis's Cmd+Tab command palette and run `Docked Traditional`. Run `Laptop Scrolling` after returning to the laptop display. Restarting Rift restores Laptop Scrolling.

The profile helper briefly focuses each connected display while it updates the workspaces, then restores the original display. The command palette also has `Reload Rift` and `Restart Rift`. Open it from Aegis's Cmd+Tab switcher by starting the search with `:`.

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

The normal Chezmoi adapter installs the official Aegis 1.1.0 bundle. This machine can instead build two stacked changes from the exact pinned revision of `~/Projects/Tools/Aegis`: modified Cmd+Tab handling and a menu-only context button.

```sh
chezmoi apply ~/.local/bin/aegis-local-install
aegis-local-install
```

The helper refuses a dirty checkout or a different revision. It builds a Release app, ad-hoc signs the app and its nested frameworks as one bundle, verifies it before and after an atomic replacement, disables automatic Sparkle updates, and records the installed revision under `~/.local/state/aegis-local-install/`. A manual Aegis "Check for Updates" can still replace the local build. `wip/aegis-cmd-tab-modifiers` keeps the first upstream-ready commit; `wip/aegis-context-button-menu` adds the second. The app binary is not stored in Chezmoi or GitHub.

With `contextButtonMenuOnly` enabled, the far-left `≡` button opens the full menu on either primary or secondary click. Scrolling over it does nothing. Layout and workspace actions remain available inside the menu.

Rift and Aegis both need Accessibility access. Aegis and BoringNotch also need login-item approval. Aegis's master HUD path stays enabled only because its notification service closes the native banner before drawing its replacement; disabling the notification HUD would make banners invisible. Its music, media, volume/brightness, device, focus, and virtual-notch HUDs stay off so BoringNotch is their sole owner. Test a harmless notification after each macOS or Aegis update.

Dragging a window to the top edge does not enter Mission Control. Ordinary Mission Control shortcuts, trackpad gestures, and Hot Corners remain available. This avoids accidental Mission Control activation while dragging Aegis items.

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

Meh+9 opens or reuses a raw WezTerm btop window in Ops on the invoking display. Each press resets its one-minute deadline. Reuse needs Rift's `{pid, idx}` identity, including the brief post-restart state where WezTerm's bundle ID or WindowServer ID can be absent. Closing is stricter: the helper schedules it only after obtaining a fresh WindowServer ID, and closes only if every identity value and timer generation still match. A Rift restart or mismatch leaves the window open.

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
