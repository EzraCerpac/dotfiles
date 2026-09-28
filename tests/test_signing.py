"""Workstation Git and JJ configuration produce SSH-signed commits.

Both templates are rendered through mise into a throwaway home holding a
fresh, passphrase-less ed25519 key, then used for a real commit (Git) and a
real push to a local bare remote (JJ signs on push).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires
from lib.tera import render_profile_dotfile

SIGNATURE_HEADER = "gpgsig -----BEGIN SSH SIGNATURE-----"


@requires("mise", "git", "ssh-keygen")
class SigningTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="signing-")
        self.addCleanup(temporary.cleanup)
        # render_profile_dotfile renders against <scratch>/home, so HOME matches.
        self.scratch = Path(temporary.name)
        self.home = self.scratch / "home"
        (self.home / ".ssh").mkdir(parents=True)
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "fixture", "-f", str(self.home / ".ssh/id_ed25519")],
            check=True,
        )
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_NOSYSTEM": "1",
            "SSH_AUTH_SOCK": "",
        }

    def run_checked(self, args: list[str], cwd: Path, **env: str) -> str:
        result = subprocess.run(args, cwd=cwd, env={**self.env, **env}, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, f"{args}\n{result.stdout}\n{result.stderr}")
        return result.stdout

    def test_git_signs_commits_with_the_ssh_key(self) -> None:
        rendered = render_profile_dotfile("workstation", "~/.config/git/config", self.scratch)
        gitconfig = self.scratch / "gitconfig"
        gitconfig.write_text(rendered)
        repo = self.scratch / "repo"
        repo.mkdir()
        git = {"GIT_CONFIG_GLOBAL": str(gitconfig)}
        self.run_checked(["git", "init", "-q"], repo, **git)
        (repo / "file.txt").write_text("signed\n")
        self.run_checked(["git", "add", "file.txt"], repo, **git)
        self.run_checked(["git", "commit", "-q", "-m", "Signed"], repo, **git)
        self.assertIn(SIGNATURE_HEADER, self.run_checked(["git", "cat-file", "commit", "HEAD"], repo, **git))

    def test_nas_git_does_not_require_a_signing_key(self) -> None:
        rendered = render_profile_dotfile("nas", "~/.config/git/config", self.scratch)
        self.assertNotIn("gpgSign", rendered)

    @requires("jj")
    def test_jj_signs_commits_when_pushing(self) -> None:
        signing = self.scratch / "signing.toml"
        signing.write_text(render_profile_dotfile("workstation", "~/.config/jj/conf.d/signing.toml", self.scratch))
        identity = self.scratch / "identity.toml"
        identity.write_text('[user]\nname = "Fixture"\nemail = "fixture@example.invalid"\n')
        jj_env = {"JJ_CONFIG": f"{identity}{os.pathsep}{signing}", "GIT_CONFIG_GLOBAL": os.devnull}
        remote = self.scratch / "remote.git"
        repo = self.scratch / "jj-repo"
        self.run_checked(["git", "init", "-q", "--bare", str(remote)], self.scratch, **jj_env)
        self.run_checked(["jj", "git", "init", "--colocate", str(repo)], self.scratch, **jj_env)
        self.run_checked(["jj", "git", "remote", "add", "origin", str(remote)], repo, **jj_env)
        (repo / "file.txt").write_text("signed on push\n")
        self.run_checked(["jj", "commit", "-m", "Signed on push"], repo, **jj_env)
        unsigned = self.run_checked(["jj", "log", "--no-graph", "-r", "@-", "-T", "commit_id"], repo, **jj_env).strip()
        self.assertNotIn(SIGNATURE_HEADER, self.run_checked(["git", "cat-file", "commit", unsigned], repo, **jj_env))
        self.run_checked(["jj", "bookmark", "create", "signed", "-r", "@-"], repo, **jj_env)
        self.run_checked(["jj", "git", "push", "--bookmark", "signed"], repo, **jj_env)
        pushed = self.run_checked(["git", "--git-dir", str(remote), "cat-file", "commit", "signed"], self.scratch, **jj_env)
        self.assertIn(SIGNATURE_HEADER, pushed)


if __name__ == "__main__":
    unittest.main()
