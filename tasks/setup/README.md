# Setup maintenance tasks

The registered tasks call these scripts from the setup root. They require
`SETUP_PROFILE` (`workstation` or `nas`) and optionally use
`SETUP_MACHINE_ID` to load the corresponding `host-<id>` environment. Each
child mise process is pinned to this setup directory and those environments.

`setup:update` saves tracked settings before and after updates. On macOS it
prepares the Homebrew `mas` formula first, then runs App Store updates alongside
other Homebrew formulae, casks, mise tools, named exceptions, and editor plugins.
It waits for App Store updates before updating standalone mise and saving the
final checkpoint. The cask stage installs missing declared casks, then
upgrades only casks without `auto_updates: true`; self-updating casks are left
to their vendor updaters. Zoom, Tailscale, Antinote, and OmniDiskSweeper use
named cask exceptions: routine updates install them if missing and skip their
upgrades. Herdr is deferred while its terminal server is running. Kanata and
Karabiner remain held for the known input bug. Other profiles use their declared
host-package stage.
Later stages continue after an earlier stage fails; failures are collected and
make the final task result nonzero once the pre-update save succeeds. The task
does not prune software, update project dependencies, publish source, or
restart services.

If the Mac App Store stage has no cached administrator authorization, a
noninteractive run defers that stage and continues. An interactive
`dots up` can prompt through `sudo -v`. A
deferred App Store stage is not a task failure.

If a wanted app has no suitable mise package backend, add one executable script
per app under `exceptions/` and one row to `exceptions.tsv`:

```text
workstation<TAB>herdr-npm
```

The row above uses a literal tab. The script name must match the second field.
Each script must update exactly one named app with its own package-manager
command. Do not use blanket `npm update -g`, `uv tool upgrade --all`, or other
whole-environment operations. Keep apps declared to native mise tools/packages
out of this list.

Zoom and Tailscale stay with their Homebrew receipts because their casks use
vendor self-updaters. Antinote and OmniDiskSweeper use named Homebrew cask
exceptions because the native mise DMG extractor cannot answer their installer
licence prompts. Routine `setup:update` installs these four only when missing;
it does not run their cask upgrades. Karabiner Elements remains held for the
known input bug, and SF Pro keeps its existing `latest` behavior. Updates for
Zoom, Karabiner Core Service, and Tailscale defer while those apps or services
are running. If a named exception needs administrator access and no access is
cached, a noninteractive run prints
`sudo -v && mise -C ~/.config/mise run setup:update`; in an interactive
terminal, Homebrew can request authorization. These commands disable Homebrew
autoremove and install cleanup for the package operation.

`mlx-audio` stays in the user's UV tool environment because Mise's native
pipx backend disables source builds, which prevents its `server` extra from
installing `webrtcvad`. Its exception upgrades only `mlx-audio` with Mise's
Python 3.13 while preserving the `server` and `tts` extras; a fresh install
uses the same interpreter and extras.

`mlx-vlm` stays in the user's UV tool environment because its installed tool
receipt includes the `ui` extra plus `torchvision` and `hf-xet`. Its exception
upgrades only `mlx-vlm` with Mise's Python 3.13 while preserving those receipt
requirements; a fresh install uses the same interpreter.

`setup:restore` requires `SETUP_HISTORY_ORIGIN` from ignored local config, set
to the private `EzraCerpac/dotfiles-state` repository. It never adopts private
history into the public source checkout.

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
available; `setup:restore` keeps auto-install disabled and does not install
prerequisites. Workstation and NAS profiles declare Node. It never saves or
publishes local defaults during restore.

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
publication remains a separate explicit `setup:backup` operation.

`setup:secrets` installs only `wakatime.cfg.age` and
`himalaya-config.toml.age`, for the workstation profile. It requires
`SETUP_AGE_IDENTITY` or `~/.config/age/keys.txt`. It validates content before
writing, uses mode `0600`, and refuses differing live files unless the exact
target is named with `--reconcile`.

The user approved Antinote and OmniDiskSweeper licences. Their cask exceptions
can install a missing app; routine updates leave upgrades to each app's updater.
