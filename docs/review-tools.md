# Review and workflow shortcuts

- `git diff` opens through the shared `hunk pager`
- `git show` and embedded diff views use `delta --side-by-side --paging=never`
- In `jjui`, `\ h` compares exactly two checked revisions, lower graph row → upper row. With nothing checked, the first menu option compares the highlighted revision with its parent. With zero or one checked, the menu also lets you set, compare, or clear a session-only base; more than two shows an error. Normal `d` reviews the highlighted revision.
- `wt` is declared in the workstation profile and initialized in fish
- `jw` is shell-initialized in fish and zsh; `dots up` updates existing workstation installs from verified jj-waltz main using isolated builds and a retained rollback binary
- On workstations, `jj resolve` tries Mergiraf first and opens remaining conflicts in Neovim's `jj-diffconflicts` view. jjui Shift-R targets the highlighted change and refreshes afterward. Edit the left pane, save, then `:qa`; `:cq` cancels the current file and preserves its original conflict. If conversion cannot preserve the file safely, the editor opens the original conflict and explains that partial automatic resolutions were discarded. `jj resolve --tool diffconflicts` skips Mergiraf; `--tool vimdiff` keeps the four-pane alternative.
- `jj-waltz` skill content is linked from this source checkout to both `~/.codex/skills/jj-waltz` and `~/.config/opencode/skills/jj-waltz`
- `wto <branch> [prompt...]` creates or switches a worktree and launches `opencode`
- `prdiff [pr]` opens `gh pr diff` output in Hunk
- `glf [git-log-args...]` selects a commit and replays it in `gitlogue`
- `gitlogue-menu` selects a Gitlogue mode, author, date range, commit, or theme
