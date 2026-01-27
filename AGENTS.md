# Repository Guidelines

## Project Structure & Module Organization
- Source root is a chezmoi source repo. Files prefixed with `dot_` map to `$HOME` (e.g., `dot_zshrc` -> `~/.zshrc`).
- Configuration lives under `dot_config/` (e.g., Neovim in `dot_config/nvim/`, Git in `dot_config/git/`).
- Bootstrap scripts use numbered `run_once_*.sh.tmpl` (01 through 04); post-setup hooks use `run_after_*.sh.tmpl`.
- Tool versions are managed via `dot_config/mise/config.toml` (mise is the single source of truth).
- See `README.md` for usage and structure overview.

## Key Files
- `run_once_01-setup-directories.sh.tmpl` — creates `~/Projects`, `~/.local/bin`, etc.
- `run_once_02-install-package-managers.sh.tmpl` — bootstraps brew (macOS) + mise
- `run_once_03-install-tools.sh.tmpl` — system packages (brew/apt) + `mise install`
- `run_once_04-setup-macos.sh.tmpl` — brew casks (wezterm, raycast)
- `run_after_setup-shell.sh.tmpl` — fish shell setup, `/etc/shells`, chsh hint
- `dot_config/fish/config.fish.tmpl` — cross-platform fish config (chezmoi template)
- `dot_config/mise/config.toml` — mise tool manifest (node, neovim, starship, fzf, etc.)
- `.chezmoiignore` — OS-conditional ignores (macOS-only configs skipped on Linux)

## Build, Test, and Development Commands
- `chezmoi status|diff`: review pending changes before applying.
- `chezmoi apply` / `chezmoi apply --dry-run`: apply changes (or simulate safely).
- `chezmoi doctor`: environment diagnostics.
- `chezmoi execute-template --init false`: parse templates to catch errors.

## Coding Style & Naming Conventions
- Shell: `bash`, `set -euo pipefail`, 4-space indent; functions use `lower_snake_case`.
- Lua (Neovim): keep modules small and descriptive; prefer `snake_case` filenames.
- Chezmoi naming: use `dot_` for homedir files; `run_once_*.sh.tmpl` for idempotent setup; keep machine-specific logic inside templates with guards.
- Markdown: follow rules in `dot_markdownlint-cli2.yaml`.

## Testing Guidelines
- Fast safety checks: `chezmoi verify` and `chezmoi diff` before `apply`.
- Aim for a clean `chezmoi doctor` and zero errors from template parsing.
- Run `chezmoi apply --dry-run` to verify no template errors.

## Commit & Pull Request Guidelines
- Commits: prefer Conventional Commits (`feat:`, `fix:`, `docs:`). Short present-tense subject; scoped where helpful (e.g., `feat(nvim): ...`).
- PRs: include purpose, scope (OS, shells, editors), sample commands run (e.g., `chezmoi diff`), and screenshots or logs for failures.
- Link related issues; describe any migration steps (e.g., re-running `run_once_...`).

## Security & Configuration Tips
- Do not commit secrets. Use templates and `[data]` in `.chezmoi.toml.tmpl` instead of hard-coding.
- Keep host/user-specific values behind template conditionals (e.g., `{{ if eq .chezmoi.os "darwin" }}` blocks).
- mise is the single source of truth for tools. It handles runtimes (node, rust), CLI tools, and supports aqua/cargo/github/ubi backends.
- brew/apt-get only for system-level packages (fish, gnupg, curl, wget, htop, tree).
