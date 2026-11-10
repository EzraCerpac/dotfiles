# Setup maintenance tasks

`dots` runs these scripts from the configuration root (`DOTS_ROOT`) inside its
mise environment. They require `SETUP_PROFILE`, one of the profiles in
`[vars] dots_profiles`, and optionally use `SETUP_MACHINE_ID` to load the
corresponding `host-<id>` environment. Each child mise process is pinned to the
configuration directory and those environments.

## What a configuration provides

Everything dots-specific that a configuration supplies lives under
`DOTS_ROOT/dots/`. Every part is optional; a configuration without any of
them works.

| Path | Purpose |
| --- | --- |
| `dots/hooks/update.d/*` | Run by `dots up` after installer exceptions |
| `dots/hooks/bootstrap.d/*` | Run by bootstrap completion after installer exceptions |
| `dots/commands/NAME` | Run as `dots NAME [ARGS...]` when `NAME` is not a built-in |
| `dots/exceptions.tsv`, `dots/exceptions/NAME` | Installer exception manifest and recipes |
| `dots/retired-dotfiles` | Retired dotfile targets whose dangling links are removed |
| `dots/history-files.tsv` | `PROFILE<TAB>~/PATH` rows (`base` = every profile): app-written files history enrollment tracks |
| `encrypted/bootstrap.PROFILE.json.age` | That profile's bootstrap bundle; bootstrap uses it implicitly and applies its private files |

Settings live in `[vars]` of `config.toml`. mise vars are strings, so a list
is one string of space-separated words.

| Setting | Meaning |
| --- | --- |
| `dots_profiles` | Required. The profiles this setup selects with `-E`, e.g. `"laptop server"` |
| `dots_source_repo` | GitHub `OWNER/NAME` of the configuration; sync, publish and remote bootstrap use it |
| `dots_state_repo` | GitHub `OWNER/NAME` of the private settings history; restore and bootstrap use it |
| `dots_self_updating_casks` | Optional. Casks routine updates leave to the app's own updater |

### Hooks

A hook is a regular executable file with a plain name (letters, digits, `.`,
`_` and `-`). Hooks run in name order, each as its own reported stage,
from `DOTS_ROOT` inside the setup's mise environment. The stage label is the
name without a leading order number or file extension, with dashes and
underscores as spaces: `20-Login-shell.sh` is reported as `Login shell`.

A name ending in `@PROFILE` (for example `30-Release@server`) makes the hook
apply only to that profile; other profiles neither list nor run it, and the
suffix is not part of the label. A suffix naming a profile outside
`dots_profiles` fails the hook stage before any hook runs.
`manager/lib/dots-hooks` implements this listing for both the updater and
bootstrap.

Every hook receives `DOTS_ROOT`, `DOTS_HOME` (the manager) and `DOTS_PROFILE`.
Update hooks also receive `DOTS_TOOLS_OK=1` when `mise install` succeeded and
`DOTS_TOOLS_UPGRADED=1` when the following tools upgrade succeeded. Bootstrap
hooks also receive `DOTS_PRIVATE_READY=1` when private inputs, restore and
history recovery are complete (or were not needed) and `DOTS_RESTORED=1` when
this run restored private settings.

Each update hook also receives `DOTS_CHANGES`, a private empty file. A hook may
append `ITEM<TAB>BEFORE<TAB>AFTER` lines to it (for example a plugin and its
old and new revision); `dots up` shows them as changes in that hook's stage
report and ignores malformed lines with a note.

Exit 0 means completed, 3 deferred (needs attention later), 4 skipped, and any
other status failed. Output goes to the stage log unchanged. A failed hook is
reported and later hooks still run, so keep a dependent chain in one hook.

### Commands

`dots NAME [ARGS...]` runs `dots/commands/NAME` when `NAME` is not a built-in
command; built-ins always win. `NAME` must be a plain name without a slash or
a leading dash. Arguments are passed literally, the working directory is the
caller's, and `DOTS_ROOT`, `DOTS_HOME` and `DOTS_PROFILE` are exported. The
command runs before mise loads the setup: no source sync, tool installs or
package updates. `dots help` lists the commands it finds.

### Installer exceptions

If a wanted app has no suitable mise package backend, add one executable recipe
per app under `dots/exceptions/` and one row to `dots/exceptions.tsv`:

```text
laptop<TAB>some-app<TAB>install-only
```

Columns are tab-separated: the profile (`base` for every profile), the recipe
name, and optional comma-separated flags. `install-only` makes `dots up` only
install the app when it is missing, for apps that update themselves.
`hold=PACKAGE` (for example `hold=brew:some-formula`) records that the recipe pins
that package, so `dots add` refuses it. Bootstrap always runs recipes with
`--install-only`.

Each recipe must update exactly one named app with its own package-manager
command. Do not use blanket `npm update -g`, `uv tool upgrade --all`, or other
whole-environment operations. Keep apps declared to native mise tools or
packages out of this list. Homebrew recipes can use `lib/brew-exception.sh`:

- `update_brew_cask_exception [--auto-updates] [--admin] TOKEN [PROCESS] [--install-only]`
- `update_brew_formula_exception TOKEN [--install-only]`
- `hold_brew_formula_exception TOKEN VERSION [REASON]`
- `hold_brew_cask_exception TOKEN VERSION APP_PATH [REASON]`

These commands disable Homebrew autoremove and install cleanup. If a recipe
needs administrator access and none is cached, a noninteractive run defers it
and prints `sudo -v && dots up`.

## `dots up`

`dots up` saves tracked settings before and after updates. It synchronizes
source, then re-executes the updated manager once. It updates declared native
packages, installs and upgrades declared mise tools (tools pinned to a
revision keep it), runs installer exceptions and update hooks, and updates
standalone mise last.

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
