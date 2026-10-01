from __future__ import annotations

import os
import pty
import select
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FISH = shutil.which("fish")
ZSH = shutil.which("zsh")


class SuperfileShellTests:
    shell: str
    shell_kind: str
    integration: Path
    shell_args: tuple[str, ...]

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="superfile-shell-")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.origin = self.home / "origin"
        self.origin.mkdir()
        self.q_target = self.home / "browse dir" / "Ezra's files"
        self.q_target.mkdir(parents=True)
        self.stale_target = self.home / "stale destination"
        self.stale_target.mkdir()
        self.lastdir_file = self.home / "state dir" / "lastdir's file"
        self.lastdir_file.parent.mkdir()
        self.args_file = self.home / "arguments"
        self.stale_seen_file = self.home / "stale-seen"

        mock_spf = self.bin / "spf"
        mock_spf.write_text(
            "#!/bin/sh\n"
            'if [ "$1" = pl ] && [ "$2" = --lastdir-file ]; then\n'
            '    printf \'%s\\n\' "$SPF_LASTDIR"\n'
            "    exit 0\n"
            "fi\n"
            'printf \'%s\\0\' "$@" >> "$SPF_ARGS"\n'
            'if [ -e "$SPF_LASTDIR" ]; then printf present > "$SPF_STALE_SEEN"; fi\n'
            'if [ -n "${SPF_WRITE_CD:-}" ]; then printf \'%s\\n\' "$SPF_WRITE_CD" > "$SPF_LASTDIR"; fi\n'
            "printf 'APP_OUTPUT\\n'\n"
            'exit "${SPF_STATUS:-0}"\n'
        )
        mock_spf.chmod(0o755)

        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "ZDOTDIR": str(self.home),
            "PATH": os.pathsep.join((str(self.bin), "/usr/bin", "/bin", "/opt/homebrew/bin")),
            "TERM": "xterm",
            "SPF_LASTDIR": str(self.lastdir_file),
            "SPF_ARGS": str(self.args_file),
            "SPF_STALE_SEEN": str(self.stale_seen_file),
            "SPF_WRITE_CD": "",
            "SPF_STATUS": "0",
        }

    def reset_mock_state(self) -> None:
        for path in (self.lastdir_file, self.args_file, self.stale_seen_file):
            path.unlink(missing_ok=True)

    def run_wrapper(self, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        source = shlex.quote(str(self.integration))
        invocation = "spf" + (" " + " ".join(shlex.quote(arg) for arg in args) if args else "")
        if self.shell_kind == "fish":
            script = (
                f"source {source}; {invocation}; set -l spf_result $status; "
                'printf \'__PWD=%s\\n\' "$PWD"; exit $spf_result'
            )
        else:
            script = (
                f"source {source}; {invocation}; local_status=$?; "
                'print -r -- "__PWD=$PWD"; exit $local_status'
            )
        return subprocess.run(
            [self.shell, *self.shell_args, script],
            cwd=self.origin,
            env={**self.env, **(extra_env or {})},
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )

    def assert_pwd(self, result: subprocess.CompletedProcess[str], path: Path) -> None:
        pwd_line = next(line for line in result.stdout.splitlines() if line.startswith("__PWD="))
        self.assertEqual(Path(pwd_line.removeprefix("__PWD=")).resolve(), path.resolve())

    def test_q_changes_directory_and_quit_or_ctrl_c_does_not(self) -> None:
        cases = (
            ("Q", shlex.quote(str(self.q_target)), 0, self.q_target),
            ("q", "", 0, self.origin),
            ("ctrl-c", "", 130, self.origin),
        )
        for key, generated_cd, expected_status, expected_pwd in cases:
            with self.subTest(key=key):
                self.reset_mock_state()
                result = self.run_wrapper(
                    extra_env={"SPF_WRITE_CD": f"cd {generated_cd}" if generated_cd else "", "SPF_STATUS": str(expected_status)}
                )
                self.assertEqual(result.returncode, expected_status, result.stderr)
                self.assert_pwd(result, expected_pwd)
                self.assertFalse(self.lastdir_file.exists())
                self.assertEqual(result.stdout.splitlines()[0], "APP_OUTPUT")

    def test_failed_exit_preserves_status_and_does_not_change_directory(self) -> None:
        self.reset_mock_state()
        result = self.run_wrapper(
            extra_env={"SPF_WRITE_CD": f"cd {shlex.quote(str(self.q_target))}", "SPF_STATUS": "23"}
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assert_pwd(result, self.origin)
        self.assertFalse(self.lastdir_file.exists())

    def test_stale_lastdir_is_removed_before_spf_runs(self) -> None:
        self.reset_mock_state()
        self.lastdir_file.write_text(f"cd {shlex.quote(str(self.stale_target))}\n")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_pwd(result, self.origin)
        self.assertFalse(self.stale_seen_file.exists(), "the mock saw a stale file at launch")
        self.assertFalse(self.lastdir_file.exists())

    def test_help_and_version_arguments_pass_through_without_cwd_or_stdout_noise(self) -> None:
        for argument in ("--help", "--version"):
            with self.subTest(argument=argument):
                self.reset_mock_state()
                result = self.run_wrapper(argument)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ["APP_OUTPUT", f"__PWD={self.origin.resolve()}"])
                self.assertEqual(self.args_file.read_bytes(), argument.encode() + b"\0")
                self.assertFalse(self.lastdir_file.exists())

    def test_arguments_are_forwarded_without_splitting(self) -> None:
        self.reset_mock_state()
        expected = ["a path/with spaces", "quote' and spaces", "--version"]
        result = self.run_wrapper(*expected)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.args_file.read_bytes(), b"\0".join(arg.encode() for arg in expected) + b"\0")


@unittest.skipUnless(FISH, "Fish required")
class FishSuperfileTests(SuperfileShellTests, unittest.TestCase):
    shell = FISH or "fish"
    shell_kind = "fish"
    integration = ROOT / "dotfiles/.config/fish/functions/spf.fish"
    shell_args = ("--no-config", "-c")

    def test_filename_completion_remains_available(self) -> None:
        candidate = self.origin / "some file.txt"
        candidate.touch()
        script = (
            f"source {shlex.quote(str(self.integration))}; "
            f"complete -C {shlex.quote('spf some')}"
        )
        result = subprocess.run(
            [self.shell, *self.shell_args, script],
            cwd=self.origin,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("some file.txt", result.stdout)


@unittest.skipUnless(ZSH, "zsh required")
class ZshSuperfileTests(SuperfileShellTests, unittest.TestCase):
    shell = ZSH or "zsh"
    shell_kind = "zsh"
    integration = ROOT / "dotfiles/.config/zsh/spf.zsh"
    shell_args = ("-f", "-c")

    def test_filename_completion_remains_available(self) -> None:
        (self.origin / "some file.txt").touch()
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [self.shell, "-f", "-i"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            cwd=self.origin,
            env=self.env,
            close_fds=True,
        )
        os.close(slave)

        def read_until(marker: bytes, timeout: float = 10) -> bytes:
            output = bytearray()
            deadline = time.monotonic() + timeout
            while marker not in output and time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
            self.assertIn(marker, output)
            return bytes(output)

        try:
            # CI runners can add writable third-party completion directories.
            # Ignore those unrelated entries instead of prompting on the PTY.
            setup = (
                "autoload -Uz compinit; compinit -i -D; "
                f"source {shlex.quote(str(self.integration))}; "
                f"cd {shlex.quote(str(self.origin))}; PROMPT=''; "
                "print -r -- __SETUP_READY__"
            )
            os.write(master, setup.encode() + b"\r")
            setup_output = read_until(b"\r\n__SETUP_READY__\r\n")
            os.write(master, b"spf some\t\rprint -r -- __COMPLETION_DONE__\r")
            completion_output = read_until(b"\r\n__COMPLETION_DONE__\r\n")
            self.assertTrue(self.args_file.exists(), f"zsh did not run the completed command:\n{setup_output!r}\n{completion_output!r}")
            self.assertEqual(self.args_file.read_bytes(), b"some file.txt\0", f"{completion_output!r}")
        finally:
            if process.poll() is None:
                try:
                    os.write(master, b"exit\r")
                    process.wait(timeout=2)
                except (OSError, subprocess.TimeoutExpired):
                    process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=2)
            os.close(master)


if __name__ == "__main__":
    unittest.main()
