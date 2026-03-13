# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). Works on macOS and Linux.

## Quick Start

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac
```

This installs chezmoi, clones the repo, bootstraps package managers, installs tools via mise, and applies all configs.

## What's Included

**Shell**: fish, starship prompt, atuin history, zoxide, fzf, carapace completions

**Editor**: neovim (LazyVim), zed

**Dev Tools**: git, gh, jj/jjui, lazygit, gitui, worktrunk, diffnav, node, rust, uv, delta, ripgrep, fd, bat, eza, jq, yazi, tmux, gum

**macOS**: aerospace (WM), alt-tab, sketchybar, karabiner, raycast, wezterm, ghostty

## Tool Management

**mise** is the single source of truth for all tools (`~/.config/mise/config.toml`). It handles runtimes (node, rust), CLI tools (fzf, ripgrep, bat, etc.), and even manages itself (chezmoi, uv). mise supports multiple backends (aqua, cargo, github, ubi) so nearly everything installs through it.

**brew/apt-get** only install system-level packages that mise can't: `fish`, `gnupg`, `curl`, `wget`, `htop`, `tree`, `sshpass` (and `build-essential`, `git`, `unzip` on Linux).

Review defaults:

- `git diff` opens in `diffnav --side-by-side`
- `git show` and embedded diff views use `delta --side-by-side --paging=never`
- `wt` is installed via mise and initialized in both fish and zsh
- `wto <branch> [prompt...]` creates or switches a worktree and launches `opencode`
- `prdiff [pr]` opens `gh pr diff` output in `diffnav`

## Repository Structure

```
dot_config/                          → ~/.config/
  fish/config.fish.tmpl              → fish shell (cross-platform template)
  mise/config.toml                   → mise tool manifest
  nvim/                              → neovim config
  git/, jj/, starship.toml, ...     → other tool configs
run_once_01-setup-directories.sh.tmpl   → create ~/Projects, ~/.local/bin, etc.
run_once_02-install-package-managers.sh.tmpl → brew (macOS) + mise
run_once_03-install-tools.sh.tmpl       → system packages + mise install
run_once_04-setup-macos.sh.tmpl         → brew casks (wezterm, raycast, alt-tab, hammerspoon)
run_once_05-setup-keyboard.sh.tmpl      → keyboard firmware bootstrap (qmk_firmware)
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

`mise run` tasks are available via `~/.mise.toml`:

- `mise run kbd_setup`
- `mise run kbd_sync`
- `mise run kbd_build`
- `mise run kbd_build_all`
- `mise run kbd_build_left`
- `mise run kbd_build_right`
- `mise run kbd_flash_left`
- `mise run kbd_flash_right`

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

- macOS-only configs (aerospace, alt-tab, sketchybar, karabiner, raycast, wezterm) are ignored on Linux via `.chezmoiignore`
- Fish config uses chezmoi templates to conditionally include Homebrew paths, OrbStack, Tailscale alias, etc.
- On Linux, system packages install via `apt-get`; on macOS, via `brew`
- All other tools install identically via mise on both platforms
