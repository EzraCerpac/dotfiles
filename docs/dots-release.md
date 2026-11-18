# The dots release

This setup runs the `dots` manager from its release.
The manager lives in its own repository, [EzraCerpac/dots](https://github.com/EzraCerpac/dots), which documents its commands;
`config.toml` pins the version every machine runs:

```toml
"github:EzraCerpac/dots" = "0.3.5"
```

mise installs it like any other tool and puts `dots` and its `dots-up` renderer on `PATH`.
`dots --version` prints the version and how it was installed, for example `dots 0.3.5 (mise)`.
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

After merging a manager change, publish the release and roll it out to every dots-managed machine.
Verify `dots --version` in a fresh login on each machine and report any offline machine as pending.
