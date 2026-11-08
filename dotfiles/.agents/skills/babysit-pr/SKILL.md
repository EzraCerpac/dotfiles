---
name: babysit-pr
description: Use when Ezra asks to monitor, watch, or babysit a GitHub pull request.
---
# Babysit PR

Monitor the requested GitHub PR through relevant CI and review feedback. First read current checks, comments, reviews, and unresolved threads. Consider unresolved existing feedback as well as new events; check whether earlier findings still apply to the current head. Verify findings in source before changing code; distinguish repo failures from infrastructure flakes. Fix real, in-scope problems and get focused proof before pushing. Explain false positives before resolving them. Keep the PR scoped to the user's goal.

Use exactly one supported watcher per PR. In T3 Code, use `watch_pull_request`; the PR-owning thread owns the watch, and delegated reviewers must not start their own. After starting the watcher, yield until its event arrives. A wake is information, not a merge decision. Call `unwatch_pull_request` before handing off or asking a question. In other harnesses, use their approved PR watcher if available. Do not create a polling or sleep loop. If no watcher is available, report that limitation and review only the state explicitly requested; do not claim continuous monitoring.

Check the live base, head, mergeability, checks, and review state before calling a PR ready. Rebase only when needed and only on the task's own branch, using `--force-with-lease` against an observed head. Respect the repository's Git or JJ workflow and protect other work. Never push to GitLab unless Ezra explicitly asks. Merge only when Ezra explicitly requests merging; otherwise leave the PR open and report readiness or blockers. Never bypass branch protection.

Use `leaving-pr-comments` for comments or replies posted on Ezra's behalf. Before handoff, stop the watcher. Report concrete fixes, CI/review status, proof, and any unresolved blocker without filler updates.
