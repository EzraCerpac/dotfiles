---
name: work-on-cerpacnas
description: Manage CerpacNAS work with native Codex Remote SSH tasks plus JJ and jw handoffs, chezmoi configuration updates, project inventory sync, validation limits, and allowlisted artifact transfer. Use when the user mentions CerpacNAS, NAS agents, remote thesis work, Mac-to-NAS handoff, remote Codex tasks, NAS project sync, or moving artifacts between the Mac and NAS.
---

# Work on CerpacNAS

Use Codex Remote SSH for tasks. Use `nas` only for repository/config coordination, validation, and artifacts.

## Resolve target first

1. Prefer an explicitly named project.
2. Otherwise use current Codex project/cwd.
3. In chezmoi source, use `nas config status|update`; do not select a manifest project.
4. In a configured project, omit project only when `nas` can infer it from cwd.
5. If `nas projects sync` is requested from an unconfigured repository, add that repository to the manifest when its identity and paths are unambiguous; follow **Add a missing current project** below.
6. If current path is unknown or ambiguous, stop and ask. Never choose the only manifest entry as fallback.

Run `nas doctor` before first NAS operation. Read [remote policy](references/remote-policy.md) before changing validation or transfer behavior. Read [project manifest](references/projects-manifest.md) before adding projects or artifacts.

Root login is intentional. Never invoke `sudo`, Docker, dangerous sandbox/approval bypass flags, or system package mutations from a remote task.

### Add a missing current project

When sync fails because cwd is not configured:

1. Confirm cwd is the repository root and read its fetch remote. Derive the project key from the repository name, local path from cwd, and NAS path by placing the same repository name directly below `remote_project_root` unless the user names another path.
2. Read [project manifest](references/projects-manifest.md). Edit the manifest through its chezmoi source, never the rendered file. Add a rendered project-rules file too; reuse supplied repository instructions when available.
3. Preserve the repository's remote name when practical. Stop if the remote URL, project key, local root, NAS destination, or rules are ambiguous or conflict with another entry.
4. Validate the chezmoi template and skill. Commit configuration on the configured dotfiles branch. Publishing still requires explicit consent when current instructions prohibit pushing.
5. After publication, run `nas config update`, then `nas projects sync <project>` to clone or fetch both hosts and install ignored `AGENTS.md`.

## Run native remote tasks

Use Codex app project/thread tools, not `nas agent`, `ssh codex exec`, or tmux:

1. List Codex projects and find host `cerpacnas`.
2. Choose deepest saved remote project containing target path. Never silently substitute another repository. If no saved project contains target, tell user which remote path must be added.
3. Create task with local environment. Never request a built-in Git worktree.
4. Inspect and steer through Codex thread tools.

For read-only exploration:

- Sync/fetch correct remote repository first.
- Create remote task directly in canonical repository; no bookmark, push, owner state, or `jw` workspace.
- Use `gpt-5.3-codex-spark`, read-only instructions, and NAS validation limits.

For implementation:

- Prepare exact `wip/<task>` handoff and NAS `jw` workspace first.
- `--push` requires explicit user publication consent. Never infer consent from request to run an agent.
- Create remote task against saved remote project containing returned workspace. Prompt it to work only in that exact path and read its `AGENTS.md` first.
- Use `gpt-5.6-sol`. Allow one work task, or two read-only explorers. Never parallelize heavy commands.
- Require one described, conflict-free result commit, moved task bookmark, then empty working commit.

Built-in collaboration subagents stay on current host. They do not replace Codex Remote SSH tasks.

## Hand off code

- Describe and conflict-check selected commit.
- Put exact result on `wip/<task>`.
- Run `nas handoff <project> <task> --to nas`; add `--push` only after explicit consent.
- Return with `nas handoff <project> <task> --to mac [--push]` after remote task stops.
- Never move `main`; never sync `.git`, `.jj`, or live project directories.

## Sync configuration, projects, and artifacts

- In chezmoi, use `nas config status` then `nas config update`. Configuration travels through published dotfiles `dev`; command never publishes it.
- Use `nas projects sync [project|--all]` to clone/fetch and install ignored rules. Omitted project resolves from cwd or fails.
- Use `nas validate <project> <task> web-format|web-pure|web-type|julia-format` for cheap checks.
- Calibrate one Julia seam with `nas validate <project> <task> focus:<seam> --calibrate`.
- Use `nas artifact plan <project> <key> --direction push|pull` first. Matching transfer with `--apply` consumes plan receipt.
