# Encrypted mise history

This migration uses mise's native dotfile history. It tracks selected live
files in place and encrypts their contents in Git with age. The native history
format keeps filenames and tracking metadata visible, so track only exact files
that belong in this private history. See the official [dotfiles history guide](https://mise.jdx.dev/history.html).

## Profile selection

`tasks/bootstrap/profile` records one role and machine ID. The global
`miserc.toml` stores mise's early environment selector as a bare array, for
example:

```toml
env = ["workstation", "host-mac-primary"]
```

mise reads that file before it discovers role and host config files. The task
also stores `SETUP_PROFILE`, `SETUP_MACHINE_ID`, and the optional history origin
in ignored `config.local.toml`. It sets history sync to `manual` and does not
need an age key.

```sh
tasks/bootstrap/profile \
  --profile workstation \
  --machine-id mac-primary \
  --origin git@github.com:EzraCerpac/dotfiles-state.git
```

`tasks/bootstrap/persist-selected` is the pre-bootstrap helper. It keeps an
existing mise role and host ID. If no role is stored yet, it uses the selected
`SETUP_PROFILE`, keeps `SETUP_MACHINE_ID` when present, or creates a stable
one-time ID and persists it. It does not save history or create a repository.
The `miserc.toml` environment selector is documented in [mise's configuration environments](https://mise.jdx.dev/configuration/environments.html#setting-mise-env-in-miserc-toml).

## Enroll exact files

Create an age identity before enrolling. The usual private key path is
`~/.config/age/keys.txt`. The task calls `age-keygen -y` to read its public
recipient; it never prints the key contents. Pass other machine and recovery
recipients with `--recipient`. Before a host's first publish, its local
recipient list must contain the complete current public recipient set so every
host can decrypt future shared checkpoints. Each host needs only its own
private identity; never copy another machine's private key to it. Older
checkpoints remain encrypted to the recipients that were configured when each
checkpoint was saved.

```sh
tasks/bootstrap/enroll-history \
  --profile workstation \
  --machine-id mac-primary \
  --identity ~/.config/age/keys.txt \
  --origin git@github.com:EzraCerpac/dotfiles-state.git \
  --recipient age1RECOVERY_PUBLIC_RECIPIENT
```

### Add a host after history has started

If the NAS identity is not available when the Mac first saves history, the Mac
can start with its own recipient. Once the NAS has an identity, share only its
public recipient with the Mac. Adding that recipient and running an ordinary
`mise bootstrap dotfiles save` creates a new checkpoint encrypted to the
expanded recipient list, even when the live file content has not changed. The
native `save` command has no `--force` flag.

This rotates the current checkpoint; it does not rewrite older commits. A fresh
host with the new private identity can connect and restore the re-encrypted
current checkpoint, while older checkpoints still require the identity that
encrypted them. Keep those earlier private identities if you need historical
restores. Reachable history is retained indefinitely, with no automatic
expiration or compaction ([mise history documentation](https://mise.jdx.dev/history.html#retention)).

For a late NAS enrollment, prepare its local identity and full public recipient
set first. Replace the sample machine ID and `age1...` values with the NAS's
stable ID and the actual public recipients:

```sh
# On the NAS: its own identity is read locally; pass the Mac public recipient.
tasks/bootstrap/enroll-history \
  --profile nas \
  --machine-id nas-primary \
  --identity ~/.config/age/keys.txt \
  --origin git@github.com:EzraCerpac/dotfiles-state.git \
  --recipient age1MAC_PUBLIC_RECIPIENT
```

Then rotate and publish the Mac's current checkpoint:

```sh
# On the Mac: refresh appends the NAS public recipient to the existing set.
tasks/bootstrap/enroll-history \
  --profile workstation \
  --machine-id mac-primary \
  --identity ~/.config/age/keys.txt \
  --origin git@github.com:EzraCerpac/dotfiles-state.git \
  --recipient age1NAS_PUBLIC_RECIPIENT \
  --refresh
mise bootstrap dotfiles save
mise -C ~/.config/mise run setup:backup
```

Finally, restore the NAS with its own identity through the fetch-only workflow:

```sh
mise -C ~/.config/mise run setup:restore
```

That workflow fetches and pulls before importing the selected host checkpoint;
it does not publish local defaults. Its enrollment refresh appends the NAS's
own public recipient and preserves the existing local recipient set. Before
the NAS's first deliberate save and backup, confirm its recipient list still
contains both Mac and NAS public recipients. The private Mac key stays on the
Mac. When ready to publish the NAS's own variant, use the explicit backup task:

```sh
mise -C ~/.config/mise run setup:backup
```

The workstation defaults are exact files:

```text
~/.codex/config.toml
~/.config/aegis/config.json
~/.config/karabiner/karabiner.json
~/.config/atuin/config.toml
~/.config/gitlogue-saver/config.toml
~/.config/nvim/lazyvim.json
~/.config/nvim/lazy-lock.json
~/.config/nvim/spell/en.utf-8.add
~/.config/fish/fish_variables
~/.cli-proxy-api/config.yaml
~/.config/goose/config.yaml
~/.wakatime.cfg
~/.config/himalaya/config.toml
~/.pi/agent/settings.json
```

The NAS defaults are `~/.codex/config.toml` and
`~/.config/fish/fish_variables`. DelftBlue enrollment needs one or more
explicit `--file` arguments. Extra `--file` arguments add exact paths to the
role defaults. Missing default candidates are skipped; a missing explicit file
is an error. Symlinks and files outside the home directory are refused.

Enrollment writes only the ignored local profile/recipient settings and a
host-specific `config.host-ID.toml` with `mode = "track"` and `encrypt = true`
for each selected path. It then runs `mise bootstrap dotfiles paths` to parse
the declarations. It does not save a checkpoint, initialize a local history
repository, set a remote, or contact a remote. Review the paths, encryption
flags, and local recipient list before the first save:

```sh
mise bootstrap dotfiles paths
mise bootstrap dotfiles save
```

Enrollment sets every selected regular file to mode `0600` only after mise has
accepted the declarations. It refuses symlink targets and never changes the
age identity's mode. The history format shares permission metadata across host
variants of the same logical path, so every host variant must use the same
`0600` policy. After restore, `setup:restore` refreshes this host's enrollment
and reapplies the current-host permission policy before it completes. If a
restore is interrupted after files arrive, resume restore before saving or
syncing. To refresh a host config separately, use:

```sh
tasks/bootstrap/enroll-history \
  --profile workstation \
  --machine-id mac-primary \
  --identity ~/.config/age/keys.txt \
  --refresh
```

Refresh appends newly present exact files, preserves the existing host config,
and refuses to proceed if any existing tracked entry is not encrypted.
The local recipient list is appended to rather than replaced, so refresh keeps
previously enrolled hosts and recovery recipients while adding this host's
identity and any `--recipient` values supplied. DelftBlue refresh also needs
the same explicit `--file` arguments used at enrollment.

The configuration is prepared before that save, so an initial plaintext
checkpoint is not created. If those files were already saved in an earlier
plaintext history, adding encryption now does not rewrite those commits; do not
share that history until it is repaired.

## Remote and restore order

Use one private Git repository and its default branch on each machine. Keep Git
credentials in the SSH agent or credential helper, never in the URL. The local
origin is stored in ignored `config.local.toml`. History sync stays manual.

Connecting an origin also runs one initial synchronization after confirmation.
With mise 2026.9.7, `origin set --sync manual --yes` publishes committed local
history to an empty origin once. `manual` controls future watcher activity:
local checkpoints continue, but network sync waits for an explicit command
such as `setup:backup` or `mise bootstrap dotfiles sync`. Use
`origin set --sync fetch-only` when the first connection must not publish; it
fetches without pushing, and you can publish later deliberately. Review the
committed history and recipient set before connecting because all committed
checkpoints are eligible for that initial publication.

On a machine restoring an existing history, run `tasks/setup/restore` first.
It stages the private repository locally, connects in fetch-only mode, reviews
native status, pulls through mise's conflict checks, then imports the selected
host's first remote checkpoint through native rollback checks. It refreshes the
host enrollment and secures active tracked files at mode `0600` before it
completes. The task requires Git, Node, and the age identity to already be
available, and does not publish local defaults.

If an existing local history store is not connected to this exact private
repository, inspect it first. Pass `--initialize-history` only when choosing to
replace it. The task validates a staged clone, then moves the old store into a
protected sibling directory with mode `0700`; keep that backup until the
recovered history is reviewed. For example, invoke the registered task with
`mise -C ~/.config/mise run setup:restore --initialize-history`.

Save later edits locally with mise, then publish deliberately with
`mise bootstrap dotfiles sync` (or the repository's `setup:backup` task).

The enrollment scripts use `SETUP_MISE_BIN` when set, which lets migration
tests and bootstrap use the staged mise binary. Otherwise they use `mise` from
`PATH`.
