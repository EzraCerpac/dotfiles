# Native Codex project setup

Keep native tasks in their app-created checkout, with one writer per checkout.
Codex owns its worktree lifecycle. JJ adoption does not authorize removal through
JJ, jw or a gardener. A coordinator needs an editing checkout only when it owns
integration work. The global AGENTS file retains these ownership boundaries.

Choose a native worktree for a new authorized coding task in a Git repository.
A read-only coordinator can stay local, as can work without Git and an interactive
session that must keep its existing checkout. Respect the user's requested
environment and the task-creation tool's requirements. Local task creation never
transfers another writer's checkout to the new task.

The app's [Git settings](https://learn.chatgpt.com/docs/developer-settings) expose
branch naming, force-push behavior, commit generation and PR generation prompts.
Those UI preferences have no verified `config.toml` key in the installed CLI
0.159.2 public schema. The regular private `~/.codex/config.toml` remains under
app ownership; never replace it with a public dotfile or invent UI-setting keys.

## One manual settings handoff

After reviewing and applying the source instructions, open **Settings > Git**:

- Use `wip/` as the task branch prefix where the branch-naming control accepts a
  prefix. Keep `main` out of task cleanup.
- Keep force pushing disabled by default. A deliberate rewrite of an owned task
  branch needs an explicitly coordinated push.
- Paste `~/.codex/app-settings/git-commit-prompt.md` into the commit-generation
  prompt field and `~/.codex/app-settings/git-pr-prompt.md` into the PR-generation
  prompt field. Until source application, use the same files under
  `dotfiles/.codex/app-settings/` in this checkout.
- Leave Review delivery at the user's existing choice; this task does not
  require changing it.

The prompt files are editable values for the UI, not automatically loaded config.
Keep the global one-line-commit and GitHub attribution fallback until the equivalent
UI values are saved and verified. Other clients still need those instructions.

In **Settings > Worktrees**, keep the worktree root at `~/.codex/worktrees` and
turn off automatic deletion during the adopted-JJ rollout. Do not archive a
worktree containing unretained local assets. The [worktree documentation](https://learn.chatgpt.com/docs/environments/git-worktrees)
describes app snapshots and restoration, but preservation of ignored project
assets and adopted JJ metadata is not established by our app pilot. The actual
pilot covered creation, adoption, review, handoff and chat archive/reopen while
the checkout remained present; deletion/restoration still needs an explicit test.
No verified `config.toml` key for these worktree UI preferences was found.

In **Local environments**, select each actual project and inspect its checked-in
`.codex/environments/environment.toml`. The schema matches the installed app's
generated Games file: `version`, `name`, `[setup].script`, and actions containing
`name`, `icon`, `command`. Only those fields are used. The jw project fetches locked
dependencies at setup and builds/tests only through actions. Dotfiles setup checks
checkout files and does not apply configuration to the host. Its test actions do
not run `dots up` or a bootstrap. The pinned ownership test action requires the
selected JJ executable to report the full tested revision; stable JJ will fail
that deliberate prerequisite check.

The old dotfiles setup pointed at `~/.config/mise` for status. The revised setup
checks the new checkout itself, so a native worktree does not route setup to the
active primary source.

The [local environment documentation](https://learn.chatgpt.com/docs/environments/local-environment)
states that setup runs when a new worktree is created and actions run in the
integrated terminal. TOML and command validation are complete; app UI import and
an actual newly created worktree consuming these files remain untested. Save or
import through the app and inspect its generated file before relying on automatic
setup. Do not silently run setup in an actively owned primary checkout.

Finally, use a local-backed task to apply the prepared **jj Workspace Gardener**
prompt-only update. The supported automation tool rejects this delegated Work
task. Keep its weekly schedule, name, model and other settings unchanged. No
undocumented automation storage update is a substitute for confirmed activation.

## Project assets

The thesis owns a separate explicit setup script and copied-instruction allowlist.
Its live Main author checkout stays in place. Use verified frozen data with actual
read-only access or task copies; symlinks alone do not enforce read-only access.
Use separate node_modules, build/figures, output/manuscript-interpretation and
mutable working-notes. Share tool caches only where concurrent writers are
supported. Promote selected outputs deliberately. Do not port shared writable
`.jwlinks.toml` links or blanket-copy ignored content.

Activate the workstation JJ pin only after active JJ writers yield and latest
local metadata is preserved. Install the verified ownership-aware jw and apply
the instructions first. The pin recipe in `resources/jj-pr9943/workstation.toml`
is not loaded by routine profiles; explicit host activation is documented in
[software ownership](software-ownership.md). Merging these source files cannot
silently select it through `dots up`. This change applies no live security grants,
private app preferences, installed tools or thesis primary state.
