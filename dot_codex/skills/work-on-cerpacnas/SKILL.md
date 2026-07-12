---
name: work-on-cerpacnas
description: Manage CerpacNAS remote Codex work through Tailscale SSH, JJ and jw handoffs, persistent remote agents, chezmoi configuration updates, project inventory sync, and allowlisted artifact transfer. Use when the user mentions CerpacNAS, NAS agents, remote thesis work, Mac-to-NAS handoff, remote Codex sessions, NAS project sync, or moving artifacts between the Mac and NAS.
---

# Work on CerpacNAS

Use `nas` as the only daily orchestration interface. Keep code, configuration, and artifacts on separate paths.

## Start safely

1. Run `nas doctor`.
2. Run `nas projects status <project>` before handoff or agent work.
3. Read [remote policy](references/remote-policy.md) before changing validation or transfer behavior.
4. Read [project manifest](references/projects-manifest.md) before adding projects or artifacts.

Root login is intentional. Still keep all work below `/root/Projects`; never invoke `sudo`, Docker, dangerous sandbox/approval bypass flags, or system package mutations from an agent. `--skip-git-repo-check` is permitted only for secondary JJ workspaces without `.git`.

## Hand off code

- Describe and conflict-check the selected commit.
- Put exact result on `wip/<task>`.
- Run `nas handoff <project> <task> --to nas`; add `--push` only with explicit publication intent.
- Start work only after command prints NAS `jw` workspace.
- Return with `nas handoff <project> <task> --to mac [--push]`.
- Never move `main`; never sync `.git`, `.jj`, or live project directories.

## Run agents

- Exploration: `nas agent start <project> <task> --mode explore -- <prompt>`.
- Implementation: `nas agent start <project> <task> --mode work -- <prompt>`.
- Inspect with `nas agent status`, `logs`, or `attach`; stop only by run id.
- Allow one work agent or two explorers. Keep validation inside NAS limits from `AGENTS.md`.
- Run cheap checks with `nas validate <project> <task> web-format|web-pure|web-type|julia-format`.
- Calibrate a Julia seam with `nas validate <project> <task> focus:<seam> --calibrate`; later runs omit `--calibrate`.
- A work agent must move the task bookmark to its described result and leave an empty working commit directly above it.

## Sync configuration and artifacts

- Use `nas config status` before `nas config update`.
- Use `nas projects sync <project>` to clone/fetch and install local rules. It never integrates work.
- Use `nas artifact plan <project> <key> --direction push|pull` first. The matching `push` or `pull --apply` consumes that one-hour plan receipt.
- The return handoff reports exact bookmark, commit, recorded checks, and Mac-only skipped checks. Also report run id and artifact key when used.
