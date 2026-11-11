# Machine setup

`~/.config/mise` is the live setup source (JJ). Native mise deploys `dotfiles/` as symlinks or copies: edit the source, and for copy-mode files and templates reapply only that target through native mise. Never run chezmoi against these destinations.

Two things live here. `manager/` is the `dots` manager, generic code that will move to its own repository: it must not depend on anything outside `manager/` (its tests run from a copy of that directory alone). Everything else is this personal configuration: `config*.toml`, `dotfiles/`, `templates/`, `setup-scripts/`, and `dots/` (hooks, commands and installer exceptions that plug into the manager). Read [manager/skills/dots/SKILL.md](manager/skills/dots/SKILL.md) before using `dots` or changing either side; [manager/README.md](manager/README.md) documents the commands.

Small changes (instruction text, a config line) go straight into the live checkout: edit, then run `dots up`, which applies them and pushes to shared `dev`. Larger or risky changes use a task worktree (Git) and a PR into `main`, which stays reviewed. Every `dots up` merges `main` into `dev`, so a merged PR goes live on the next `dots up`; don't run it while another agent has uncommitted edits in the live checkout.

Use `dots status`, `dots up`, `dots backup`, and `dots restore` for routine maintenance. Updates must not prune packages or restart services. The one exception is Capd: macOS `dots up` may rebuild and reinstall a changed `EzraCerpac/capd` `main` and restore its running state, and does nothing when it is already current; NAS updates skip it.

This repository is public. `miserc.toml`, `config.local.toml`, and `config.host-*.toml` are local and ignored; app-written settings live in the private `dotfiles-state` repository. Claude Code `settings.json` renders from a template (see `docs/agent-instructions.md`). Never commit keys or app state.

Roles are `workstation` and `nas`. Preserve host exceptions, services, system software, app data, and signed local desktop builds. Read `docs/agent-instructions.md` before changing agent instructions and `docs/migration.md` before changing installer exceptions or moving an app.

Tests: `tests/run` for this configuration, `manager/tests/run` for the manager ([testing](docs/testing.md)).

For cloud tasks that touch the NASes or HouseAtlas, read [Cloud NAS access](docs/cloud-nas-access.md) first. It does not authorize logins, service changes, or broader network access.
