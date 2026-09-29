"""The source-tree re-includes must not re-admit secret-shaped files.

``.gitignore`` re-includes dotfiles/, templates/ and seeds/ so user-global
ignore patterns cannot hide managed files. That negation also overrides the
repository's own secret patterns unless they are repeated after it.
"""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Only the repository's .gitignore counts: no personal excludesfile.
GIT_ENV = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}

MUST_IGNORE = (
    ".env",
    "dotfiles/.config/app/.env",
    "dotfiles/.config/app/.env.production",
    "templates/.config/app/secrets/token.txt",
    "seeds/.config/app/secrets/token.txt",
    "dotfiles/.ssh/id_ed25519",
    "dotfiles/.ssh/id_rsa",
    "dotfiles/.config/app/client.pem",
    "dotfiles/.config/app/tls.key",
    "dotfiles/.config/app/identity.p12",
    "dotfiles/.config/age/keys.txt",
    "seeds/.config/app/settings.local",
    "locks/mise.workstation/npm-example/1.0.0/aube-lock.yaml",
)
MUST_TRACK = (
    "dotfiles/.config/fish/config.fish",
    "dotfiles/.ssh/id_ed25519.pub",
    "dotfiles/.config/app/.env.example",
    "setup-scripts/setup/secrets",
    "encrypted/bootstrap.json.age",
)


def is_ignored(path: str) -> bool:
    result = subprocess.run(
        ["git", "check-ignore", "--quiet", "--no-index", path], cwd=ROOT, env=GIT_ENV, check=False
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(f"git check-ignore failed for {path}")
    return result.returncode == 0


class GitignoreTests(unittest.TestCase):
    def test_secret_shaped_files_stay_ignored_inside_source_trees(self) -> None:
        self.assertEqual([path for path in MUST_IGNORE if not is_ignored(path)], [])

    def test_managed_files_are_not_ignored(self) -> None:
        self.assertEqual([path for path in MUST_TRACK if is_ignored(path)], [])

    def test_no_tracked_file_is_ignored(self) -> None:
        listing = subprocess.run(
            ["git", "ls-files", "--cached", "--ignored", "--exclude-standard"],
            cwd=ROOT, env=GIT_ENV, capture_output=True, text=True, check=True,
        )
        self.assertEqual(listing.stdout.split(), [])


if __name__ == "__main__":
    unittest.main()
