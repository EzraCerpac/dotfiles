# Explicit setup tasks

These tasks replace setup hooks that used to run during dotfile application.
They do not run as part of ordinary bootstrap or `setup:update`. Invoke them
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
| `setup-scripts/install/jw-build-install.sh` | Local jj-waltz build hook | Builds `~/Projects/jj-waltz` with Cargo's lockfile and installs the verified `jw` binary in `~/.local/bin`. |
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
| `setup-scripts/local/ensure-homebrew-exceptions.sh` | Brooklyn and MacTeX prerequisites | On workstation macOS only, installs Homebrew if absent using a checksum-pinned official installer; it does not install or update packages. |
| `setup-scripts/local/finish-dotfiles.sh` | Post-dotfiles permissions | Verifies private modes after file application; workstation and DelftBlue only. |
| `setup-scripts/local/private-permissions.sh` | SSH template preparation and explicit permission repair | Before dotfile apply, sets the SSH template source to `0600` so mise renders `~/.ssh/config` with the same mode and reports it as applied. After apply, sets `~/.ssh` and `~/.config/jj` to `0700`, the rendered SSH config to `0600`, and regular jj config copies to `0600`. It skips declared public-source symlinks and refuses directory or SSH-target symlinks. |

## Operational boundaries

`setup:update` does not build local Aegis or Rift. It does not restart CLIProxyAPI,
change the login shell, change sudo PAM settings, update Herdr plugins, or
provision keyboard hardware. Those are explicit tasks or separate lifecycle
operations.

The current desktop uses AeroSpace and Aegis. Rift stays inactive by default;
its activation path can replace the active manager and load its LaunchAgent. The
Rift LaunchAgent source must remain valid XML, and a cutover should retain the
current inactive state until a deliberate manager handoff.

The AeroSpace task stages the active custom `0.21.3-PR2245-Local` build from
clean source commit `0c0671cc593a556a1627a10aee601671e6cbeb3e` in
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
| `run_onchange_06-build-jj-waltz.sh.tmpl` | Explicit locked source build on workstation and checksum-pinned release install on NAS. |
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
