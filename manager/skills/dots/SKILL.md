---
name: dots
description: Work in a configuration managed by the dots dotfiles manager (mise config plus dots/). Use when asked to add or remove a tool, package or dotfile, write a dots hook, command or installer exception, inspect or update a machine with dots, or change files in a mise config repository that has a dots/ directory.
---

# dots

`dots` manages machines from a mise configuration repository.
Two directories matter; find them before changing anything:

```sh
dots internal home        # DOTS_HOME: the manager (code, docs, this skill)
echo "${DOTS_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"   # DOTS_ROOT: the configuration
```

Change the configuration, not the manager, unless the task is about the manager itself.
The configuration's `dots/README.md` documents hooks, commands and installer exceptions; `$(dots internal home)/README.md` documents the commands.

## Safe and unsafe commands

Read-only, run freely:

```sh
dots help                 # commands, including the configuration's own
dots status               # profile, source repo, packages, tools, dotfiles, history
dots plan                 # mise's bootstrap plan
dots remove --dry-run X   # what removing X would do
```

These change the machine, the configuration or a remote repository.
Run them only when the user asks for that action:
`dots up`, `dots sync`, `dots apply`, `dots add`, `dots remove`, `dots bootstrap`, `dots remote`, `dots backup`, `dots restore`, `dots publish`, `dots init`.
`dots up` and `dots sync` push to the shared `dev` branch.
Do not run them while someone else has uncommitted edits in the live checkout.

## Profiles

`[vars] dots_profiles` in `config.toml` lists the profiles, for example `"laptop server"`.
`config.toml` applies everywhere; `config.PROFILE.toml` adds to one profile.
The machine's own profile is in the ignored `config.local.toml` (`env.SETUP_PROFILE`).
Put a declaration in the narrowest file that fits: shared tools in `config.toml`, machine-type tools in the profile file.

## Add or remove software

Prefer `dots add`, which installs first and records only what worked:

```sh
dots add ripgrep                      # current profile's config.PROFILE.toml
dots add --base ripgrep               # config.toml, every profile
dots add --profile server ripgrep     # another profile's file
dots add npm:prettier cargo:hexyl brew-cask:firefox
dots add https://github.com/OWNER/REPO
dots remove --dry-run ripgrep
```

When the user only wants the declaration written, edit the TOML by hand with mise syntax (`[tools]`, `[bootstrap.packages]`) and leave installation to their next `dots up`.

## Add a dotfile

Put the file under `dotfiles/` in the configuration and declare it:

```toml
[dotfiles]
"~/.config/app/config.toml" = { source = "dotfiles/.config/app/config.toml", mode = "symlink" }
```

Use `mode = "template"` with a `.tera` source for per-machine values, and `variants = [{ os = "macos" }]` or `{ profile = "laptop" }` to restrict it.
When you remove a declaration, add its target to `dots/retired-dotfiles` so stale links get cleaned up.
App-written files that must not be linked go in `dots/history-files.tsv` (`PROFILE<TAB>~/PATH`), which tracks them in encrypted settings history.

## Hooks, commands and installer exceptions

All live in the configuration's `dots/`; read its `README.md` before writing one.

- Update hook: executable `dots/hooks/update.d/NN-Name`, run by `dots up` after packages, tools and installer exceptions.
  Bootstrap hook: `dots/hooks/bootstrap.d/NN-Name`.
  A `@PROFILE` suffix (`30-Backups@server`) limits it to one profile.
  Exit 0 completed, 3 deferred, 4 skipped, anything else failed.
  Hooks get `DOTS_ROOT`, `DOTS_HOME` and `DOTS_PROFILE`; update hooks may append `ITEM<TAB>BEFORE<TAB>AFTER` lines to `$DOTS_CHANGES`.
- Command: executable `dots/commands/NAME`, run as `dots NAME ARGS...` in the caller's directory, before mise loads; built-in names win.
- Installer exception, for an app no mise backend can install: an executable recipe `dots/exceptions/NAME` that updates exactly that app, plus a row `PROFILE<TAB>NAME[<TAB>FLAGS]` in `dots/exceptions.tsv`.
  Flags: `install-only` for self-updating apps, `hold=PACKAGE` for a pinned package.
  Homebrew recipes can use `$DOTS_HOME/lib/brew-exception.sh` (see `$DOTS_HOME/tasks/README.md`).
  Under `dots up` recipes get `$DOTS_CHANGES` too, for the same change lines.

Make new hooks and recipes executable (`chmod +x`), start them with `set -euo pipefail`, keep them safe to rerun, and check them with `bash -n`.

## Rules

- Never commit secrets, keys, tokens or app state.
  `miserc.toml`, `config.local.toml` and `config.host-*.toml` are machine-local and stay ignored; never write `[tools]`, `[dotfiles]` or packages into them.
- Small changes (a config line, a hook, instruction text) go into the live checkout; the user then runs `dots up` or `dots sync` to share them through `dev`.
- Larger or risky changes go on a task branch from `origin/main` with a pull request into `main`; a merged PR reaches every machine on its next `dots up`.
- Never force-push, rewrite `dev` or `main`, or merge `dev` wholesale into `main`.
- Do not run machine-changing commands unless asked; say which command the user should run instead.
- If the configuration has tests, run them: `dots test`, or `tests/run` in the configuration.
