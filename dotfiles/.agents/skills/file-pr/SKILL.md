---
name: file-pr
description: Use when Ezra asks to create, open, or file a pull request.
---
# File PR

Confirm the correct VCS, remote, base, branch/bookmark, and current diff. Check whether a PR already exists and ensure its contents match the request. Respect repo templates and title conventions; lead the description with the user problem and resulting behavior, then concise implementation and checks actually run. Do not claim unrun checks passed or that staged configuration is installed.

Before submitting, inspect the title, body, quotes, and attachments for secrets or private details. Use GitHub PR tooling only for GitHub remotes. Never push to a GitLab remote unless Ezra explicitly asks for that push; creating a PR does not imply permission to push to GitLab. Follow the repository's JJ or Git history instructions and preserve unrelated changes.

Use `leaving-pr-comments` for any comment posted on Ezra's behalf. If the user also asked to monitor the PR, continue with `babysit-pr`. Include the verified model and harness only when the harness exposes them; otherwise name the harness without guessing.
