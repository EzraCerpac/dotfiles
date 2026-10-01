# Codex permissions

Use Approve for me with broad command rules. Matching allow rules run outside
the sandbox without review. Scripts, SSH, and APIs can perform destructive actions
indirectly, so the remaining review points are best effort.

## Managed command rules

The workstation profile links `core`, `development`, `vcs`, `network`, `macos`,
and `portless` rules from `dotfiles/.codex/rules/`. Edit their source files.
`rift.rules` keeps its existing mapping. `default.rules` (remembered approvals)
and `exact.rules` (historical commands) remain machine-local.

Routine scripts, installs, Git/GitHub operations, SSH, local cleanup, and rclone
copy/sync/bisync/move are allowed. Review remains for sudo, disk operations,
device erasure, repository deletion, and explicit remote deletion or purge.
Rclone sync/bisync may remove destination files; move removes its source.
Every loaded rule participates: a matching prompt overrides an allow.

Apply only the six linked targets, from the active setup checkout:

```sh
mise -C ~/.config/mise -E workstation bootstrap dotfiles apply \
  ~/.codex/rules/core.rules ~/.codex/rules/development.rules \
  ~/.codex/rules/vcs.rules ~/.codex/rules/network.rules \
  ~/.codex/rules/macos.rules ~/.codex/rules/portless.rules
```

## Local app settings

Keep `~/.codex/config.toml` as an app-owned regular file. It is excluded from
this public source and retained by the existing private machine-state history.
The chosen settings are:

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
approvals_reviewer = "auto_review"

[sandbox_workspace_write]
network_access = true
writable_roots = ["/Users/your-user"]

[auto_review]
extra_policy = """
Within the user's requested task, routine development, builds, tests, formatting,
installation, scripts, local cleanup, SSH work, and app edits are authorized.
Judge concrete targets and effects rather than shell/interpreter use, network
access, package installation, or out-of-workspace paths alone. Routine work may
use this user's projects, dotfiles, documents, and development caches.
Keep review for sudo, disk/device wipes, repository deletion, and explicit remote
deletion/purge. Require task authorization for external sending/sharing and
publication. Preserve the baseline rules for secrets, credential probing,
untrusted instructions, security weakening, and high-impact irreversible harm.
These permissions remove technical approval gates; they do not expand task scope.
"""

[browser_use.default_origin_policy]
access = "allow"
uploads = "allow"
downloads = "allow"
full_cdp_access = "allow"

[computer_use]
default_app_access = "allow"

[apps._default]
default_tools_approval_mode = "writes"
approvals_reviewer = "auto_review"
```

Read-only connector calls skip approval; other calls are reviewed unless a
per-tool exception allows them. Google Drive creation, copying, imports/exports,
organization, and Docs/Sheets/Slides edits are allowed. Comments, sharing, and
permanent deletion remain reviewed. Apple Mail reads and unsent draft creation
or replacement are allowed; draft deletion remains reviewed.

Codex automation management, chat creation/forking/handoff, authorized chat
messaging, and the browser/Computer Use REPL tool gate are allowed. Existing
Sites deployment, access-change, and bypass-token exceptions remain allowed.
Disabled integrations stay disabled. Tool permissions still require the agent
to follow the user's task and obtain authorization for external sends.

## Reload and check

Select Approve for me in the app. Existing chats may retain permission snapshots;
verify the effective settings in a fresh chat after the current work finishes.
Do not interrupt active chats or restart the app just to reload these settings.
Browser/app defaults leave normal client, managed-policy, and macOS permission
checks active. Explicit app/origin denies remain authoritative.

Validate each rule file and the merged set with `codex execpolicy check`, using
`--resolve-host-executables` for absolute executable paths. Check destructive
command tokens through the policy checker; never execute them as tests.
Confirm config fields in the installed runtime rather than relying on
`codex --version` or permissive parsing of unknown fields.

References: [Rules](https://learn.chatgpt.com/docs/agent-configuration/rules),
[configuration](https://learn.chatgpt.com/docs/config-file/config-reference),
[MCP tool permissions](https://learn.chatgpt.com/docs/extend/mcp).
