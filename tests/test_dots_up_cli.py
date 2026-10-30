from __future__ import annotations

import fcntl
import json
import os
import pty
import select
import shutil
import signal
import struct
import subprocess
import termios
import tempfile
import time
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]
MODULE_ROOT = SOURCE_ROOT / "setup-scripts/dots-up"


class DotsUpCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("go") is None:
            raise unittest.SkipTest("Go is required for dots-up CLI integration tests")
        if not (MODULE_ROOT / "go.mod").is_file():
            raise unittest.SkipTest("dots-up Go module is not present in this checkout")
        cls.build = tempfile.TemporaryDirectory(prefix="dots-up-build-")
        cls.binary = Path(cls.build.name) / "dots-up"
        result = subprocess.run(
            ["go", "build", "-o", str(cls.binary), "./cmd/dots-up"],
            cwd=MODULE_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode:
            raise AssertionError(f"could not build dots-up CLI:\n{result.stderr}")

    @classmethod
    def tearDownClass(cls) -> None:
        build = getattr(cls, "build", None)
        if build is not None:
            build.cleanup()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="dots-up-fixture-")
        self.root = Path(self.temp.name)
        self.runner = self.root / "fake-runner"
        self.args_log = self.root / "runner-args"
        self.runner.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "trap 'printf interrupted >\"$DOTS_UP_INTERRUPT_LOG\"; exit 130' INT\n"
            "exec 5<&0\n"
            "if [[ -n \"${DOTS_UP_PROTOCOL_LOG:-}\" ]]; then\n"
            "  tty_state=not-a-tty; [[ -t 0 ]] && tty_state=tty\n"
            "  printf 'ack_fd=%s\\nstdin=%s\\n' \"${DOTS_UP_ACK_FD:-unset}\" \"$tty_state\" >\"$DOTS_UP_PROTOCOL_LOG\"\n"
            "fi\n"
            "printf '%s\\n' \"$@\" >\"$DOTS_UP_ARGS_LOG\"\n"
            "line_no=0\n"
            "while IFS= read -r event; do\n"
            "  if [[ \"${DOTS_UP_OMIT_STAGE_END:-0}\" == 1 && \"$event\" == *stage_end* ]]; then continue; fi\n"
            "  line_no=$((line_no + 1))\n"
            "  if [[ -n \"${DOTS_UP_STREAM_NONCE:-}\" ]]; then\n"
            "    printf '\\036dots-up/1:%s:%s\\037' \"$DOTS_UP_STREAM_NONCE\" \"$event\"\n"
            "  else\n"
            "    event_fd=\"${DOTS_UP_EVENT_FD:-3}\"\n"
            "    printf '%s\\n' \"$event\" >&\"$event_fd\"\n"
            "  fi\n"
            "  if [[ \"${DOTS_UP_ACK_AFTER:-0}\" != 0 && \"$line_no\" == \"$DOTS_UP_ACK_AFTER\" ]]; then\n"
            "    ack_fd=\"${DOTS_UP_ACK_FD:-4}\"\n"
            "    IFS= read -r ack <&\"$ack_fd\"\n"
            "    printf '%s\\n' \"$ack\" >\"$DOTS_UP_ACK_LOG\"\n"
            "    IFS= read -r response <&5\n"
            "    printf '%s\\n' \"$response\" >\"$DOTS_UP_INPUT_LOG\"\n"
            "  fi\n"
            "  if [[ \"${DOTS_UP_DELAY_AFTER_LINE:-0}\" == \"$line_no\" ]]; then sleep \"${DOTS_UP_DELAY_SECONDS:-0.5}\"; fi\n"
            "done <\"$DOTS_UP_FIXTURE\"\n"
            "if [[ -n \"${DOTS_UP_NOISY_OUTPUT:-}\" ]]; then printf '%s\\n' \"$DOTS_UP_NOISY_OUTPUT\"; fi\n"
            "if [[ -n \"${DOTS_UP_DELAY:-}\" ]]; then sleep \"$DOTS_UP_DELAY\"; fi\n"
            "exit \"${DOTS_UP_FIXTURE_EXIT:-0}\"\n",
            encoding="utf-8",
        )
        self.runner.chmod(0o755)
        self.fixture = self.root / "fixture.jsonl"
        self.state = self.root / "state"
        self.env = os.environ.copy()
        self.env.update(
            {
                "DOTS_UP_RUNNER": str(self.runner),
                "DOTS_UP_STATE_DIR": str(self.state),
                "DOTS_UP_FIXTURE": str(self.fixture),
                "DOTS_UP_ARGS_LOG": str(self.args_log),
                "DOTS_UP_ACK_LOG": str(self.root / "ack"),
                "DOTS_UP_INPUT_LOG": str(self.root / "input"),
                "DOTS_UP_INTERRUPT_LOG": str(self.root / "interrupted"),
                "DOTS_UP_PROTOCOL_LOG": str(self.root / "protocol"),
                "NO_COLOR": "1",
            }
        )
        self.env.pop("CLICOLOR_FORCE", None)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _latest_report(self) -> tuple[Path, dict[str, object]]:
        reports = sorted(self.state.glob("*/report.json"), key=lambda path: path.stat().st_mtime_ns)
        self.assertTrue(reports, "the run did not persist a report")
        path = reports[-1]
        return path, json.loads(path.read_text(encoding="utf-8"))

    def _events(self, events: list[dict[str, object]]) -> None:
        self.fixture.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")

    def _run(self, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [str(self.binary), "--root", str(SOURCE_ROOT), *args],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def _write_window_size(self, fd: int, rows: int, columns: int) -> None:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))

    def _run_in_pty(self, *args: str, extra_env: dict[str, str] | None = None):
        gate_read, gate_write = os.pipe()
        pid, master = pty.fork()
        if pid == 0:
            os.close(gate_write)
            os.read(gate_read, 1)
            os.close(gate_read)
            env = self.env.copy()
            env.pop("CI", None)
            env["TERM"] = "xterm-256color"
            if extra_env:
                env.update(extra_env)
            os.chdir(self.root)
            argv = [str(self.binary), "--root", str(SOURCE_ROOT), *args]
            try:
                os.execve(str(self.binary), argv, env)
            except OSError as exc:
                os.write(2, f"could not execute dots-up: {exc}\n".encode())
                os._exit(127)
        os.close(gate_read)
        self._write_window_size(master, 30, 100)
        before = termios.tcgetattr(master)
        os.write(gate_write, b"1")
        os.close(gate_write)
        return self.PTYChild(pid, master), master, master, before

    class PTYChild:
        def __init__(self, pid: int, master: int) -> None:
            self.pid = pid
            self.master = master
            self.returncode: int | None = None
            self.output = bytearray()

        def poll(self) -> int | None:
            if self.returncode is None:
                waited, status = os.waitpid(self.pid, os.WNOHANG)
                if waited:
                    self.returncode = os.waitstatus_to_exitcode(status)
            return self.returncode

        def wait(self, timeout: float | None = None) -> int:
            deadline = None if timeout is None else time.monotonic() + timeout
            while self.poll() is None:
                if deadline is not None and time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired("dots-up", timeout)
                ready, _, _ = select.select([self.master], [], [], 0.05)
                if ready:
                    try:
                        self.output.extend(os.read(self.master, 8192))
                    except OSError:
                        pass
            return self.returncode or 0

        def kill(self) -> None:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    @staticmethod
    def _read_pty_until(master: int, needle: bytes, timeout: float = 5.0) -> bytes:
        output = bytearray()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 8192)
                except OSError:
                    break
                output.extend(chunk)
                if needle in output:
                    return bytes(output)
        raise AssertionError(f"timed out waiting for {needle!r}; output was {bytes(output)!r}")

    def test_plain_mode_passes_mas_and_reports_unchanged_run_without_color(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "workstation", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "mise tools", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "No changes"},
            ]
        )

        result = self._run("--plain", "--mas")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.args_log.read_text().splitlines(), ["--mas"])
        self.assertIn("mise tools", result.stdout)
        self.assertNotIn("\x1b[", result.stdout)
        self.assertNotIn("\x1b[", result.stderr)
        self.assertTrue(self.state.exists())

    def test_change_and_deferral_events_are_retained_in_report(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "nas-test"},
                {"v": 1, "kind": "stage_start", "id": "source", "group": "Source & settings", "label": "Sync configuration", "terminal": "hidden"},
                {"v": 1, "kind": "change", "stage": "source", "item": "mise", "before": "old", "after": "new"},
                {"v": 1, "kind": "notice", "severity": "attention", "summary": "Source sync deferred; local edits preserved", "action": "Review local changes"},
                {"v": 1, "kind": "stage_end", "id": "source", "status": "attention", "exit_code": 0, "summary": "Deferred; local source preserved"},
            ]
        )

        result = self._run("--plain")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("new", result.stdout)
        self.assertIn("local edits preserved", result.stdout)
        self.assertTrue(self.state.exists())

    def test_partial_and_prerequisite_failures_return_nonzero(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "nas-test"},
                {"v": 1, "kind": "stage_start", "id": "packages", "group": "Packages", "label": "Host packages", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "packages", "status": "ok", "exit_code": 0, "summary": "completed"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Mise tools", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "failed", "exit_code": 43, "summary": "Tool status failed", "action": "Retry dots up"},
                {"v": 1, "kind": "stage_start", "id": "upgrade", "group": "Tools", "label": "Tool upgrades", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "upgrade", "status": "skipped", "exit_code": 0, "summary": "Skipped because tool status failed"},
            ]
        )

        result = self._run("--plain", extra_env={"DOTS_UP_FIXTURE_EXIT": "1"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tool status failed", result.stdout + result.stderr)
        _, report = self._latest_report()
        self.assertIn("Retry dots up", json.dumps(report))

    def test_verbose_shows_runner_output_while_plain_stays_concise(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "nas-test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Mise tools", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "completed"},
            ]
        )
        env = {"DOTS_UP_NOISY_OUTPUT": "detailed fixture output"}

        plain = self._run("--plain", extra_env=env)
        verbose = self._run("--verbose", extra_env=env)

        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(verbose.returncode, 0, verbose.stderr)
        self.assertNotIn("detailed fixture output", plain.stdout)
        self.assertIn("detailed fixture output", verbose.stdout)

    def test_non_tty_defaults_to_plain_fallback(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "nas-test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Mise tools", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "completed"},
            ]
        )

        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Mise tools", result.stdout)
        self.assertNotIn("\x1b[", result.stdout)

    def test_last_reopens_saved_report_without_running_fake_updater(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "saved-run", "profile": "nas", "host": "nas-test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Saved stage", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "Saved report marker"},
            ]
        )
        first = self._run("--plain")
        self.assertEqual(first.returncode, 0, first.stderr)
        previous_args = self.args_log.read_text()

        last = self._run("--last")

        self.assertEqual(last.returncode, 0, last.stderr)
        self.assertEqual(self.args_log.read_text(), previous_args)
        report_path, report = self._latest_report()
        self.assertIn("Saved stage", json.dumps(report))
        self.assertIn(str(report_path.parent), last.stdout + last.stderr)

    def test_last_replays_past_handoff_as_history_without_releasing_terminal(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "saved-auth-run", "profile": "workstation", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "auth", "group": "Packages", "label": "Past authorization", "terminal": "handoff"},
                {"v": 1, "kind": "handoff_end", "id": "auth"},
                {"v": 1, "kind": "terminal_end"},
                {"v": 1, "kind": "stage_end", "id": "auth", "status": "ok", "exit_code": 0, "summary": "Authorization complete"},
            ]
        )
        first = self._run("--plain")
        self.assertEqual(first.returncode, 0, first.stderr)
        previous_args = self.args_log.read_text()

        last = self._run("--last")

        self.assertEqual(last.returncode, 0, last.stderr)
        self.assertEqual(self.args_log.read_text(), previous_args)
        report_path, report = self._latest_report()
        self.assertIn("Past authorization", json.dumps(report))
        self.assertIn(str(report_path.parent), last.stdout + last.stderr)

        process, master, slave, before = self._run_in_pty("--last")
        try:
            replay = self._read_pty_until(master, b"Finished")
            self.assertIn(b"Past authorization", replay)
            self.assertNotIn(b"terminal input is now available", replay)
            self.assertNotIn(b"unexpected terminal", replay)
            self.assertEqual(self.args_log.read_text(), previous_args)
            os.write(master, b"q")
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def test_last_option_validation_returns_usage_error(self) -> None:
        result = self._run("--last", "--mas")

        self.assertEqual(result.returncode, 2)
        self.assertIn("--last cannot be combined", result.stderr)

    def test_interactive_handoff_acknowledges_restores_terminal_and_accepts_input(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "workstation", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "auth", "group": "Packages", "label": "Authorize package updates", "terminal": "handoff"},
                {"v": 1, "kind": "stage_end", "id": "auth", "status": "ok", "exit_code": 0, "summary": "Authorization complete"},
            ]
        )
        process, master, slave, before = self._run_in_pty(
            "--no-wait",
            extra_env={"DOTS_UP_ACK_AFTER": "2"},
        )
        try:
            self._read_pty_until(master, b"terminal input is now available")
            deadline = time.monotonic() + 5
            while not (self.root / "ack").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "ack").exists(), "runner did not receive handoff acknowledgement")
            self.assertEqual((self.root / "ack").read_text().strip(), "go:auth")
            os.write(master, b"fixture authorization response\n")
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0)
            self.assertEqual((self.root / "input").read_text().strip(), "fixture authorization response")
            _, report = self._latest_report()
            self.assertIn("Authorization complete", json.dumps(report))
            after = termios.tcgetattr(slave)
            self.assertEqual(after, before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def test_handoff_without_prompt_waits_uses_child_pty_and_completes(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "workstation", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "auth", "group": "Packages", "label": "Authorization handoff", "terminal": "handoff"},
                {"v": 1, "kind": "stage_end", "id": "auth", "status": "ok", "exit_code": 0, "summary": "Authorization complete"},
            ]
        )
        process, master, slave, before = self._run_in_pty("--no-wait")
        try:
            process.wait(timeout=8)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(self.root.joinpath("protocol").read_text().splitlines(), ["ack_fd=4", "stdin=tty"])
            _, report = self._latest_report()
            self.assertIn("Authorization complete", json.dumps(report))
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def _run_auto_handoff_without_stage_end(self, no_wait: bool) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "workstation", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "auth", "group": "Packages", "label": "Authorize package updates", "terminal": "handoff"},
                {"v": 1, "kind": "stage_end", "id": "auth", "status": "ok", "exit_code": 0, "summary": "This event is deliberately dropped"},
            ]
        )
        args = ("--no-wait",) if no_wait else ()
        process, master, slave, before = self._run_in_pty(
            *args,
            extra_env={
                "DOTS_UP_ACK_AFTER": "2",
                "DOTS_UP_OMIT_STAGE_END": "1",
            },
        )
        try:
            self._read_pty_until(master, b"terminal input is now available")
            os.write(master, b"fixture authorization response\n")
            if not no_wait:
                self._read_pty_until(master, b"Finished")
                os.write(master, b"q")
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired as exc:
                raise AssertionError(f"handoff report did not close; PTY tail: {bytes(process.output[-4000:])!r}") from exc
            self.assertEqual(process.returncode, 0)
            self.assertEqual((self.root / "input").read_text().strip(), "fixture authorization response")
            _, report = self._latest_report()
            auth_results = [
                event for event in report["events"]
                if event.get("kind") == "stage_end" and event.get("id") == "auth"
            ]
            self.assertEqual(len(auth_results), 1)
            self.assertEqual(auth_results[0]["status"], "attention")
            self.assertIn("exited before this step reported a result", auth_results[0]["summary"])
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def test_auto_handoff_exit_without_stage_end_restores_and_dismisses(self) -> None:
        self._run_auto_handoff_without_stage_end(no_wait=False)

    def test_auto_handoff_exit_without_stage_end_honors_no_wait(self) -> None:
        self._run_auto_handoff_without_stage_end(no_wait=True)

    def test_manual_terminal_returns_to_finished_report_when_hidden_stage_ends(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Long-running hidden stage", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "completed"},
            ]
        )
        process, master, slave, before = self._run_in_pty(
            extra_env={"DOTS_UP_DELAY_AFTER_LINE": "2", "DOTS_UP_DELAY_SECONDS": "1"},
        )
        try:
            self._read_pty_until(master, b"Long-running hidden stage")
            os.write(master, b"t")
            output = self._read_pty_until(master, b"Terminal view")
            output += self._read_pty_until(master, b"Finished")

            deadline = time.monotonic() + 0.5
            while time.monotonic() < deadline and process.poll() is None:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        output += os.read(master, 8192)
                    except OSError:
                        break
            self.assertIsNone(process.poll(), "the finished report closed before q was pressed")
            self.assertNotIn(b"unexpected manual terminal end", output.lower())

            os.write(master, b"q")
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def test_resize_during_run_and_ctrl_c_restore_terminal(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Long-running stage", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "completed"},
            ]
        )
        process, master, slave, before = self._run_in_pty(
            extra_env={"DOTS_UP_DELAY": "30"},
        )
        try:
            self._read_pty_until(master, b"Long-running stage")
            os.write(master, b"q")
            time.sleep(0.2)
            self.assertIsNone(process.poll(), "q should not close an active update")
            self._write_window_size(slave, 42, 120)
            os.kill(process.pid, signal.SIGWINCH)
            time.sleep(0.3)
            self.assertIsNone(process.poll(), "the dashboard exited during resize")
            os.write(master, b"\x03")
            process.wait(timeout=8)
            self.assertNotEqual(process.returncode, 0)
            self.assertTrue((self.root / "interrupted").exists(), "the runner did not receive cancellation")
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)

    def test_interactive_finished_report_can_be_dismissed(self) -> None:
        self._events(
            [
                {"v": 1, "kind": "run_start", "id": "fixture", "profile": "nas", "host": "test"},
                {"v": 1, "kind": "stage_start", "id": "tools", "group": "Tools", "label": "Fixture stage", "terminal": "hidden"},
                {"v": 1, "kind": "stage_end", "id": "tools", "status": "ok", "exit_code": 0, "summary": "completed"},
            ]
        )
        process, master, slave, _ = self._run_in_pty()
        try:
            self._read_pty_until(master, b"Finished")
            os.write(master, b"q")
            process.wait(timeout=5)
            self.assertEqual(process.returncode, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            os.close(master)


if __name__ == "__main__":
    unittest.main()
