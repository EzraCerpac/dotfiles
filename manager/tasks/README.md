# Manager tasks

`dots` runs these scripts from the configuration root (`DOTS_ROOT`) inside its
mise environment. They require `SETUP_PROFILE`, one of the profiles in
`[vars] dots_profiles`, and optionally use `SETUP_MACHINE_ID` to load the
corresponding `host-<id>` environment. Each child mise process is pinned to the
configuration directory and those environments.

The commands and the configuration they read are described in
[the manager README](../README.md) and [the `dots/` reference](../init/README.md).
This page records how `dots up` and `dots restore` work in detail.

## Homebrew recipe helpers

An installer exception recipe (see [the `dots/` reference](../init/README.md#installer-exceptions)) must update exactly one named app with its own package-manager command.
Do not use blanket `npm update -g`, `uv tool upgrade --all`, or other whole-environment operations.
Homebrew recipes can source `"$DOTS_HOME/lib/brew-exception.sh"` and call:

- `update_brew_cask_exception [--auto-updates] [--admin] TOKEN [PROCESS] [--install-only]`
- `update_brew_formula_exception TOKEN [--install-only]`
- `hold_brew_formula_exception TOKEN VERSION [REASON]`
- `hold_brew_cask_exception TOKEN VERSION APP_PATH [REASON]`

These disable Homebrew autoremove and install cleanup.
The update helpers append each verified installation or upgrade to the stage's `DOTS_CHANGES` file.
If a recipe needs administrator access and none is cached, a noninteractive run defers it and prints `sudo -v && dots up`.

## `dots up`

`dots up` saves tracked settings before and after updates. It synchronizes
source, then re-executes the updated manager once. It updates declared native
packages, installs and upgrades declared mise tools (tools pinned to a
revision keep it), runs installer exceptions and update hooks, and updates
standalone mise last.

Each stage's changes reach the report and the first screen as `change` events
with an action (installed, updated, removed or changed). `dots up` derives
package, tool and standalone mise changes from snapshots taken before and after
the stage; hooks and installer exception recipes report theirs as
`ITEM<TAB>BEFORE<TAB>AFTER` lines in `DOTS_CHANGES`; source sync reports the
configuration revision it adopted.

On macOS, a host whose configuration declares `brew-cask:` or `mas:` packages
gets separate Homebrew formula and cask stages; other hosts update their
declared native packages in one pass. Mac App Store updates are skipped by
default. `dots up --mas` includes them when `mas:` packages are declared: it
prepares the Homebrew `mas` formula first, then runs App Store updates
alongside the other updates and waits for them before updating standalone mise
and saving the final checkpoint. The cask stage installs missing declared
casks, then upgrades only casks without `auto_updates: true` and not listed in
`dots_self_updating_casks`.

Later stages continue after an earlier stage fails; failures are collected and
make the final result nonzero once the pre-update save succeeds. The task does
not prune software, update project dependencies, publish source, or restart
services. If the opted-in Mac App Store stage has no cached administrator
authorization, a noninteractive run defers that stage and continues; an
interactive `dots up --mas` can prompt through `sudo -v`.

## `dots restore`

`dots restore` requires `SETUP_HISTORY_ORIGIN` from ignored local config, set
to the private `dots_state_repo` repository. It never adopts private history
into the public source checkout.

For a host with no local history store, restore stages and validates a bare
clone, connects it with native fetch-only mode, prints the incoming status, and
uses mise's conflict checks to pull. Mise 2026.9.7's fresh fetch-only origin
setup can create a new empty local history before fetching an older remote
history; its `pull` may succeed without materializing that earlier state. The
task therefore resolves the fetched remote commit and applies that initial
checkpoint with native `dotfiles rollback --dry-run` followed by the confirmed
rollback. It then secures only the exact tracked files active for this host at
mode `0600`, and sets history sync to `manual`. On mise 2026.9.7, host variants
separate file contents but share tracked-file permission metadata, so every
enrolled encrypted regular file follows the same `0600` policy. If restore stops
after installing a history store, a private pending marker lets the next
restore resume this seed step instead of treating the store as established. It
refreshes the selected host's exact-file enrollment after the files arrive,
then filters native `dotfiles paths --json` entries to `mode = "track"` before
applying permissions. It requires Git, the age identity, and Node to be already
available; restore keeps auto-install disabled and does not install
prerequisites. It never saves or publishes local defaults during restore.

If a local history store exists but is not connected to this exact private
repository, inspect it before proceeding. Pass `--initialize-history` only
after choosing to replace that store. Restore first verifies a staged clone,
moves the old store into a mode-`0700` sibling directory named
`repo.git.pre-restore.*`, and then installs the clone. A failed clone leaves
the old store at its original path. Keep the sibling backup until its history
has been reviewed.

Before any restore, the task checks the current user's mise history watcher
process and the native launchd/systemd service definition. If the watcher is
running or its state cannot be confirmed, stop it through its service owner and
retry. The task never stops services itself. Restore begins in fetch-only mode;
publication remains a separate explicit `dots backup` operation.
