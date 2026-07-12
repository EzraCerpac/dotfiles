# AGENTS.md

- Use `jj`. Make short, one-line commits. Squash incremental changes when useful, prefer merges over rebases, and finish on an empty working commit.
- Move only `wip/...` bookmarks for task work. Never move `main` or push without explicit approval.
- Use `jw` for workspaces. Never use built-in Git worktrees. Clean up task workspaces and bookmarks when appropriate.
- Avoid divergent commits. Resolve accidental divergence immediately.
- Prefer simple designs over backwards compatibility and unnecessary architecture.
- Use `uv` for Python commands.
- Explain TypeScript, web-app, and API architecture in plain language.

## CodeGraph

When `.codegraph/` exists, use CodeGraph before `rg`, `fd`, or broad file reads to locate or understand code. Use `codegraph explore` for questions and call paths, and `codegraph node` for one symbol or file.

## CerpacNAS

- Root login is intentional. Never use `sudo`, Docker, system package mutation, or dangerous sandbox or approval bypass flags.
- Do not run heavy commands in parallel.
