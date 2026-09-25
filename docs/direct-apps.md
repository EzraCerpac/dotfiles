# Direct Mac application inventory

Snapshot: 2026-09-14. This pre-cutover inventory fills the gap between the
workstation's package manifest and the apps in `/Applications` and
`~/Applications`. The 25 Homebrew
cask receipts stay covered by [software ownership](software-ownership.md) and
[cask transfer notes](cask-transfers.md); this file covers other installed
bundles and the direct-install exceptions. See [Mac cutover progress](migration.md#mac-cutover-progress)
for later adoption and transfer status.

Versions below use the live bundle's `CFBundleShortVersionString`, with the
bundle build in parentheses when useful. Steam has no short-version key, so its
listed `6.1` is the bundle build. A Homebrew receipt or an app's
`_MASReceipt/receipt` is direct owner evidence. The App Store app
`de Volkskrant` also carries `iTunesMetadata.plist` with item ID `418873064`.
Where no package or App Store receipt exists, “vendor direct” is an inference
from the signed app and its product identity. Local ownership is inferred from
matching app IDs and the checked-out project or install workflow. Those labels
do not prove the exact installer used.

The Homebrew cask lookup used the official
[Homebrew JSON API](https://formulae.brew.sh/docs/api/). The cask tokens below
are current API tokens, and their app artifacts fit the mise 2026.9.7 static
cask parser allowlist
([parser source](https://github.com/jdx/mise/blob/v2026.9.7/src/system/packages/brew/cask/artifacts.rs)).
This snapshot records candidate support and pre-cutover owner evidence. Later
adoption and update status is in [Mac cutover progress](migration.md#mac-cutover-progress).
Treat a bundle as mise-owned only after native package status confirms it.
The v2026.9.7 `adopt=true` path is for a matching unmanaged app without Homebrew
metadata; a matching name or path alone does not establish ownership.

## Native cask candidates in the 2026-09-14 snapshot

These direct vendor bundles have a matching current Homebrew cask artifact.
At the snapshot date, the 21 `brew-cask:` targets below were declared in
`config.workstation.toml` with `adopt = true`, but adoption had not been
confirmed. “Vendor updates” means the cask metadata sets
`auto_updates: true`; it does not mean mise must leave the app unchanged. In the
pinned v2026.9.7 source, `latest` casks and receipts already at the target
version are skipped. Otherwise, an explicit upgrade may proceed only when the
receipt matches the cask's single app artifact, the live app version is readable
and older than the cask version, and the app is not running. Failed checks are
reported as skips; a running app is reported as running and self-updating. This
path needs no `--greedy` flag or config override
([upgrade source](https://github.com/jdx/mise/blob/v2026.9.7/src/system/packages/brew/cask/mod.rs#L78-L124)).

| Installed app and live version | Current owner evidence | Declared mise target | App and cask notes |
| --- | --- | --- | --- |
| Antinote 2.1.2 | Vendor direct, inferred | `brew-cask:antinote` | Vendor updater may run |
| Blender 5.2.0 | Vendor direct, inferred | `brew-cask:blender` | Regular cask upgrades |
| Cotypist 2026.3.1 (79) | Vendor direct, inferred | `brew-cask:cotypist` | Vendor updater may run |
| CrossOver 26.3 (26.3.0.39832) | Vendor direct, inferred | `brew-cask:crossover` | Vendor updater may run; preserve license/account state |
| Google Chrome 152.0.7977.82 | Google-signed direct app | `brew-cask:google-chrome` | Vendor updater may run |
| Grammarly Desktop 1.183.1 | Vendor direct, inferred | `brew-cask:grammarly-desktop` | Vendor updater may run; cask targets Grammarly Desktop |
| Glaze 0.8.0 | Raycast-signed direct app | `brew-cask:raycast-glaze` | Vendor updater may run; this is the `glaze.app` product, not the similarly named University of Chicago cask |
| Helium 0.16.6.1 | Vendor direct, inferred | `brew-cask:helium-browser` | Vendor updater may run; selected by the `helium.computer` cask, not the unrelated `helium` token |
| MEGAsync 6.2.0 | Mega-signed direct app | `brew-cask:megasync` | Vendor updater may run; keep sync/account state with MEGA |
| Mathpix Snipping Tool 3.4.16 | Vendor direct, inferred | `brew-cask:mathpix-snipping-tool` | Vendor updater may run |
| OmniDiskSweeper 1.15.1 (38.0.0) | Vendor direct, inferred | `brew-cask:omnidisksweeper` | Vendor updater may run |
| Orion 1.1.2 (151) | Vendor direct, inferred | `brew-cask:orion` | Vendor updater may run; preserve browser profile |
| Plex 1.115.0 | Vendor direct, inferred | `brew-cask:plex` | Vendor updater may run; Plex libraries remain Plex-owned |
| PyCharm 2025.3.3 (PY-253.31033.139) | JetBrains-signed direct app | `brew-cask:pycharm` | Vendor updater may run; keep JetBrains account and IDE settings |
| QLMarkdown 1.0.24 (50) | Vendor direct, inferred | `brew-cask:qlmarkdown` | Vendor updater may run; includes its Quick Look integration |
| RustDesk 1.4.9 (67) | Vendor direct, inferred | `brew-cask:rustdesk` | Regular cask upgrades |
| Shottr 1.9.1 (128) | Vendor direct, inferred | `brew-cask:shottr` | Vendor updater may run |
| Steam (CFBundleVersion 6.1) | Valve app; Steam self-updater | `brew-cask:steam` | Vendor self-updater; games and libraries remain Steam-owned |
| T3 Code (Nightly) 0.0.34-nightly.20260816.1108 | Vendor direct, inferred | `brew-cask:t3-code@nightly` | Vendor updater may run; this preserves the Nightly channel |
| Transmission 4.1.3 (14718.1.399) | Vendor direct, inferred | `brew-cask:transmission` | Vendor updater may run |
| Wispr Flow 1.5.530 | Vendor direct, inferred | `brew-cask:wispr-flow` | Vendor updater may run |

The cask metadata marks all but Blender and RustDesk with `auto_updates: true`.
This describes the cask metadata and declarations at the snapshot date; it is
not the current `dots up` upgrade policy. Current routine updates install
missing declared casks and skip upgrades for casks marked `auto_updates: true`.
Use native package status for current ownership and update results.

## Later management changes

After this snapshot, Blender, CrossOver, Helium Browser, MEGAsync, Mattermost,
Grammarly Desktop, and Cotabby were removed from the workstation declarations.
They remain installed on the Mac and are no longer installed or updated by
`dots`. Their rows and receipts above/below are retained as historical evidence
from the 2026-09-14 inventory. Cotabby's receipt remains part of the historical
25-receipt inventory; it is not a current mise declaration.

Raycast Glaze and Wispr Flow were removed from the Mac and from the current
workstation declarations after the snapshot. Their rows above record the
previous installed versions and cask targets only.

## App Store, local, and vendor exceptions

| Installed app and live version | Current owner evidence | Selected owner |
| --- | --- | --- |
| ChatGPT.app 26.908.40834 (8881) | OpenAI-signed direct app; bundle ID is `com.openai.codex` | OpenAI app updater. Defer a cask declaration: `chatgpt` targets `ChatGPT.app`, while `codex-app` targets `Codex.app`; neither API record proves which package owns this live bundle. |
| Developer 11.0.2 (1102.3.1) | App Store receipt | App Store |
| de Volkskrant 7.45.0 (52768) | App Store wrapper metadata; item ID `418873064` | App Store |
| eduVPN 4.1.3 (2456) | App Store receipt | App Store |
| Folder Preview 3.1 (132) | App Store receipt | App Store; `folder-preview-pro` targets a separate `Folder Preview Pro.app` |
| geteduroam 2.5 (178) | App Store receipt | App Store |
| Goodnotes 7.1.18 (3892200.147026606) | App Store receipt | App Store |
| Home Assistant 2026.9.0 (2026.2874) | App Store receipt | App Store; a same-name cask exists, but it is not the current owner |
| Logic Pro 11.1.1 (6157) | App Store receipt | App Store |
| NordVPN 10.10.1 (375) | App Store receipt | App Store; the direct cask alias is not the current owner |
| WhatsApp 26.35.74 (1063790046) | App Store receipt | App Store; keep this receipt and account path |
| Aegis 1.1.0 | Existing local source, signing, and install workflow | Local build; already described in [software ownership](software-ownership.md) |
| AeroSpace 0.21.3-PR2245-Hyper | Local build at the live path; stale Homebrew receipt is not the live owner | Local build; already described in [cask transfer notes](cask-transfers.md) |
| KeyType 1.6 (8) | Bundle ID maps to `~/Projects/KeyType` | Local project/build workflow |
| KeyType Dev 1.6 (8) | Bundle ID maps to that project's dev-install script | Local project/build workflow |
| SoloTrace 0.1.0 (202607271343) | Bundle ID and app name map to `~/Projects/solotrace` | Local project/build workflow |
| VoiceInk 2.13 (213) | Local build from `~/Projects/Tools/VoiceInk`; active weekly updater preserves the local build and signing workflow | Keep the local build owner; do not transfer to stock `brew-cask:voiceink` |
| TurboFieldfare Uncensored 0.7.1 (`d50bf4f`) | User-level app with an ad-hoc signature; no vendor or package receipt found | Keep as a local app; no global package declaration |
| BoringNotch 2.7.3 (271) | Vendor app; no matching Homebrew cask in the official API | Vendor app/update path |
| Edist 1.3.3 | Jules Le Prince-signed app; no matching cask | Vendor app/update path |
| Gateway 1.0.1 | Atkinson Advanced Modeling-signed app; no matching cask | Vendor app/update path |
| Mapping Tonal Harmony Pro 10.5.8 | MDECKS Music-signed app; no matching cask | Vendor app/update path |
| Neovim 1.3 (534) | Automator application stub with a local workflow, not the Goneovim app | Local Automator workflow; Neovim CLI remains separately managed |
| Omni 0.3.18 (1) | Han Xiao-signed app; no matching cask | Vendor app/update path; distinct from OmniDiskSweeper |
| ScreenControl 1.1.0 | Pushbrands-signed app; no matching cask | Vendor app/update path |
| SINE Player 1.4.1 (1.4.1.1570) | Orchestral Tools-signed app in `~/Applications` | Vendor app/account; licensed sample content stays with SINE Player |
| TypeSeer 1.1.3 (163) | Vendor-signed app; no matching cask | Vendor app/update path |
| Vital 1.5.5 | Matthew Tytel-signed app; no matching cask | Vendor app/account; presets and licensed content stay with Vital |
| Xcode 27.0 (25183.45.9) | Apple-signed app, without an App Store receipt; no matching cask | Apple developer distribution/update path; exact install source remains unverified |
| logioptionsplus 2.7.970334 | Logitech app; cask `logi-options+` uses an installer script with `sudo: true`, which the tested parser rejects | Logitech installer/update path; do not add a mise cask declaration |
| oMLX 0.7.0.dev2 (2657) | Developer ID-signed app; no matching cask | Vendor app; model files and catalogs stay oMLX-owned |
| `tunnel-client` 0.0.11 | Proofloom's documented Secure MCP Tunnel client at `~/.local/bin/tunnel-client`; no source/build mapping found | Proofloom-scoped vendor exception; update only through its documented vendor distribution path |
| `vibez` | Local CLI at `~/.local/bin/vibez`; source at `~/Projects/Archive/vibez` | Archived project artifact; rebuild only through its project workflow |

The live direct app signature or receipt identifies the distributor, not whether
its updater is currently enabled. Keep the named App Store, Apple, vendor, and
local owners until their own update route is deliberately changed. `Home
Assistant`, `NordVPN`, and `WhatsApp` have cask records, but their App Store
receipts are the observed owners. Do not replace those receipts just to make the
package list look uniform.

`Dome Keeper` and `Inscryption` are user-level games and remain owned by Steam;
they are not package-manager targets. Model weights, media libraries, and
licensed plug-in or sample content likewise remain with their application.

## Scope and verification

The cask API lookup covered exact app artifacts and names in one read-only
request. Native cask aliases were checked for parser compatibility only; no
installer was run. App Store ownership came from embedded receipts or, for
`de Volkskrant`, its App Store wrapper metadata. Vendor labels without a receipt
are inferences from the signed app identity. A later handoff still needs an
item-specific check of app state, permissions, update behavior, and uninstall
effects.

The registered `vendor-apps` exception in `setup:update` reads the named entries
in [`setup-scripts/setup/vendor-apps.tsv`](../setup-scripts/setup/vendor-apps.tsv). `Pinned`
records a local/project owner; it does not say the app is current, tested, or
healthy. `Deferred` records an app or vendor update path that remains manual.
The report checks only whether each declared target path exists, prints its
owner and next step, and never runs an updater or launches an app.

At the snapshot date, Homebrew-owned app bundles—including CodexBar, Cotabby,
Crisp, Hammerspoon, Homerow, JabRef, Karabiner-Elements and its helper,
Mattermost, MiddleClick, OrbStack, Raycast, Tailscale, WezTerm, and Zoom—were
present in the 25 cask receipt inventory. Cotabby and Mattermost remain
installed but are no longer declared by `dots`. The installed Homebrew receipts
for apps not present in `/Applications` also remain documented there. This
inventory does not mark any unlisted application as unwanted.
