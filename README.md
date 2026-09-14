# Dotfiles

Personal dotfiles managed with mise's native `bootstrap dotfiles` workflow. The source checkout is `~/.config/mise`, from `EzraCerpac/dotfiles`. Supports Apple Silicon macOS, Linux workstations, CerpacNAS, and DelftBlue; Intel macOS is intentionally unsupported.

## Quick Start

Install mise 2026.9.7 or newer before using the native dotfiles adoption flow. Select the machine role explicitly in the local `~/.config/mise/miserc.toml`: `workstation`, `nas`, or `delftblue`. The role is never inferred from the host name. See the [migration and setup guide](docs/migration.md) for adoption, daily commands, history, and rollback.

The current macOS window workflow is documented in [CONTEXT.md](CONTEXT.md). Herdr's settings and shortcuts live in [its configuration](dotfiles/.config/herdr/config.toml).

For local prose cleanup, see the [humanize-text runbook](docs/humanize-text.md). Run `humanize-text configure` once, then use `humanize-text FILE.typ` or `humanize-clipboard`.

## What's Included

**Shell**: fish, starship prompt, atuin history, zoxide, fzf, carapace completions

**Editor**: neovim (LazyVim)

**Dev Tools**: git, gh, jj/jjui, lazygit, gitui, worktrunk, diffnav, node, rust, uv, delta, ripgrep, fd, bat, eza, jq, yazi, tmux, gum

**macOS**: AeroSpace, Aegis bar and switcher, JankyBorders, Karabiner, Raycast, WezTerm; Rift remains an explicit optional local build.

## Tool and setup management

`~/.config/mise` is the setup root and source checkout. Shared configuration lives in `config.toml`; the explicit role files are `config.workstation.toml`, `config.nas.toml`, and `config.delftblue.toml`. For workstation and NAS, `setup:update` upgrades declared packages and tools without pruning undeclared installations. DelftBlue's update task stays disabled pending its restricted workflow. Use the task entry point for routine setup work:

```sh
mise -C ~/.config/mise run setup:status
mise -C ~/.config/mise run setup:update
```

Dotfile source and private settings history have separate repositories and histories. `EzraCerpac/dotfiles` is ordinary JJ-managed source; native mise history uses a separate private Git repository named `dotfiles-state`. `setup:backup` is the explicit network publication path. `setup:restore` fetches first, restores tracked state, refreshes host enrollment, enforces mode `0600`, and never publishes local defaults.

The [software inventory](docs/software-ownership.md) records the pre-cutover tools; [migration status](docs/migration.md#mac-cutover-progress) records the live handoff. Custom Homebrew formulae and unsupported casks have named installer exceptions under the same update command. Grok CLI remains pinned to `1.0.4` because the native registry cannot discover its latest release; upgrading requires an intentional pin change.

For authenticated GitHub downloads, mise reads the existing `gh auth login`
credential through a credential command. Tokens stay in the system credential
store. Interactive updates can request administrator authorization for the
package exceptions; noninteractive runs report those items as deferred.

See [docs/migration.md](docs/migration.md) for recovery steps and current acceptance status.

Review defaults:

- `git diff` opens in `diffnav --side-by-side`
- `git show` and embedded diff views use `delta --side-by-side --paging=never`
- `wt` is declared in the workstation profile and initialized in fish
- `jw` is built from the local `~/Projects/jj-waltz` checkout and shell-initialized in fish and zsh
- `jj-waltz` skill content is linked from this source checkout to both `~/.codex/skills/jj-waltz` and `~/.config/opencode/skills/jj-waltz`
- `wto <branch> [prompt...]` creates or switches a worktree and launches `opencode`
- `prdiff [pr]` opens `gh pr diff` output in `diffnav`
- `glf [git-log-args...]` selects a commit and replays it in `gitlogue`
- `gitlogue-menu` selects a Gitlogue mode, author, date range, commit, or theme

## Source layout

| Path | Purpose |
| --- | --- |
| `config.toml` and `config.<role>.toml` | Shared mise configuration, tasks, and explicit machine profiles |
| `dotfiles/` | Native symlink sources; editing a linked target edits this source |
| `templates/` | Files rendered with Tera when `edit --apply` or apply is requested |
| `tasks/setup/` | Status, update, backup, restore, and encrypted app-state tasks |
| `tasks/install/` and `tasks/local/` | Explicit install and machine lifecycle tasks |
| `encrypted/` | Existing age-encrypted WakaTime and Himalaya sources; private settings history is stored separately |

The role selection and private history origin belong in ignored local mise configuration, not in the public source repository.

## Keyboard Workflow (Corne + QMK)

Keyboard source lives at `~/.config/keyboard/corne-qmk` and syncs into a local `qmk_firmware` checkout at `~/Projects/keyboards/qmk_firmware`.

Commands:

- `kbd provision` → validate setup prerequisites, prepare QMK, activate VirtualHID, and install the Kanata daemon
- `kbd doctor` → diagnose macOS Kanata/Karabiner runtime, TCC grants, and duplicate VirtualHID daemons
- `kbd sync` → copy keymap source into `qmk_firmware`, regenerate layout images, and reload HUD
- `kbd build` → build `crkbd/rev1:ezra_corne` (`rp2040_ce` by default)
- `kbd build-all` → build both `rp2040_ce` and `sparkfun_pm2040`
- `kbd build --left` / `kbd build --right` → build convenience left/right-tagged UF2 artifacts
- `kbd flash left` / `kbd flash right` → authoritative split-handedness flash flow (`uf2-split-left/right`)
- `kbd layout-images` → regenerate JSON/YAML/SVG/PNG layer images from `keymap.c`
- `kbd hud-reload` → reload Hammerspoon HUD overlay
- `kbd open-artifacts` → open UF2 artifact folder in Finder

`kbd provision` is an explicit lifecycle task; it may request `sudo`. If macOS needs DriverKit, Input Monitoring, or Accessibility approval, the command stops with the exact System Settings action. Complete that action, then rerun the same task; finished stages are safe to repeat.

Run keyboard tasks from the setup root so mise loads the selected profile:

- `mise -C ~/.config/mise run kbd_provision`
- `mise -C ~/.config/mise run kbd_sync`
- `mise -C ~/.config/mise run kbd_build`
- `mise -C ~/.config/mise run kbd_build_all`
- `mise -C ~/.config/mise run kbd_build_left`
- `mise -C ~/.config/mise run kbd_build_right`
- `mise -C ~/.config/mise run kbd_flash_left`
- `mise -C ~/.config/mise run kbd_flash_right`
- `mise -C ~/.config/mise run kbd_hud`
- `mise -C ~/.config/mise run kbd_images`

## Adding/Editing Configs

Edit ordinary symlinked files at their native target; the target is the tracked source. Edit a Tera template with `--apply` to render and deploy the result. Add globally shared links with `-g`, or scope an entry to a profile:

```bash
mise -C ~/.config/mise bootstrap dotfiles edit ~/.config/fish/config.fish
mise -C ~/.config/mise bootstrap dotfiles edit --apply ~/.config/atuin/config.toml
mise -C ~/.config/mise bootstrap dotfiles add --mode symlink -g ~/.config/new-app/config.yaml
mise -C ~/.config/mise bootstrap dotfiles add --mode symlink --path ~/.config/mise/config.workstation.toml ~/.config/new-app/config.yaml
```

Change `workstation` to `nas` or `delftblue` for a profile-specific entry. Use `setup:update` for declared package/tool updates; it does not publish source or restart services.

## Cross-Platform Notes

- Intel macOS is not supported; macOS package declarations target Apple Silicon
- OS and profile variants select the appropriate files and package declarations
- Tera templates provide small machine-specific values; ordinary linked files remain directly editable
- The `workstation`, `nas`, or `delftblue` role must be selected explicitly in local mise configuration

## CerpacNAS Remote Codex

The explicit `nas` profile describes shared configuration and user-space tools. Coordinate NAS work from a Mac task, with separate worker tasks through native Codex Remote SSH. The local `work-on-cerpacnas` skill in `~/.agents/skills/` describes this workflow. Existing `nas`/`cerpacnas` SSH aliases continue to use root. NAS activation is still pending a reachable host and compatibility checks; this README does not claim the profile has been applied there.

## DelftBlue Profile

This repo now supports a conservative `delftblue` profile for TU Delft's cluster.
It is intentionally smaller than the normal Linux workstation setup:

- package-manager bootstrap is skipped
- workstation-heavy config is excluded
- bash stays the default shell
- module-based Julia/MPI helpers are added
- Slurm starter templates live in `~/.config/delftblue/jobs/`
- local SSH and `rsync` helpers are installed via `~/.ssh/config` and `~/.local/bin/db*`

Select `delftblue` explicitly in that machine's ignored local mise configuration. Keep the host's netid, Slurm account, and optional project-storage root in local settings; do not copy them into the public shared configuration. The cluster profile is not cut over or accepted. Existing `.bashrc` and `.bash_profile` files need explicit conflict review and targeted deployment; DelftBlue does not automatically adopt Linux skeleton files.

Important helpers:

- `dbdev-bootstrap`
- `dbdev-install`
- `dbspack`
- `dbdev [command ...]`
- `dbacct`, `dblimits`, `dbjobs`
- `dbcpu [time] [cpus] [mem-per-cpu]`
- `dbgpusmoke [time] [mem-per-cpu]`
- `dbjulia-mpi-init <project-dir>`
- `dbpush`, `dbpull`
- `dbprojectpush`, `dbprojectpull` when `project_storage_root` is set

Important shell functions on DelftBlue:

- `dbmod-julia`
- `dbmod-julia-mpi`

The DelftBlue profile can now also render a cluster-aware Neovim setup and a broader dev shell.
That layer is still explicit and conservative:

- bootstrap the default dev layer with `dbdev-bootstrap`
- run `dbdev-bootstrap` on the login node, because compute nodes do not have outbound internet
- `dbdev-bootstrap` also installs `jj`, `jjui`, `nvim`, `bat`, `zoxide`, and `tv` from pinned release binaries on the login node
- `dbdev-bootstrap` also installs `eza`, `rg`, `fd`, `atuin`, and `carapace` from pinned release binaries on the login node
- `dbdev-install` is now just a compatibility check; the default dev layer is module-first and does not need a compute-node install step
- the DelftBlue Neovim overlay disables Mason-driven installs and Sidekick runtime hooks, so cluster startup stays quiet and does not keep retrying unavailable tools
- `tree-sitter` CLI is optional on DelftBlue and only used when the module system provides it
- if you explicitly want Spack as an extra layer, use `dbdev-bootstrap --with-spack`
- load it only when needed with `dbdev`
- the default DelftBlue bash shell also restores lightweight niceties like `..`, `...`, `v`, `ls -> eza`, and guarded `atuin` / `zoxide` / `tv` init
- a DelftBlue-only `~/.bash_profile` is rendered to source `~/.bashrc`, so those bash customizations appear in fresh login shells
- `Ctrl-R` is assigned to Atuin, `Ctrl-T` to Television shell integration, and `Ctrl-E` to bash's `edit-and-execute-command`
- Television bash integration is generated once into `~/.config/television/shell/integration.bash` and sourced from `~/.bashrc`; `bash-preexec` is installed under `~/.local/share/bash-preexec/` and sourced before `atuin init bash --disable-up-arrow --disable-ctrl-r` so new commands are recorded correctly
- on DelftBlue, Atuin keeps all local SQLite state under `/tmp/$USER/atuin/` instead of the default home-directory path: `history.db`, `records.db`, `meta.db`, `kv.db`, and `scripts.db`
- keys and session remain on persistent home storage
- on DelftBlue, Atuin also uses normal `fuzzy` search and `sync_frequency = "0"` so each command syncs immediately from node-local storage
- on DelftBlue, bash runs a quick integrity check on the local Atuin DB at shell startup and automatically rotates it out if it is not a valid SQLite database
- use `dbatuin-reset` in a DelftBlue bash shell to rotate out malformed local Atuin DBs and repopulate from sync
- use `dbshell-check` in a DelftBlue bash shell to inspect loaded functions and active key bindings
- bash also loads `carapace` as an extra completion bridge when available
- use a visual node only for GPU/CUDA-related setup that needs internet plus a visible GPU
- module availability varies by partition, so `dbdev` only loads tools that actually exist in the current environment
- optional editor-side tools that are not available in the current Spack set are skipped, and the DelftBlue Neovim overlay disables those integrations automatically
- `AGENTS.md` stays in the repo only and is not deployed into `$HOME`

## Herdr terminal workflow

WezTerm is the terminal window; Herdr owns terminal organization and persistence:

- a **session** is one persistent Herdr server containing all local work
- a **workspace** is one project row in Herdr's left sidebar
- a **tab** is one activity inside a workspace
- a **pane** is a visible terminal split inside a tab
- a Rift workspace is a macOS window-management space and is unrelated to a Herdr workspace

Closing WezTerm or pressing `Ctrl-B`, then `q`, detaches the client without stopping pane processes. Opening WezTerm again reattaches to the local default session. Herdr does not pin workspace rows; an open `Remote shells` workspace stays in the sidebar because the session persists.

Useful keys all start with the default `Ctrl-B` prefix:

- `up` / `down`: Herdr Plus Projects / Quick Actions
- `t`: Picker Plus search across agents, remotes, workspaces, projects, sessions, and actions
- `left` / `right`: previous / next workspace
- `Alt-1..9`: switch workspace; `1..9`: switch tab
- `d`: close Herdr workspace; `Shift-d`: remove its `jw` checkout
- `h/j/k/l`: focus panes; `w`: workspace picker; `?`: full key help

Herdr Plus manages the reproducible project layouts under `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`. Use the `Remote shells` project for a local shell and a normal `ssh delftblue` tab. SSH keepalives reduce idle disconnects. DelftBlue still needs `kinit` on the login node when `/tudelft.net` credentials expire.

Picker Plus exposes `CerpacNAS` as a remote Herdr target. Its custom integration clears the inherited `HERDR_ENV` marker before running Herdr's remote handoff, while global nested launches remain disabled. It bootstraps a matching remote binary when needed and opens the NAS server's own persistent sidebar. The NAS session is separate from the local sidebar; detach it with `Ctrl-B`, then `q`.
