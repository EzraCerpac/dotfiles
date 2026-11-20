# Agent instruction ownership

Edit the reviewed source for a specific instruction file. Apply only that file's intentional change; do not run a blanket bootstrap, chezmoi apply, package update, or service restart to synchronize agent policy.

| Host/client | Source | Deployed target |
| --- | --- | --- |
| Mac and Linux workstation Codex | `templates/.codex/AGENTS.md.tera` | rendered `~/.codex/AGENTS.md` |
| Mac OpenCode | `~/.config/mise/dotfiles/.config/opencode/AGENTS.md` | linked `~/.config/opencode/AGENTS.md` |
| Mac Claude | `~/.config/mise/dotfiles/.claude/CLAUDE.md` | linked `~/.claude/CLAUDE.md` |
| CerpacNAS Codex | `templates/.codex/AGENTS.md.tera` | rendered `/root/.codex/AGENTS.md` |
| CerpacNAS OpenCode | standalone `/root/.config/opencode/AGENTS.md` | same file; host exception |
| Driehuis Codex | `templates/.codex/AGENTS.md.tera` | rendered `/Users/server/.codex/AGENTS.md` |
| Driehuis Claude | `/Users/server/.config/mise/dotfiles/.claude/CLAUDE.md` (same source as Mac) | linked `/Users/server/.claude/CLAUDE.md` |

Edit the shared Codex policy and host notes in `templates/.codex/AGENTS.md.tera`.
Mise renders it for the selected `workstation` or `nas` role on macOS and Linux.
The template adds the Keychain note on macOS and the reminder,
thesis-retirement and Code Mode notes for NASes.
The first apply replaces the old symlink with a regular file.

Retain actual host and tool availability and service and project ownership.
NAS thesis execution is retired, and research repositories, data and history remain.
Instruction files do not change model, context, access or approval settings.
Retain the CerpacNAS standalone OpenCode route.
Old chezmoi/Projects-dotfiles copies and protected snapshots are recovery material.

Check or apply just the Codex file on the target machine with its usual mise profile:

```sh
mise -C ~/.config/mise bootstrap dotfiles diff ~/.codex/AGENTS.md
MISE_NO_HOOKS=1 mise -C ~/.config/mise bootstrap dotfiles apply ~/.codex/AGENTS.md
```

For linked Claude and OpenCode files, use `readlink` and `diff` to check drift.
A local shell does not retarget a native Codex task to another host.

## Claude settings

`templates/.claude/settings.json.tera` holds the keys this repository owns in `~/.claude/settings.json` on every macOS host; the NAS profile gets its own host-containment line. mise merges them into the file (`merge = true`) and leaves every other key to Claude Code, so plugins it enables, `/model`, `statusLine` and other settings it writes survive an apply. An owned key Claude changes is reset on the next apply, and an owned array (the `autoMode` lists) replaces Claude's whole. Change an owned key in the template and reapply only that file:

```sh
mise -C ~/.config/mise bootstrap dotfiles diff ~/.claude/settings.json
mise -C ~/.config/mise bootstrap dotfiles apply ~/.claude/settings.json
```

Merging never deletes a key. To drop an owned key, remove it from the template and delete it once on each macOS host, for example `tmp=$(mktemp) && jq 'del(.KEY)' ~/.claude/settings.json > "$tmp" && cat "$tmp" > ~/.claude/settings.json; rm -f "$tmp"`. Merge edits take no `variants`, so off macOS the template renders only `$schema`: a host without the file gets one holding just that key.

## Shared skills

Installers such as `rex skill setup` and `npx skills` write to `~/.agents/skills`, which Codex reads but Claude Code does not. Every dotfiles apply runs `setup-scripts/local/link-agent-skills.sh`, which links each shared skill directory into `~/.claude/skills/<name>`. A skill Claude already has under that name is kept, and links to removed shared skills are pruned. Run the script directly to link a newly installed skill without a full apply.

The `dots` skill ships with the [dots release](dots-release.md), which links it into `~/.agents/skills/dots` and `~/.claude/skills/dots` itself on every run; the script finds both links pointing at the same skill and leaves them alone.
