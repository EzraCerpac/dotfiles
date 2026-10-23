# Explicit setup tasks

These tasks replace setup hooks that used to run during dotfile application.
Most remain explicit; bootstrap installs a missing workstation `jw`, and
`setup:update` updates an existing workstation `jw`. Invoke explicit tasks
through the setup checkout so mise reads this configuration:

```sh
mise -C ~/.config/mise run <task>
```

The parent setup configuration registers the task names. The task scripts live
under `setup-scripts/local/` and `setup-scripts/install/`.

Install native packages through the selected profile's mise package bootstrap
before running their app configuration or service tasks. For example, the
CLIProxyAPI formula remains a package declaration; the two local tasks below
only configure its settings link and start its service.

| Task script | Replaces | What it does |
| --- | --- | --- |
| `setup-scripts/install/jw-build-install.sh` | Workstation jj-waltz build hook | Builds verified `EzraCerpac/jj-waltz` main with Cargo's lockfile in disposable source/build directories and atomically activates a versioned `jw`. `dots up` passes `--update-existing` so it skips hosts without `jw`. |
| `setup-scripts/install/jw-nas-release.sh` | NAS jj-waltz release branch | Downloads the pinned static x86-64 Linux release, checks its SHA-256 and version, then installs it. |
| `setup-scripts/install/nas-modern-git.sh` | NAS modern Git hook | Checks and installs the pinned micromamba binary, creates or updates the user-space `git>=2.41` environment, and links `~/.local/bin/git` only when that path is free or already owned by this environment. |
| `setup-scripts/install/herdr-plugins.sh` | Pinned Herdr plugin hook | Installs the four pinned plugins when their current commit differs. Requires Herdr and `jq`. |
| `setup-scripts/local/antinote-bridge-build.sh` | Antinote bridge build hook | Builds the source in `dotfiles/.local/share/personal-concierge/antinote-bridge/main.swift` and atomically installs its binary. The source fingerprint is kept under `~/.local/state/mise/`. |
| `setup-scripts/local/shell-select.sh` | Login-shell hook | Resolves a validated Fish executable, then asks native mise to add it to `/etc/shells` and update the account. Workstation and NAS profiles use the same path; a noninteractive run without passwordless administrator access reports a resumable deferral. |
| `setup-scripts/local/touchid-sudo.sh` | Touch ID hook | Adds `pam_tid.so` to `/etc/pam.d/sudo_local` with `sudo`; it is a no-op when already enabled. |
| `setup-scripts/local/cliproxy-configure.sh` | CLIProxyAPI configuration hook | Preserves a previous Homebrew config beside the target if needed, then links the user's config. It does not change service state. |
| `setup-scripts/local/cliproxy-service.sh` | CLIProxyAPI service part | Starts the Homebrew service only when it is stopped. It leaves a running service alone. |
| `setup-scripts/local/aegis-local-install.sh` | Aegis local build/install helper | Calls the deployed `~/.local/bin/aegis-local-install` helper. That helper can quit/reopen Aegis and write its updater defaults, so run it only when intentionally installing the local build. |
| `setup-scripts/local/aegis-signing-setup.sh` | Aegis signing setup helper | Calls the deployed signing helper when a local signing identity needs setup. |
| `setup-scripts/local/rift-local-install.sh` | Rift local build/install helper | Calls the deployed helper. By default it builds and stages only; `--activate` is the explicit service/manager handoff. |
| `setup-scripts/local/rift-signing-setup.sh` | Rift signing setup helper | Calls the deployed signing helper when needed. |
| `setup-scripts/local/aerospace-local-build.sh` | Preserve the active AeroSpace local build | Builds the pinned clean source revision with SwiftPM and Xcode into a versioned staging directory. It never replaces the active app or CLI. |
| `setup-scripts/local/voiceink-build.sh` | VoiceInk local-build owner exception | Builds the current clean VoiceInk source with its local updater guard and stable Apple Development signature, then stages the app without installing or launching it. |
| `setup-scripts/local/capd-build.sh` | capd local fork build | Packages the clean fork with its app, CLI, agent and share extension, signs with the existing Apple Development identity and stages it outside the checkout. |
| `setup-scripts/local/capd-install.sh` | capd local fork activation | Installs a named stage, preserves the app, data and preferences, then restores the prior app/agent running state. Rolls back on failure. |
| `setup-scripts/local/ensure-homebrew-exceptions.sh` | Brooklyn and MacTeX prerequisites | On workstation macOS only, installs Homebrew if absent using a checksum-pinned official installer; it does not install or update packages. |
| `setup-scripts/local/finish-dotfiles.sh` | Post-dotfiles permissions | Verifies private modes after file application; workstation and NAS. |
| `setup-scripts/local/private-permissions.sh` | SSH template preparation and explicit permission repair | Before dotfile apply, sets the SSH template source to `0600` so mise renders `~/.ssh/config` with the same mode and reports it as applied. After apply, sets `~/.ssh` and `~/.config/jj` to `0700`, the rendered SSH config to `0600`, and regular jj config copies to `0600`. It skips declared public-source symlinks and refuses directory or SSH-target symlinks. |

## Operational boundaries

On workstations already using `jw`, `dots up` checks
`https://github.com/EzraCerpac/jj-waltz.git` main and builds only when its full
source commit differs. It preserves the development checkout, including
unpublished work. Each activated binary lives at
`~/.local/libexec/jj-waltz/<version>-<12-character-commit>/jw`, with a full
`source-commit` marker and a validated SHA-256 build identity. The active
`~/.local/bin/jw` symlink changes only after repository, Cargo artifact, version
and digest validation. Unchanged updates skip Cargo; transient source and target
directories are removed after success or failure. A concurrent updater reports
failure without replacing the active binary.

The installer accepts the existing marker-only versioned layout, a regular
executable identifying as `jw`, or the known
`~/Projects/jj-waltz/target/release/jw` link. It refuses foreign links and
symlinked installation directories. Legacy executables are copied into the
managed root before activation, and `~/.local/libexec/jj-waltz/previous` points
to the last working binary. Both that binary and older versioned binaries are
retained for rollback; the updater never prunes them. To roll back, inspect
`previous`, then atomically repoint `~/.local/bin/jw` to that binary. Network,
build and validation failures leave the active binary intact and appear in
the `dots up` failure report. `JW_INSTALL_DIR` still selects the launcher
directory; `JW_SOURCE_DIR` is no longer used because builds must come from
verified main. The NAS release installer and the selected `jj` pin retain
their existing lifecycle.

`setup:update` does not build local Aegis or Rift. It does not restart CLIProxyAPI,
change the login shell, change sudo PAM settings, update Herdr plugins, or
provision keyboard hardware. Those are explicit tasks or separate lifecycle
operations.

The current desktop uses AeroSpace and Aegis. Rift stays inactive by default;
its activation path can replace the active manager and load its LaunchAgent. The
Rift LaunchAgent source must remain valid XML, and a cutover should retain the
current inactive state until a deliberate manager handoff.

The AeroSpace task stages the active custom `0.21.3-PR2245-Local-CacheFocusFix` build from
source commit `d2792f5bcd5b35af2fcc3160b41dc6cd0201c592` in
`~/Projects/Tools/AeroSpace`. It uses Xcode Release for the app and an arm64
SwiftPM Release build for the CLI, signing with the current app's Apple
Development identity. The revision keeps the PR2245 fullscreen fix, Hyper
hover-focus pause, and Codex quick-switcher popup exclusion; the user confirmed
Cmd+P remains on workspace E with the final behavior. The task stages and
validates both binaries under `~/.local/state/aerospace-pr2245/staged/`. It does
not install files into `/Applications` or `~/.local/opt`, quit AeroSpace, or
change login items. Set `AEROSPACE_SOURCE_DIR`, `AEROSPACE_STAGE_ROOT`, or
`AEROSPACE_CODESIGN_IDENTITY` only when using a different checkout, staging
location, or already provisioned signing identity.

VoiceInk remains owned by its local source checkout because its build uses a
machine-local Whisper framework and `LOCAL_BUILD` behavior. Run
`mise -C ~/.config/mise run local:voiceink-build` only after the source is
committed and clean, the checked-in package lockfile and existing package
checkouts are present, and the Whisper framework is already built. The task
uses `LocalBuild.xcconfig`, the local entitlements, the existing package
checkouts, Xcode's package/macro validation flags, and the current app's Apple
Development identity. It stages the app under
`~/.local/state/voiceink/staged/<source-revision>` and refuses to overwrite a
different artifact at that path. It does not fetch or merge source, resolve new
package versions, install or launch VoiceInk, or touch preferences, transcripts,
recordings, downloaded models, or Parakeet Unified. Live app and Parakeet checks
remain separate from this build task.

Capd is owned by `https://github.com/EzraCerpac/capd`,
with `main` as the install source.
The working checkout at `~/Projects/capd` remains available for development
and is not used as the update source.
Run `mise -C ~/.config/mise run local:capd-update` to fetch `origin/main` into a
task-owned temporary checkout, build it, and install it with rollback.
The command does not move local bookmarks or integrate upstream.
Use `local:capd-build` to create a signed stage without installing it.
On macOS workstations, `dots up` runs this same updater after the declared tool
updates. It checks fork `main` and exits without signing, building, or restarting
Capd when the installed app has matching provenance and a valid signature.
NAS updates skip the workstation-only app updater. The explicit build task still
stages a fresh build when requested.

The fork packaging script uses SwiftPM's `swiftbuild` engine,
preserves the locked dependency resolution,
packages the app without making a release DMG,
and records the repository, branch and full source revision in the app's
`Info.plist`.
The task checks that provenance before staging.
The signing identity comes from the installed app or `CAPD_CODESIGN_IDENTITY`;
on a new host, supply an existing identity explicitly.
The stage is stored under `~/.local/state/capd/staged/`
and includes a matching `BUILD-INFO` record.
`CAPD_STAGE_ROOT` can override the staging path.

Install a stage created by `local:capd-build` explicitly with
`mise -C ~/.config/mise run local:capd-install -- /absolute/path/to/stage`.
The install task accepts only a stage marked as `EzraCerpac/capd` `main`
and checks that its app metadata matches the recorded revision.
It removes copied Finder extended attributes before signature validation.
It stops the app and its loaded `dev.jxd.capd.agent`,
copies the whole `~/Library/Application Support/capd` directory after both
writers exit, exports preferences,
and retains the previous app, CLI link and LaunchAgent under
`~/.local/state/capd/backups/`.
It replaces `/Applications/capd.app`, links `~/.local/bin/capd` to the bundled
CLI and restores the prior running state.
Any install or restart failure restores the previous app, data and preferences.
After launching the app, the task requires its process to remain alive for
three seconds; an immediate startup crash also triggers rollback.
If stopping or rollback fails, the task reports the retained backup for repair.
Set `CAPD_BACKUP_ROOT` only when choosing another private backup location.

`vendor-apps.tsv` records Capd as managed by `local:capd-update`.
The workstation `dots up` stage and Capd's in-app update action both invoke
that updater, which builds and installs the current fork `main` revision only
when needed.
The old cask receipt and `/opt/homebrew/bin/capd` link were moved into the
original rollback backup after the live app, agent and capture checks passed;
no cask uninstall was run.
The original release and library remain in the host's private
`~/.local/state/capd/backups/` directory.

The first switch from the release certificate to the local signing identity required
removing the stale Capd app entry from macOS Device Control and Data Access, then
adding `/Applications/capd.app` again. Toggling the old entry was insufficient.
Subsequent builds retain the same designated signing requirement.

The CerpacNAS modern Git installer keeps the existing user-space recipe. It
does not upgrade system Git, install system packages, or alter NAS services.
Re-running it explicitly asks micromamba to reconcile `git>=2.41` in the same
user-space prefix.

Brooklyn and MacTeX are named installer exceptions that need Homebrew. The
workstation pre-packages hook runs `local:ensure-homebrew-exceptions` first. It
checks Homebrew in `PATH` and the standard `/opt/homebrew` and `/usr/local`
prefixes, then exits without changes when it finds a working installation. On
a fresh Mac without Homebrew, it downloads the official
[Homebrew/install revision](https://github.com/Homebrew/install/commit/8949852f785a3bacaba2a979d0790337950b0a4a),
checks SHA-256
`25548e1da7930c1563dbbe2cb05834a4131c4da09234540b6fdac812fda3c287`, and only
then runs it with normal interactive macOS admin prompts. It fails before
download in non-interactive environments and never installs or updates
packages itself.

The Antinote bridge build requires macOS and the checked-in source file. Its
output and build marker stay outside the source checkout. The NAS static `jw`
release task supports x86-64 Linux only; other NAS architectures need a separate
verified artifact before installation.

Register the finish task with a direct path derived from the selected setup
directory, without starting another mise process from the hook:

```toml
[bootstrap.hooks]
post-dotfiles = 'bash "${MISE_CONFIG_DIR:-$HOME/.config/mise}/setup-scripts/local/finish-dotfiles.sh"'
```

Mise runs this hook after dotfile apply, including during `mise bootstrap`, and
before later defaults and tools steps. The task is repeatable and does not
restart apps or services.

## Legacy hook map

The source checkout currently contains 17 numbered `run_once`, `run_onchange`,
and `run_after` scripts. Their replacement responsibilities are:

| Legacy hook | Mise replacement |
| --- | --- |
| `run_after_03-reconcile-tools.sh.tmpl` | `[tools]`, `[bootstrap.packages]`, and one named installer exception for each remaining unsupported app. Do not reintroduce broad reconciliation or pruning. |
| `run_after_10-enable-touchid-for-sudo.sh.tmpl` | Explicit `local:touchid-sudo`. |
| `run_after_25-configure-gitlogue-screensaver.sh.tmpl` | Native current-host `com.apple.screensaver.idleTime = 0`. Do not restart Hammerspoon as part of dotfile application. |
| `run_after_26-sync-jj-waltz-skill.sh.tmpl` | An explicit task that calls the deployed `codex-sync-jj-waltz` helper. Do not sync it during bootstrap or routine updates. |
| `run_after_27-install-herdr-plugins.sh.tmpl` | Explicit `install:herdr-plugins`, pinned to the four current commits; install the Herdr binary through its own package owner. |
| `run_after_30-setup-cliproxyapi.sh.tmpl` | Native CLIProxyAPI package declaration, then separate `local:cliproxy-configure` and `local:cliproxy-service` tasks. |
| `run_after_setup-shell.sh.tmpl` | Explicit `local:shell-select`; supported workstation and NAS profiles select Fish through native `bootstrap.user` settings. |
| `run_once_01-setup-directories.sh.tmpl` | Profile-specific directory setup plus the rendered Git configuration. |
| `run_once_02-install-package-managers.sh.tmpl` | Standalone mise installation is a bootstrap prerequisite. Homebrew remains the native package manager; ChezMoi is retired. |
| `run_once_03-install-tools.sh.tmpl` | `[tools]`, `[bootstrap.packages]`, and named installer exceptions. |
| `run_once_04-setup-macos.sh.tmpl` | Native macOS defaults for the existing Dock, Mission Control, screenshot, keyboard, and Show Desktop values. The hot-key declaration patches only `AppleSymbolicHotKeys[36].enabled`, preserving its parameters and sibling entries. Do not restart Dock, SystemUIServer, or `cfprefsd` automatically. |
| `run_once_07-remove-legacy-kbd-commands.sh.tmpl` | One-time migration cleanup for the listed obsolete keyboard commands, outside bootstrap and routine updates. |
| `run_onchange_03-install-packages.sh.tmpl` | Native `[bootstrap.packages]` declarations with platform restrictions. |
| `run_onchange_05-configure-mission-control.sh.tmpl` | Native Mission Control default for top-edge window drag; no Dock restart. |
| `run_onchange_05-install-nas-git.sh.tmpl` | Explicit `install:nas-modern-git`, preserving the pinned micromamba user-space recipe. |
| `run_onchange_06-build-jj-waltz.sh.tmpl` | Locked isolated main build for existing workstation `jw` during `dots up`; checksum-pinned explicit release install on NAS. |
| `run_onchange_07-build-antinote-bridge.sh.tmpl` | Explicit `local:antinote-bridge-build`; output and marker stay outside the source checkout. |

Directory setup and native macOS defaults must preserve their observed values.
The keyboard cleanup and jj-waltz skill sync remain one-time or explicit
operations; neither belongs in `setup:update`.

The two defaults formerly missing from the workstation profile are represented
by mise 2026.9.7's typed `defaults_entries`: the screensaver timeout is scoped
to the current host, and the Show Desktop hot-key change patches only its
`enabled` field. This preserves the existing screensaver module, hot-key
parameters, and other shortcuts without a separate script or preference-daemon
restart.
