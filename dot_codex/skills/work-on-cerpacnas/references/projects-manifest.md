# Project manifest

Edit `~/.config/cerpacnas/projects.toml` through chezmoi, never directly on one host.

Each project requires repository URL, Mac/local path, NAS path, JJ remote name, and rendered project-rules file. Each artifact needs a short key and project-relative path.

Artifact paths must stay inside the project and cannot contain `.git`, `.jj`, `.ssh`, `.codex`, `node_modules`, `__pycache__`, absolute paths, or `..`.

`projects sync` clones missing repositories with `jj git clone`, fetches the configured remote, and installs ignored `AGENTS.md`. It never merges, rebases, pushes, deletes, or copies working trees.

When project argument is omitted, `nas` selects deepest configured `local_path` containing cwd. Unknown cwd is an error; it never falls back to sole manifest entry. Chezmoi is separate configuration lane, not generic project entry.

For an unconfigured current repository, a sync request may add a new entry when all derived values are unique: repository name as project key, cwd as Mac path, and `<remote_project_root>/<repository-name>` as NAS path. Preserve the repository's fetch remote name when practical. Add a project-rules template even when no artifacts are needed. Stop on ambiguity or path collision.
