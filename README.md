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

**Dev Tools**: git, gh, jj/jjui, node, uv, delta, ripgrep, fd, bat, eza, jq, yazi, tmux, gum

**macOS**: aerospace (WM), sketchybar, karabiner, raycast, wezterm, ghostty

## Package Manager Priority

Tools are installed using this priority chain:

1. **mise** — single source of truth for tool versions (`~/.config/mise/config.toml`)
2. **cargo** — Rust toolchain
3. **brew** — system packages and macOS casks
4. **uv** — Python toolchain
5. **apt-get** — Linux system packages

## Repository Structure

```
dot_config/                          → ~/.config/
  fish/config.fish.tmpl              → fish shell (cross-platform template)
  mise/config.toml                   → mise tool manifest
  nvim/                              → neovim config
  git/, jj/, starship.toml, ...     → other tool configs
run_once_01-setup-directories.sh.tmpl   → create ~/Projects, ~/.local/bin, etc.
run_once_02-install-package-managers.sh.tmpl → brew, mise, cargo, uv
run_once_03-install-tools.sh.tmpl       → system packages + mise install
run_once_04-setup-macos.sh.tmpl         → brew casks (wezterm, ghostty, raycast)
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
