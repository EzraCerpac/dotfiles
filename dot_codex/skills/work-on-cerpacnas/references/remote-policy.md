# CerpacNAS policy

- Existing root SSH access is intentional. Restrict Codex to workspace-write or read-only sandbox and `/root/Projects`.
- Never use `--dangerously-bypass-approvals-and-sandbox`, `sudo`, Docker, or package-manager mutation from an agent.
- Code crosses machines only through published `wip/...` bookmarks and verified commit ids.
- Configuration crosses through dotfiles `dev` plus targeted review before apply.
- Artifacts cross through allowlisted, non-deleting rsync. Dry-run first.
- Run one work agent or two explorers. Keep heavy validation on Mac/CI.
- NAS results never establish runtime or memory-performance claims.
