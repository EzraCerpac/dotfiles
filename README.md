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

`brew` on macOS and `apt-get` on Linux install the general-purpose CLI tools and system dependencies used day to day.

`mise` is reserved for versioned runtimes and a small set of tools where pinning matters (`~/.config/mise/config.toml`). Today that mainly means Neovim nightly, Rust, UV, and Julia.

Review defaults:

- `git diff` opens in `diffnav --side-by-side`
- `git show` and embedded diff views use `delta --side-by-side --paging=never`
- `wt` is installed via Homebrew and initialized in fish
- `jw` is built from the local `~/Projects/jj-waltz` checkout and shell-initialized in fish and zsh
- `jj-waltz` skill content is sourced from `~/Projects/jj-waltz/skills/jj-waltz` and auto-synced on `chezmoi apply` to both `~/.codex/skills/jj-waltz` and `~/.config/opencode/skills/jj-waltz`
- `wto <branch> [prompt...]` creates or switches a worktree and launches `opencode`
- `prdiff [pr]` opens `gh pr diff` output in `diffnav`

## Repository Structure

```
dot_config/                          → ~/.config/
  fish/config.fish.tmpl              → fish shell (cross-platform template)
  mise/config.toml                   → versioned runtimes and pinned tools
  nvim/                              → neovim config
  git/, jj/, starship.toml, ...     → other tool configs
run_once_01-setup-directories.sh.tmpl   → create ~/Projects, ~/.local/bin, etc.
run_once_02-install-package-managers.sh.tmpl → brew (macOS) + mise
run_once_03-install-tools.sh.tmpl       → install general CLI tools via brew/apt, then versioned tools via mise
run_once_04-setup-macos.sh.tmpl         → brew casks (wezterm, raycast, alt-tab, hammerspoon)
run_once_05-setup-keyboard.sh.tmpl      → keyboard firmware bootstrap (fails loudly until kbd-setup exists)
run_after_setup-shell.sh.tmpl           → fish shell setup, /etc/shells, default shell
run_after_10-enable-touchid-for-sudo.sh.tmpl → macOS Touch ID for sudo via /etc/pam.d/sudo_local
run_after_15-setup-karabiner-virtualhid.sh.tmpl → macOS Karabiner VirtualHID activation + daemon
run_after_20-setup-kanata-launchd.sh.tmpl → macOS kanata launch daemon via /Library/LaunchDaemons
```

## Keyboard Workflow (Corne + QMK)

Keyboard source lives at `~/.config/keyboard/corne-qmk` and syncs into a local `qmk_firmware` checkout at `~/Projects/keyboards/qmk_firmware`.

Commands:

- `kbd-setup` → install keyboard build dependencies and clone/update `qmk_firmware`
- `kbd-sync` → copy keymap source into `qmk_firmware`, regenerate layout images, and reload HUD
- `kbd-build` → build `crkbd/rev1:ezra_corne` (`rp2040_ce` by default)
- `kbd-build-all` → build both `rp2040_ce` and `sparkfun_pm2040`
- `kbd-build-left` / `kbd-build-right` → build convenience left/right-tagged UF2 artifacts
- `kbd-flash-left` / `kbd-flash-right` → authoritative split-handedness flash flow (`uf2-split-left/right`)
- `kbd-layout-images` → regenerate JSON/YAML/SVG/PNG layer images from `keymap.c`
- `kbd-hud-reload` → reload Hammerspoon HUD overlay
- `kbd-open-artifacts` → open UF2 artifact folder in Finder

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

- `mise run kbd_setup`
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
- `dbdev-bootstrap` also installs `jj` and `jjui` from their Linux release binaries on the login node
- `dbdev-install` is now just a compatibility check; the default dev layer is module-first and does not need a compute-node install step
- if you explicitly want Spack as an extra layer, use `dbdev-bootstrap --with-spack`
- load it only when needed with `dbdev`
- use a visual node only for GPU/CUDA-related setup that needs internet plus a visible GPU
- module availability varies by partition, so `dbdev` only loads tools that actually exist in the current environment
- optional editor-side tools that are not available in the current Spack set are skipped, and the DelftBlue Neovim overlay disables those integrations automatically

If this repo is also applied on your macOS machine, WezTerm and SSH can be set up so DelftBlue feels like a first-class remote terminal:

- `~/.ssh/config` renders a `Host delftblue` entry with key-based auth settings for `~/.ssh/id_ed25519`
- WezTerm exposes `SSH:delftblue` as a remote domain and a launcher entry
- opening DelftBlue from that WezTerm remote domain makes normal tab/split keys stay on DelftBlue
- remote bash emits OSC 7 cwd updates so new remote tabs/splits can inherit the current directory
- DelftBlue docs recommend `ssh-copy-id delftblue` for passwordless login on a trusted machine; if you log in with SSH keys and later need `/tudelft.net`, run `kinit` on the login node
