# Runtime compatibility audit

Audit against `~/.local/state/mise-migration/20260914-173012` and the live workstation. No build, installer, or package update was run for the audit.

Later removals supersede the proposed ownership actions below: the Pi CLI,
`remindctl`, `copilot-cli`, and the global npm Codex CLI were removed from the
Mac and package configuration. The native base-profile `codex` tool remains.
Treat the audit paths, versions, and recommendations below as historical.

## Historical Pi package cutover audit

The audit recorded these five references in Pi user settings, rather than as
mise `npm:` tools:

- `npm:@ollama/pi-web-search`
- `npm:caveman-pi`
- `npm:pi-constell-plan`
- `npm:pi-markdown-preview`
- `npm:pi-mono-btw`

At audit time all five were installed in the global npm root and had no `bin`
entry. Pi 0.80.3 listed them in `~/.pi/agent/settings.json`; its legacy package
lookup used `/opt/homebrew/lib/node_modules`. A Node owner change could change
that root, while mise installs npm tools in isolated package roots.

The audit proposed using Pi 0.80.3's stable user install under
`~/.pi/agent/npm/node_modules` and a dedicated plugin setup task. That updater
and its seed configuration are no longer part of the current setup. This
historical proposal does not describe a current Pi installation or update path.

The audit also recorded `pi` (`@earendil-works/pi-coding-agent`), `codex`,
`codex-acp`, and `agent-browser` as global npm CLIs. Pi and npm Codex were later
removed from the Mac and package configuration. The native `codex` tool is
retained; `codex-acp` and `agent-browser` remain separately managed. `portless`
is a project-owned symlink. `npm` comes with Node.

## Runtime command owners

The shell files define no aliases for these command names; they resolve through mise shims and then their active backend. Fish's `pluto` and `lss` aliases call `julia` by name.

| Command | Resolution recorded during audit | Workstation declaration and compatibility at audit time |
| --- | --- | --- |
| `node` / `npm` | Mise shim fell through to Homebrew Node 26.7.0 at `/opt/homebrew/Cellar/node/26.7.0/bin/node`; `npm root -g` was `/opt/homebrew/lib/node_modules`. | `node = "latest"` can own the runtime. The Pi plugin-path concern above was part of the historical audit. No retained dotfile pins the Node 22 keg path. |
| `go` | Mise Go 1.27.0 at `~/.local/share/mise/installs/go/1.27.0/bin/go`. | Existing mise resolution already matches the target. |
| `rustc` / `cargo` | Rustup shims at `~/.cargo/bin/rustup`, using `RUSTUP_TOOLCHAIN=1.98.0`. The command reports Rust 1.98.0. | `rust = "latest"` is not proof of direct mise ownership while the Rustup override remains. Keep the Rustup environment and Homebrew fallback in view during later cleanup. Dotfiles source `~/.cargo/env` or add `~/.cargo/bin`; they do not pin a toolchain path. |
| `julia` | Mise Julia 1.12.6 at `~/.local/share/mise/installs/julia/1.12.6/bin/julia`. | The workstation profile keeps the exact 1.12.6 request and upstream release URLs. Julia aliases remain command-name based. |
| `uv` / `uvx` | Mise Aqua uv 0.12.5 at `~/.local/share/mise/installs/uv/latest/uv-aarch64-apple-darwin/`. | Existing mise resolution already matches the target. The remctl wrapper also invokes mise explicitly. |
| `rg` | Homebrew ripgrep 15.2.0 at `/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg`; mise 15.1.0 is installed but inactive. | `ripgrep = "latest"` is suitable for native mise ownership; no retained dotfile hard-codes the Homebrew executable. |
| `codex` | Homebrew's npm CLI 0.153.4 at `/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js`. ChatGPT.app also has its own app-owned executable. | The npm CLI was later removed; the native base-profile `codex` tool is retained, separately from ChatGPT.app. |

The audit snapshot had seven global uv tools: `keymap-drawer`, `maturin`, `mlx-audio`, `mlx-vlm`, `mlx-whisper`, `typ2docx`, and `worldlines`. The `pipx:` declarations (`keymap-drawer`, `mlx-whisper`, `worldlines`, plus `xonsh`, which moved from Homebrew 0.24.2 to mise pipx and was not part of the seven-tool UV snapshot) have since been removed as unwanted, together with their installs, shims, and lock entries. `maturin` now uses the PyO3 GitHub release backend with `filter_bins = "maturin"`; its binary was checked for macOS arm64, Linux x64, and Linux arm64. `typ2docx` is removed from `[tools]` because the locked pipx install cannot build its source distribution. The named [typ2docx exception](../setup-scripts/setup/exceptions/typ2docx) builds a version-pinned release with Mise Python 3.13, Rust, and Cargo in per-run UV and Cargo directories, then switches `~/.local/bin/typ2docx` only after `--help` passes. It backs up a recognized prior UV symlink, leaves the default UV and Cargo directories alone, skips a verified prior install during `--install-only`, and skips unchanged releases during routine updates. No `pipx:` tools remain declared.

The Fedora arm64 source-build and launcher-swap probe verified `typ2docx --help`, its isolated install, a backup for the existing UV launcher, and unchanged default UV/Cargo directories. With the run-root lookup fixed, the current script also passed Fedora checks for repeated `--install-only` no-ops and a same-version update against a 0.8.0 marker derived from the installed distribution metadata: it passed `--help` and left the launcher and run list unchanged. Disposable mocks covered invalid arguments and changed-version install/backup behavior. The current version-pinned source-build path was not rerun through another full compile.

## Python and local executables

`~/.local/bin/remctl` calls `mise -C "$HOME/.config/mise" exec python@3.13 -- python3 ~/.local/libexec/remctl/remctl`. That selects mise Python 3.13.12 today, and `python = "3.13"` in the workstation profile preserves the selector. There is no hard-coded Homebrew Python path in the wrapper.

RemCTL's Python code has no PyObjC dependency. The `AppKit` and `Foundation` imports in its source are inside Swift text passed to `swift`; they are native frameworks, not Python modules. RemCTL's source docs say Python 3.10+ and zero Python dependencies. [The explicit install task](../setup-scripts/local/remctl-install.sh) uses the checked-out `~/Projects/Tools/remctl/install.sh`, stages its output and config outside the live target, disables shell setup, checks the CLI under mise Python 3.13, verifies the Swift helper identities, then swaps only `~/.local/libexec/remctl`. It requires Xcode Command Line Tools for the Swift and Objective-C helpers. The task does not run Reminders onboarding or touch the managed `~/.local/bin/remctl` wrapper.

`~/.local/bin/agenda` points to `~/.local/libexec/agenda/agenda`, currently an arm64 Mach-O with ad-hoc signature identifier `com.arraypress.agenda`. [The explicit build/install task](../setup-scripts/local/agenda-build-install.sh) snapshots the checked-out `~/Projects/Tools/swift-agenda` package sources into task-owned staging, builds with the locked `Package.resolved` and `--skip-update`, copies any Swift resource bundles, preserves the embedded permission `Info.plist`, and verifies the version, architecture, bundle identity and ad-hoc signature before swapping only `~/.local/libexec/agenda`. It does not call `Scripts/build-release.sh` in the source checkout because that script clears `dist/`. The task does not touch the managed `~/.local/bin/agenda` wrapper. By comparison, Antinote already has a source-backed `local:antinote-bridge-build` task.

## Historical cutover items

- The audit proposed moving the five Pi plugins out of mise npm declarations and wiring `setup-scripts/setup/exceptions/pi-plugins` after encrypted user settings were present. That updater and its seed configuration are no longer part of the current setup.
- Register the RemCTL and agenda tasks in the local task configuration. They are explicit tasks; neither runs during ordinary setup. Both task files passed `bash -n` and ShellCheck. Neither build was executed, and the existing binaries remain untouched.
- Keep Python 3.13 in the mise parent config used by the remctl wrapper. No PyObjC install is required based on the inspected source.
