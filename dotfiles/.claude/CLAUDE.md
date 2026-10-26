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

Unless the task is extremely small, delegate heavily: tell each subagent what to do, which model and reasoning effort fit the task, and what to return. Limit the work you do yourself. Choose models by strength:
- Opus does frontend and UI design and any substantial writing.
- Sonnet suits routine implementation and research subagents that do not need Opus-level judgement.
- Haiku is the cheap native choice for search, file inventories, log triage and other read-only fan-out.
- Through Codex (codex-subagents plugin: `codex_task`, `codex_task_group`, `codex_followup`, `codex_wait_any`; pick the model with `advanced.model`): gpt-6.1-luna (`luna`) for bulk read-only work, consider this model free; gpt-6.1-terra for simple browser and desktop computer-use tasks; gpt-6.1-sol (`sol`) for more demanding computer use and code review. Never spawn GPT-6 Astra as a subagent.
- Never spawn Fable or Astra as a subagent.

Before calling a large change done, have gpt-6.1-sol review it through Codex, then fix or explain each finding. Brief narrowly, ask for concise findings with file:line references, and spot-check results you build on. Effort: high by default, xhigh for hard problems. Sol is extremely strict, so consider if all findings are worth adressing. Don't let perfect be the enemy of good and beware of scope creap.

# Tools and formatting

- Python via uv; mise as the general tool manager. Local web servers via the linked Portless install and the portless skill.
- Before committing code changes, run the repo's quick `mise run format` when it exists, scoped to the changed files. If it can't be scoped safely around unrelated work, use a narrower formatter command or report the limitation; never reformat unrelated files.
- Repos may hold instruction files (such as AGENTS.md) that are deliberately untracked via `.git/info/exclude`: read and follow them even though git doesn't show them, and never commit them.
