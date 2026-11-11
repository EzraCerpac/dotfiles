# Dotfiles

Your shell, Neovim, pagers, and everyday CLI tools travel with you. The
workstation profile adds language runtimes, specialist tools, and desktop
applications. `dots` is
the short interface to the setup; ordinary `mise` commands still work inside
individual projects. The `dots` manager lives in [`manager/`](manager/README.md),
which documents every command; this README covers how this setup uses it.

Run `dots` in an interactive terminal to browse commands and review their options.
Choose Run to execute a command;
its existing terminal prompts remain available.
Advanced arguments are entered one literal token at a time.
Explicit commands such as `dots up` continue to run directly.

`dots status` opens a read-only inventory of the selected machine.
Use `dots reports [COMMAND]` to browse saved runs.
Put shared display options before the command,
for example `dots --plain status` or `dots --no-wait backup`.
The existing `dots up --plain`, `--verbose`, `--no-wait`, and `--last` options
continue to work.

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
you do not repeat it during everyday use. Both roles select Fish as your login
shell, including new SSH sessions. CerpacNAS uses the NAS role; its older Linux
compatibility choices and rollback location are in [the NAS guide](docs/cerpacnas.md).
For the optional macOS concierge services, follow the separate
[concierge setup guide](docs/concierge-nas.md); its runtime sources and private
enrollment must be supplied separately.

Public configuration comes from this repository. Restoring private app settings
also needs the private history credentials and the machine's age key; see
[settings recovery](docs/history.md). Existing nonempty setup directories need
reconciliation before adoption; this command is for a fresh setup.

Before applying a changed setup, run `dots plan` to inspect mise's native plan.
To set up a machine reachable over SSH, use `dots remote my-new-box --profile nas`.
This installs mise and adopts the repository permanently on that host. Use
`--profile workstation` for another development computer. SSH must already work;
Tailscale enrollment cannot provide the initial connection. `--dry-run` still
connects to the host and stages files.

On Fedora, native mise resources install Tailscale from its signed vendor
repository and bootstrap starts its service when systemd is available. Other
Linux distributions currently need the vendor client installed first. Normal
updates do not start services.

The final bootstrap step handles private recovery, installer exceptions, local
builds, JJ initialization, Atuin enrollment, history enrollment, and Tailscale. It prints completed, deferred, and failed
steps. Resolve the reported prerequisite and rerun `dots bootstrap`; it keeps
existing configuration and connected Tailscale identities. It never selects an
exit node or advertises routes. Without an enrollment key, Tailscale uses its
interactive browser login.

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

Up/Down recall commands entered in this shell session. Ctrl-R searches Atuin's
persistent history across sessions. To switch an already open shell to local
recall, run `set -g fish_history ''`; existing saved history is retained.

Run `dots sync` or `dots up` to share ordinary public source edits through `dev`.
Managed live checkouts follow `dev`;
native task worktrees stay separate and are never initialized or published by sync.
`main` remains the reviewed branch.
The settings watcher and encrypted private settings history stay separate.

Sync captures public files, scans them before creating snapshot ancestry,
merges away from the live tree, validates the host configuration with local overlays,
and pushes without force.
Compatible text edits merge.
Conflicting text uses the genuine file save time attached to its content,
with a stable machine identifier breaking ties.
Receiving, merging and reviewing files do not count as saves.
The first import has unknown save times;
conflicts with unknown or implausible timestamps stay pending.
Ambiguous delete-versus-edit keeps edited content;
type conflicts stay pending.
Merge parents retain alternatives, and sync prints commit IDs for recovery:
`git show COMMIT:path/to/file`.

Network or authentication failure leaves a durable local queue and reports
“Saved locally” or “Push pending”.
The next `dots up` retries while useful maintenance continues after deferral.
Secret findings queue publication without putting flagged files in snapshot ancestry.
Private selectors, ignored local lockfiles and app state stay local.

For a one-time migration of an inspected older live checkout,
set `DOTS_ADOPT_DEV_PARENT` to its full current source-parent commit ID
(`jj log --ignore-working-copy -r @- --no-graph -T commit_id`, or Git `HEAD`).
This opt-in applies only before the first managed adoption;
it preserves existing edits and records their observed mtimes as unverified history.
Unset it after adoption.
Historical save-time collisions remain pending.

PR extraction is manual.
Create a focused task branch from `origin/main`,
copy or cherry-pick only the desired change from `dev`,
and review the resulting diff against `main`.
Do not move shared `dev` or merge it wholesale into `main`.
Use `dots publish --bookmark wip/your-task` for a reviewed main-based JJ stack.
`dots publish --all` remains available for private main-based stacks;
it refuses shared dev ancestry.
Publication scans outgoing commits and asks for review confirmation.

On the other machine, run `dots up` to fetch shared `dev`, apply ordinary dotfiles,
and update tools.
Open a new shell to load changed shell configuration.
Use `dots sync` for configuration without software upgrades,
or `dots apply ~/.ssh/config` to render one locally edited template.

Use `dots sync --source-only` to fetch and advance only the reviewed shared source.
It keeps the repository, ancestry, local-edit and concurrent-change guards, and
checks the incoming public source and minimum mise version through an isolated
stored-value TOML read of the public incoming config. It does not copy or
save private settings, render/apply dotfiles, run bootstrap hooks, or upgrade tools.
It uses the existing selected mise environment to run the synchronizer, with
automatic installs, updates and hooks disabled for that invocation.
Existing symlinks immediately reflect changes to their source files, so source
advancement can still change configuration read by applications. Private selector
files and ignored local lockfiles stay in place; legacy tracked-lock migration
requires ordinary `dots sync`. Incoming ignore rules must protect local selectors
and lockfiles. If settings change during advancement, the previous source revision
is restored when the new child is still empty; concurrent public edits are retained
for manual reconciliation. Run ordinary `dots sync` when deployment is wanted.
For an exact reviewed revision, set `DOTS_EXPECTED_MAIN` to its full commit ID when
running source-only sync. The wrapper captures that value before mise selects its
environment; a changed remote main then defers before advancement.

Unrelated task history and concurrent edits are preserved.
When safe adoption is deferred, `dots up` reports “source sync deferred”
and continues maintenance using the current configuration.
The sync backend returns status 3 for deferral;
the updater completes successfully if its remaining stages succeed.
No command force-pushes, rebases a task, or writes conflict markers into live files.

## Update this computer

When you want the installed setup brought up to date, run:

```sh
dots up
```

Mac App Store updates are skipped by default. On a macOS workstation, use
`dots up --mas` to include them; this may request administrator authorization.
The flag has no effect on other platforms or profiles.

Let it finish and read the result. It synchronizes the shared source, checkpoints
app-written settings, installs newly declared packages and tools, runs upgrades
and named installer exceptions, updates editor plugins, then updates mise. Tools track the latest stable release by default.
Kanata and Karabiner stay on their known working versions.
Python 3.13 and 3.12 remain available for applications that require them; the
default Python tracks latest. Setup lockfiles stay local and ignored: they record
this host’s resolutions without creating source changes after each update. Tool
choices and intentional version holds remain tracked; project lockfiles are unaffected. It may request an admin
password; running applications or unavailable vendor updaters are reported as
deferred. Close an affected app when convenient and rerun the command.

This does not publish dotfile source, update project dependencies,
upgrade the operating system, restart unrelated services, or prune software. For a look
without changes, use `dots status`.

HouseAtlas maintenance is a separate, deliberate caller, the configuration
command [`dots/commands/houseatlas`](dots/commands/houseatlas):
`dots houseatlas check`, `dots houseatlas apply`, or
`dots houseatlas status`. These currently
return **unavailable**, exit 3, and send no request. They do not read stdin,
load mise, synchronize source, install a runtime or run package updates.
Unsupported actions/options exit 2. Ordinary `dots up` never invokes HouseAtlas.

The source adapter uses HouseAtlas's existing fixed `MaintenanceOwner.call`
check/apply/status tools, preserving the original bounded UTF-8 request and
updater result. It supplies no transport, credentials or maintenance authority.
Check can stage bytes; `ok=true` means handled, and phase, `healthVerified` and
`recoveryNeeded` determine the outcome. One caller permits at most one apply
attempt, even when its response is lost. Thereafter it allows only status for
that original operation ID; it never retries apply or creates another ID.
Historical success is not fresh installed evidence.

Before enabling an installed binding, the HouseAtlas owner must qualify the
shared controller, durable operation reconciliation across caller restarts,
target and action-time authorization. The CLI deliberately has no environment
override, endpoint option, dynamic import or shell-installer fallback.
[dotfiles #64](https://github.com/EzraCerpac/dotfiles/issues/64) tracks this caller;
[HouseAtlas #290](https://github.com/EzraCerpac/HouseAtlas/issues/290) owns the
controller/API/MCP/app contract. Claude's HouseAtlas deployment tooling remains
separate and is not invoked by dots.


## Add a tool

Suppose you want Watchexec available everywhere you work on this machine. Run:

```sh
dots add watchexec
```

Mise selects its preferred backend, installs the latest version, and records it
in the active profile: `config.workstation.toml` on your main computer, or
`config.nas.toml` on a NAS. Review the changed manifest and share it with
`dots sync` when you want other machines with that role to receive the tool.

If the tool belongs in the everyday toolkit on **every** machine, say
`dots add --base watchexec`; that targets the shared `config.toml`.
`dots add --profile nas ripgrep` targets the NAS additions without changing this
machine's role. The workstation already includes Rust for `cargo:` tools. For a
project dependency, add it to that project instead.

These commands select `~/.config/mise` before loading configuration, so they
work from your thesis checkout or any other directory. Backends, GitHub release
apps and what happens on failure are described in
[adding software](manager/README.md#adding-software).

## Remove a tool

When you no longer want something, run `dots remove watchexec`. It uninstalls
the software and deletes its declaration from whichever setup config has it;
`--dry-run` shows the plan first. Kanata and Karabiner are held and cannot be
removed this way. See [removing software](manager/README.md#removing-software).

## Choose what belongs on a machine

`config.toml` is the shared base: the shell, navigation/search tools, Git/JJ,
GitHub CLI, completions, prompt, Neovim, pagers, and their configuration. Every role
loads it. A NAS therefore receives the same everyday terminal toolkit.

`workstation` adds the full development and desktop setup. It supports Apple
Silicon macOS and glibc Linux x64/ARM64, with explicit OS restrictions on packages
and files. Intel Mac support has additional backend restrictions and installer
exceptions; availability is checked per tool. See the bootstrap validation notes
for what has actually been tested.

`nas` adds NAS-specific configuration and smaller runtime choices. It does
not own operating-system packages, storage, media services, or Compose projects.
CerpacNAS's Debian 10 compatibility is handled through host-local tool choices;
see [the NAS guide](docs/cerpacnas.md).

The DelftBlue profile is retired; its configuration remains in repository
history. SSH access to the cluster outlived it: to render the `delftblue` host in
`~/.ssh/config`, put your NetID in the ignored local configuration, where it stays
out of this public repository:

```sh
mise config set --file ~/.config/mise/config.local.toml vars.delftblue_netid YOUR_NETID
dots apply ~/.ssh/config
```

## Source layout

| Path | Purpose |
| --- | --- |
| `config.toml` and `config.<role>.toml` | Global mise settings, tools, bootstrap declarations, and machine profiles |
| `dots/` | How this setup plugs into `dots`: update and bootstrap hooks, the `houseatlas` command, installer exceptions and their recipes, history files, retired dotfiles ([reference](dots/README.md)) |
| `setup-tasks.toml` and `setup-scripts/` | Setup tasks, available with `mise -C ~/.config/mise run` without adding them to project task lists |
| `dotfiles/` | Native symlink sources; editing a linked target edits this source |
| `templates/` | Files rendered with Tera when `edit --apply` or apply is requested |
| `manager/` | The `dots` manager, kept free of anything personal: see [its README](manager/README.md) |
| `setup-scripts/setup/` | Editor maintenance helpers and the WakaTime secret installer |
| `setup-scripts/install/` and `setup-scripts/local/` | Explicit install and machine lifecycle tasks |
| `encrypted/` | Age-encrypted private inputs: the workstation bootstrap bundle `bootstrap.workstation.json.age`, the Atuin bundle and WakaTime; private settings history is stored separately |
| `tests/` | This configuration's tests; run them with `dots test` (see [testing](docs/testing.md)) |
| `archive/` | Configuration kept for reference but never deployed, such as Herdr; see its README to restore an entry |

The role selection and private history origin belong in ignored local mise configuration, not in the public source repository.

## More

| Topic | Guide |
| --- | --- |
| Recovering settings, bootstrap bundles, replacement machines | [Recovery](docs/recovery.md) |
| Shared shell history and Atuin login | [Atuin](docs/atuin.md) |
| Editing linked files and templates, cross-platform notes | [Dotfiles](docs/dotfiles.md) |
| Review defaults and shortcuts (`hunk`, `jjui`, `wto`, `prdiff`, `glf`) | [Review tools](docs/review-tools.md) |
| Rex sessions, NAS connections and project launcher | [Rex](docs/rex.md) |
| Corne keyboard and Kanata | [Keyboard](docs/keyboard.md) |
| CerpacNAS and remote Codex tasks | [NAS guide](docs/cerpacnas.md) |
| Cloud proxy access to NAS web services and HouseAtlas | [Cloud NAS access](docs/cloud-nas-access.md) |
| Tests and CI | [Testing](docs/testing.md) |
| Presentation Mode and preserving a running demo (`present showcase`) | [Presentation modes](docs/present.md) |
| Secret scanning, signing, leaked-credential rotation | [Security](docs/security.md) |
| Window managers | [Runbook](docs/window-manager-runbook.md) |
| Settings history internals | [History](docs/history.md) |
| The `dots` manager and its commands | [manager/README.md](manager/README.md) |
| How this setup got here (chezmoi hook map, validation logs) | [Setup history](docs/history/README.md) |
