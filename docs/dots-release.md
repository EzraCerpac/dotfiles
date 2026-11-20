# The dots release

This setup runs the `dots` manager from its release.
The manager lives in its own repository, [EzraCerpac/dots](https://github.com/EzraCerpac/dots), which documents its commands;
`config.toml` declares that every machine follows its latest release:

```toml
"github:EzraCerpac/dots" = "latest"
```

mise installs it like any other tool and puts `dots` on `PATH`.
`dots --version` prints the installed version.

## How the configuration reaches it

Tasks in `setup-tasks.toml` call the public `dots` commands,
since mise puts the declared tools on a task's `PATH`.
Hooks, commands and installer exceptions use the running `dots` on `PATH`.

`mise bootstrap` runs its dotfiles hooks before its tools step, and a hook gets neither mise nor the declared tools on `PATH`.
The native bootstrap hooks can reach the manager through `setup-scripts/local/dots`,
which runs `mise x github:EzraCerpac/dots -- dots …` and so installs the declared release on first use.
A new machine therefore needs nothing beyond the command in the [README](../README.md#start-a-new-machine).

## Moving to a new release

Nobody edits the shared declaration for a release.
The Tools stage of `dots up` upgrades `dots` through mise, like the other tools that track their latest release.
mise sees a new release once its release cache and index catch up,
which can take about an hour after publishing and has no fixed bound,
so a run before then keeps the current version.

The run that finds the new release reports `dots A -> B, used from the next run`;
that run finishes on the old version, and the next one uses the new one.
The old version stays installed, because updates never prune.

A machine whose local configuration names an explicit `dots` version runs that version instead of the shared declaration,
and `dots up` does not move it to the latest release.

After publishing a manager release, let each dots-managed machine pick it up with `dots up`.
Verify `dots --version` in a fresh invocation on each machine and report any offline machine as pending.
