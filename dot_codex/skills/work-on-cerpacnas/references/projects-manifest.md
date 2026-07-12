# Project manifest

Edit `~/.config/cerpacnas/projects.toml` through chezmoi, never directly on one host.

Each project requires repository URL, Mac/local path, NAS path, JJ remote name, and rendered project-rules file. Each artifact needs a short key and project-relative path.

Artifact paths must stay inside the project and cannot contain `.git`, `.jj`, `.ssh`, `.codex`, `node_modules`, `__pycache__`, absolute paths, or `..`.

`projects sync` clones missing repositories with `jj git clone`, fetches the configured remote, and installs ignored `AGENTS.md`. It never merges, rebases, pushes, deletes, or copies working trees.
