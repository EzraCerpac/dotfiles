---
name: full-stop
description: Use only when the user explicitly asks to prepare a change through a PR ready for their merge, such as "full stop" in a clear task instruction.
---
# Full stop

Follow `full-send` through implementation, focused proof, `sol-loop`, filing with `file-pr`, and `babysit-pr`. Sol approval on the final behavior diff is a readiness gate: if Sol is unavailable, times out, or leaves an unresolved blocker or should finding, report the blocker and do not call the PR ready. Stop when every other full-send readiness gate passes. This request authorizes task-branch commits, pushes, rebase conflict resolution, and `--force-with-lease` against the observed task-branch head. It never authorizes merging, enabling auto-merge, entering a merge queue, pushing to a default branch, or bypassing protection.

Inspect and disable pre-existing auto-merge or merge-queue enrollment before work; if it cannot be prevented, stop and report the blocker. Recheck before each push. Verify readiness against the final diff and latest PR head: focused proof, required checks green, review findings addressed, no human change requests, branch current, and GitHub says mergeable. Leave the PR open and unmerged. Report its link, head, checks, review outcome, proof, and remaining risks.

Never push to GitLab unless Ezra explicitly asks. Preserve unrelated work and use the repository's actual Git or JJ workflow. Do not trigger this skill from conversational emphasis; require a clear task request.
