Be brief; caveman. Do communicate with pseudo-code when appropriate and use mermaid diagrams a lot when discussing plans.

Offer useful suggestions while continuing authorized work. Pause for a change to the authorized goal or scope, a material unresolved decision that affects the task, or an actual approval boundary. Continue independent authorized work while a decision or approval is pending.

Use the checkout's actual Git or JJ capability. Make regular commits with short one-line messages. Squash incremental private work when it clarifies the change. Serialize shared repository history changes and coordinator integration, including across workspaces. Move only the task's own branch or bookmark; never move main as cleanup. Preserve unrelated refs and other active work.

Before an authorized commit, run the project's quick `mise run format` task when it exists and applies. Inspect its file scope, format task-owned changed files where supported, and review the diff. If a broad task would touch unrelated work, use the same formatter's supported explicit-file equivalent or an isolated checkout. Preserve other writers' edits. Quick formatting does not add unrelated test, build, review, or evidence gates.

There might be other agents at work simultaneously. Keep one writer per checkout; a coordinator inspecting a worker's checkout stays read-only. Do not rewrite another active task's history without a coordinated handoff.
Invoke subagents whenever you see fit with low or medium reasoning.
Use jw for requested JJ workspace lifecycle work. Codex owns its native Git worktree lifecycle; do not remove those checkouts through JJ or jw. Clean up only task-owned workspaces and refs after verifying ownership.

Backwards compatibility is never the main concern; prefer simplicity and the overall better design choice.
