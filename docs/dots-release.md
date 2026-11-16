# The dots release

This setup runs the `dots` manager from its release.
The manager lives in its own repository, [EzraCerpac/dots](https://github.com/EzraCerpac/dots), which documents its commands;
`config.toml` pins the version every machine runs:

```toml
"github:EzraCerpac/dots" = "0.3.0"
```

mise installs it like any other tool and puts `dots` and its `dots-up` renderer on `PATH`.
`dots --version` prints the version and how it was installed, for example `dots 0.3.0 (mise)`.
The release links its own agent skill into `~/.claude/skills/dots` and `~/.agents/skills/dots` whenever it runs.

## How the configuration reaches it

Tasks in `setup-tasks.toml` call `dots internal …`, since mise puts the declared tools on a task's `PATH`.
Scripts that `dots` itself runs (hooks, commands, installer exceptions) get `DOTS_HOME`.

`mise bootstrap` runs its dotfiles hooks before its tools step, and a hook gets neither mise nor the declared tools on `PATH`.
So the bootstrap hooks and `setup-scripts/local/common` reach the manager through `setup-scripts/local/dots`,
which runs `mise x github:EzraCerpac/dots -- dots …` and so installs the pinned release on first use.
A new machine therefore needs nothing beyond the command in the [README](../README.md#start-a-new-machine).

## Moving to a new release

Change the version in `config.toml` through a pull request.
The next `dots up` installs it with the other newly declared tools and reports `dots A -> B, used from the next run`;
that run finishes on the old version, and the next one uses the new one.
The old version stays installed, because updates never prune.

## Switching a machine from the in-repo manager

Until this setup used the release, `dots` ran from `manager/` in this checkout, through a `~/.local/bin/dots` link,
and a copy of its skill sat in `~/.agents/skills/dots`.
Each machine switches once, by hand, after the change that removed `manager/` is on `main`.

An old `dots up` that meets the change cannot finish it: its sync merges, pushes and updates the checkout,
but the dotfiles apply then fails (`APPLY FAILED`, because the hooks are handed the deleted `manager/` as `DOTS_HOME`)
and the run stops after the sync (`manager/tasks/update: No such file or directory`).
Nothing is removed or half-applied, and the steps below finish the switch whether or not that run happened:

```sh
# Set the old copied skill aside (the release links its own); delete the backup once you have checked it.
[ -L ~/.agents/skills/dots ] || [ ! -e ~/.agents/skills/dots ] || mv ~/.agents/skills/dots ~/.agents/dots-skill.before-release
[ ! -L ~/.claude/skills/dots ] || rm ~/.claude/skills/dots
~/.local/bin/mise x github:EzraCerpac/dots@0.3.0 -- dots up
```

The released `dots` syncs, applies the dotfiles (which removes the dead `~/.local/bin/dots` link), links its skill and runs the rest of the update.
Open a new shell; `dots --version` prints `dots 0.3.0 (mise)` and `dots status` lists the skill links.
The old `dots-up` renderer (`github:EzraCerpac/dotfiles`) stays installed but unused;
remove it with `mise uninstall --all github:EzraCerpac/dotfiles` if you like.
