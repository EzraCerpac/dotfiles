# Window-manager runbook

This is the operating manual for Ezra's Rift, Aegis, and BoringNotch setup. The vocabulary is in [CONTEXT.md](../CONTEXT.md). The daily desktop uses a locally signed Rift build from `~/Projects/Tools/rift`, with `~/.local/bin/rift` and `~/.local/bin/rift-cli` as its managed paths. Homebrew Rift 0.5.3 remains installed at `/opt/homebrew/bin/rift` and `/opt/homebrew/bin/rift-cli` as the rollback path.

The local Rift source is based on the selected upstream `main` revision. The Aegis source is `~/Projects/Tools/Aegis`; its local build uses the pinned review stack. Record the concrete revisions in installer receipts rather than copying hashes into this runbook.

Rift manages windows and virtual workspaces. Aegis draws the workspace bar, provides Cmd+Tab, shows system status, and provides the command palette. BoringNotch owns media, volume, brightness, and device HUDs. AeroSpace, SketchyBar, AltTab, and SVIM do not run beside them.

## Workspace model

There are fourteen zero-based Rift workspaces. Aegis shows the indices, with four label overrides.

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

Thesis and workspaces 3 through 8 have no broad automatic app rule. Atlas and other browsers stay where they open. ChatGPT goes to workspace 2. Mail and WhatsApp go to Comms. Music goes to Media. Herdr-titled WezTerm windows go to Terminal Hub. Raw shells, btop, and Gitlogue screensaver windows do not match the Herdr rule.

Meh+M selects Media on the preferred external display. Hyper+M opens or reuses Music there. Hyper+0 through Hyper+8 move the focused window and follow it. Hyper+B, Hyper+T, and Hyper+E move a window to Browser Hub, Terminal Hub, and Comms. Hyper+9 moves a window to Ops on the preferred external display. With no external display, these actions use the current display.

Empty workspaces are hidden from the Aegis bar. The focused workspace remains visible even when empty. Occupancy comes from managed windows, so minimized, hidden, Finder, and icon-excluded windows can keep a workspace visible. The filter changes only the bar. Shortcuts, app rules, moves, Cmd+Tab, and context-menu actions can still reach every workspace.

## Keyboard controls

Meh is Cmd+Ctrl+Alt. Hyper adds Shift. On the internal keyboard, the bottom-left Option key remains the ordinary `@meh` modifier. The Corne has no private Tab translation.

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
| Hyper+Space | Toggle floating with centered smart-size placement |
| Meh+Space | Raise the floating window |
| Hyper+Tab | Move the window to the display on the right |
| Meh+- or Meh+= | Shrink or grow horizontally |
| Hyper+- or Hyper+= | Shrink or grow vertically |
| Hyper+A | Activity Monitor |
| Hyper+F | Finder |
| Hyper+W | WhatsApp |
| Hyper+Y | System Settings |
| Hyper+M | Music |
| Hyper+Enter | Raw fish login shell in a new WezTerm window |

The S, C, E, and T keys retain tap-hold behavior in the keyboard configuration. Tap them promptly when they are part of a global shortcut. Bare Cmd+Tab and Cmd+Shift+Tab belong to Aegis. Modified Cmd+Tab combinations containing Option or Control pass through to Rift, so repeated Meh+Tab presses do not open Aegis. Ordinary WezTerm launches still enter Herdr.

Rift's overview is the primary Mission Control interface. Arrows or Tab select, Enter or a click activates, and Escape or a click outside dismisses. Four-finger swipe up still opens native Mission Control as a fallback, where Raycast's blank helper tile may appear.

## Rift layout and window rules

The local Rift config uses scrolling layout with 70 percent columns, 30 to 90 percent resize limits, 180 ms animations at 120 FPS, focus-follows-mouse, and no pointer warping, hiding, or suspend key. It sets `window_insertion_point` to `next_to_selection`, uses 10 px inner and outer gaps, enables the 180 ms overview fade, and disables the experimental stack line. Built-in displays keep the 10 px top gap. Every external display uses a 58 px top gap: 48 px for Aegis and the normal 10 px breathing gap. UUID-specific gap overrides remain more specific than the external-display default.

The local single-column patch sets `single_column_width_ratio` to `1.0`. A workspace with one non-floating column fills the usable tiling width while preserving gaps. Floating windows do not count. Multiple columns keep the normal 70 percent behavior. Explicit fullscreen remains separate. A manual shrink starts at the configured 90 percent maximum; growing past that limit restores automatic full width. Adding, removing, joining, or expelling a window while a layout has or reaches one column clears the manual override. Multi-column manual widths remain unchanged.

Four-finger horizontal swipes switch directly between non-empty workspaces and produce one haptic when a switch commits. Scrolling-layout gestures stay disabled, so horizontal swipes do not also scroll the column strip. Vertical Mission Control gestures, shortcuts, and Hot Corners remain available. Before using side-by-side displays, switch to Docked Traditional because scrolling windows can leak across horizontal displays. Restarting Rift returns to Laptop Scrolling.

The local gesture fallback patch keeps the global workspace-swipe handler active in scrolling layouts when scrolling-layout gestures are disabled. Without that fallback, Rift selects the disabled scrolling handler and drops the four-finger swipe.

The local app-rule patch adds inclusive window-size matchers. ChatGPT standard windows no larger than 600 by 700 logical pixels stay unmanaged, while the full ChatGPT window still goes to workspace 2. Unknown window dimensions do not match this rule.

Rift's focus blacklist covers Raycast, Dock, SystemUIServer, SecurityAgent, and Spotlight. This prevents focus-follows-mouse from stealing focus when the pointer crosses a system utility. The app rules use exact bundle IDs:

- ChatGPT goes to workspace 2.
- Mail and WhatsApp go to Comms.
- Music goes to Media.
- Herdr-titled WezTerm windows go to Terminal Hub.
- btop-titled WezTerm windows go to Ops.
- Antinote, Weather, Contacts, and Raycast stay unmanaged or floating according to their rule. Antinote's built-in pin shortcut is Shift+Cmd+P. Pinned notes remain visible above other apps after focus moves; keyboard input follows the newly focused app. Unpinning restores hide-on-focus-loss behavior. This user-selected pin shortcut takes precedence over Antinote's normal Print shortcut.
- ChatGPT Computer Use, Browser Use, update prompts, and similar role-based transient dialogs stay unmanaged.
- Sheets remain managed but floating so they stay attached to their parent.
- Orion preview helpers matching the configured preview prefix stay unmanaged. Ordinary Orion browser windows remain managed and are manually anchored in Browser Hub.

Transient rules come before workspace routes. Role-based matching handles future previews without title-specific ChatGPT rules. JankyBorders runs as the existing Homebrew service with a 5-point white active border and a transparent inactive color, so only the focused window has a visible outline.

## Runtime profiles and Aegis commands

Laptop Scrolling is the tracked default. Docked Traditional is for side-by-side displays. Both profiles update all fourteen workspaces on every connected display without rewriting the tracked Rift file. The helper briefly focuses each display while it updates, then restores the original display.

Aegis's Cmd+Tab command palette includes these entries in this order:

1. `Laptop Scrolling`
2. `Docked Traditional`
3. `All Workspaces`
4. `Current Workspace`
5. `Reload Rift`
6. `Restart Rift`

The two overview commands call `rift-cli execute mission-control show-all` and `rift-cli execute mission-control show-current`. The layout commands change Rift's runtime layout without writing over Chezmoi. A Rift restart returns to scrolling. Open the palette by starting the Aegis switcher search with `:`.

## Aegis behavior

Aegis shows the Rift workspace indices `0` through `9`, `B`, `T`, `E`, and `M`. The indices remain Rift's source of truth. The bar uses `Auto` multi-monitor mode. The far-left context button opens its full menu on either primary or secondary click when `contextButtonMenuOnly` is enabled. Scrolling over it does nothing.

The system-status pill uses a 28 pt outer height, roughly 14 pt content, and an adaptive minimum width. Its size fields remain configurable through the standalone status-sizing follow-up. The workspace pills, status pill, and Cmd+Tab follow the selected Aegis theme. Liquid Glass affects those pills and Cmd+Tab on supported macOS versions; older systems and Reduce Transparency use the matching solid fallback. The settings window uses an opaque native background.

Native macOS owns notifications. The Aegis notification setting controls whether Aegis observes and draws an additional notification HUD. When it is off, Aegis does not dismiss native banners. Do not add notification exclusions that make a banner disappear. BoringNotch remains the sole owner of media, volume, brightness, and device HUDs. Aegis's music, media, volume/brightness, device, focus, and virtual-notch HUDs stay off. Aegis creates notch controllers only for hardware-notch displays unless virtual notches are explicitly enabled, so an external-only setup does not invent a centered notch.

Aegis treats each Rift workspace response as authoritative. Closed apps and newly ignored helpers therefore disappear from Cmd+Tab after its next refresh. It hides its bar on a display showing native macOS fullscreen or another unmanaged Space, while bars on other displays remain. Rift refreshes run one at a time, retain the strongest pending request, and recheck a native Space transition when Rift initially returns an unchanged or unknown display snapshot. Aegis applies the resolved fullscreen state before raising its bar window, so returning to an already-fullscreen video cannot place the bar above the macOS menu bar. Meh+F fullscreen within gaps stays managed and keeps the bar visible.

## Installation and configuration lifecycle

The ordinary Chezmoi apply installs tracked files, the official pinned Aegis bundle, and the rollback packages. The local Rift and Aegis builds are opt-in. Chezmoi never activates a local Rift build: a plain apply only stages the managed files and login agent.

For a local Rift cutover:

1. Create or update `~/Projects/Tools/rift` from the selected upstream base. Keep the checkout clean at the pinned revision.
2. Run `rift-local-signing-setup` once. It walks you through creating the `Rift Local Code Signing` identity in Keychain Access, then validates its trust. It never exports the private key.
3. Run plain `rift-local-install`. It builds locked arm64 `rift` and `rift-cli` binaries, signs them with the identity hash, verifies architecture, identifiers, signatures, trust, and designated requirements, and stages them under `~/.local/state/rift-local-install/releases/<revision>/`. It does not stop, start, or reconfigure the running service. The stable `current` pointer and `~/.local/bin/` links are unchanged.
4. Run the staged candidate directly, for example `~/.local/state/rift-local-install/releases/<revision>/rift config check --config ~/.config/rift/config.toml`, and inspect the release and signing state before activation.
5. Run `rift-local-install --activate` only for the cutover. It snapshots the current pointer, links, receipt, and service state; stops the managed service; atomically switches `current`; bootstraps the candidate LaunchAgent; verifies that it stays running; and writes the receipt. Any activation failure rolls back the pointer, links, receipt, and previously loaded service.
6. Grant Accessibility access if macOS asks, reload the config, and inspect the live service. Do not use an environment flag or Chezmoi apply to activate Rift.

The managed login agent points at `~/.local/bin/rift`. Homebrew's Rift remains installed and untouched. The Aegis adapter normally installs the official 1.1.0 bundle. To use the pinned local Aegis source, run `aegis-local-signing-setup` once and invoke `aegis-local-install` explicitly. It requires a clean source checkout at the exact pinned revision, builds a Release app, signs it with the stable local identity, verifies the bundle and nested code, replaces `/Applications/Aegis.app` atomically, disables automatic Sparkle checks, and records a receipt under `~/.local/state/aegis-local-install/`. It restores the old app if replacement or verification fails. The binary stays out of Chezmoi and GitHub. A manual Aegis update check can still replace it.

The local Aegis source combines the current reviewable PR stack plus three separate upstream-ready follow-ups: `feat(rift): allow configured CLI path`, `fix(notifications): respect notification HUD setting`, and `fix(menu-bar): honor system status sizing`. The first resolves an optional absolute executable path for Rift commands and subscriptions. The second leaves native banners alone when the Aegis notification HUD is off and starts or stops monitoring when the setting changes. The third makes the existing status sizing fields control an adaptive-min pill with a 28 pt outer height and roughly 14 pt content. Keep these changes separate from unrelated reliability, switcher, or visual branches. Reserve `fix(media): stop adapter on app termination` for the separate future MediaService orphan-adapter fix; it is not implemented here. A fresh certificate or Aegis replacement may need new Accessibility and Screen Recording approval. Remove only a stale Aegis entry from Privacy & Security, then add the replacement app. Do not reset other applications' grants. XCTest hosts must not request Accessibility or install a global event tap.

Aegis writes UI changes to `~/.config/aegis/config.json`. The `ca` workflow re-adds that allowlisted file before applying, so deliberate Aegis changes enter the JJ working copy. Keep the JSON outside hand-written lock tests so Aegis remains free to add or reorder settings.

## Monthly candidate builds

The monthly `rift-monthly-refresh` job runs on the first Saturday at 10:00 Europe/Amsterdam in a managed JJ workspace. It fetches upstream, restacks the custom Rift commits, builds, and runs the tests. It may move only `wip/rift-monthly-candidate`.

The job never pushes, signs, installs, restarts services, changes the daily pin, or edits Chezmoi. A failed candidate workspace stays available with the exact conflict or test failure. A successful candidate runs for one week before becoming the daily pin or being turned into an upstream PR.

## Validation and live acceptance

Run template parsing, a targeted Chezmoi dry-run, JSON parsing, `git diff --check`, and the relevant shell tests before applying. Do not add tests that freeze Ezra's chosen workspaces, shortcuts, gestures, gaps, or other preferences.

The local Rift checker is offline and does not start AppKit, Accessibility, WindowServer, or a service:

```sh
rift config check --config ~/.config/rift/config.toml
```

It must parse TOML and run semantic validation. A successful check means that the file exists and is valid. `rift-cli execute config reload` validates and applies against the running service. `rift --validate` mainly checks Rift's saved layout and is not a full config linter.

Use these live queries after Accessibility approval:

```sh
RIFT_CLI_PRETTY=1 rift-cli execute config get
rift-cli query workspaces
rift-cli query windows
rift-cli query displays
/bin/launchctl print "gui/$(id -u)/git.acsandmann.rift"
```

Run Rift formatting, Clippy, unit tests, locked release builds, and the offline checker tests. Run Aegis unit tests for the configured CLI resolver, notification startup and transitions, and status sizing without launching permission-sensitive production services from XCTest. Run the remaining Chezmoi, package, keyboard, Herdr, and presentation dry-run tests.

After the live cutover, confirm one Rift daemon, one Aegis subscription, and one JankyBorders service process. Check workspace overview selection and dismissal, modified Cmd+Tab, horizontal four-finger workspace gestures, Mission Control's vertical fallback, focus-follows-mouse, keyboard focus and move commands, smart floating, Meh+Space, stacks, fullscreen modes, resizing, profile switching, app routing, btop reuse, sleep and wake, and external-display recovery.

Confirm normal ChatGPT, Mail, WhatsApp, Music, Herdr, btop, Orion, and Atlas behavior. Confirm transient ChatGPT previews, update prompts, Computer Use, Browser Use, Antinote, Weather, Contacts, Raycast, and Orion Preview helpers stay out of Rift layouts. Confirm the active border is white and inactive borders are invisible. Send one benign notification and verify the native banner remains visible and clickable. Confirm BoringNotch alone owns media, volume, brightness, and device HUDs. Confirm Aegis and BoringNotch survive logout and login.

## btop

Meh+9 opens or reuses one raw WezTerm btop window in Ops. It uses the invoking display when no external display is connected and the preferred external display otherwise. The helper stores Rift's `{pid, idx}` identity, the WindowServer ID, and a timer generation. It focuses that exact window and keeps it fullscreen within Rift's gaps. Repeated presses reuse the window and reset its one-minute deadline.

The timer checks whether Ops is active on btop's display. While it is active, btop stays open and the helper checks again after another minute. After leaving Ops, btop closes at the next check. Reuse accepts the exact WezTerm bundle ID or the restart fallback with `bundle_id = null`, `app_name = WezTerm`, and a btop title. The helper schedules a close only after it obtains a fresh WindowServer ID and closes only when every identity value and timer generation still match. A Rift restart, failed query, or mismatch fails closed, clears the timer, and leaves the window open.

## Presentation mode

Presentation mode temporarily quits both Aegis and BoringNotch so their bars and HUDs do not cover presentation content. Exiting presentation restores both applications and their login behavior. It does not remove their configuration or change the daily Rift pin.

## Troubleshooting

If Rift does not start after a reboot, inspect its one-shot login agent and Accessibility grant. The local service exits after a denied grant instead of restarting in a loop. Restore its switch and run `rift-local-install --activate` again. Do not reinstall the stock KeepAlive service.

If the Aegis switcher reports `Accessibility required`, `Recovering`, or `Failed`, grant the current signed app access and relaunch it. A certificate replacement creates a new app identity, so the old Accessibility entry may need to be removed and the new `/Applications/Aegis.app` added. Screen Recording denial falls back to icons until activation or an explicit retry.

If a Raycast tile remains in native Mission Control, quit and reopen Raycast, then restart Dock once. Rift's overview does not include that tile. Dragging a window to the top edge does not enter Mission Control. Four-finger swipe up remains the native fallback and may still show Raycast's helper tile.

If an ignored helper appears in Cmd+Tab, wait for Aegis's next authoritative workspace refresh. Relaunch Aegis once if the cache remains stale. If a grey border surrounds an ignored window, check that the running JankyBorders process has a transparent inactive color and that only one service process exists.

If side-by-side displays show scrolling leakage, run Docked Traditional from the Aegis palette before testing. Run Laptop Scrolling after returning to the laptop. A Rift restart also restores Laptop Scrolling.

## Stop and rollback

To stop the local trial without rewriting JJ history:

```sh
/bin/launchctl bootout "gui/$(id -u)/git.acsandmann.rift"
osascript -e 'tell application id "Aegis.Aegis" to quit'
osascript -e 'tell application id "theboringteam.boringnotch" to quit'
```

Disable Aegis Launch at Login before removing its app. Create a new JJ working child from the parent of the migration commit, apply that Chezmoi state, restore the Homebrew Rift paths in the login agent, and start the Homebrew desktop stack. Keep the migration commit intact. Do not rewrite history.

The official Aegis build is the fallback. Quit the local app, move it aside, and apply Chezmoi to reinstall the pinned official bundle. Keep the local source, receipts, and inactive binaries if a later trial may need them. BoringNotch settings remain in its application container.

## References

- [Rift](https://github.com/acsandmann/rift)
- [Rift configuration reference](https://github.com/acsandmann/rift/wiki/Config)
- [Aegis](https://github.com/CCMurphy-dev/Aegis)
- [BoringNotch releases](https://github.com/TheBoredTeam/boring.notch/releases)
