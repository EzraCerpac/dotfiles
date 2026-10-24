<!-- Shared Codex policy: agentic-cleanup-20261005 -->
Use /visualize heavily to show information in a nice way.

Offer useful suggestions while continuing authorized work. Pause for a change to the authorized goal or scope, a material unresolved decision that affects the task, or an actual approval boundary. Continue independent authorized work while a decision or approval is pending. Use the question tool when asking Ezra a question. When appropriate, suggest useful next steps; you are a teammate.

Before saying done, run the smallest check that matches the task's risk and the user's actual success criterion. Normal tests or direct inspection are enough unless the task changes a browser UI, physical device, deployed service, performance claim, or other boundary the user will rely on. Do not add evidence packages, provenance tracking, receipts, digests, independent review, fresh replications, or extra acceptance gates unless the user requests them or they are necessary for publication, deployment, security, destructive work, or scientific claims being promoted as final evidence. Report material checks that remain open.

Use native Codex Git worktrees by default for isolated agent coding. Codex owns their creation, attachment, restore, and archive lifecycle. Inspect the actual checkout before choosing Git or JJ commands: a Git-only worktree needs Git; use JJ where the checkout supports it. `jw` is optional for JJ workspace work; read the jj-waltz skill when using it. Do not create a second workspace merely to satisfy a ritual or assume changing a shell directory retargets Codex's native Git panels. Run commands in the selected checkout explicitly and report its actual path and capabilities. Do not remove or forget Codex-owned worktrees through destructive JJ or `jw` cleanup.

Keep one writer per checkout; orchestrators inspect and coordinate without editing a worker's checkout. Separate Git worktrees still share refs, and JJ workspaces can share history. Never move or rewrite another active task's branch, bookmark or ancestors without a coordinated handoff; serialize shared JJ history mutations and coordinator integration. Untracked or ignored instructions, data, and secrets do not automatically follow into an isolated checkout; inspect what is needed and copy or isolate it explicitly within the authorized scope.

Make short, one-line commits. Squash incremental private work and rebase private task commits when that clarifies the stack; prefer merges for shared history. Serialize history-changing commands within a repository, including across workspaces. In JJ checkouts, describe a change before creating children, move only the task's bookmark to the completed, described change, then leave the working copy on an empty child. In Git checkouts, use the task's own branch. Never move main as task cleanup. Preserve unrelated refs and externally owned worktrees; clean up only task-owned resources when appropriate. Pushing to GitHub remotes is fine within the task. Never push to GitLab remotes (e.g. the thesis `origin` on gitlab.ewi.tudelft.nl) unless the user explicitly asks for that push. Use `gh stack` only for actual stacked PR work after checking checkout compatibility.

Before an authorized commit, run the project's quick `mise run format` task when it exists and applies. Inspect its file scope, format task-owned changed files where supported, and review the diff. If a broad task would touch unrelated work, use the same formatter's supported explicit-file equivalent or an isolated checkout. Preserve other writers' edits. Quick formatting does not add unrelated test, build, review, or evidence gates.

During authorized coding work in JJ checkouts, agents may recover inspected pre-existing mutable divergence. Inspect all variants, affected descendants, bookmarks and other active work first. Use `jj converge --no-interactive` with explicit revisions for one change ID at a time. Check the operation diff, remaining divergence, file conflicts and bookmark targets afterwards; command success alone is not proof of recovery. Stop when recovery is ambiguous or would affect protected history or other active work. Read-only audits remain read-only. Consult the jj-waltz lifecycle reference for recovery details.

Edit mise-managed jj config through its linked file or source. For deliberate direct config changes, use `jj config ... --file <path>` after checking loaded config paths. For stack tests, use `jj run --revision '<revset>' --ignore-changes --jobs 1 -- <command>`; use rewriting mode only for intended fixes, and `--ignore-errors` only when collecting all failures deliberately.

Delegate heavily, by prompt rather than persona: tell each subagent what to do, which model and effort fit the task, and what to return. Do not create or rely on fixed agent roles. gpt-6-luna is the default subagent model; use it freely, even 30 at once, for read-only work such as search, inventories, logs, extraction, digests and research, but never for edits. Choose writing subagents by strength: gpt-6.1-sol for implementation, debugging and anything that benefits from computer use or browser and desktop automation, where Codex is strongest; Claude Opus through Claude Code MCP for frontend and UI design and any substantial writing; Claude Sonnet through Claude Code MCP for routine Claude-side implementation. GPT-6 Astra may lead a task but is never spawned as a subagent. Have gpt-6.1-sol review every large change Claude makes before calling it done. Keep planning, architecture, integration and final accountability in the lead; extremely small, bounded edits may finish there. Brief narrowly, ask for concise findings with file:line references, and spot-check results you build on. Follow the runtime host's delegation policy, available models and capacity; do not create a new task unless authorized. Use native Codex worktrees for authorized isolated coding, and local for read-only coordination or an interactive checkout that must stay in place. Local mode does not authorize edits to another writer's checkout.

Some AGENTS.md and other content is intentionally not tracked (see .git/info/exclude).

Use uv for Python. Follow a project's declared package manager and existing lockfile workflow, including npm, pnpm or yarn. Prefer bun for new TypeScript projects and projects that already use it, when bun is available on the selected host. Do not migrate an existing project or install bun solely to satisfy this preference. Prefer the built-in browser for visual web checks and the most direct API or CLI for semantic work. For local web servers, use the linked Portless installation and its skill when available on the selected host.

At task end, close only task-started resources, including simulators, apps, servers. Preserve pre-existing resources: if a requested browser check was already open or useful to show Ezra, leave it open. Verify ownership first.

Exploration may finish with a useful partial result and clear caveats. Do not turn exploratory work into publication-grade validation. Run focused tests for changed behavior and likely regressions. Do not add tests or smoke checks only as a completion ritual.

Backwards compatibility never main concern, prefer simplicity and overall best design-choice. Keep codebase simple. Less is more. Again: always evaluate if less code can do the job.

For file and directory discovery, prefer fd over find.

Prefer using the in-app browser over external browsers.

For PRs and messages on GitHub, begin with this disclosure. Use the exact model identifier only when verified
from this task's supported metadata. If it cannot be verified, write "model
unverified". Do not guess the provider, model version, variant or reasoning effort
from a task title, generic label, or brand-selection placeholder:

> [!NOTE]
> **<verified model identifier, or model unverified>** is writing on behalf of Ezra.

Describe the final change for a reviewer who has not seen the conversation. Lead with the concrete problem and resulting behavior. Use a before/after example when helpful. Include only relevant implementation detail, validation actually performed, and material limits. Keep simple changes to a short paragraph plus validation. Follow the repository PR template when present. Do not claim unrun tests passed or staged configuration is installed. Omit conversational history and abandoned approaches unless they explain a review-relevant tradeoff. Do not add scope, commits, files, or deployment claims absent from the diff and evidence.
<!-- End shared Codex policy -->
