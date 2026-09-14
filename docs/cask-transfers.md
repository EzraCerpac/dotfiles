# Homebrew cask transfer notes

This is a read-only pre-cutover transfer snapshot dated 2026-09-14. For later
Mac status, see [Mac cutover progress](migration.md#mac-cutover-progress).
Installed versions come
from `~/.local/state/mise-migration/20260914-173012/brew-installed.json`.
Artifact, uninstall, update, and target details come from
`HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 --cask --installed`. All 25
installed Caskroom entries still have `.metadata/INSTALL_RECEIPT.json` files.
The Caskroom `Casks/*.json` snapshots are empty for most entries, so the
artifact and uninstall details below describe the current published cask
metadata. Re-query these before a later transfer; they can change upstream.

At snapshot time, no cask had been installed or removed. No app had been closed,
and no service, package, configuration, receipt, or Homebrew tap had been
changed for this inventory. A filtered copy of the metadata is in the private scratch file
`~/.local/state/mise-migration/work/casks/cask-artifacts.tsv`.

A private recovery snapshot is now prepared at
`~/.local/state/mise-migration/work/casks/cask-backups-20260914/`. It contains
the 22 candidate caskroom trees and receipts, installed app bundles, selected
small configuration and preference files, fonts, and listed package-owned
artifacts. AeroSpace is separate and includes its current app and CLI; Brooklyn
and MacTeX are excluded. `manifest.tsv` records source and backup paths, modes,
owners, sizes, and symlink targets. All 22 copied receipts and the recorded
path, type, mode, size, and symlink matches were checked. See `README.txt` in
the snapshot for its exact scope and exclusions.

A separate protected rollback copy of the active AeroSpace app and CLI is kept
at `~/.local/state/mise-migration/work/mac-cutover/aerospace-latest/`. This
copy matches the current `0.21.3-PR2245-Local` build at commit
`0c0671cc593a556a1627a10aee601671e6cbeb3e`; the older AeroSpace recovery
copies remain intact.

## Transfer gate

The Homebrew `.metadata` receipts block native mise from cleanly taking over an
existing Caskroom install. Do not edit or delete receipt files by hand, and do
not use `brew uninstall --cask --zap`. For a supported transfer, back up the
item-specific state below, then remove only Homebrew's ownership with ordinary
`brew uninstall --cask` and install the declared native mise package:

```sh
token=example
# Back up only this app's required state into:
# ~/.local/state/mise-migration/work/casks/$token/
brew uninstall --cask "$token"
mise -C ~/.config/mise bootstrap packages apply "brew-cask:$token" --yes
mise -C ~/.config/mise bootstrap packages status
```

The Homebrew uninstall still runs its declared uninstall hooks. Those can quit
apps, unload launch agents, remove package receipts and system files, or invoke
an app-specific script even without `--zap`. Use one cask at a time, in an
approved maintenance window, and keep the backup until its launch, preferences,
CLI links, and relevant workflow all pass. The command above is a future
per-cask procedure; it was not run during this inventory.

The v2026.9.7 parser accepts app, binary, simple pkg, font, completion, generic
artifact, command-wrapper, and structured flight-step metadata. It deliberately
ignores `manpage` artifacts. Three concrete exclusions emerged:

| Cask | Evidence | Handling |
| --- | --- | --- |
| `brooklyn` | Its install artifact is `screen_saver`; the v2026.9.7 non-install allowlist and install parsers do not handle that artifact, so parsing ends with `unsupported artifact type screen_saver`. | Keep Homebrew as owner and update it through Brew. |
| `mactex-no-gui` | The current `pkg` metadata is an array containing the pkg and a choices object. The v2026.9.7 parser rejects pkg arrays with more than one entry (`pkg installer choices are not supported yet`). | Keep Homebrew as owner and update it through Brew. |
| `aerospace` | The native tap evaluator fails on `nikitabobko/tap/aerospace` with an uninitialized `HOMEBREW_PREFIX` before cask installation. More importantly, the live app is the local `0.21.3-PR2245-Local` build at commit `0c0671cc593a556a1627a10aee601671e6cbeb3e`, while Homebrew still records `0.21.3-Beta` at the same `/Applications/AeroSpace.app` destination. | Keep it under the local build/install exception. Never uninstall or upgrade the stale Brew cask receipt as part of a routine transfer. |

`manpage`, `postflight_steps` with supported `run`/`terminate_process` steps,
and command wrappers are not blanket blockers in v2026.9.7. The other 22
entries pass the static artifact-type review, but this does not prove that each
download, installer, app launch, permission prompt, or self-updater will work
on this Mac. `cotabby` is from GitHub tap `fujacob/cotabby`; tap membership by
itself is not a blocker. The installed `ollama-app` receipt identifies
`homebrew/cask`; the separate local `ollama-app@0.20.3` tap file is not the
owner of this installation.

The parser can install `pkg` artifacts, but v2026.9.7 upgrades for
`auto_updates` casks require exactly one app artifact. Package-only
`karabiner-elements`, `tailscale-app`, and `zoom` therefore skip with
`requires a single owned app`. The `font-sf-pro` cask uses version `latest`, which
the native upgrader also skips. Keep all four Homebrew-owned; `setup:update` now
runs their named Brew updater exceptions. Do not transfer them to native
`brew-cask` declarations.

## Original suggested order at snapshot time

This queue predates the completed transfers; see [Mac cutover progress](migration.md#mac-cutover-progress)
for current status.

1. Transfer the three Nerd Font casks first. They place font files in
   `~/Library/Fonts` and have no app processes or custom uninstall hooks.
2. Transfer `battery`, `cotabby`, `copilot-cli`, `jabref`, `mattermost`, and
   `warp` one by one. `font-sf-pro` is parser-compatible but is a licensed
   Apple pkg; keep its account/license source available. `copilot-cli` is slated
   for mise Aqua ownership rather than `brew-cask`; check the CLI identity
   before removing the cask.
3. Schedule `codexbar`, `crisp`, `hammerspoon`, `homerow`, `middleclick`,
   `raycast`, and `wezterm` only after their running processes can be closed
   safely. At the inventory snapshot these apps were running. Keep terminal
   sessions, accessibility/input settings, login items, and preferences in
   view during their individual checks.
4. Schedule `ollama-app` and `orbstack` separately after backing up the
   configuration or confirming where the current service/data owner lives.
   These packages touch model storage or virtual machines. Leave OrbStack to
   the end: Homebrew's uninstall hook runs `orbctl _internal brew-uninstall`.
5. Keep `brooklyn`, `mactex-no-gui`, `karabiner-elements`, `tailscale-app`, and
   `zoom` with Homebrew. Keep AeroSpace with its local build owner. Do not fold
   these exceptions into a blanket mise cask update.

The process snapshot came from `NSWorkspace` on 2026-09-14. Running names were
AeroSpace, CodexBar, Crisp, Hammerspoon, Homerow, Karabiner-Core-Service,
MiddleClick, OrbStack, Raycast and its helpers, Tailscale, and WezTerm. This is
only a point-in-time check; look again before each future transfer. Zoom was
not running, but its pkg postflight declares a process-termination step, so
the native installer can still close Zoom if it is open at install time.

## Cask-by-cask inventory

The “preserve” paths are candidate state paths derived from the cask's current
`zap` stanza or its package ownership. Ordinary uninstall does not run `zap`,
but preserving the listed configuration before a handoff makes recovery clear.
Do not copy large model or VM stores unless a measured backup plan calls for it.

| Installed cask and version | Install target and artifact | State or uninstall behavior to preserve |
| --- | --- | --- |
| `aerospace` 0.21.3-Beta | Cask targets `/Applications/AeroSpace.app` and `/opt/homebrew/bin/aerospace`; dozens of manpages and `xattr` postflight steps. Live app/CLI instead report `0.21.3-PR2245-Local`, commit `0c0671cc593a556a1627a10aee601671e6cbeb3e`. | Running local build; source is `~/Projects/Tools/AeroSpace`. CLI is `~/.local/opt/aerospace-pr2245/bin/aerospace`. The protected current app/CLI copy is in `~/.local/state/mise-migration/work/mac-cutover/aerospace-latest/`; earlier copies and rollback notes remain in `~/.local/state/aerospace-pr2245/`. The local source checkout is clean at the installed commit. The explicit mise task only builds and stages; it does not replace the active app or CLI. |
| `battery` 1.4.0 | `/Applications/battery.app`; app may install `/usr/local/bin/smc` on first use. `auto_updates: true`. | Uninstall explicitly deletes `/usr/local/bin/smc`. Candidate data: `~/.battery`, `~/Library/Application Support/battery`, and `~/Library/Preferences/{co.palokaj.battery,org.mentor.Battery}.plist`. |
| `brooklyn` 2.1.0 | `~/Library/Screen Savers/Brooklyn.saver`; `screen_saver` artifact. | Not supported by the v2026.9.7 cask parser. Keep Brew ownership. `zap` would remove the saver file. |
| `codexbar` 0.55.1 | `/Applications/CodexBar.app`; CLI `/opt/homebrew/bin/codexbar`. | Running. Uninstall has `quit`. Candidate data: `~/.codexbar`, `~/Library/Application Support/CodexBar`, `~/Library/Application Support/com.steipete.codexbar`, and `~/Library/Preferences/com.steipete.codexbar.plist`. |
| `copilot-cli` 1.0.41 | Binary `/opt/homebrew/bin/copilot`; generated shell completions; `auto_updates: true`. | No cask `zap` state. Intended destination is mise Aqua; verify the Aqua package is the same CLI before removing this cask. |
| `crisp` 1.5.0 | `/Applications/Crisp.app`; helper CLI `/opt/homebrew/bin/crispctl`; `auto_updates: true`. | Running. Uninstall quits Crisp and removes its login item. Candidate data: `~/Library/Application Support/Crisp`, `~/Library/Preferences/com.crisp.app.plist`. |
| `cotabby` 0.6.2-beta | `/Applications/Cotabby.app`; tap `fujacob/cotabby`. | No declared `zap` or custom uninstall hook. Add its GitHub tap source to mise before a later transfer. |
| `font-fira-code-nerd-font` 3.4.0 | Font files under `~/Library/Fonts/FiraCodeNerdFont*.ttf`, `FiraCodeNerdFontMono*.ttf`, and `FiraCodeNerdFontPropo*.ttf`. | Font-only; files are reproducible and no personal app state is listed. |
| `font-hack-nerd-font` 3.5.1 | Font files under `~/Library/Fonts/HackNerdFont*.ttf`, `HackNerdFontMono*.ttf`, and `HackNerdFontPropo*.ttf`. | Font-only; files are reproducible and no personal app state is listed. |
| `font-sf-pro` latest | `SF Pro Fonts.pkg`; pkg receipt `com.apple.pkg.SFProFonts`. | Simple one-pkg install is supported, but preserve the Apple licensing/account path. Uninstall uses `pkgutil`; no cask `zap` data is declared. |
| `font-symbols-only-nerd-font` 3.5.1 | `SymbolsNerdFont-Regular.ttf` and `SymbolsNerdFontMono-Regular.ttf` under `~/Library/Fonts`. | Font-only; files are reproducible and no personal app state is listed. |
| `hammerspoon` 1.1.1 | `/Applications/Hammerspoon.app`; CLI `/opt/homebrew/bin/hs`; `auto_updates: true`. | Running. Uninstall quits Hammerspoon. Candidate state: `~/.hammerspoon` and `~/Library/Preferences/org.hammerspoon.Hammerspoon.plist`. |
| `homerow` 1.5.3 | `/Applications/Homerow.app`; `auto_updates: true`. | Running; preserve Accessibility authorization. Candidate state: `~/Library/Application Support/com.superultra.Homerow` and `~/Library/Preferences/com.superultra.Homerow.plist`. |
| `jabref` 5.15 | `/Applications/JabRef.app`. | No process seen. Candidate state: `~/Library/Application Support/JabRef` and `~/Library/Preferences/org.jabref.cli.plist`; keep bibliography libraries at their existing locations. |
| `karabiner-elements` 16.0.0 | `Karabiner-Elements.pkg`; CLI `/opt/homebrew/bin/karabiner_cli`; support files under `/Library/Application Support/org.pqrs`. `auto_updates: true`. | Core service was running. Uninstall includes early/script hooks, launchctl and signal actions, pkg receipt removal, and deletion of `/Library/Application Support/org.pqrs`. Back up `~/.config/karabiner`, `~/.local/share/karabiner`, and `~/Library/Application Support/Karabiner-Elements`; test the virtual HID driver and key mappings after an approved handoff. |
| `mactex-no-gui` 2026.0324 | `mactex-20260324.pkg`, with a separate installer choices object. | Parser-incompatible. Brew uninstall removes TeX package receipt and `/Library/TeX`, `/usr/local/texlive/2026`, `/etc/paths.d/TeX`, and `/etc/manpaths.d/TeX`; keep with Brew. |
| `mattermost` 6.3.0 | `/Applications/Mattermost.app`. | No process seen. Uninstall quits Mattermost. Candidate state: `~/Library/Application Support/Mattermost`, `~/Library/Containers/Mattermost.Desktop`, and `~/Library/Preferences/Mattermost.Desktop.plist`. |
| `middleclick` 3.2.0 | `/Applications/MiddleClick.app`. | Running. Uninstall quits the app and removes its login item. No `zap` is declared; check `~/Library/Preferences/art.ginzburg.MiddleClick.plist` before transfer. |
| `ollama-app` 0.30.6 | `/Applications/Ollama.app`; CLI `/opt/homebrew/bin/ollama`; `auto_updates: true`. | Installed from `homebrew/cask`; no Ollama GUI process seen. Uninstall stops its launch agent and quits the app. Preserve `~/.ollama` and `~/Library/Application Support/Ollama`; model data can be large and should remain with Ollama. |
| `orbstack` 2.2.1,20628 | `/Applications/OrbStack.app`; CLI `/opt/homebrew/bin/orbctl` and `/opt/homebrew/bin/orb`; shell completions; `auto_updates: true`. | Running. Brew uninstall calls `orbctl _internal brew-uninstall`; preserve `~/.orbstack` and the existing `~/OrbStack` data. Native metadata has a supported structured `run` postflight step. Do not copy virtual-machine data as part of a routine app backup. |
| `raycast` 1.104.22 | `/Applications/Raycast.app`; `auto_updates: true`. | Running with helpers. Uninstall quits the app and removes its login item. Candidate state: `~/.config/raycast`, `~/Library/Application Support/com.raycast.macos`, and `~/Library/Preferences/com.raycast.macos.plist`; verify extensions and Accessibility permissions. |
| `tailscale-app` 1.98.2 | `Tailscale-<version>-macos.pkg` installs `/Applications/Tailscale.app` and its network extension; current published version is 1.102.4 and `auto_updates: true`. | Tailscale and its network extension were running. Uninstall quits the app, removes login items and pkg receipts, and deletes package-owned CLI/helper files. Preserve the current account/network state; candidate paths include `/Library/Tailscale` and `~/Library/Containers/io.tailscale.ipn.macsys`. Check connectivity after a planned handoff. |
| `warp` 2026.08.19.08.15.stable_01 | `/Applications/Warp.app`; `auto_updates: true`. | No process seen. Candidate state: `~/.warp`, `~/Library/Application Support/dev.warp.Warp-Stable`, and `~/Library/Preferences/dev.warp.Warp-Stable.plist`. |
| `wezterm` 20240203-110809,5046fc22 | `/Applications/WezTerm.app`; CLI links under `/opt/homebrew/bin`; shell completions. | Running. Do not close active terminals for this inventory. Candidate state: `~/.local/share/wezterm`; the tracked WezTerm config remains separately managed. |
| `zoom` 7.0.5.81138 | `zoomusInstallerFull.pkg`; installs `/Applications/zoom.us.app`; `auto_updates: true`. | No Zoom process seen. The installer postflight can terminate `zoom.us.app`; uninstall unloads Zoom services, kills the app process, removes its pkg receipt and privileged helper. Candidate user state includes `~/.zoomus`, `~/Documents/Zoom`, `~/Desktop/Zoom`, and `~/Library/Application Support/zoom.us`. |

## AeroSpace owner and recovery

The active AeroSpace build is owned by its local source checkout, not by
`brew-cask` or the stale Homebrew receipt. The checkout at
`~/Projects/Tools/AeroSpace` is clean at commit
`0c0671cc593a556a1627a10aee601671e6cbeb3e` (`fix: exclude Codex quick switcher
from workspace management`). The local mise task builds the Xcode Release app
and arm64 SwiftPM Release CLI into a versioned staging directory. It does not
install over `/Applications/AeroSpace.app` or
`~/.local/opt/aerospace-pr2245/bin/aerospace`, and it does not quit the running
window manager. Do not run `install-from-sources.sh`: it performs Homebrew
uninstall/install operations.

The installed build note is
`~/.local/state/aerospace-pr2245/README.md`. The fresh protected copy at
`~/.local/state/mise-migration/work/mac-cutover/aerospace-latest/` contains the
current app and CLI for cutover recovery. Earlier app/CLI copies and the
rollback procedure remain under `~/.local/state/aerospace-pr2245/`. Homebrew's
`0.21.3-Beta` receipt is stale and must not be treated as the active owner.

## Sources

- [mise Homebrew cask documentation](https://mise.jdx.dev/bootstrap/packages/brew.html)
- [mise v2026.9.7 cask artifact parser](https://github.com/jdx/mise/blob/v2026.9.7/src/system/packages/brew/cask/artifacts.rs)
- [mise v2026.9.7 cask artifact allowlist](https://github.com/jdx/mise/blob/v2026.9.7/src/system/packages/brew/cask/state.rs#L1362-L1388)
- [mise v2026.9.7 release](https://github.com/jdx/mise/releases/tag/v2026.9.7)
- [Homebrew cask API](https://formulae.brew.sh/docs/api/)
- Existing [software ownership](software-ownership.md) and [window-manager runbook](window-manager-runbook.md)
