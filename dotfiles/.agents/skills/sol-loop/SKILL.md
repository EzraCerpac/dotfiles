---
name: sol-loop
description: Use when Ezra explicitly requests an iterative independent code review loop, for example "sol loop".
---
# Sol loop

Use one independent reviewer per round. In T3 Code, first inspect `orchestrator_capabilities` and use its supported delegation mechanism to select GPT Sol; outside T3 use a supported Sol subagent if available. Do not substitute another model silently. If unavailable, say so and continue the primary task without claiming independent review.

Default to three rounds total. Extend to five only for security, permissions, auth, data-loss, or concurrency issues with an evidenced blocker/should finding, or when Ezra asks. Stop early when only nits remain. Keep a ledger of stable finding IDs, severity, outcome, and usage only when the harness reports it.

Establish the base and scoped diff for the actual VCS. For Git, fetch/read the relevant refs before selecting the merge base. For JJ, inspect change IDs, bookmarks, and workspace state; use the task change and repository's JJ conventions. Do not stash, discard, or include unrelated edits. State intent, scope, and checks already run to the reviewer; request review only, with no edits, commits, pushes, comments, or nested reviewers.

Classify findings yourself: blocker means intended behavior is wrong; should means a realistic bug in scope; nit means the rest. Make the smallest justified fix, add a focused regression test only when needed and supported by the project, or decline with evidence. Do not grow scope to appease a reviewer. Re-run focused checks after behavior changes. Request another round only for unresolved blocker/should items, changed behavior, or review that no longer covers the diff. Agreement is not proof; report unresolved disagreement and any checks not run.
