# Encrypted mise history

mise native dotfile history stores selected live files in a private Git
repository and encrypts their contents with age. Filenames and tracking
metadata remain visible, so track exact files only.

## The layout

Use one private repository with one branch per machine:

| machine | branch | private identity |
| --- | --- | --- |
| Mac | `host-mac-primary` | Mac `~/.config/age/keys.txt` |
| CerpacNAS | `host-cerpacnas` | NAS `~/.config/age/keys.txt` |

The old `main` branch remains preserved as legacy history. New saves and
restores select the host branch stored in ignored `config.local.toml` as
`history.origin.branch`. The branch is derived from the stable machine ID as
`host-<machine-id>`.

Each host keeps its own private age identity. Share public recipients when a
host needs to decrypt another host's encrypted checkpoint; never copy a peer's
private key. Before a host's first save, its recipient list must include every
public recipient needed for future recovery. A later recipient change creates a
new encrypted checkpoint; it does not re-encrypt older commits.

## Enroll a host

Persist the role and machine ID first:

```sh
setup-scripts/bootstrap/profile \
  --profile workstation \
  --machine-id mac-primary \
  --origin git@github.com:EzraCerpac/dotfiles-state.git
```

Enroll exact files with that host's identity. `--recipient` accepts a public
age recipient for recovery or another machine; it never accepts a private key:

```sh
setup-scripts/bootstrap/enroll-history \
  --profile workstation \
  --machine-id mac-primary \
  --identity ~/.config/age/keys.txt \
  --origin git@github.com:EzraCerpac/dotfiles-state.git \
  --recipient age1RECOVERY_PUBLIC_RECIPIENT
```

The NAS uses the same shape with `--profile nas`, `--machine-id cerpacnas`,
and its own `~/.config/age/keys.txt`; adding the Mac's recovery public recipient
lets the Mac's recovery key decrypt NAS checkpoints. Missing role defaults are skipped, explicit
`--file` paths must exist, symlinks are refused, and tracked files are secured
at mode `0600` after declarations are accepted.

Review the declarations before network publication:

```sh
mise bootstrap dotfiles paths
```

Enrollment prepares local configuration and may cause the native history store
to create its first local checkpoint when the surrounding bootstrap initializes
history. Treat that checkpoint as sensitive until its encryption and recipient
set are reviewed. A normal deliberate checkpoint is:

```sh
mise bootstrap dotfiles save
```

## Create the host branch once

mise 2026.9.10 refuses `origin set --branch` when the named branch does not yet
exist in a non-empty remote. Create each branch once from a reviewed local
store, after confirming that every reachable tracked version is encrypted:

```sh
branch=host-mac-primary
origin=git@github.com:EzraCerpac/dotfiles-state.git
history_dir="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/history"
git --git-dir="$history_dir/repo.git" \
  push "$origin" "HEAD:refs/heads/$branch"
mise bootstrap dotfiles origin set "$origin" \
  --branch "$branch" --sync manual --yes
```

Use `host-cerpacnas` for CerpacNAS. This is an explicit one-time preparation;
bootstrap and enrollment do not create remote branches or publish history.
Never push a host checkpoint to `main`. The first `origin set` may publish the
already reviewed local checkpoint on the pre-created host branch, so review
before running it.

## Back up deliberately

History sync remains manual. `dots backup` verifies that the persisted branch
matches this machine ID before it saves and syncs:

```sh
dots backup
```

A missing or mismatched `history.origin.branch` stops before save or sync. This
keeps a legacy `main` origin from receiving a new host checkpoint.

## Restore a host

Pre-create the host branch before first restore. The restore task clones only
`host-<machine-id>`, connects in fetch-only mode, reviews native status, pulls
through native conflict checks, and applies the selected host checkpoint. It
does not publish local defaults:

```sh
dots restore
```

If the local store is unconnected or belongs to another repository, inspect it
first. Use `--initialize-history` only when deliberately replacing it; the task
keeps the old bare store in a protected sibling backup. If the requested host
branch is absent, restore stops before replacing the local store.

After recovery, enrollment refreshes the current host's encrypted exact-file
entries and restores the `0600` permission policy. Keep the private Mac key on
the Mac and the private NAS key on the NAS.

## Bootstrap bundle boundary

The workstation may use the historical implicit encrypted bootstrap bundle.
NAS bootstrap ignores that implicit workstation bundle, so a Mac-only bundle
cannot block NAS recovery or history enrollment. NAS uses a bundle only when
`SETUP_BOOTSTRAP_BUNDLE`, `SETUP_BUNDLE_IDENTITY`, or the persisted
`vars.bootstrap_bundle_identity` explicitly selects one. An explicit or
persisted bundle with a missing or wrong identity remains an error/deferred
condition; do not work around it by copying a peer's private key.

The local history origin, branch, sync mode, age identity paths, and recipient
list belong in ignored local configuration. Do not commit credentials or
private identities.
