# Current policy

The manifests are authoritative: shared terminal tools, Neovim, and pagers load
for both roles. Tools track latest releases; Kanata and Karabiner are held for
the known input bug. Herdr updates defer while its server is running. Older
Python interpreters are application compatibility dependencies. The inventory
below records the migration baseline; it is not a list of current version pins.

# Software ownership inventory

Snapshot: 2026-09-14. This pre-cutover inventory uses read-only Homebrew, mise, `npm -g`,
and `uv tool list` output. Homebrew queries used `HOMEBREW_NO_AUTO_UPDATE=1`;
no package was installed, upgraded, uninstalled, or pruned for this inventory.
For later Mac state, see [Mac cutover progress](migration.md#mac-cutover-progress).

Later package removals supersede affected rows in this snapshot: Remindctl,
Copilot CLI, Pi, and the global npm Codex CLI were removed from package
configuration and the Mac. Claude Code, Grok, and Antigravity CLI were also
removed from package configuration and their executable installs were
uninstalled. The native base-profile `codex` tool remains; the ChatGPT app's
embedded executable remains app-owned.

The profile files show the declarations used to plan this migration. This
snapshot does not establish current ownership after later cutover batches. For
bundles that are still pending, keep the current installation until its
individual transfer and acceptance check has completed.

## Ownership rules

| Software | Current installation/owner | Desired owner and update path |
| --- | --- | --- |
| Portable runtimes and CLIs | Homebrew formulae, mise installs, or shell fallback | `[tools]`; `mise upgrade` within the declared request |
| Native libraries, shell integration, and host utilities | Homebrew formulae in `/opt/homebrew` | `brew:` entries in `[bootstrap.packages]`; `mise bootstrap packages upgrade` |
| Mac applications and fonts | Homebrew casks and app bundles in `/Applications` | `brew-cask:` entries in `[bootstrap.packages]`, after staged ownership transfer |
| Global Node applications | `/opt/homebrew/lib/node_modules`, binaries in `/opt/homebrew/bin` | mise `npm:` tools; local project checkouts remain project-owned |
| Global Python applications | uv tools in `$UV_TOOL_DIR` (currently `$HOME/.local/share/uv/tools`) | No mise `pipx:` tools are currently declared (the former ones were removed as unwanted); use a named isolated installer exception when the package needs a custom build or stable launcher |
| Local projects, models, content, and services | Existing project or application | Remain with that owner; migrations and service lifecycle get explicit tasks |

Mise's native package declarations are additive. Do not run `mise bootstrap
packages prune` during this migration: undeclared Homebrew kegs and cask
receipts remain available for the staged handoff and rollback. Package and
cask support details are in the [mise package docs](https://mise.jdx.dev/bootstrap/packages/)
and [Homebrew manager docs](https://mise.jdx.dev/bootstrap/packages/brew.html).

## Duplicate and runtime decisions

| Item | Observed active resolution | Other installed copy | Desired declaration and next action |
| --- | --- | --- | --- |
| Go | mise shim selects Go 1.27.0 from the mise install | Homebrew `go` 1.27.0 is present but not installed-on-request; `brew uses --installed go` returned no installed dependents | Keep `go = "latest"` in mise; verify dependent scripts before removing the Brew copy |
| Rust | `rustc` reports 1.98.0 from the active Rustup toolchain; `RUSTUP_TOOLCHAIN` currently selects `1.98.0-aarch64-apple-darwin` | Homebrew Rust 1.97.1 and a mise `rust` symlink entry | Keep mise `rust = "latest"`; inspect the environment override before claiming routine Rust upgrades work; retain Brew until dependent workflows pass |
| Julia | mise HTTP tool 1.12.6 | Homebrew Julia 1.12.6 | Keep the exact 1.12.6 request and its upstream HTTP URLs in `config.workstation.toml`; remove Brew only after the mise path passes the Julia workflows |
| uv | mise Aqua tool 0.12.5 | Homebrew uv 0.12.0 | Keep mise `uv = "latest"`; verify all uv and remctl tasks before removing Brew |
| Node.js | mise shim falls through to Homebrew Node 26.7.0 | Homebrew `node@22` 22.23.2 is also installed, but keg-only | New owner is mise Node `latest`, preserving the currently selected 26 line. Audit scripts for explicit Node 22 paths before retiring that keg |
| ripgrep | mise shim falls through to Homebrew ripgrep 15.2.0 | No separate mise install is active | New owner is mise Aqua `ripgrep`; confirm `rg` resolution after profile activation before removing Brew |
| Neovim | mise vfox tool 0.12.4 | No Homebrew formula root | Keep exact version 0.12.4 and switch the new declaration to Aqua; this backend change needs an install and editor check |
| Python | Homebrew Python 3.13.14 is the current interpreter used by the remctl wrapper | Homebrew Python 3.11.15 also installed | Declare mise Python 3.13. Keep 3.11 until absolute-path and consumer scans show it is unused; the setup wrapper is being changed to `mise -C <setup> exec python@3.13 -- …` |
| Codex CLI | At audit, `codex` resolved to global npm package 0.153.4 at `/opt/homebrew/bin/codex` | ChatGPT.app also contained a bundled `codex` executable | The npm CLI was later removed from config and the Mac. The native base-profile `codex` tool remains; ChatGPT.app's executable remains app-owned. |
| remindctl | At audit, the installed Homebrew binary reported 0.3.4; the tap formula pointed to official upstream v0.3.7 | The migration tested mise `github:openclaw/remindctl` v0.3.6 | Remindctl was later removed from config and the Mac. Its removal did not change Reminders access. |

The 2026-09-14 pre-cutover inventory recorded 99 Homebrew formulae installed on
request. Since then, 43 redundant formulae were retired after fresh Fish
resolution checks and full keg clones; required dependency runtimes remain.
Formulae selected for mise tool ownership are listed below with their observed
Brew version and new tool name. Homebrew's `git-delta` formula becomes mise's
`delta` tool; these are two names for the same CLI and must not be declared twice.

| Baseline Homebrew formula and version | New mise `[tools]` owner |
| --- | --- |
| `actionlint` 1.7.12; `age` 1.3.1; `atuin` 18.19.0; `bat` 0.26.1; `carapace` 1.7.3 | Same-named Aqua tools |
| `btop` 1.4.7 | Aqua tool on Linux; macOS retained as `brew:btop` because Aqua does not support Darwin arm64 |
| `cargo-audit` 0.22.2; `eza` 0.23.5 | `cargo:cargo-audit`; `cargo:eza` (Rust dependency declared) |
| `cmake` 4.4.1; `deno` 2.9.5; `fd` 10.5.0; `fzf` 0.74.3; `gh` 2.98.0 | Aqua CMake; core Deno; Aqua `fd`, `fzf`, and `gh` |
| `git-delta` 0.19.2; `git-lfs` 3.7.1; `gitleaks` 8.30.1; `glow` 2.1.2; `gum` 2.0.0 | `delta`; Aqua `git-lfs`, `gitleaks`, `glow`, and `gum` |
| `jj` 0.45.1; `jjui` 0.10.9; `jq` 1.8.2; `lazygit` 0.64.1 | Same-named Aqua tools |
| `node` 26.7.0; `pnpm` 11.24.0; `opencode` 1.18.15 | Core Node; Aqua pnpm and OpenCode |
| `pandoc` 3.10.1; `rclone` 1.75.0; `ripgrep` 15.2.0; `sccache` 0.17.0 | GitHub Pandoc; same-named Aqua tools |
| `starship` 1.26.0; `swiftformat` 0.62.1; `swiftlint` 0.65.0; `television` 0.15.9 | Same-named Aqua/GitHub tools |
| `tinymist` 0.15.2; `tmux` 3.7c; `typst` 0.15.1; `typstyle` 0.15.0 | Same-named Aqua tools |
| `tlrc` 1.13.1 | `cargo:tlrc` with the declared Rust dependency |
| `usage` 6.4.1 | Explicit `aqua:jdx/usage` package |
| `worktrunk` 0.74.0; `xcodegen` 2.46.0; `yazi` 26.8.15; `yt-dlp` 2026.7.4; `zoxide` 0.10.0 | Same-named Aqua/GitHub tools |
| `julia` 1.12.6; `rust` 1.97.1; `uv` 0.12.0 | Existing mise ownership is retained; Brew duplicates are pending workflow checks |
| `python@3.13` 3.13.14_1 | Mise Python 3.13, needed by remctl and global CLI environments |

Other installed roots awaiting a consumer audit are `node@22` 22.23.2 and
`python@3.11` 3.11.15_4. They are intentionally absent from the desired
declarations. Do not remove them until path scans and dependent workflows are
complete. The Homebrew `mise` 2026.9.2 formula moves to the standalone mise
installer and self-update task. `chezmoi` 2.71.1 is migration rollback state,
not a desired package. The current Rift formula is owned by the signed local
build task described below.

## Homebrew packages retained in the workstation profile

These 45 formula roots have no verified portable mise backend in the installed
registry or belong in the shared host prefix. Their intended native owner is a
`brew:` package declaration restricted to macOS arm64 in
`config.workstation.toml`.

| Current root formula and observed version | Reason / migration note |
| --- | --- |
| `osx-cross/arm/arm-none-eabi-binutils` 2.41; `osx-cross/arm/arm-none-eabi-gcc@9` 9.5.0_2; `osx-cross/avr/avr-gcc@9` 9.5.0; `qmk/qmk/qmk` 1.1.8 | Keyboard firmware toolchain; keep together and validate its build task |
| `felixkratz/formulae/borders` 1.9.0; `kanata` 1.12.0; `m1ddc` 1.2.0; `xdot` 1.6 | macOS display/input integration; update through setup, then check behavior without restarting services |
| `btop` 1.4.7 | Native macOS Homebrew owner; the selected Aqua package supports Linux but not Darwin arm64 |
| `cliproxyapi` 7.2.145 and 7.2.155; `unbound` 1.25.2 | Host services; install/update package separately from service activation, and report any deferred restart |
| `curl` 8.21.0; `dos2unix` 7.5.6; `fish` 4.8.1; `gnupg` 2.5.21; `htop` 3.5.3; `rsync` 3.5.0; `sshpass` 1.10; `tree` 2.3.2; `wget` 1.25.0 | Host utilities, shell path, or native integration |
| `ffmpeg` 8.1.2_1; `librsvg` 2.62.3; `openfst` 1.8.4; `pillow` 12.3.0; `poppler` 26.08.0; `pulseaudio` 17.0; `tesseract` 5.5.3 | Native libraries/media stack; retain dependency closure in the Homebrew prefix |
| `gitlogue` 0.10.0; `harper` 2.8.0; `himalaya` 2.0.0; `modem-dev/tap/hunk` 0.17.0 | Existing application CLIs without a registry backend selected here |
| `antoniorodr/memo/memo` 0.6.0; `dastrobu/tap/mail-mcp` 0.5.0; `mole` 1.48.1; `openai-whisper` 20250625_5; `pdfpc` 4.7.0 | Keep current native recipes pending direct replacement evidence |
| `steipete/tap/peekaboo` 3.9.8; `summarize` 0.21.11; `pngpaste` 0.2.3 | Mac-specific applications/helpers without a selected portable backend |
| `graphviz` 15.1.0; `llvm` 22.1.8; `lua` 5.5.0; `pkgconf` 3.0.7 | Build/runtime support in the native prefix |
| `ezracerpac/tap/typst-time-machine` 0.1.3 | Existing tap recipe; keep separate from versioned Typst tools |

This is a manager change, not a request to move or rebuild `/opt/homebrew`.
Tapped package declarations need their tap sources present in root
`[bootstrap.brew.taps]` configuration. The required formula taps are
`antoniorodr/memo`, `dastrobu/tap`, `felixkratz/formulae`, `modem-dev/tap`,
`osx-cross/arm`, `osx-cross/avr`, `qmk/qmk`, `steipete/tap`, and
`ezracerpac/tap`. The selected tapped casks additionally use
`fujacob/cotabby` and `nikitabobko/tap`. The machine currently has 16 taps:
`acsandmann/tap`, `antoniorodr/memo`, `dastrobu/tap`, `ezracerpac/local-casks`,
`ezracerpac/tap`, `felixkratz/formulae`, `fujacob/cotabby`, `jundot/omlx`,
`manaflow-ai/cmux`, `modem-dev/tap`, `nikitabobko/tap`, `osx-cross/arm`,
`osx-cross/avr`, `qmk/qmk`, `steipete/tap`, and `typewhisper/tap`.

The initial Mac package preflight was a declaration check, not a transfer.
Its snapshot found 46 of 48 Homebrew formula declarations installed (`bash`
and `mas` were missing) and 21 `adopt = true` casks matching unmanaged app
bundles. Later cutover status is in [Mac cutover progress](migration.md#mac-cutover-progress);
this baseline does not describe which transfers have happened since. Ten Mac
App Store IDs were skipped because `mas` was unavailable. The original baseline
also has four cask exceptions: pinned AeroSpace, Brooklyn, MacTeX, and Copilot
CLI.

## Global npm and Python applications at audit time

The npm listing came from `/opt/homebrew/lib/node_modules`. The audit proposed
moving executable CLIs to mise's native npm backend with floating `latest`
requests. Pi was removed from the Mac and package configuration later, along
with the npm Codex CLI; the native `codex` tool remains. The proposed Pi plugin
updater is no longer part of the current setup. Plugin rows below preserve
audit-time package details and do not assert a current install or updater.

| Global npm package at audit | Version at audit | Audit-time owner or later disposition |
| --- | --- | --- |
| `@earendil-works/pi-coding-agent` | 0.80.3 | Pi CLI; later removed from config and the Mac |
| `@ollama/pi-web-search` | 0.0.5 | Pi plugin recorded in audit-time settings; current install status is not established here |
| `@openai/codex` | 0.153.4 | npm CLI later removed from config and the Mac; native `codex` retained |
| `@zed-industries/codex-acp` | 0.16.0 | `npm:@zed-industries/codex-acp` |
| `agent-browser` | 0.25.3 | `npm:agent-browser` |
| `caveman-pi` | 1.0.0 | Pi plugin recorded in audit-time settings; current install status is not established here |
| `pi-constell-plan` | 0.1.8 | Pi plugin recorded in audit-time settings; current install status is not established here |
| `pi-markdown-preview` | 0.10.0 | Pi plugin recorded in audit-time settings; current install status is not established here |
| `pi-mono-btw` | 1.7.4 | Pi plugin recorded in audit-time settings; current install status is not established here |

`npm` 11.19.0 remains supplied by the selected mise Node tool. `portless`
0.15.6 is a symlink to a local project checkout rather than a registry install;
the project remains its owner and its source update stays out of the routine
dotfiles updater.

No `pipx:` tools are currently declared. The former `pipx:` CLIs
(`keymap-drawer`, `mlx-whisper`, `worldlines`, `xonsh`) were removed as
unwanted, along with their installs, shims, and lock entries. `maturin` uses
the upstream GitHub release backend, while `typ2docx` uses the named isolated
UV exception at `setup-scripts/setup/exceptions/typ2docx`.

| Former uv tool | Version at removal | Replacement owner |
| --- | --- | --- |
| `maturin` | 1.14.1 | `github:PyO3/maturin` with `filter_bins = "maturin"` |
| `typ2docx` | 0.8.0 | Isolated UV exception `setup-scripts/setup/exceptions/typ2docx`; stable launcher at `~/.local/bin/typ2docx` |

`mise` documents these backends for global applications: [npm](https://mise.jdx.dev/dev-tools/backends/npm.html)
and [pipx](https://mise.jdx.dev/dev-tools/backends/pipx.html). The uv tools
should be reinstalled and tested before their old uv environments are removed.

## Cargo-installed development CLIs

Cargo install metadata identified eight additional commands. Six were missing
from the profile and now have explicit owners. Aqua/GitHub release backends
avoid rebuilding crates where verified release assets exist.

| Current Cargo bin and version | Desired owner |
| --- | --- |
| `dist` (`cargo-dist` 0.31.0) | `aqua:axodotdev/cargo-dist` |
| `stylua` 2.4.0 | `aqua:JohnnyMorganz/StyLua` |
| `tokei` 14.0.0 | `cargo:tokei` with the declared Rust toolchain |
| `trunk` 0.21.14 | `github:trunk-rs/trunk` pinned to 0.21.14 |
| `tt` (`tytanic` 0.3.4) | `github:typst-community/tytanic` |
| `typst-package-check` 0.6.0 | Git-backed Cargo tool pinned to `typst/package-check` revision `d1bd0af255d688ce568be3c254efbdb002dc247a` |
| `tinymist` (`tinymist-cli` 0.14.16) | Already declared as `tinymist = "latest"`; Cargo copy is the old duplicate |
| `ttm` (`typst-time-machine` 0.1.2) | Local project build; retain `brew:ezracerpac/tap/typst-time-machine` as the native package owner |

The `trunk` registry shorthand maps to `npm:@trunkio/launcher`, not the Rust
WASM build tool installed from the `trunk` crate, so the explicit GitHub
release owner preserves the intended CLI. Trunk release assets include the
current macOS/Linux target architectures. Tytanic provides macOS arm64 and Linux
musl assets; Linux compatibility should be checked during its install. `typst-package-check`
has no release shorthand, so its Cargo Git source retains the exact installed
commit. A fresh Fish resolution selects the declared mise Tinymist; the old
Cargo binary remains an inert duplicate. The Cargo-installed `ttm` came from
`~/Projects/typst-time-machine` and duplicates the declared Homebrew recipe.

## Cask transfer list

The pre-cutover baseline contained 25 Homebrew cask receipts. At that snapshot,
the profile declared 42 casks: 21 ordinary existing Homebrew casks and 21
unmanaged app bundles marked for native adoption. Copilot CLI was proposed for
a mise tool, but that transfer was later canceled and the CLI and cask were
removed from package configuration and the Mac. For later Mac status, see
[Mac cutover progress](migration.md#mac-cutover-progress). AeroSpace remains the
pinned local PR2245/Hyper build. Brooklyn and MacTeX stay with named Homebrew
installer exceptions because their artifacts are unsupported by mise 2026.9.7.
See [the transfer inspection](cask-transfers.md) before any handoff.

Native package status completed with Ruby 4 available after removing those
three exceptions. It recognized existing installations; this does not transfer
Homebrew cask ownership. Ruby 4 is now a declared mise tool for tap evaluation.

| Baseline cask | Installed version | Target / transfer group |
| --- | --- | --- |
| `aerospace` | Receipt: 0.21.3-Beta; live: 0.21.3-PR2245-Hyper | Local build, excluded from package upgrades |
| `battery` | 1.4.0 | `brew-cask`; low-impact app |
| `brooklyn` | 2.1.0 | Named Homebrew exception: unsupported screensaver artifact |
| `codexbar` | 0.55.1 | `brew-cask`; low-impact app |
| `copilot-cli` | 1.0.41 | Audit-time proposed Aqua transfer; later canceled, then removed from config and the Mac |
| `cotabby` | 0.6.2-beta | `brew-cask`; low-impact app |
| `crisp` | 1.5.0 | `brew-cask`; low-impact app |
| `font-fira-code-nerd-font` | 3.4.0 | `brew-cask`; font |
| `font-hack-nerd-font` | 3.5.1 | `brew-cask`; font |
| `font-sf-pro` | latest | `brew-cask`; licensed font, keep account/license path intact |
| `font-symbols-only-nerd-font` | 3.5.1 | `brew-cask`; font |
| `hammerspoon` | 1.1.1 | `brew-cask`; separate desktop-control acceptance |
| `homerow` | 1.5.3 | `brew-cask`; input/accessibility permissions |
| `jabref` | 5.15 | `brew-cask`; preserve preferences and library links |
| `karabiner-elements` | 16.0.0 | `brew-cask`; separate input-driver acceptance |
| `mactex-no-gui` | 2026.0324 | `brew-cask`; large package, verify artifact and uninstall metadata |
| `mattermost` | 6.3.0 | `brew-cask`; preserve account/app state |
| `middleclick` | 3.2.0 | `brew-cask`; separate input acceptance |
| `ollama-app` | 0.30.6 | `brew-cask`; keep models/data with Ollama |
| `orbstack` | 2.2.1 (20628) | `brew-cask`; separate containers/network acceptance |
| `raycast` | 1.104.22 | `brew-cask`; preserve preferences and permissions |
| `tailscale-app` | 1.98.2 | `brew-cask`; separate connectivity acceptance |
| `warp` | 2026.08.19 | `brew-cask`; preserve terminal state |
| `wezterm` | 20240203-110809 (5046fc22) | `brew-cask`; preserve terminal state |
| `zoom` | 7.0.5.81138 | `brew-cask`; vendor updater and permissions |

Before each transfer, inspect the exact cask's artifacts, uninstall metadata,
auto-update policy, permissions, and data paths. Stop or close only the app in
its scheduled group, uninstall without `--zap`, install with mise, then verify
launch and preferences. `aerospace`, `hammerspoon`, `homerow`, `karabiner-elements`,
`middleclick`, `orbstack`, `raycast`, and `tailscale-app` need live checks before
their current owner is removed. In mise v2026.9.7, `auto_updates` does not by
itself block an explicit cask upgrade. `latest` casks and receipts already at
the target are skipped. Otherwise, mise proceeds only when the receipt matches
the cask's single app artifact, its live version is readable and older than the
cask version, and the app is not running. Failed checks are reported as skips;
a running app is reported as running and self-updating. No `--greedy` flag or
config override is needed
([pinned upgrade source](https://github.com/jdx/mise/blob/v2026.9.7/src/system/packages/brew/cask/mod.rs#L78-L124)).

## Named exceptions and deferred work

| Item | Current owner | Desired owner / rule |
| --- | --- | --- |
| mise 2026.9.2 | Former Homebrew formula; standalone mise is live | Keep the standalone mise installer at the tested 2026.9.7 baseline; update last in `setup:update` |
| chezmoi 2.71.1 | Removed Homebrew package; original setup is in the protected rollback snapshot | Keep the snapshot for rollback until target acceptance |
| Rift 0.5.3 | `acsandmann/tap/rift`, local signed build and LaunchAgent | Existing local source/build/signing task owns it; keep out of ordinary package upgrades and verify active AeroSpace behavior remains unchanged |
| Aegis | Existing local source/build/signing setup | Keep its locally signed app bundle path and signing identity; expose the existing build/install flow as an explicit task |
| CLIProxyAPI | Homebrew formula/service | Package update is separate from configuration and service activation; report service work as deferred |
| `portless` 0.15.6 | Symlink to its project checkout | Project owns source/build/version; no global package update |
| CerpacNAS modern Git | Existing user-space micromamba recipe | Preserve system Git; continue through a mise task after actual NAS compatibility checks |
| `karabiner-elements`, `tailscale-app`, `zoom`, and `font-sf-pro` | Homebrew casks; pkg-only auto-updaters or the `latest` SF Pro version | Keep Homebrew ownership; native updates cannot handle these targets. The explicit Brew updater exceptions run through `setup:update`. |
| Homebrew Python 3.11 and Node 22 | Homebrew formulas | Keep through absolute-path and dependent-workflow audits; no broad cleanup |
| Casks not yet resolved | Existing owner, receipt, or absent app bundle | Transfer only after live ownership checks; Battery, Warp, and Ollama have no app bundle and await user preference |

The NAS profile retains its six existing mise tools—`gh`, `jj`, `node`,
`ripgrep`, `tmux`, and `uv`—and adds `age` and `jq` for encrypted enrollment
and structured maintenance output. It has no native system packages. Its
modern Git recipe remains a separate exception. The NAS architecture, libc,
space, service supervisor, and second-login checks are still required before
applying that profile.

## Validation still required

1. Load each profile under the staged mise 2026.9.7 binary and confirm Mac/Linux
   filtering; verify no workstation installer runs for NAS or DelftBlue.
2. Add and validate tap source URLs in root `[bootstrap.brew.taps]` before the
   package plan is applied.
3. Confirm every cask is supported by the tested mise version and capture its
   uninstall/auto-update details before scheduling transfers.
4. Run command and dependent-workflow checks before removing duplicate kegs,
   Python 3.11, Node 22, or the old package manager.
5. Run fresh Linux apt/dnf/pacman bootstrap tests; package names and architectures
   are declarations, not evidence that those distros have passed.

## Integration corrections

- Homebrew receipts mark 99 formulae as installed on request. The earlier 79
  count did not cover every requested receipt; the table covers all 99.
- Herdr uses the native mise registry backend, pinned to 0.8.2. The 0.9.0
  client cannot attach to the preserved 0.8.2 server. Upgrade this pin only
  when existing terminal sessions can be restarted deliberately.
- The audit found five Pi plugin packages without CLI binaries and proposed an
  explicit Pi package-store updater. Pi was later removed from config and the
  Mac, and that updater is no longer part of the current setup.
- Apple's Git remains OS-owned on the Mac; Linux workstation Git is installed
  through its native package manager. NAS keeps its user-space Git recipe.
