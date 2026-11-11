# dots/

This directory is how this configuration plugs into the `dots` manager.
Every part is optional; delete what you do not use. `dots init` created it and
never overwrites what is here.

| Path | Purpose |
| --- | --- |
| `hooks/update.d/` | Executables `dots up` runs after packages, tools and installer exceptions |
| `hooks/bootstrap.d/` | Executables `dots bootstrap` runs after installer exceptions |
| `commands/NAME` | An executable run as `dots NAME [ARGS...]` (built-in commands win) |
| `exceptions.tsv`, `exceptions/NAME` | Apps mise cannot install, each with its own recipe |
| `history-files.tsv` | App-written files tracked in encrypted settings history |
| `retired-dotfiles` | Removed dotfile targets whose dangling links may be deleted |

Settings live in `[vars]` of `config.toml`: `dots_profiles` (required, the
profiles you select with `mise -E`, as space-separated words),
`dots_source_repo` and `dots_state_repo` (GitHub `OWNER/NAME` of this
configuration and of its private settings history), and the optional
`dots_self_updating_casks`, `dots_publish_on_behalf_of` and
`dots_atuin_username`.

## Hooks

A hook is an executable file with a plain name (letters, digits, `.`, `_`,
`-`). Hooks run in name order from the configuration root, each as its own
reported stage; a failed hook does not stop later ones. The stage label is the
name without a leading number or extension, dashes and underscores as spaces:
`20-Login-shell.sh` reports as `Login shell`. A name ending in `@PROFILE`
(`30-Backups@server`) applies only to that profile; other profiles do not list
it at all.

Every hook gets `DOTS_ROOT` (this configuration), `DOTS_HOME` (the manager) and
`DOTS_PROFILE`. Update hooks also get `DOTS_TOOLS_OK=1` and
`DOTS_TOOLS_UPGRADED=1` when those stages succeeded, and `DOTS_CHANGES`: append
`ITEM<TAB>BEFORE<TAB>AFTER` lines to it and `dots up` shows them as changes in
the hook's report. Bootstrap hooks also get `DOTS_PRIVATE_READY=1` once private
settings are recovered and `DOTS_RESTORED=1` when this run restored them.

Exit 0 means completed, 3 deferred (needs attention), 4 skipped, anything else
failed. For example, `hooks/update.d/50-Fonts@laptop`:

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Skipped: macOS only'; exit 4; }
before="$(fc-list | wc -l)"
"$DOTS_ROOT/scripts/install-fonts"
printf 'fonts\t%s\t%s\n' "$before" "$(fc-list | wc -l)" >> "$DOTS_CHANGES"
```

## Commands

`dots NAME ARGS...` runs `commands/NAME` with the arguments unchanged, in the
caller's directory, with `DOTS_ROOT`, `DOTS_HOME` and `DOTS_PROFILE` set. It runs
before mise loads the setup. `dots help` and the `dots` menu list commands.

## Installer exceptions

One row per app in `exceptions.tsv`, tab-separated: the profile (`base` for
every profile), the recipe name, and optional comma-separated flags:

```text
laptop	some-app	install-only
```

`exceptions/some-app` is an executable that installs or updates exactly that
app. `install-only` makes `dots up` only install it when missing (for apps that
update themselves); `hold=brew:formula` records that the recipe pins that
package, so `dots add` refuses it. Bootstrap passes `--install-only`. Under
`dots up` a recipe also gets `DOTS_CHANGES`, like an update hook: append
`ITEM<TAB>BEFORE<TAB>AFTER` for what it verifiably installed (`not installed`
as BEFORE) or updated.

## History files and retired dotfiles

`history-files.tsv` rows are `PROFILE<TAB>~/PATH` (`base` for every profile);
history enrollment tracks those that exist. `retired-dotfiles` lists one
`~/PATH` per line; `lib/retire-dotfiles.sh` in the manager deletes each only
while it is a dangling link into this checkout. Call it from a mise
`post-dotfiles` hook: `bash "$DOTS_HOME/lib/retire-dotfiles.sh" "$DOTS_ROOT"`.
