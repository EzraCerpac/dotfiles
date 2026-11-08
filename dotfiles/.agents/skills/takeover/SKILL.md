---
name: takeover
description: Use when Ezra explicitly asks to take over an existing PR, branch, or agent task.
---
# Takeover

Finish the original goal while preserving prior contributors' credit. Read the original request, current code and head, review findings, later user corrections, and uncommitted state. Treat the handoff as context, not proof. Do not defend a flawed implementation because someone already built it.

Inspect the actual Git or JJ checkout. Preserve authorship, co-author trailers, bookmarks, and other contributors' work. Do not overwrite unrelated work or update the original PR in place unless explicitly requested. Use `modernize` to determine whether an old PR still fits current code. Rework only what is needed to finish the original goal.

Verify the original failure and realistic workflow using checks proportionate to the change. If asked to file/update and monitor a PR, use `file-pr` then `babysit-pr`. Use `leaving-pr-comments` for replies. Merge or close an inherited PR only when Ezra explicitly authorizes that action. Report inherited state, changes, proof, preserved credit, and remaining decisions.
