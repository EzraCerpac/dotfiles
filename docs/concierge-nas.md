# Concierge on a macOS NAS

The `concierge:*` tasks manage four user LaunchAgents: a WhatsApp collector,
a WhatsApp read bridge, a Mail bridge, and a combined iCloud bridge. They require
an explicitly named macOS host and run in that user's logged-in GUI session.
They do not establish availability before login.

## Supply the runtime separately

This repository contains the bootstrap script, task definitions and configuration
template. It does **not** contain the concierge adapters, their dependency locks,
credentials or private state. Cloning GitHub `main` is not a complete runtime
installation, even after these bootstrap additions are merged.

Obtain a reviewed copy of the external `personal-concierge` runtime and preserve
its source revision or private source backup. Set `projectDir` to that copy.
It must include the complete modules and their local imports:

| Module under `integrations/` | Required entry point and dependency files |
| --- | --- |
| `whatsapp-read/wacli/` | `mcp.mjs`, `read.mjs` and their imports |
| `mail-read/` | `maintained_mcp.py`, its imports and `requirements.lock` |
| `icloud-pilot/` | `mcp_stdio.py`, its imports, `pyproject.toml` and `uv.lock` |
| `icloud-dav/` | Complete module, `pyproject.toml` and `uv.lock` |

Install compatible Node, uv, `wacli` and `tunnel-client` binaries separately and
record their versions with the private deployment notes. The bootstrap checks
that these executables exist; it does not install or pin them. The WhatsApp
module requires Node 22.13 or later. The tunnel client must support the
`sample_mcp_stdio_local` profile and file-based runtime-key references.

Rebuild uses Python 3.13.15 for both locked iCloud environments. It creates a
missing Mail environment with Python 3.14.7 and installs its hash-pinned
IMAPClient 4.1.0 lock. An existing Mail environment is reused; verify its Python
version yourself with `concierge:doctor`. Network access to the configured Python
and package sources is needed unless all dependencies are already cached.
Do not copy virtual environments between architectures.

## Back up and enroll privately

Before replacement-machine work, take a protected backup of the runtime sources
and private configuration, provider sessions, WhatsApp store, policy/grant files,
write journals, before-write backups and iCloud writer identity. Coordinate a
consistent backup with the relevant runtime's writers; these tasks do not stop
services or create state backups. Keep recovery material outside this public
repository, with owner-only access and encryption for transported backups.
`dots backup` alone does not promise coverage of concierge state.

Preserve `~/.local/share/dottie-icloud/edit-writer.json` across an approved
migration, together with the related journals and backups. If the external
runtime includes `integrations/icloud-pilot/writer_identity_ops.py`, its `backup`
and `restore --backup <private-backup-path>` commands provide guarded identity
recovery. Never overwrite a different identity or bypass pending-write checks.

Enroll or restore each provider session and credential through the runtime's
human-controlled private enrollment flow. Pair WhatsApp, provision Mail credential
references, authorize iCloud access and review the exposure/write grants. Create
separate approved tunnel bindings and store their runtime keys in private files.
Expired sessions require reauthorization. The bootstrap does not create grants,
log in to providers, export credentials or prove that authorization is valid.

## Configure the target host

Start from [runtime.example.json](../resources/concierge/runtime.example.json).
Copy it to `~/.config/dottie/runtime.json` outside the checkout, using a private
parent directory and mode `0600`. Do not overwrite an existing configuration.

Replace the hostname and tunnel placeholders, and select the actual project,
executable and private file paths. `expectedHost` must equal Node's `os.hostname()`
on the target. The service labels and backend kinds are fixed. Keep each private
path home-relative (`~/...`); runtime keys, sessions and profile directories must
be owned by the runtime user and inaccessible to other users. Symlinked private
paths and writable shared LaunchAgent directories are refused. Mail's account
reference definition may be mode `0644`; its credentials must remain private.

Keep `remindersEdits: false` until the external runtime's edit support, grants
and state recovery have been reviewed. Enabling it adds `--with-edit` to the
combined iCloud command. That command already includes `--with-create` and
`--with-dav`; `false` does not make the entire endpoint read-only. The external
runtime's policies determine which operations are actually allowed.

A tunnel service may specify `readinessFiles`, an array of `~/...` paths to
required private enrollment or policy files. Missing files block rebuild.
Presence is only a filesystem check; it does not verify the content or a provider
session. Keep account IDs, tunnel IDs, credentials, archives and health URLs out
of this repository and public diagnostic output.

## Inspect, then activate explicitly

From the target user's normal logged-in session, with the setup checkout in its
usual location:

```sh
mise -C ~/.config/mise -E nas run concierge:plan
mise -C ~/.config/mise -E nas run concierge:doctor
```

`plan` checks existing definitions and private references without installing
anything. `doctor` reports paths, versions, profile bindings and launchd state;
it does not prove provider access or cloud invocation. Treat both outputs as
private. `concierge:stage` optionally writes private plist files under
`~/.local/state/dottie-concierge-stage` without loading them.

After source delivery, backup and manual enrollment are complete:

```sh
mise -C ~/.config/mise -E nas run concierge:rebuild
```

Rebuild refuses definition or profile-binding drift before dependency changes.
It syncs locked Python dependencies, creates missing tunnel profiles, installs
missing LaunchAgents and bootstraps only unloaded labels. It does not restart
loaded labels or replace differing definitions. Dependency sync still occurs
when labels are already loaded, so use it in a supervised maintenance window.
If another `wacli` process exists, collector startup is skipped to avoid a
second writer. Inspect the reported `skipped` and `blocked` fields.

After activation, check provider reads, session reuse, the single WhatsApp
collector and the reviewed write policies. Verify fresh calls through the actual
cloud client separately. Service state alone is not end-to-end proof. The
collector keeps media downloads off and sets unlimited message/database
retention, which needs storage monitoring.

For drift or failed recovery, preserve the existing files and reconcile against
the protected backup. Service restarts, grant changes and state restoration are
separate supervised operations; this bootstrap does not perform them for you.
