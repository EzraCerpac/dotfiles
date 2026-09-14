# Setup maintenance tasks

The registered tasks call these scripts from the setup root. They require
`SETUP_PROFILE` (`workstation`, `nas`, or `delftblue`) and optionally use
`SETUP_MACHINE_ID` to load the corresponding `host-<id>` environment. Each
child mise process is pinned to this setup directory and those environments.

`setup:update` saves tracked settings before and after updates. On macOS it runs
Homebrew formulae, Homebrew casks, and Mac App Store packages as independent
stages, then updates declared mise tools, named exceptions, editor plugins, and
standalone mise last. Other profiles use their declared host-package stage.
Later stages continue after an earlier stage fails; failures are collected and
make the final task result nonzero once the pre-update save succeeds. The task
does not prune software, update project dependencies, publish source, or
restart services.

If the Mac App Store stage has no cached administrator authorization, a
noninteractive run defers that stage and continues. An interactive
`mise -C ~/.config/mise run setup:update` can prompt through `sudo -v`. A
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

Zoom, Karabiner Elements, Tailscale, and SF Pro stay with their Homebrew
receipts because mise 2026.9.7 skips their package-only auto-updating casks or
the `latest` SF Pro version. `setup:update` runs their named Brew exceptions;
each checks and updates only its own cask with `brew outdated --cask --greedy`
and `brew upgrade --cask --greedy`. Existing receipts make `--install-only` a
no-op. Updates defer while Zoom, Karabiner Core Service, or Tailscale is
running. If one of these exceptions needs administrator access and no access is
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
