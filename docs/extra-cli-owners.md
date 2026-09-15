# Extra installed CLI ownership

This note closes the installed-command inventory beyond Homebrew, npm, and uv.
The audit inspected entry names, symlink destinations, file types, shebangs,
registry metadata, and limited project README/package metadata for two local
executables. It did not read credentials or print environment values, and made
no system changes.

## Native mise owners added

These installed developer CLIs now have explicit Aqua owners in
`config.workstation.toml`. All three are limited to the workstation matrix:
macOS arm64, Linux x64, and Linux arm64. Their Aqua registry definitions are
linked below for review.

| Installed command | Current location | Mise owner |
| --- | --- | --- |
| `claude` | `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.233` | `aqua:anthropics/claude-code`; registry supports Darwin and Linux. [Registry definition](https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/anthropics/claude-code/registry.yaml) |
| `grok`, `agent` | `~/.local/bin/grok` and `~/.local/bin/agent` → Grok's bundled release under `~/.grok` | `aqua:x.ai/cli/grok`; the package definition exports both names and maps macOS/architecture asset names. [Registry definition](https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/x.ai/cli/grok/registry.yaml) |
| `agy` | `~/.local/bin/agy` (standalone macOS arm64 executable) | `aqua:google-antigravity/antigravity-cli`; release assets use OS/architecture names. [Registry definition](https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/google-antigravity/antigravity-cli/registry.yaml) |

The Grok registry package declares both executables, so one mise tool entry
owns both `grok` and `agent`. The existing vendor directory may still contain
application state; package ownership transfer should preserve it.

## Already accounted for

- `herdr` has a native mise owner in `config.workstation.toml`.
- `agenda`, `antinote`, and `remctl` are source-mapped wrappers in
  `dotfiles/.local/bin`; their dedicated source-installer tasks are underway.
  Keep those as explicit local-tool owners rather than adding duplicate
  package entries.
- `portless` is a symlink into its project checkout and remains project-owned.
- `jw`, `rift`, and `rift-cli` point into the jj-waltz build or the local Rift
  installation. Their build/signing lifecycle remains task-owned.
- `maturin` maps to the `github:PyO3/maturin` tool declared in
  `config.workstation.toml`, and `typ2docx` maps to the named isolated UV
  exception. The former `pipx:` CLIs (`keymap`, `mlx-whisper`, `worldlines`,
  `xonsh`, including the `osmgemma` entry points from the old `mlx-vlm`
  environment) and `neonrp` are no longer declared; they were removed as
  unwanted.
- `humanize-text` and `humanize-clipboard` point to the source-mapped local
  `humanize-text` script. The `ai-text-detector` source wrapper has the
  shebang `uv run --python 3.12 --script`; `config.workstation.toml` now declares
  Python 3.12 after 3.13, keeping 3.13 as the default and exposing the needed
  versioned interpreter.

## Do not promote helper names into package declarations

The remaining names are mostly personal wrappers, setup commands,
window-manager helpers, DelftBlue/SSH helpers, or application launchers. Where
the migration has a matching dotfile or template mapping, that mapping owns the
command; otherwise keep it as a local helper instead of adding a package
entry. `~/bin/game` is a CrossOver shortcut, and `~/.opencode/bin` is absent.

`tunnel-client` is a standalone local Mach-O executable with no source mapping
in this dotfiles tree. Proofloom's project documentation uses `tunnel-client`
v0.0.11 for supervised Secure MCP Tunnel development. Keep it as a
Proofloom-scoped vendor exception; no source or build task was found by this
read-only audit.

`vibez` is also a standalone local Mach-O executable, but its source is present
at `~/Projects/Archive/vibez` as a Go terminal Apple Music player. Treat it as
an archived-project application/build exception, not a general developer CLI
to add to the workstation tool set.

The inventory found no reason to source ephemeral helper scripts into the
migration. Existing `*.lock` sidecars and Python environment links are not
separate CLI tools.
