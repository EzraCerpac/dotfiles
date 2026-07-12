# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). Supports Apple Silicon macOS and Linux. Intel macOS is intentionally unsupported.

## Quick Start

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac
```

This installs chezmoi, clones the repo, bootstraps package managers, installs core tools with `brew` or `apt`, installs versioned runtimes with `mise`, and applies all configs.

## What's Included

**Shell**: fish, starship prompt, atuin history, zoxide, fzf, carapace completions

**Editor**: neovim (LazyVim)

**Dev Tools**: git, gh, jj/jjui, lazygit, gitui, worktrunk, diffnav, node, rust, uv, delta, ripgrep, fd, bat, eza, jq, yazi, tmux, gum

**macOS**: aerospace (WM), alt-tab, sketchybar, karabiner, raycast, wezterm, ghostty

## Tool Management

General-purpose CLI tools, system dependencies, Homebrew taps, and casks are listed in `.chezmoidata/packages.yaml`.
`chezmoi apply` reconciles them through one generated `run_after_03-reconcile-tools.sh` module. It keeps per-adapter fingerprints under `~/.local/state/chezmoi/tool-reconcile`, checks for missing tools, and invokes only affected ecosystem installers. It never removes undeclared tools.

`mise` is reserved for versioned runtimes and a small set of tools where pinning matters (`~/.config/mise/config.toml`). Today that mainly means Neovim nightly, Rust, UV, and Julia.

For one-off Homebrew installs, use the pending-list helpers:

- `bi ripgrep` installs a formula and records it in `~/.local/state/chezmoi/brew-pending/Brewfile`
- `bic wezterm` installs a cask and records it in the same pending file
- `brew-pending` reviews pending entries
- `brew-promote` moves pending entries into `.chezmoidata/packages.yaml`
- `brew-adopt` interactively reviews Homebrew formulae and casks installed outside those helpers

Review defaults:

- `git diff` opens in `diffnav --side-by-side`
- `git show` and embedded diff views use `delta --side-by-side --paging=never`
- `wt` is installed via Homebrew and initialized in fish
- `jw` is built from the local `~/Projects/jj-waltz` checkout and shell-initialized in fish and zsh
- `jj-waltz` skill content is sourced from `~/Projects/jj-waltz/skills/jj-waltz` and auto-synced on `chezmoi apply` to both `~/.codex/skills/jj-waltz` and `~/.config/opencode/skills/jj-waltz`
- `wto <branch> [prompt...]` creates or switches a worktree and launches `opencode`
- `prdiff [pr]` opens `gh pr diff` output in `diffnav`
- `glf [git-log-args...]` selects a commit and replays it in `gitlogue`
- `gitlogue-menu` selects a Gitlogue mode, author, date range, commit, or theme

## Repository Structure

```
dot_config/                          → ~/.config/
  fish/config.fish.tmpl              → fish shell (cross-platform template)
  mise/config.toml.tmpl              → profile-aware versioned runtimes and pinned tools
  nvim/                              → neovim config
  git/, jj/, starship.toml, ...     → other tool configs
run_once_01-setup-directories.sh.tmpl   → create ~/Projects, ~/.local/bin, etc.
run_once_02-install-package-managers.sh.tmpl → brew (macOS) + mise
run_after_03-reconcile-tools.sh.tmpl    → reconcile packages, mise tools, and standalone tools
run_once_04-setup-macos.sh.tmpl         → macOS defaults
run_onchange_06-build-jj-waltz.sh.tmpl  → rebuild local `jw` when the `jj-waltz` Rust source changes
run_once_07-remove-legacy-kbd-commands.sh.tmpl → remove old `kbd-*` helper commands
run_after_setup-shell.sh.tmpl           → fish shell setup, /etc/shells, default shell
run_after_10-enable-touchid-for-sudo.sh.tmpl → macOS Touch ID for sudo via /etc/pam.d/sudo_local
```

`chezmoi apply` rebuilds the local `jw` binary through a `run_onchange` script whose rendered fingerprint is computed from the external `~/Projects/jj-waltz` Rust build inputs. This lets chezmoi notice local source changes even though that checkout is not managed by this dotfiles repo.

## Keyboard Workflow (Corne + QMK)

Keyboard source lives at `~/.config/keyboard/corne-qmk` and syncs into a local `qmk_firmware` checkout at `~/Projects/keyboards/qmk_firmware`.

Commands:

- `kbd provision` → validate prerequisites managed by `chezmoi apply`, prepare QMK, activate VirtualHID, and install the Kanata daemon
- `kbd doctor` → diagnose macOS Kanata/Karabiner runtime, TCC grants, and duplicate VirtualHID daemons
- `kbd sync` → copy keymap source into `qmk_firmware`, regenerate layout images, and reload HUD
- `kbd build` → build `crkbd/rev1:ezra_corne` (`rp2040_ce` by default)
- `kbd build-all` → build both `rp2040_ce` and `sparkfun_pm2040`
- `kbd build --left` / `kbd build --right` → build convenience left/right-tagged UF2 artifacts
- `kbd flash left` / `kbd flash right` → authoritative split-handedness flash flow (`uf2-split-left/right`)
- `kbd layout-images` → regenerate JSON/YAML/SVG/PNG layer images from `keymap.c`
- `kbd hud-reload` → reload Hammerspoon HUD overlay
- `kbd open-artifacts` → open UF2 artifact folder in Finder

`kbd provision` is the sole keyboard lifecycle command. Run it explicitly after `chezmoi apply`; it may request `sudo`. If macOS needs DriverKit, Input Monitoring, or Accessibility approval, the command stops with the exact System Settings action. Complete that action, then rerun the same command; finished stages are safe to repeat.

`mise run` keyboard tasks are defined in the source repo's repo-local [`mise.toml`](mise.toml), and `.chezmoiignore` keeps that file from being deployed to `~/mise.toml`. Run them from this chezmoi checkout, not from arbitrary directories.

`~/Projects` is auto-trusted via `~/.config/mise/config.toml`, so project repos under that tree do not need manual `mise trust`.

This chezmoi checkout is intentionally not auto-trusted. If needed, trust it explicitly before running repo-local keyboard tasks:

```bash
cd ~/.local/share/chezmoi
mise trust
mise run kbd_flash_left
```

If you still have a legacy home-level `mise` task file from the old setup, remove it once:

```bash
rm -f ~/mise.toml ~/.mise.toml
```

After cleanup, the keyboard tasks should only appear when your current directory is this chezmoi checkout.

Available repo-local tasks:

- `mise run kbd_provision`
- `mise run kbd_sync`
- `mise run kbd_build`
- `mise run kbd_build_all`
- `mise run kbd_build_left`
- `mise run kbd_build_right`
- `mise run kbd_flash_left`
- `mise run kbd_flash_right`
- `mise run kbd_hud`
- `mise run kbd_images`

## Adding/Editing Configs

```bash
chezmoi edit ~/.config/fish/config.fish   # edit source file
chezmoi apply                              # apply changes
chezmoi-smart-apply                        # re-add trusted app-written drift, then apply
chezmoi add ~/.config/new-app/config.yaml  # track a new file
chezmoi update                             # pull + apply from remote
```

`chezmoi-smart-apply` is the safe path for tracked app configs that mutate themselves in `$HOME`.
It auto-readds only explicitly allowlisted plain files from `~/.config/chezmoi/smart-apply.toml`
and stops for manual `chezmoi merge` if any other destination drift is present.

## Cross-Platform Notes

- Intel macOS is not supported; Homebrew paths and bootstrap scripts assume Apple Silicon macOS when `chezmoi.os == "darwin"`
- macOS-only configs (aerospace, alt-tab, sketchybar, karabiner, raycast, wezterm) are ignored on Linux via `.chezmoiignore`
- Fish config uses chezmoi templates to conditionally include Homebrew paths, OrbStack, Tailscale alias, etc.
- On Linux, system packages install via `apt-get`; on macOS, via `brew`
- `mise` is used only for version-sensitive runtimes and pinned tools, not as the universal installer

## CerpacNAS Remote Codex

The `nas` chezmoi profile keeps CerpacNAS headless and small. It installs a minimal user-space toolset, shared Codex rules, the `work-on-cerpacnas` skill, a project manifest, and the `nas` command. It also installs modern Git in a small micromamba prefix because Debian 10's Git is too old for current JJ credential operations. Existing `nas`/`cerpacnas` SSH aliases continue to use root; agent commands stay sandboxed below `/root/Projects` and never use `sudo`, Docker, or dangerous sandbox/approval bypass flags. Codex receives `--skip-git-repo-check` only because secondary JJ workspaces intentionally have no `.git` directory.

Use GitHub/JJ for code, chezmoi `dev` for configuration, and allowlisted rsync only for artifacts:

```bash
nas doctor
nas projects status thesis
nas projects sync thesis
nas handoff thesis my-task --to nas --push
nas agent start thesis my-task --mode explore -- "Inspect the requested seam"
nas agent status
nas validate thesis my-task web-type
nas validate thesis my-task focus:selector --calibrate
nas handoff thesis my-task --to mac --push
nas artifact plan thesis data
nas artifact push thesis data --apply
```

`nas projects sync --all` reconciles only projects declared in `~/.config/cerpacnas/projects.toml`. It clones or fetches; it never merges, rebases, pushes, deletes, or mirrors live project directories. Artifact commands exclude repository metadata, dependencies, caches, and credentials and never use `rsync --delete`.

The NAS profile auto-selects on the CerpacNAS hostname. It follows the dotfiles `dev` branch and leaves `main` untouched. Its static x86_64-musl `jw` installer runs only when the exact release archive checksum is pinned in chezmoi data; until v0.3.1 is published, it skips safely.

## DelftBlue Profile

This repo now supports a conservative `delftblue` profile for TU Delft's cluster.
It is intentionally smaller than the normal Linux workstation setup:

- package-manager bootstrap is skipped
- workstation-heavy config is excluded
- bash stays the default shell
- module-based Julia/MPI helpers are added
- Slurm starter templates live in `~/.config/delftblue/jobs/`
- local SSH and `rsync` helpers are installed via `~/.ssh/config` and `~/.local/bin/db*`

Set it in your chezmoi config on DelftBlue:

```toml
[data]
profile = "delftblue"

[data.delftblue]
netid = "ecerpac"
slurm_account = "education-eemcs-msc-cosse"
project_storage_root = "/path/to/project/storage" # optional
```

Important helpers:

- `dbdev-bootstrap`
- `dbdev-install`
- `dbspack`
- `dbdev [command ...]`
- `dbacct`, `dblimits`, `dbjobs`
- `dbcpu [time] [cpus] [mem-per-cpu]`
- `dbgpusmoke [time] [mem-per-cpu]`
- `dbjulia-mpi-init <project-dir>`
- `dbpush`, `dbpull`
- `dbprojectpush`, `dbprojectpull` when `project_storage_root` is set

Important shell functions on DelftBlue:

- `dbmod-julia`
- `dbmod-julia-mpi`

The DelftBlue profile can now also render a cluster-aware Neovim setup and a broader dev shell.
That layer is still explicit and conservative:

- bootstrap the default dev layer with `dbdev-bootstrap`
- run `dbdev-bootstrap` on the login node, because compute nodes do not have outbound internet
- `dbdev-bootstrap` also installs `jj`, `jjui`, `nvim`, `bat`, `zoxide`, and `tv` from pinned release binaries on the login node
- `dbdev-bootstrap` also installs `eza`, `rg`, `fd`, `atuin`, and `carapace` from pinned release binaries on the login node
- `dbdev-install` is now just a compatibility check; the default dev layer is module-first and does not need a compute-node install step
- the DelftBlue Neovim overlay disables Mason-driven installs and Sidekick runtime hooks, so cluster startup stays quiet and does not keep retrying unavailable tools
- `tree-sitter` CLI is optional on DelftBlue and only used when the module system provides it
- if you explicitly want Spack as an extra layer, use `dbdev-bootstrap --with-spack`
- load it only when needed with `dbdev`
- the default DelftBlue bash shell also restores lightweight niceties like `..`, `...`, `v`, `ls -> eza`, and guarded `atuin` / `zoxide` / `tv` init
- a DelftBlue-only `~/.bash_profile` is rendered to source `~/.bashrc`, so those bash customizations appear in fresh login shells
- `Ctrl-R` is assigned to Atuin, `Ctrl-T` to Television shell integration, and `Ctrl-E` to bash's `edit-and-execute-command`
- Television bash integration is generated once into `~/.config/television/shell/integration.bash` and sourced from `~/.bashrc`; `bash-preexec` is installed under `~/.local/share/bash-preexec/` and sourced before `atuin init bash --disable-up-arrow --disable-ctrl-r` so new commands are recorded correctly
- on DelftBlue, Atuin keeps all local SQLite state under `/tmp/$USER/atuin/` instead of the default home-directory path: `history.db`, `records.db`, `meta.db`, `kv.db`, and `scripts.db`
- keys and session remain on persistent home storage
- on DelftBlue, Atuin also uses normal `fuzzy` search and `sync_frequency = "0"` so each command syncs immediately from node-local storage
- on DelftBlue, bash runs a quick integrity check on the local Atuin DB at shell startup and automatically rotates it out if it is not a valid SQLite database
- use `dbatuin-reset` in a DelftBlue bash shell to rotate out malformed local Atuin DBs and repopulate from sync
- use `dbshell-check` in a DelftBlue bash shell to inspect loaded functions and active key bindings
- bash also loads `carapace` as an extra completion bridge when available
- use a visual node only for GPU/CUDA-related setup that needs internet plus a visible GPU
- module availability varies by partition, so `dbdev` only loads tools that actually exist in the current environment
- optional editor-side tools that are not available in the current Spack set are skipped, and the DelftBlue Neovim overlay disables those integrations automatically
- `AGENTS.md` stays in the repo only and is not deployed into `$HOME`

## Herdr terminal workflow

WezTerm is the terminal window; Herdr owns terminal organization and persistence:

- a **session** is one persistent Herdr server containing all local work
- a **workspace** is one project row in Herdr's left sidebar
- a **tab** is one activity inside a workspace
- a **pane** is a visible terminal split inside a tab
- an AeroSpace workspace is a separate macOS desktop and is unrelated to a Herdr workspace

Closing WezTerm or pressing `Ctrl-B`, then `Q`, detaches the client without stopping pane processes. Opening WezTerm again reattaches to the local default session. Herdr does not pin workspace rows; an open `Remote shells` workspace stays in the sidebar because the session persists.

Useful keys all start with the default `Ctrl-B` prefix:

- `up` / `down`: Herdr Plus Projects / Quick Actions
- `t`: Picker Plus search across agents, remotes, workspaces, projects, sessions, and actions
- `left` / `right`: previous / next workspace
- `Shift-1..9`: switch workspace; `1..9`: switch tab
- `h/j/k/l`: focus panes; `w`: workspace picker; `?`: full key help

Herdr Plus manages the reproducible project layouts under `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`. Use the `Remote shells` project for a local shell and a normal `ssh delftblue` tab. SSH keepalives reduce idle disconnects. DelftBlue still needs `kinit` on the login node when `/tudelft.net` credentials expire.

Picker Plus exposes `CerpacNAS` as a remote Herdr target. Selecting it runs Herdr's remote attach flow, bootstraps a matching remote binary when needed, and opens the NAS server's own persistent sidebar. The NAS session is separate from the local sidebar; detach it with `Ctrl-B`, then `Q`.
