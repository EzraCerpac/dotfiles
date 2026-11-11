# Legacy chezmoi hook map

Historical record of the 2026 move from chezmoi to native mise.
The current tasks are in [Explicit setup tasks](../lifecycle.md).

The chezmoi source checkout contained 17 numbered `run_once`, `run_onchange`,
and `run_after` scripts. Their replacement responsibilities are:

| Legacy hook | Mise replacement |
| --- | --- |
| `run_after_03-reconcile-tools.sh.tmpl` | `[tools]`, `[bootstrap.packages]`, and one named installer exception for each remaining unsupported app. Do not reintroduce broad reconciliation or pruning. |
| `run_after_10-enable-touchid-for-sudo.sh.tmpl` | Explicit `local:touchid-sudo`. |
| `run_after_25-configure-gitlogue-screensaver.sh.tmpl` | Native current-host `com.apple.screensaver.idleTime = 0`. Do not restart Hammerspoon as part of dotfile application. |
| `run_after_26-sync-jj-waltz-skill.sh.tmpl` | An explicit task that calls the deployed `codex-sync-jj-waltz` helper. Do not sync it during bootstrap or routine updates. |
| `run_after_27-install-herdr-plugins.sh.tmpl` | Retired: Herdr is archived (`archive/herdr/`). |
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
