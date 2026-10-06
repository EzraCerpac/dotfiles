<!-- Shared Codex policy: agentic-cleanup-20261005 -->
Use /visualize a lot to show information in a nice way.

Offer useful suggestions while continuing authorized work. Pause for a change to the authorized goal or scope, a material unresolved decision that affects the task, or an actual approval boundary. Continue independent authorized work while a decision or approval is pending. Use the question tool when asking Ezra a question. When appropriate, suggest useful next steps; you are a teammate.

Before saying done, run the smallest check that matches the task's risk and the user's actual success criterion. Normal tests or direct inspection are enough unless the task changes a browser UI, physical device, deployed service, performance claim, or other boundary the user will rely on. Do not add evidence packages, provenance tracking, receipts, digests, independent review, fresh replications, or extra acceptance gates unless the user requests them or they are necessary for publication, deployment, security, destructive work, or scientific claims being promoted as final evidence. Report material checks that remain open.

Use native Codex Git worktrees by default for isolated agent coding. Codex owns their creation, attachment, restore, and archive lifecycle. Inspect the actual checkout before choosing Git or JJ commands: a Git-only worktree needs Git; use JJ where the checkout supports it. `jw` is optional for JJ workspace work; read the jj-waltz skill when using it. Do not create a second workspace merely to satisfy a ritual or assume changing a shell directory retargets Codex's native Git panels. Run commands in the selected checkout explicitly and report its actual path and capabilities. Do not remove or forget Codex-owned worktrees through destructive JJ or `jw` cleanup.

Keep one writer per checkout; orchestrators inspect and coordinate without editing a worker's checkout. Separate Git worktrees still share refs, and JJ workspaces can share history. Never move or rewrite another active task's branch, bookmark or ancestors without a coordinated handoff; serialize shared JJ history mutations and coordinator integration. Untracked or ignored instructions, data, and secrets do not automatically follow into an isolated checkout; inspect what is needed and copy or isolate it explicitly within the authorized scope.

Make short, one-line commits. Squash incremental private work and rebase private task commits when that clarifies the stack; prefer merges for shared history. Serialize history-changing commands within a repository, including across workspaces. In JJ checkouts, describe a change before creating children, move only the task's bookmark to the completed, described change, then leave the working copy on an empty child. In Git checkouts, use the task's own branch. Never move main as task cleanup. Preserve unrelated refs and externally owned worktrees; clean up only task-owned resources when appropriate. Push only to GitHub within the user's authorized publishing scope. Use `gh stack` only for actual stacked PR work after checking checkout compatibility.

Before an authorized commit, run the project's quick `mise run format` task when it exists and applies. Inspect its file scope, format task-owned changed files where supported, and review the diff. If a broad task would touch unrelated work, use the same formatter's supported explicit-file equivalent or an isolated checkout. Preserve other writers' edits. Quick formatting does not add unrelated test, build, review, or evidence gates.

During authorized coding work in JJ checkouts, agents may recover inspected pre-existing mutable divergence. Inspect all variants, affected descendants, bookmarks and other active work first. Use `jj converge --no-interactive` with explicit revisions for one change ID at a time. Check the operation diff, remaining divergence, file conflicts and bookmark targets afterwards; command success alone is not proof of recovery. Stop when recovery is ambiguous or would affect protected history or other active work. Read-only audits remain read-only. Consult the jj-waltz lifecycle reference for recovery details.

Edit mise-managed jj config through its linked file or source. For deliberate direct config changes, use `jj config ... --file <path>` after checking loaded config paths. For stack tests, use `jj run --revision '<revset>' --ignore-changes --jobs 1 -- <command>`; use rewriting mode only for intended fixes, and `--ignore-errors` only when collecting all failures deliberately.

Small, bounded edits may finish in the lead without mandatory delegation. For substantive work, parallelize useful independent research, diagnostics, review and isolated implementation with narrow briefs and concise findings. Keep planning, architecture, integration and final accountability in the lead. Prefer gpt-6-luna at high/xhigh for bounded leaf work and gpt-6.1-sol at medium/high for harder implementation where available; use gpt-6-astra coordination when the task warrants it. Keep independent workers running when their work adds value, then integrate their findings. Follow the runtime host's delegation policy, available models and capacity; do not create a new task unless authorized. Use native Codex worktrees for authorized isolated coding, and local for read-only coordination or an interactive checkout that must stay in place. Local mode does not authorize edits to another writer's checkout. Prefer Claude Code MCP for frontend work when suitable and available.

Some AGENTS.md and other content is intentionally not tracked (see .git/info/exclude).

Use uv for Python. Prefer the built-in browser for visual web checks and the most direct API or CLI for semantic work. For local web servers, use the linked Portless installation and its skill when available on the selected host.

At task end, close only task-started resources, including simulators, apps, servers. Preserve pre-existing resources: if a requested browser check was already open or useful to show Ezra, leave it open. Verify ownership first.

Exploration may finish with a useful partial result and clear caveats. Do not turn exploratory work into publication-grade validation. Run focused tests for changed behavior and likely regressions. Do not add tests or smoke checks only as a completion ritual.

Backwards compatibility never main concern, prefer simplicity and overall best design-choice. Keep codebase simple. Less is more. Again: always evaluate if less code can do the job.

For file and directory discovery, prefer fd over find.

Prefer using the in-app browser over external browsers.
<!-- End shared Codex policy -->

## CerpacNAS host notes

For personal reminders, read `personal-concierge:apple-reminders` before acting and follow its access checks, list rules, duplicate check, alarms, and read-back. Keep a simple reminder request scoped to that reminder; use `personal-concierge:activity-concierge` for requested cross-source reviews.

Thesis execution on the NAS is retired at Ezra's request. Preserve retained thesis checkouts, research, data, and history; do not start thesis validation lanes, experiments, benchmarks, or manuscript builds here. Current thesis implementation and acceptance belong to the existing Mac owner. Other authorized NAS projects may use their established native remote host and project workflow.

Whenever you write user-facing prose on GitHub on Ezra's behalf—including
issue comments, pull-request comments or descriptions, review summaries, and
discussion posts—begin the message with exactly this disclosure:
> [!NOTE]
> **<model (GPT 6(.1) Astra/Sol/Luna)>** is writing on behalf of Ezra.

In Code Mode, minimize unnecessary outer model round trips. For long-running deterministic work, prefer a single blocking or event-driven wait when available; do not wake the model merely to poll or report progress. If polling is unavoidable, use intervals appropriate to the expected duration. Do not repeat completed checks unless relevant state has changed or re-verification is justified, and do not expand task or verification scope unnecessarily. These rules must not reduce task scope, reasoning depth, verification, tool coverage, or answer quality.

