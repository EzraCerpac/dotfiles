# CerpacNAS policy

- Existing root SSH access is intentional. Use native Codex Remote SSH tasks and exact project/workspace paths.
- Never use `--dangerously-bypass-approvals-and-sandbox`, `sudo`, Docker, or package-manager mutation from an agent.
- Code crosses machines only through published `wip/...` bookmarks and verified commit ids.
- Configuration crosses through dotfiles `dev` plus targeted review before apply.
- Artifacts cross through allowlisted, non-deleting rsync. Dry-run first.
- Run one work task or two explorers. Keep heavy validation on Mac/CI.
- NAS results never establish runtime or memory-performance claims.
