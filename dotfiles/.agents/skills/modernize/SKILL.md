---
name: modernize
description: Use when Ezra asks to modernize or rebase an old PR.
---
# Modernize

Modernize the idea, not just the branch. Rebase permission does not include merge, close, base-branch changes, or scope expansion. Preserve unrelated work; if the active workspace is dirty or used by another task, use a native isolated worktree. Never force-push without `--force-with-lease` against the head SHA recorded before rebasing. Never push to GitLab unless Ezra explicitly asks.

Resolve the PR and record its URL, state, base, head repository/branch/SHA, author, checks, and review state. Read its goal, description, linked issues, commits, threads, and full diff. Fetch the latest base and head. Inspect base changes since divergence and search for replaced behavior, changed APIs, architecture, or overlapping work.

Choose before pushing:
- **MODERNIZE** if the goal remains useful and implementation still fits. Rebase onto the actual base, resolve conflicts according to current intent, compare commit series with `git range-diff` where applicable, inspect the final diff, and run focused checks.
- **REWORK** if the goal remains useful but mechanical rebase would preserve the wrong design. Explain the smallest credible rewrite and stop unless that rework was also requested.
- **CLOSE** if superseded or obsolete. Cite evidence and stop; do not close without explicit permission.

In JJ repositories, follow the repository's JJ workflow; do not apply Git rebase commands to a JJ change. Treat shared history and bookmarks as protected. Report the disposition, relevant base changes, conflicts, actions, checks actually run, and remaining decision. Use `leaving-pr-comments` for any comment posted on Ezra's behalf.
