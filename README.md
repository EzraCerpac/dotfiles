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

**Dev Tools**: git, gh, jj/jjui, lazygit, gitui, node, rust, uv, delta, ripgrep, fd, bat, eza, jq, yazi, tmux, gum

**macOS**: aerospace (WM), sketchybar, karabiner, raycast, wezterm, ghostty

## Tool Management

**mise** is the single source of truth for all tools (`~/.config/mise/config.toml`). It handles runtimes (node, rust), CLI tools (fzf, ripgrep, bat, etc.), and even manages itself (chezmoi, uv). mise supports multiple backends (aqua, cargo, github, ubi) so nearly everything installs through it.

**brew/apt-get** only install system-level packages that mise can't: `fish`, `gnupg`, `curl`, `wget`, `htop`, `tree` (and `build-essential`, `git`, `unzip` on Linux).

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
run_once_04-setup-macos.sh.tmpl         → brew casks (wezterm, raycast)
run_after_setup-shell.sh.tmpl           → fish shell setup, chsh hint
```

## Adding/Editing Configs

```bash
chezmoi edit ~/.config/fish/config.fish   # edit source file
chezmoi apply                              # apply changes
chezmoi add ~/.config/new-app/config.yaml  # track a new file
chezmoi update                             # pull + apply from remote
```

## Cross-Platform Notes

- macOS-only configs (aerospace, sketchybar, karabiner, raycast, wezterm) are ignored on Linux via `.chezmoiignore`
- Fish config uses chezmoi templates to conditionally include Homebrew paths, OrbStack, Tailscale alias, etc.
- On Linux, system packages install via `apt-get`; on macOS, via `brew`
- All other tools install identically via mise on both platforms
