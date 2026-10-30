"""Exercise typ2docx launcher recovery without network access or source builds."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "setup-scripts/setup/exceptions/typ2docx"


class Typ2docxTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.launcher = self.home / ".local/bin/typ2docx"
        self.launcher.parent.mkdir(parents=True)
        self.runs = self.root / "data/uv-exceptions/typ2docx/runs"
        self.old_run = self.runs / "prior"
        self.old_candidate = self.old_run / "bin/typ2docx"
        self.old_candidate.parent.mkdir(parents=True)
        (self.old_run / "typ2docx-version").write_text("0.8.0\n")
        self.launcher.symlink_to(self.old_candidate)
        self.install_log = self.root / "installs"
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "MISE_DATA_DIR": str(self.root / "data"),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "FIXTURE_BIN": str(self.bin),
            "FIXTURE_ROOT": str(self.root),
        }
        self._executable(self.bin / "mise", '#!/bin/bash\n[[ "$1" == which ]] || exit 1\nprintf "%s/%s\\n" "$FIXTURE_BIN" "$2"\n')
        self._executable(self.bin / "python3.13", f'''#!{sys.executable}
import os
import sys
if sys.argv[1:] == ["-"]:
    print("0.8.0")  # Stand in for the PyPI lookup; never execute its network code.
elif sys.argv[1:] == ["-c", 'import sys; print(f"{{sys.version_info.major}}.{{sys.version_info.minor}}")']:
    print("3.13")
else:
    os.execv({sys.executable!r}, [{sys.executable!r}, *sys.argv[1:]])
''')
        for tool in ("rustc", "cargo"):
            self._executable(self.bin / tool, f"#!/bin/sh\necho '{tool} fixture'\n")
        self._executable(self.bin / "uv", f'''#!{sys.executable}
import os
from pathlib import Path
import sys
args = sys.argv[1:]
if args == ["--version"]:
    print("uv fixture")
elif args == ["tool", "dir"]:
    print(Path(os.environ["FIXTURE_ROOT"]) / "default-uv-tools")
elif args[:2] == ["tool", "install"]:
    assert args[-1] == "typ2docx==0.8.0", args
    assert os.environ["UV_TOOL_BIN_DIR"] in os.environ["PATH"].split(os.pathsep)
    candidate = Path(os.environ["UV_TOOL_BIN_DIR"]) / "typ2docx"
    candidate.write_text("#!/bin/sh\\nexit 0\\n")
    candidate.chmod(0o700)
    with (Path(os.environ["FIXTURE_ROOT"]) / "installs").open("a") as log:
        log.write(str(candidate) + "\\n")
elif args != ["tool", "list", "--show-paths"]:
    raise AssertionError(args)
''')

    def _executable(self, path, content):
        path.write_text(content)
        path.chmod(0o700)

    def _run(self, *arguments):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), *arguments],
            env=self.env, text=True, capture_output=True, check=False, timeout=10,
        )

    def test_healthy_same_version_is_unchanged(self):
        self._executable(self.old_candidate, "#!/bin/sh\necho help-output\necho health-warning >&2\nexit 0\n")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Already current typ2docx 0.8.0", result.stdout)
        self.assertNotIn("health-warning", result.stderr)
        self.assertNotIn("help-output", result.stdout)
        self.assertEqual(self.launcher.readlink(), self.old_candidate)
        self.assertEqual(list(self.runs.iterdir()), [self.old_run])
        self.assertFalse(self.install_log.exists())

    def test_broken_same_version_is_rebuilt(self):
        for broken in ("failed-help", "dangling-interpreter"):
            with self.subTest(broken=broken):
                self.launcher.unlink()
                self.launcher.symlink_to(self.old_candidate)
                interpreter = self.old_run / "python"
                if broken == "dangling-interpreter":
                    interpreter.symlink_to(self.root / "removed-python")
                    content = f"#!{interpreter}\n"
                else:
                    content = "#!/bin/sh\necho broken-help\necho broken-warning >&2\nexit 1\n"
                self._executable(self.old_candidate, content)
                result = self._run()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Rebuilding typ2docx 0.8.0", result.stdout)
                if broken == "failed-help":
                    self.assertIn("broken-help", result.stderr)
                    self.assertIn("broken-warning", result.stderr)
                candidate = self.launcher.resolve()
                self.assertNotEqual(candidate, self.old_candidate)
                self.assertEqual(candidate.parents[1].parent, self.runs)
                self.assertEqual((candidate.parents[1] / "typ2docx-version").read_text(), "0.8.0\n")
                self.assertEqual(subprocess.run([str(self.launcher), "--help"]).returncode, 0)
                backups = list(self.launcher.parent.glob(".typ2docx.uv-backup.*"))
                self.assertTrue(any(backup.readlink() == self.old_candidate for backup in backups))
                self.assertTrue(self.old_candidate.exists())

    def test_install_only_still_refuses_broken_existing_install(self):
        self._executable(self.old_candidate, "#!/bin/sh\nexit 1\n")
        result = self._run("--install-only")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failed its --help check", result.stderr)
        self.assertEqual(self.launcher.readlink(), self.old_candidate)
        self.assertFalse(self.install_log.exists())


if __name__ == "__main__":
    unittest.main()
