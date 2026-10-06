# Agent instruction ownership

Edit the reviewed source for a specific instruction file. Apply only that file's intentional change; do not run a blanket bootstrap, chezmoi apply, package update, or service restart to synchronize agent policy.

| Host/client | Source | Deployed target |
| --- | --- | --- |
| Mac Codex | `~/.config/mise/dotfiles/.codex/AGENTS.md` | linked `~/.codex/AGENTS.md` |
| Mac OpenCode | `~/.config/mise/dotfiles/.config/opencode/AGENTS.md` | linked `~/.config/opencode/AGENTS.md` |
| Mac Claude | standalone `~/.claude/CLAUDE.md` | same file |
| CerpacNAS Codex | `/root/.config/mise/dotfiles/.codex/AGENTS.cerpacnas.md` | linked `/root/.codex/AGENTS.md` |
| CerpacNAS OpenCode | standalone `/root/.config/opencode/AGENTS.md` | same file; host exception |
| Driehuis Codex | `/Users/server/.config/mise/dotfiles/.codex/AGENTS.driehuisnas.md` | linked `/Users/server/.codex/AGENTS.md` |

Codex globals contain the same inline block between `Shared Codex policy` markers, followed by host notes. The macOS workstation role selects `AGENTS.md`; Linux workstations select `AGENTS.linux.md` with the common block and no Keychain guidance; the NAS role selects `AGENTS.cerpacnas.md` on Linux and `AGENTS.driehuisnas.md` on macOS through native mise destination variants. All four sources are tracked in the same public tree, so updating source does not replace a NAS adapter with Mac policy. Role selection remains mandatory. Retain NAS reminder/GitHub disclosure clauses, actual host/tool availability, macOS-only Keychain guidance, and service/project ownership. NAS thesis execution is retired; research repositories, data and history remain. These files do not change model, context, access or approval settings. OpenCode's workstation-only source declaration does not establish a NAS deployment; retain the CerpacNAS standalone route. Old chezmoi/Projects-dotfiles copies and protected snapshots are recovery material, not alternative authority for these links.

After reviewing a deliberate instruction edit, update its expected postimage in `setup-scripts/agent-instructions/manifest.json`. Update the shared-block hash and all four Codex sources together when changing the common block. Preserve host notes. The manifest tracks exactly the six routes above; installed presence does not establish loading, enablement or historical use.

Run the read-only checker on demand from this setup checkout:

```sh
python3 setup-scripts/agent-instructions/check.py --host mac
python3 setup-scripts/agent-instructions/check.py --host cerpacnas --ssh
python3 setup-scripts/agent-instructions/check.py --host driehuisnas --ssh
```

The checker reads only explicit instruction paths and prints hashes/link matches. It skips content if a link points somewhere unexpected, validates the common block, and uses the established `cerpacnas`/`driehuisnas` aliases with batch mode and strict known-host checking. It neither copies files nor repairs drift. Exit 0 means the selected routes match the reviewed manifest; exit 1 means instruction drift; connection/validation failures mean the check could not complete. A local shell does not retarget a native Codex task to another host. Selected instruction ownership was verified on 2026-10-05; package/service/machine acceptance is a separate question.
