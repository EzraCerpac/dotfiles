# Repository Guidelines

## Project Structure & Module Organization
- Source root is a chezmoi source repo. Files prefixed with `dot_` map to `$HOME` (e.g., `dot_zshrc` -> `~/.zshrc`).
- Configuration lives under `dot_config/` (e.g., Neovim in `dot_config/nvim/`, Git in `dot_config/git/`).
- One‑time bootstrap scripts use `run_once_*.sh.tmpl`; post‑setup hooks use `run_after_*.sh.tmpl`.
- Utility scripts are in `scripts/` (e.g., `scripts/validate.sh`, `scripts/health-check.sh`).
- See `Makefile` for helper targets and `CHEZMOI_GUIDE.md`/`README.md` for usage.

## Build, Test, and Development Commands
- `chezmoi status|diff`:
  review pending changes before applying.
- `chezmoi apply` / `chezmoi apply --dry-run`:
  apply changes (or simulate safely).
- `chezmoi doctor`:
  environment diagnostics.
- `chezmoi execute-template --init false`:
  parse templates to catch errors.
- `make help`:
  list repo targets.
- `make doctor` / `make validate` / `make clean`:
  doctor, run validations, and clean temp files.

## Coding Style & Naming Conventions
- Shell: `bash`, `set -euo pipefail`, 4‑space indent; functions use `lower_snake_case` (see `scripts/validate.sh`).
- Lua (Neovim): keep modules small and descriptive; prefer `snake_case` filenames.
- Chezmoi naming: use `dot_` for homedir files; `run_once_*.sh.tmpl` for idempotent setup; keep machine‑specific logic inside templates with guards.
- Markdown: follow rules in `dot_markdownlint-cli2.yaml`.

## Testing Guidelines
- Primary checks: `make validate` or `./scripts/validate.sh` (syntax, tool configs, templates, symlinks, permissions).
- Fast safety checks: `chezmoi verify` and `chezmoi diff` before `apply`.
- Aim for a clean `chezmoi doctor` and zero errors from the validation script.

## Commit & Pull Request Guidelines
- Commits: prefer Conventional Commits (`feat:`, `fix:`, `docs:`). Short present‑tense subject; scoped where helpful (e.g., `feat(nvim): ...`).
- PRs: include purpose, scope (OS, shells, editors), sample commands run (e.g., `chezmoi diff`, `make validate`), and screenshots or logs for failures.
- Link related issues; describe any migration steps (e.g., re‑running `run_once_...`).

## Security & Configuration Tips
- Do not commit secrets. Use templates and `[data]` in `.chezmoi.toml.tmpl` instead of hard‑coding.
- Keep host/user‑specific values behind template conditionals (e.g., `{{ if eq .os "darwin" }}` blocks).
- Validate permissions (`scripts/validate.sh`) and avoid leaking private paths into tracked files.

