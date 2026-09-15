# mise dotfiles migration

The current daily interface is `dots`; see the [worked examples](../README.md).
The base now supplies the shared shell, editor, pagers, and CLI configuration.
Workstation and NAS are additions to that base. The DelftBlue selector is retired
and rejects bootstrap; the historical rollout notes below describe its earlier
preservation and tests, not an active supported profile.

The native mise setup is live on the Mac, with acceptance still staged.
CerpacNAS is unreachable; leave all NAS state unchanged and do not retry until
network access returns. A fresh Fedora 44 ARM64 bootstrap and reapply passed,
including all 67 native tools and the typ2docx installer exception. The Arch check
was incidental and Ubuntu testing was canceled; no three-distribution matrix is claimed. Seven
native-history tests and production restore integration passed; these checks do
not establish machine cutover.

## Source and state

| State | Location or owner | Purpose |
| --- | --- | --- |
| Public setup source | `~/.config/mise`, cloned from `EzraCerpac/dotfiles` | Mise configuration, tasks, symlink sources, and templates. Ordinary source history is JJ-managed. |
| Private machine settings | Native mise history repository `dotfiles-state` | Separate Git history for encrypted, exact-file settings; distinct from the JJ-managed public source. |
| Protected rollback snapshot | `~/.local/state/mise-migration/latest/` | Local archives of the original checkout and managed live files, with metadata for modes and links. |

The public source and native mise history have different jobs and different histories. Do not put live application state or credentials in the public source repository. `encrypted/` contains ciphertext for the WakaTime and Himalaya configuration files; `setup:secrets` decrypts and installs those files. This is separate from native history enrollment: exact app-written regular files stay at their normal paths and are tracked in encrypted private history. Other application state remains owned by its application.

## Bootstrap and machine role

Use mise 2026.9.7 or newer before adopting the source repository. On a fresh Mac, run bootstrap from an interactive terminal. Its pre-packages hook installs Homebrew automatically when missing and may request normal macOS administrator approval. A noninteractive run with no Homebrew stops with instructions to retry in a terminal. Select the workstation role explicitly:

```sh
mise -E workstation bootstrap --adopt https://github.com/EzraCerpac/dotfiles.git
```

On a fresh NAS host (including Intel macOS, where the base tools and brew
formulae now also cover `macos/x64`), select the nas role explicitly. The
bootstrap hooks derive `SETUP_PROFILE` from the `-E` selector, so no manual
export is needed before this first command:

```sh
mise -E nas bootstrap --adopt https://github.com/EzraCerpac/dotfiles.git
```

The adoption behavior used by this migration requires that minimum version. Native `--adopt` refuses an existing nonempty `~/.config/mise` unless it is already a Git checkout matching the requested origin. Keep existing package-manager installations during the staged handoff; do not prune undeclared packages as a migration shortcut.

This fresh-machine command is not a command to rerun on the Mac. Its native mise
source and standalone binary are live there; see [Mac cutover progress](#mac-cutover-progress).
Keep remaining app transfers staged and individually reviewed. Do not run
`--adopt` over the existing setup, run a broad bootstrap, or transfer casks as
part of a source replacement.

The final setup root is `~/.config/mise`. Use `tasks/bootstrap/profile` to persist exactly one explicit role and stable host ID in the ignored local `miserc.toml` and `config.local.toml`: `workstation`, `nas`, or `delftblue`. The role is never selected from a hostname. Keep private history connection details and machine-local values in ignored local mise configuration. See [docs/history.md](history.md) for exact-file enrollment.

`tasks/bootstrap/enroll-history` prepares encrypted exact-file tracking locally. It does not create a checkpoint or contact the private remote; review the selected paths and recipients before the first save.

## Intended daily workflows

Run setup tasks from the setup root so mise reads its configuration and role:

```sh
dots status
dots up
dots backup
dots restore
```

| Need | Native mise workflow | Effect |
| --- | --- | --- |
| Inspect machine setup | `dots status` | Reports selected profile, declared packages and tools, dotfiles/history, and installer exceptions. |
| Update declared setup | `dots up` | Saves local settings before and after updates. On Mac, Homebrew formulae, casks, and Mac App Store packages run as independent stages; later stages still run after a stage failure. The task does not prune software, update project dependencies, publish source, or restart services. DelftBlue rejects this task pending its restricted workflow. |
| Edit an ordinary linked file | `mise -C ~/.config/mise bootstrap dotfiles edit <target>` | Opens the native linked target, which is the source file. |
| Edit and apply a template | `mise -C ~/.config/mise bootstrap dotfiles edit --apply <target>` | Edits the Tera template and applies the rendered target. |
| Add a global symlink | `mise -C ~/.config/mise bootstrap dotfiles add --mode symlink -g <target>` | Adds a link shared across profiles. |
| Add a profile-specific symlink | `mise -C ~/.config/mise bootstrap dotfiles add --mode symlink --path ~/.config/mise/config.<profile>.toml <target>` | Writes the entry to that profile's configuration file. Replace `<profile>` with `workstation`, `nas`, or `delftblue`. |
| Publish private settings | `dots backup` | Saves local settings and explicitly publishes native mise history. Network publication is manual. |
| Restore private settings | `dots restore` | Fetches first, reviews status, applies native conflict checks and the initial remote checkpoint, refreshes host enrollment, and secures tracked files. It never publishes local defaults. |
| Replace an unconnected local history store | `dots restore --initialize-history` | Use only after inspecting the store and choosing to replace it. The task stages and validates the remote clone, then moves the old store to a protected sibling backup. |

`setup:secrets` handles only the WakaTime and Himalaya ciphertext for the workstation profile. It validates decrypted content and installs regular files with mode `0600`; it is not native history enrollment or a general app-state backup. Enroll exact app-written files separately with `tasks/bootstrap/enroll-history`.

The Mac update runs Homebrew formulae, Homebrew casks, and Mac App Store packages
independently, then declared mise tools and named exceptions. With no cached
administrator authorization, a noninteractive run defers the Mac App Store
stage and continues. An interactive run can prompt through `sudo -v`. A deferred
stage is not a failure; updater failures are collected and make the final task
result nonzero.

Recovery starts in fetch-only mode and uses native rollback checks to materialize the first remote checkpoint. After the files arrive, `setup:restore` refreshes the current host's encrypted exact-file enrollment and reapplies mode `0600`. Mise shares permission metadata across host variants, so every host variant of an enrolled logical path must use the same `0600` mode. Git, Node, and the age identity must already be available; restore does not install prerequisites. Do not save or publish until the task completes successfully.

Use `--initialize-history` only when an existing local mise history store is not connected to the configured private repository. The task keeps the old store in a `repo.git.pre-restore.*` sibling directory with mode `0700`; retain it until the recovered history is reviewed. The flag is not needed for a machine with no local history store.

## Mac cutover progress

Status as of 2026-09-15.

The Mac uses the JJ-backed mise source and standalone mise binary. The source
manages 254 configuration files after retiring the two PyCharm helpers; 14 exact-file settings are tracked in encrypted
history. The local watcher captures edits automatically, while sync and push
remain manual. Mac backup, private push, and host identity checks are complete.

44 redundant Homebrew formulae were retired after fresh Fish resolution checks
and full keg clones; required dependency runtimes remain. Three Nerd Fonts,
Mattermost, and 17 direct-app adoptions are complete. Cotabby and JabRef passed
launch and signature checks. OrbStack, CodexBar, Cotabby, JabRef, Crisp,
Hammerspoon, Homerow, MiddleClick, and Raycast were transferred without `--zap`
and passed launch/signature checks. Hammerspoon also loaded its config and
reported Accessibility enabled. The user-requested `vibez` VM removal succeeded
with `orbctl delete --force`; the later OrbStack listing was empty.

Antinote and OmniDiskSweeper use named Homebrew exceptions after explicit
installer licence approval. The native mise disk-image extractor cannot answer
their licence prompts; Homebrew handles these installers under `setup:update`.
Antinote 2.1.2 was adopted, and OmniDiskSweeper was installed at 1.16; both
passed signature checks and were running successfully. Blender transferred to 5.2.1 with launch and signature checks.
Logic Pro and de Volkskrant remain Apple-account exceptions because mas does not
recognize the installed receipts. PyCharm's declaration and helpers were removed; its app remains in the
private rollback copy and its preferences were left untouched. Battery, Warp,
and Ollama were removed from the manifest and their stale Homebrew registrations
retired at the user’s request. Settings and model files remain untouched.
WezTerm transferred and reattached to its original Herdr server; all 12 shell
processes survived. Herdr is pinned to 0.8.2 because the 0.9.0 client cannot
attach to that server's private protocol. Change this pin only during an
intentional terminal-session restart.

The Audio and VLM UV exceptions now use mise Python 3.13.15 while preserving
their original extras and explicit dependencies. All 12 commands passed help
checks. Five obsolete UV environments were moved into protected rollback
storage, and the two unused native MLX installs were removed.
Eight old Cargo installations and nine old global npm packages were retired
after replacement checks and backups. Rust proxies, global npm, the linked
Portless project, and project dependencies remain intact.

Crisp's uninstall removed its launch-at-login registration. It was restored
through macOS Login Items, which now lists Crisp under Open at Login and shows
it running in the background. After restarting, its own launch-at-login setting
also remained enabled. Its display controls work. Physical keyboard,
Homerow, and MiddleClick confirmation is pending.

Zoom, Karabiner-Elements, Tailscale, and SF Pro remain Homebrew updater
exceptions in `setup:update`: mise cannot upgrade the pkg-only auto-updating
casks or the `latest` SF Pro cask. The old Homebrew mise and chezmoi installs
have been removed. Overall Mac acceptance remains open; no pristine-machine test
is claimed.

The canonical Mac `setup:update` run exited 0. Homebrew formula and cask stages
passed; Mac App Store, Zoom, and SF Pro updates deferred for administrator
authorization, while Karabiner and Tailscale deferred because they were running.
Other named exception stages completed or reported their own deferrals. All 27
setup tests passed. `setup:status` exited 0 with the local watcher active and 14
encrypted files tracked; `setup:backup` published successfully. The five thesis
project manifest files remained unchanged. This updater result does not close
the pending physical checks above.

Custom-tap formulas use explicit Homebrew exceptions because the native adapter
misreads their Python helper modules, macOS requirements, or old dependency
aliases. This covers Memo, QMK, Peekaboo, the three pinned keyboard toolchains,
Borders, Hunk, mail-mcp, and typst-time-machine. Each exception updates only its
listed formula. Remindctl moved to the native GitHub backend and retained its
existing Reminders access. Mise uses the existing GitHub CLI credential via a
credential command; it does not store the token in this checkout.

The [direct app inventory](direct-apps.md),
[software ownership inventory](software-ownership.md), and
[cask transfer notes](cask-transfers.md) preserve dated pre-cutover evidence;
use this section for later Mac status.

## Migration status

This table reports observed readiness separately from the intended workflows above.

| Area | Current status |
| --- | --- |
| Mac workstation | Native source is live; canonical `setup:update` exited 0 with explicit deferrals. Seventeen direct-app adoptions and the WezTerm transfer are complete; overall acceptance remains staged. |
| CerpacNAS | Network is unavailable. Defer all NAS work and leave its configuration and live state unchanged until network access returns. |
| DelftBlue | The cluster has not been deployed. Existing `.bashrc` and `.bash_profile` conflicts require explicit review and targeted deployment; the profile does not auto-adopt skeleton files. |
| Linux profiles | Fresh Fedora 44 ARM64 bootstrap and persisted-role reapply passed, including shell/tool checks and private-file permissions. Its task container was removed. The Arch check was incidental; only Fedora is the required baseline. |
| Private mise history | Mac exact-file enrollment, backup, and private push are complete; the local automatic watcher and edit capture passed checks. NAS history setup is deferred. Use `--initialize-history` only for a reviewed, unconnected local store. |
| Source/profile fixtures | JJ identity is fixed, and all three profile fixture apply/reapply checks pass. Fixture results do not establish DelftBlue cluster deployment. |
| Mac inventories | The pre-cutover snapshot recorded 99 Homebrew formula receipts; 44 redundant formulae have since been retired. The [direct app inventory](direct-apps.md) remains the dated bundle snapshot. |
| Grok CLI | Explicitly pinned to `1.0.4` because native registry latest-version discovery is unavailable; release changes require an intentional pin update. |
| Host identity | Mac role, stable ID, and encrypted enrollment are complete. NAS host enrollment is deferred while it is unreachable. |
| Rollback snapshot | Protected local snapshot is available at `~/.local/state/mise-migration/latest/`. |

## Rollback

The snapshot contains `source.tar.gz` for the original setup checkout, including its `.git` and `.jj` data, and `live.tar.gz` for managed live files plus the existing `~/.config/mise`. `live-metadata.json` records file modes and links. There is no automatic rollback executable.

If rollback is needed, keep package and application ownership intact while restoring files:

1. Stop native mise watchers or scheduled setup runs, and save any new settings that must be retained.
2. Inspect the archive contents and `live-metadata.json` before restoring anything.
3. Remove only symlinks created by the mise migration, then selectively restore the original managed files. Reuse the preserved legacy checkout; do not overwrite its `.git` or `.jj` directories from the archive, since other work may have changed that repository since the snapshot.
4. Restore the previous manager's entry points and configuration as a separate step. Reconcile package or application ownership one item at a time; leave installed packages in place until their prior owner is working again.

Do not extract either archive broadly over a live home directory: active applications and managers may own paths in the same tree. Keep the protected snapshot until all target machines and the private-history recovery path pass acceptance.

The published tag `legacy/chezmoi-2026-09-14` preserves the initial chezmoi file tree. DelftBlue remains on its existing setup; do not run a cluster `chezmoi update` against the converted `main` branch.

### Shared-base follow-up validation

The short `dots` interface and base/profile composition have focused fixture
coverage. Fedora 44 ARM64 additionally ran the new locked Hunk 0.22.0,
Diffnav 0.10.0, Eza 0.23.5, and Delta 0.19.2 binaries; Hunk also displayed a
synthetic Git diff successfully. This checks the added Linux pager binaries,
not a fresh full workstation bootstrap or CerpacNAS compatibility. The test
container was removed and the pre-existing PostgreSQL container was preserved.
