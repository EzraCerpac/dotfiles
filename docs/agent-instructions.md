# Agent instruction ownership

Edit the reviewed source for a specific instruction file. Apply only that file's intentional change; do not run a blanket bootstrap, chezmoi apply, package update, or service restart to synchronize agent policy.

| Host/client | Source | Deployed target |
| --- | --- | --- |
| Mac Codex | `~/.config/mise/dotfiles/.codex/AGENTS.md` | linked `~/.codex/AGENTS.md` |
| Mac OpenCode | `~/.config/mise/dotfiles/.config/opencode/AGENTS.md` | linked `~/.config/opencode/AGENTS.md` |
| Mac Claude | `~/.config/mise/dotfiles/.claude/CLAUDE.md` | linked `~/.claude/CLAUDE.md` |
| CerpacNAS Codex | `/root/.config/mise/dotfiles/.codex/AGENTS.cerpacnas.md` | linked `/root/.codex/AGENTS.md` |
| CerpacNAS OpenCode | standalone `/root/.config/opencode/AGENTS.md` | same file; host exception |
| Driehuis Codex | `/Users/server/.config/mise/dotfiles/.codex/AGENTS.driehuisnas.md` | linked `/Users/server/.codex/AGENTS.md` |
| Driehuis Claude | `/Users/server/.config/mise/dotfiles/.claude/CLAUDE.md` (same source as Mac) | linked `/Users/server/.claude/CLAUDE.md` |

Codex globals contain the same inline block between `Shared Codex policy` markers, followed by host notes. The macOS workstation role selects `AGENTS.md`; Linux workstations select `AGENTS.linux.md` with the common block and no Keychain guidance; the NAS role selects `AGENTS.cerpacnas.md` on Linux and `AGENTS.driehuisnas.md` on macOS through native mise destination variants. All four sources are tracked in the same public tree, so updating source does not replace a NAS adapter with Mac policy. Role selection remains mandatory. Retain NAS reminder clauses, actual host/tool availability, macOS-only Keychain guidance, and service/project ownership. NAS thesis execution is retired; research repositories, data and history remain. These files do not change model, context, access or approval settings. OpenCode's workstation-only source declaration does not establish a NAS deployment; retain the CerpacNAS standalone route. Old chezmoi/Projects-dotfiles copies and protected snapshots are recovery material, not alternative authority for these links.

The seven routes above are the only instruction files this setup manages; installed presence does not establish loading, enablement or historical use. Update the shared block and all four Codex sources together when changing the common block, and preserve host notes.

To check drift on demand, compare each deployed file with its source using `diff` and `readlink` (over `ssh` for the NAS hosts) without reading anything else under the home directory. A local shell does not retarget a native Codex task to another host. Selected instruction ownership was verified on 2026-10-05; package/service/machine acceptance is a separate question.

## Claude settings

`~/.claude/settings.json` on every macOS host renders from `templates/.claude/settings.json.tera` (mode 0600). The NAS profile gets its own host-containment line, and the herdr session hook appears only where its script exists. Claude Code may rewrite the deployed file; carry intended changes back into the template and reapply only that target:

```sh
mise -C ~/.config/mise bootstrap dotfiles diff ~/.claude/settings.json
mise -C ~/.config/mise bootstrap dotfiles apply ~/.claude/settings.json
```

## Shared skills

Installers such as `rex skill setup` and `npx skills` write to `~/.agents/skills`, which Codex reads but Claude Code does not. Every dotfiles apply runs `setup-scripts/local/link-agent-skills.sh`, which links each shared skill directory into `~/.claude/skills/<name>`. A skill Claude already has under that name is kept, and links to removed shared skills are pruned. Run the script directly to link a newly installed skill without a full apply.
