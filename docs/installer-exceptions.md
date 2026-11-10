# Installer exceptions and dots hooks in this setup

The generic contract (hook rules, the `dots/exceptions.tsv` format and the
Homebrew recipe helpers) is documented with the manager in
[`manager/tasks/README.md`](../manager/tasks/README.md). This page records this
setup's own choices.

## Update and bootstrap hooks

`dots up` runs [`dots/hooks/update.d`](../dots/hooks/update.d) after installer
exceptions and before the Mac App Store result: the Herdr live handoff and
shell configuration (workstation), the jw NAS release (NAS), the Codex ACP
native executable, jw main source and Capd fork main (workstation; Capd on
macOS only), then Neovim plugins. Neovim plugins run after the exceptions
because `nas-neovim-source` builds Neovim on the NAS. Hooks that do not apply
to a profile report themselves as skipped.

Bootstrap runs [`dots/hooks/bootstrap.d`](../dots/hooks/bootstrap.d) after
installer exceptions and before Atuin: the Codex ACP payload, missing public
defaults after a restore, the jw NAS release, Neovim, the Fish, Herdr and
login shell chain, the current-user keyboard, and personal command builds.

`dots houseatlas check|apply|status` is [a configuration
command](../dots/commands/houseatlas); it replaced `dots up houseatlas`.

## Homebrew cask policy

CodexBar is listed in `dots_self_updating_casks` and is excluded from routine
cask upgrades because its cask omits `auto_updates`; setup still installs it
when missing.

Zoom and Tailscale stay with their Homebrew receipts because their casks use
vendor self-updaters. Antinote and OmniDiskSweeper use named Homebrew cask
exceptions because the native mise DMG extractor cannot answer their installer
licence prompts. The user approved Antinote and OmniDiskSweeper licences. These
four are `install-only` in [`dots/exceptions.tsv`](../dots/exceptions.tsv):
routine `dots up` installs them only when missing and leaves upgrades to each
app's updater. SF Pro keeps its existing `latest` behavior. Updates for Zoom and
Tailscale defer while those apps are running.

Kanata and Karabiner-Elements remain held for the known input bug
(`hold=` rows in the manifest); `dots add` refuses them. Herdr is deferred while
its terminal server is running.

## UV tool exceptions

`mlx-audio` stays in the user's UV tool environment because Mise's native
pipx backend disables source builds, which prevents its `server` extra from
installing `webrtcvad`. Its exception upgrades only `mlx-audio` with Mise's
Python 3.13 while preserving the `server` and `tts` extras; a fresh install
uses the same interpreter and extras.

`mlx-vlm` stays in the user's UV tool environment because its installed tool
receipt includes the `ui` extra plus `torchvision` and `hf-xet`. Its exception
upgrades only `mlx-vlm` with Mise's Python 3.13 while preserving those receipt
requirements; a fresh install uses the same interpreter.

## Secrets

`setup:secrets` ([`setup-scripts/setup/secrets`](../setup-scripts/setup/secrets))
installs only `wakatime.cfg.age` and `himalaya-config.toml.age`, for the
workstation profile. It requires `SETUP_AGE_IDENTITY` or
`~/.config/age/keys.txt`. It validates content before writing, uses mode
`0600`, and refuses differing live files unless the exact target is named with
`--reconcile`.
