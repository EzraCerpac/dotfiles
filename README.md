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

When the shortcut is ready to share, run `dots publish` from any directory.
It shows the proposed source diff, scans every commit in it for secrets
(see [security guardrails](docs/security.md)), asks for a short description and
confirmation, then publishes a `wip/` branch and opens a pull request. Review and merge that PR
on GitHub. Source publication is always explicit; the settings watcher and
updater never push your edits.

If you are already working on a private JJ stack, select its bookmark explicitly
with `dots publish --bookmark wip/your-task`. The command will not quietly include
unrelated unpublished commits in the default flow.

Use `dots publish --all` to put every unpublished commit leading to the current
checkout into one PR. It skips an empty working child and leaves other local
heads alone. If `main` advanced, it previews the stack and asks before merging
`main` into it. A conflicted merge stays local for you to resolve; no branch is
pushed until a later run shows and confirms the full final diff. Repeating
`--all` updates the open aggregate PR when one exists.

On the other machine, run `dots up`. It fetches merged `main`, applies the Fish
change and other ordinary dotfiles, then updates tools. Open a new shell to load
the shortcut. If you only want configuration, use `dots sync`; this does not
upgrade software or activate services. `dots apply ~/.ssh/config` remains useful
when you want to render one locally edited template.

Local edits or unpublished history are preserved. When they prevent a safe
source advance, `dots up` says “source sync deferred” and still updates tools
using the current configuration. It returns status 3 for that partial result;
actual failures return status 1. Review or publish the local changes, then rerun
it. Neither command stashes, rebases private work, or resolves conflicts for you.

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
Kanata and Karabiner stay on their known working versions. A running Herdr server
uses its supported live handoff after mise installs the replacement. A failed
handoff is reported for attention; the updater does not kill terminal sessions.
Python 3.13 and 3.12 remain available for applications that require them; the
default Python tracks latest. Setup lockfiles stay local and ignored: they record
this host’s resolutions without creating source changes after each update. Tool
choices and intentional version holds remain tracked; project lockfiles are unaffected. It may request an admin
password; running applications or unavailable vendor updaters are reported as
deferred. Close an affected app when convenient and rerun the command.

This does not publish dotfile source, update project dependencies,
upgrade the operating system, restart unrelated services, or prune software. For a look
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
`dots add brew-cask:firefox`. A `brew:` request prefers a formula and automatically
selects a cask when the formula is confirmed absent. Network and recipe errors
stop the attempt. `brew-cask:` explicitly selects a cask.
New Homebrew declarations are restricted to macOS
automatically, so they do not become Linux requirements. Existing declarations
keep their options. Unsupported recipes still need a named installer exception;
`dots` reports a backend failure for recipes it cannot install.

For a project that publishes GitHub releases, pass its HTTPS repository URL:
`dots add https://github.com/jaskirat1616/mactap-app`. A prebuilt command-line
release uses mise's GitHub backend. A macOS app shipped as a ZIP or tar archive
is recorded with a local install hook, so mise upgrades also replace the app in
`/Applications`; no Homebrew cask is needed. The hook will not overwrite an app
that `dots` did not install. DMG and pkg installers are rejected with an
explanation. If `dots` cannot choose one download, name it with
`--asset 'tool-*-macos-arm64.zip'`, which takes a name or glob and requires
exactly one URL. Only the latest stable release assets are used and no script
from the repository runs, so a source-only repository cannot be installed.

New requests are recorded after successful installation. On failure, `dots add`
shows the requested declaration and asks whether to record it for a later retry;
the default is No. Noninteractive runs never record failed requests. Existing
declarations remain in place. With multiple requests, earlier successful installs
stay recorded and the command stops at the first failure.
Tool installs stage only the requested static declaration. If that declaration
contains a mise template, use mise directly from its trusted configuration;
unrelated target templates and hooks are not evaluated by `dots add`.

All these commands select `~/.config/mise` before loading configuration. They
work from your thesis checkout or any other directory. An explicit `--path` is
the only way to redirect the write to an arbitrary file. `dots help` explains
the available actions; ordinary project-local `mise use` is unchanged.

## Remove a tool

When you no longer want something, run:

```sh
dots remove watchexec
```

`dots uninstall` does the same thing. The command uninstalls the software and
deletes its declaration. Settings and app data stay where they are. By default
it searches every active setup config, including your local and host files.
`--base`, `--profile workstation|nas`, and `--path FILE` narrow the search the
same way they do for `dots add`. If another active config still declares the
tool, only the selected declaration is removed and the software stays
installed.

You can name the target by its exact declaration, such as `brew-cask:firefox`
or `npm:prettier`, or by a GitHub repository URL. Backend identifiers retain
their exact spelling; short names and GitHub repository names ignore case.
A short name works when it matches exactly one declaration. If a bare
`[tools]` key such as `jq` clashes with another manager's package, `mise:jq`
selects the mise declaration explicitly. `dots remove mactap`
also finds a GitHub app that `dots` installed. If a name matches more than
one declaration, the command lists them and stops.

Each kind of tool is removed by its own installer:

- **mise tools:** `mise unuse` edits the named file. After removal,
  `mise prune --yes --tools TOOL` removes unused versions of that tool. Mise
  keeps versions that tracked project configs and tool stubs still use.
- **Native packages** (Homebrew, apt, dnf, pacman, apk, mas): one targeted
  uninstall. Dependents and transaction previews are checked first. Nothing is
  pruned globally, and the command never uses zap, purge, or force.
- **GitHub apps** installed by `dots add`: the app moves to the Trash, then mise
  removes its unused release installation. Its ownership record is deleted
  after removal succeeds. A failure restores the staged app.

Kanata and Karabiner are held and cannot be removed this way. When the command
can't confirm that a removal is safe, it stops. If a step fails, the command
restores the target's declarations and its staged app. It does not reinstall
native packages that were already uninstalled.

`--dry-run` shows the plan without changing anything. `--keep-installed` deletes
only the declaration and leaves the software installed. A GitHub app's
ownership record is kept, so a later `dots remove` can still uninstall it.

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
| `setup-tasks.toml` and `setup-scripts/` | Setup tasks, available with `mise -C ~/.config/mise run` without adding them to project task lists |
| `dotfiles/` | Native symlink sources; editing a linked target edits this source |
| `templates/` | Files rendered with Tera when `edit --apply` or apply is requested |
| `setup-scripts/setup/` | Status, update, backup, restore, and encrypted app-state tasks |
| `setup-scripts/install/` and `setup-scripts/local/` | Explicit install and machine lifecycle tasks |
| `encrypted/` | Age-encrypted private inputs; private settings history is stored separately |
| `tests/` | Test suites; run them with `dots test` (see [testing](docs/testing.md)) |
| `archive/` | Configuration kept for reference but never deployed; see its README to restore an entry |

The role selection and private history origin belong in ignored local mise configuration, not in the public source repository.

## More

| Topic | Guide |
| --- | --- |
| Recovering settings, bootstrap bundles, replacement machines | [Recovery](docs/recovery.md) |
| Shared shell history and Atuin login | [Atuin](docs/atuin.md) |
| Editing linked files and templates, cross-platform notes | [Dotfiles](docs/dotfiles.md) |
| Review defaults and shortcuts (`hunk`, `jjui`, `wto`, `prdiff`, `glf`) | [Review tools](docs/review-tools.md) |
| Herdr sessions, workspaces and keys | [Herdr](docs/herdr.md) |
| Corne keyboard and Kanata | [Keyboard](docs/keyboard.md) |
| CerpacNAS and remote Codex tasks | [NAS guide](docs/cerpacnas.md) |
| Tests and CI | [Testing](docs/testing.md) |
| Secret scanning, signing, leaked-credential rotation | [Security](docs/security.md) |
| Window managers | [Runbook](docs/window-manager-runbook.md) |
| Settings history internals | [History](docs/history.md) |
