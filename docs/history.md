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
dots internal profile \
  --profile workstation \
  --machine-id mac-primary \
  --origin git@github.com:EzraCerpac/dotfiles-state.git
```

The tracked files are native `[dotfiles]` track entries in
`config.workstation.toml` and `config.nas.toml`. Each entry lists, as
`{ profile = "host-<machine-id>" }` variants, the machines that keep that file.
The variant is the file's stream in history (`home@host-mac-primary/...`):
never rename or remove one that has history, and add a new machine by adding its
own variant. Missing files are listed with 0 files and saved once they exist;
paths outside HOME are reported as invalid.

Prepare the host's age identity and recipients. `--recipient` accepts a public
age recipient for recovery or another machine; it never accepts a private key:

```sh
dots internal enroll-history \
  --profile workstation \
  --machine-id mac-primary \
  --identity ~/.config/age/keys.txt \
  --origin git@github.com:EzraCerpac/dotfiles-state.git \
  --recipient age1RECOVERY_PUBLIC_RECIPIENT
```

The NAS uses the same shape with `--profile nas`, `--machine-id cerpacnas`,
and its own `~/.config/age/keys.txt`; adding the Mac's recovery public recipient
lets the Mac's recovery key decrypt NAS checkpoints. The task secures this
host's tracked files at mode `0600`, refuses symlinks, and exits with status 3
when no entry names this host's profile.

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
bootstrap and `enroll-history` do not create remote branches or publish history.
Never push a host checkpoint to `main`. The first `origin set` may publish the
already reviewed local checkpoint on the pre-created host branch, so review
before running it.

Machines enrolled before the track entries moved into the shared
configuration also keep generated copies in their ignored
`config.host-<machine-id>.toml`. They are identical and harmless; remove them
with [the declaration cleanup](history-declarations.md).

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

After recovery, restore refreshes the current host's identity and recipients
and restores the `0600` permission policy. Keep the private Mac key on
the Mac and the private NAS key on the NAS.

## Bootstrap bundle boundary

Each profile's bundle is `encrypted/bootstrap.PROFILE.json.age`; bootstrap uses
it implicitly when it exists. Only the workstation has one
(`encrypted/bootstrap.workstation.json.age`), so a Mac-only bundle cannot block
NAS recovery or history enrollment. NAS uses a bundle only when
`SETUP_BOOTSTRAP_BUNDLE`, `SETUP_BUNDLE_IDENTITY`, or the persisted
`vars.bootstrap_bundle_identity` explicitly selects one. An explicit or
persisted bundle with a missing or wrong identity remains an error/deferred
condition; do not work around it by copying a peer's private key.

The local history origin, branch, sync mode, age identity paths, and recipient
list belong in ignored local configuration. Do not commit credentials or
private identities.
