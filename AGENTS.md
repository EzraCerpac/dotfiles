# Machine setup

`~/.config/mise` is the live setup source: plain Git with `HEAD` on `dev`, never JJ. Native mise deploys `dotfiles/` as symlinks or copies: edit the source, and for copy-mode files and templates reapply only that target through native mise. Never run chezmoi against these destinations.

This is a personal configuration for the `dots` manager, which lives in its own repository, [EzraCerpac/dots](https://github.com/EzraCerpac/dots); `config.toml` pins the release every machine runs ([dots release](docs/dots-release.md)). Everything here is configuration: `config*.toml`, `dotfiles/`, `templates/`, `setup-scripts/`, and `dots/` (hooks, commands and installer exceptions that plug into the manager). Read the `dots` skill before using `dots` or changing `dots/`; [the manager's README](https://github.com/EzraCerpac/dots#readme) documents the commands. Manager changes go to EzraCerpac/dots and reach this setup by moving the pin.

Small changes (instruction text, a config line) go straight into the live checkout: edit, then run `dots up`, which commits them and pushes to shared `dev`. Pushing a commit straight to `origin/dev` from a task worktree is fine too. Larger or risky changes use a task worktree (Git) and a PR into `main`, which stays reviewed. Every sync merges `main` into `dev` (published side wins conflicts), so a merged PR goes live on the next `dots up`; don't run it while another agent has uncommitted edits in the live checkout. If sync stops because the checkout is in the wrong shape, follow [sync migration](docs/sync-migration.md).

Use `dots status`, `dots up`, `dots backup`, and `dots restore` for routine maintenance. Updates must not prune packages or restart services. The one exception is Capd: macOS `dots up` may rebuild and reinstall a changed `EzraCerpac/capd` `main` and restore its running state, and does nothing when it is already current; NAS updates skip it.

This repository is public. `miserc.toml`, `config.local.toml`, and `config.host-*.toml` are local and ignored; app-written settings live in the private `dotfiles-state` repository. Claude Code `settings.json` takes only the keys its template owns (see `docs/agent-instructions.md`). Never commit keys or app state.

Roles are `workstation` and `nas`. Preserve host exceptions, services, system software, app data, and signed local desktop builds. Read `docs/agent-instructions.md` before changing agent instructions and `docs/migration.md` before changing installer exceptions or moving an app.

Tests: `tests/run` ([testing](docs/testing.md)); the manager is tested in its own repository.

For cloud tasks that touch the NASes or HouseAtlas, read [Cloud NAS access](docs/cloud-nas-access.md) first. It does not authorize logins, service changes, or broader network access.

## Code Review Rules

When reviewing a pull request, read [REVIEW.md](REVIEW.md) first and follow it.
