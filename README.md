# Dotfiles

Your shell, Neovim, pagers, and everyday CLI tools travel with you. The
workstation profile adds language runtimes, specialist tools, and desktop
applications. `dots` is
the short interface to the setup; ordinary `mise` commands still work inside
individual projects.

## Start a new machine

From a normal interactive terminal, with Git and curl available:

```sh
curl -fsSL https://mise.run | sh && "$HOME/.local/bin/mise" -E workstation bootstrap --adopt EzraCerpac/dotfiles
```

This uses the [official mise installer](https://mise.jdx.dev/installing-mise.html),
clones this repository to `~/.config/mise`, and bootstraps your workstation.
Homebrew is installed automatically on a Mac when needed; its installer can ask
for administrator approval. On a pristine Mac, install Apple's Command Line
Tools if Git prompts for them. Open a new terminal when bootstrap finishes.

Use `workstation` for a normal Mac or Linux development machine. Use `nas` in
place of `workstation` for the smaller NAS role. The choice is saved locally;
you do not repeat it during everyday use. CerpacNAS itself has not been cut over
or tested while its network is unavailable.

Public configuration comes from this repository. Restoring private app settings
also needs the private history credentials and the machine's age key; see
[settings recovery](docs/history.md). Existing nonempty setup directories need
reconciliation before adoption; this command is for a fresh setup.

## Change Fish, then share the change

Suppose you want `croot` to expand to `cd ~/Projects`. Open your normal
`~/.config/fish/config.fish` and add:

```fish
abbr -a croot 'cd ~/Projects'
```

Save it and open a new terminal tab. Type `croot`, then Space, to try it.
The live file links into this repository, so saving already changed the source.
There is no re-add or apply step for an existing linked file. Mac-specific shell
changes belong in `~/.config/fish/conf.d/10-macos.fish` instead.

When you want another machine to receive the shortcut, go to `~/.config/mise`
and inspect `jj diff`. Describe the change, push a `wip/` bookmark, then open and
merge a PR to `main`. For example:

```sh
jj describe -m "feat(fish): add projects shortcut"
jj bookmark create wip/fish-shortcut -r @
jj git push --bookmark wip/fish-shortcut
```

Open the PR on GitHub, or use `gh pr create --web`. Run `jj new` after publishing
to leave an empty change for your next edit. Source changes are never pushed
by the updater or the settings watcher.

On the other already-migrated machine, open its setup checkout and check
`jj status` first. Preserve and reconcile any local edits. With a clean working
copy, fetch with `jj git fetch`, inspect `jj diff --from @- --to main@origin`,
and use `jj new main@origin` when ready to adopt the reviewed revision. The
linked Fish file changes with that checkout; open a new shell to load it.

If the incoming change adds managed files or updates a template, run `dots apply`
to create the links and render the templates. `dots apply ~/.ssh/config` limits
application to that target. It does not upgrade tools. Newly declared tools are
installed by `dots bootstrap`, which applies the full declared machine setup.

## Update this computer

When you want the installed setup brought up to date, run:

```sh
dots up
```

Let it finish and read the result. It checkpoints app-written settings, upgrades
declared packages and tools, runs the named installer exceptions, updates editor
plugins, then updates mise. Tools track the latest stable release by default.
Kanata and Karabiner stay on their known working versions. Herdr is deferred
while its terminal server is running, to avoid breaking open sessions.
Python 3.13 and 3.12 remain available for applications that require them; the
default Python tracks latest. Lockfiles record the installed selections and
advance with `dots up`; they do not impose permanent version caps. It may request an admin
password; running applications or unavailable vendor updaters are reported as
deferred. Close an affected app when convenient and rerun the command.

This does not fetch or publish dotfile source, update project dependencies,
upgrade the operating system, restart services, or prune software. For a look
without changes, use `dots status`.

## Add a tool

Suppose you want Watchexec available everywhere you work on this machine. Run:

```sh
dots add watchexec
```

Mise selects its preferred backend, installs the latest version, and records it
in the active profile: `config.workstation.toml` on your main computer, or
`config.nas.toml` on a NAS. Review the changed manifest and lockfiles in JJ and
publish them when you want other machines with that role to receive the tool.

If the tool belongs in the everyday toolkit on **every** machine, say
`dots add --base watchexec`. That targets the shared `config.toml` instead.
`dots add --profile nas ripgrep` targets the NAS additions without changing this
machine's role. For an explicit file, use
`dots add --path ~/other/config.toml watchexec`.

For a global npm command such as Prettier, use `dots add npm:prettier`.
Mise owns the installation and tracks the latest release. If it is a
project dependency, add it to that project's package.json instead.

For a Cargo CLI, use `dots add cargo:hexyl`. The `cargo:` prefix selects its
source; mise still owns installation and updates. Source builds may take longer
and need a Rust toolchain. The workstation already includes Rust.

For a native Mac library, use `dots add brew:libmagic`; a Mac app looks like
`dots add brew-cask:firefox`. New Homebrew declarations are restricted to macOS
automatically, so they do not become Linux requirements. Existing declarations
keep their options. Unsupported recipes still need a named installer exception;
`dots` reports a backend failure rather than silently changing package managers.

All these commands select `~/.config/mise` before loading configuration. They
work from your thesis checkout or any other directory. An explicit `--path` is
the only way to redirect the write to an arbitrary file. `dots help` explains
the available actions; ordinary project-local `mise use` is unchanged.

## Choose what belongs on a machine

`config.toml` is the shared base: the shell, navigation/search tools, Git/JJ,
GitHub CLI, completions, prompt, Neovim, pagers, and their configuration. Every role
loads it. A NAS therefore receives the same everyday terminal toolkit.

`workstation` adds the full development and desktop setup. It supports Apple
Silicon macOS and glibc Linux x64/ARM64, with explicit OS restrictions on packages
and files. Fedora 44 ARM64 is the tested fresh Linux baseline; Intel Macs are
not supported by this setup.

`nas` adds the NAS-specific configuration and smaller runtime choices. It does
not own DSM updates, storage, media services, or Compose projects. Actual NAS
binary and shell compatibility must be checked when the host becomes reachable.

The DelftBlue profile is retired. Its old configuration remains in repository
history; the cluster and existing SSH access are not changed by this retirement.

## Recover app-written settings

The watcher saves selected app-written files locally in encrypted history.
When you want to publish those snapshots, run `dots backup`. On a replacement
machine, configure the private history connection and key, then follow
[the restore guide](docs/history.md) and use `dots restore`.

This private recovery history is separate from publishing your Fish source or
tool declarations with JJ. Keep age keys outside both repositories. The older
migration backups remain available; see [migration and rollback](docs/migration.md).

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
