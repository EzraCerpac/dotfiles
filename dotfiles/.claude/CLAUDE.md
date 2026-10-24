# Checkouts and version control

- Use the checkout's actual workflow: Git or JJ, whichever it already uses. Run every command explicitly in the selected checkout; changing the shell directory does not retarget the app's Git panel, so report the checkout you actually worked in and take task status from its own Git/JJ output.
- Worktrees the Codex or Claude app created belong to that app: work in them as they are and leave their lifecycle to it. Do not adopt them into JJ just to route a task.
- Use the jj-waltz skill and `jw` for requested JJ workspace lifecycle work or unclear JJ ownership, and for recovering divergent mutable JJ changes (its lifecycle reference has the procedure; recover one change ID at a time and stop when it is ambiguous or touches protected history or other active work). It is not a mandatory step for ordinary coding.
- One writer per checkout. Parallelize independent work in separate authorized checkouts, and serialize history-changing commands within a repository, including across workspaces.

# History and publishing

- Short, one-line commits. Squash incremental private work and rebase private task commits when that clarifies the stack; prefer merges for shared history.
- Move only the task's own branch or bookmark; never move main as task cleanup. In JJ: describe a change before creating children, move the task bookmark to the finished, described change, then leave the working copy on an empty child.
- Preserve unrelated refs and worktrees you don't own; clean up only resources the task created.
- Pushing to GitHub remotes is fine within the task. Never push to GitLab remotes (e.g. the thesis `origin` on gitlab.ewi.tudelft.nl) unless Ezra explicitly asks for that push.
- Use `gh stack` only for real stacked-PR work, after checking the checkout supports it.
- Any prose posted on GitHub on Ezra's behalf (issue and PR comments, PR descriptions, review summaries, discussion posts) starts with exactly this disclosure, filled with the actual model name (e.g. Opus 5.5, Sonnet 5.5, Haiku 5.5):
  > [!NOTE]
  > **<model name>** is writing on behalf of Ezra.

# Delegation and models

Delegate heavily, by prompt rather than persona: tell each subagent what to do, which model and effort fit the task, and what to return. Do not create or rely on fixed agent roles. Choose models by strength:
- Opus leads by default and does frontend and UI design and any substantial writing itself or in an Opus subagent.
- Sonnet suits routine implementation and research subagents that do not need Opus-level judgement.
- Haiku is the cheap native choice for search, file inventories, log triage and other read-only fan-out.
- Through Codex (codex-subagents plugin: `codex_task`, `codex_task_group`, `codex_followup`, `codex_wait_any`; pick the model with `advanced.model`): gpt-6-luna (`luna`) for bulk read-only work, run as wide as useful but never for edits; gpt-6.1-sol (`sol`) for anything that benefits from computer use or browser and desktop automation, where Codex is strongest. Never spawn GPT-6 Astra as a subagent.
- Fable only when Ezra asks or Opus at xhigh has already failed.

Before calling a large change done, have gpt-6.1-sol review it through Codex, then fix or explain each finding. Keep planning, architecture, integration and final accountability in the lead, and one writer per checkout. Brief narrowly, ask for concise findings with file:line references, and spot-check results you build on. Effort: high by default, xhigh for hard problems, max only when asked.

# Tools and formatting

- Python via uv; mise as the general tool manager. Local web servers via the linked Portless install and the portless skill.
- Before committing code changes, run the repo's quick `mise run format` when it exists, scoped to the changed files. If it can't be scoped safely around unrelated work, use a narrower formatter command or report the limitation; never reformat unrelated files.
- Repos may hold instruction files (such as AGENTS.md) that are deliberately untracked via `.git/info/exclude`: read and follow them even though git doesn't show them, and never commit them.
