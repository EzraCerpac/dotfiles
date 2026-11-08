---
name: full-send
description: Use only when the user explicitly asks to take a task through a merged GitHub pull request (for example, "full send").
---
# Full send

The user is asking for end-to-end work through a merged GitHub PR. Complete the requested change, prove it with checks appropriate to the task, obtain independent review with `sol-loop`, file it with `file-pr`, and use `babysit-pr` for CI and review feedback. Fix substantive findings and recheck the final diff.

This explicit request authorizes merging this task's GitHub PR after the merge gate passes, and rebasing this task's branch with `--force-with-lease` when needed. It does not authorize deleting data, production changes, closing an unrelated PR, bypassing branch protections, or force-pushing another branch. Never push to GitLab unless the user explicitly asks for that push. Never use `--admin`.

Before coding, inspect the actual checkout, VCS, branch or bookmark, dirty state, and project instructions. Preserve unrelated work. In JJ, follow the repository's JJ workflow and only move the task's own bookmark. If the current working copy has unrelated changes, work in a native isolated worktree when available.

Use the smallest proof that establishes the behavior: reproduce and retest the failure, run focused project checks, and inspect UI directly only when UI behavior changed. Do not add evidence packages or checks unrelated to the task. Report checks actually run and any material gaps.

Merge only when the latest diff is proven, `sol-loop` has approved the final behavior diff with no unresolved blocker or should findings, required checks pass, review findings are resolved or explained, no human review requests changes, and GitHub reports the PR mergeable and current. If Sol is unavailable, times out, or leaves an unresolved disagreement, stop with the PR open and unmerged; report the review gate blocker. Do not treat missing review as approval. Use the repository's normal merge method and branch protections. If the gate cannot pass safely, leave the PR open and explain the blocker. Do not ask for a decision you can make within this grant; ask when intent is materially ambiguous or a next step exceeds it.

Use `leaving-pr-comments` for comments posted on Ezra's behalf. Final report: PR link, merge result, proof, review outcome, and any remaining risk.
