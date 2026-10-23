# Setup source ownership

On managed hosts, `~/.config/mise` is the active setup source. Native mise deploys static files under `dotfiles/` in their declared symlink or copy mode. For symlinked files, edit the linked file or its source. For copy-mode files, edit the source and reapply only that intentional file through native mise; editing the deployed copy does not update its source. Use native mise dotfile application for templates. Do not run chezmoi against these destinations. Isolated task checkouts hold reviewed source changes; inspect the selected checkout before editing or deploying.

Use JJ where the checkout supports it and Git in Git-only worktrees. Retain the old checkouts and protected backups for rollback.

Use `dots status`, `dots up`, `dots backup`, or `dots restore` for routine maintenance. `dots` selects the setup directory before mise loads configuration; internal scripts retain explicit directory selection. Project dependencies remain project-owned. Updates must not prune packages, restart services, or publish source automatically.

Capd is a user-authorized exception to the routine update boundary: macOS workstation `dots up` may install a changed, locally built `EzraCerpac/capd` `main` revision and restore its prior running state. Its updater must exit without rebuild or restart when the installed app matches current fork `main`; NAS updates must skip Capd.

`miserc.toml`, `config.local.toml`, and `config.host-*.toml` are local and ignored. App-written settings remain regular files with encrypted history in the private `dotfiles-state` repository. Keep private keys and application state out of this public repository.

The shared base loads for every machine. Explicit roles are `workstation` and `nas`; DelftBlue is retired. Codex instructions on the Mac, CerpacNAS, and Driehuis NAS resolve to their local mise sources. This verifies selected instruction ownership, not full machine cutover. Preserve host exceptions, services, and system software. DelftBlue is preserved without a cluster deployment. See `docs/agent-instructions.md` for the selected sources and on-demand drift check.

See `docs/migration.md` and the ownership guides before changing installer exceptions or transferring an app. Keep existing app data and signed local desktop builds intact.

# Cloud NAS tasks

For cloud tasks accessing the NASes or HouseAtlas, read
[Cloud NAS access](docs/cloud-nas-access.md) before choosing a route or testing
connectivity. It records bounded read-only checks and dated service observations;
it does not authorize login, service changes, or broader network access.
