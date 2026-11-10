"""Exercise Mac NAS registration with isolated apps, plists and mocked commands."""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = Path("Contents/Helpers/Rex Server.rex/Contents/MacOS/rex")
REQUIREMENT = '=anchor apple generic and certificate leaf[subject.OU] = "AG92C3PT77" and identifier "com.superlogical.rex"'

# On macOS use the actual plist tool, including its escaping and canonical XML.
# Other hosts emulate only these plist operations with the Python standard library.
MOCK = r'''
import json, os, pathlib, plistlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name in ('uname', 'hostname', 'id'):
    print(os.environ.get('MOCK_' + name.upper(), {'uname': 'Darwin', 'hostname': 'DriehuisNAS', 'id': 'server'}[name]))
elif name == 'codesign':
    sys.exit(1 if os.environ.get('BAD_SIGNATURE') == args[-1] else 0)
elif name == 'sudo':
    target = pathlib.Path(os.environ['TEST_TARGET'])
    if args[:7] == ['install', '-o', 'root', '-g', 'wheel', '-m', '0644']:
        source, staged = map(pathlib.Path, args[7:])
        assert staged.name == 'registered.plist' and source.parent == staged.parent
        shutil.copyfile(source, staged)
        if os.environ.get('RACE_TARGET') == '1':
            target.write_text('concurrent daemon\n')
        elif os.environ.get('RACE_TARGET') == 'symlink-directory':
            target.symlink_to(os.environ['TEST_RACE_DIRECTORY'])
        elif os.environ.get('RACE_TARGET') == 'directory':
            target.mkdir()
    elif args[0] == '/bin/link':
        assert pathlib.Path(args[2]) == target
        try:
            os.link(args[1], target)
        except FileExistsError:
            sys.exit(1)
    elif args == ['launchctl', 'bootstrap', 'system', str(target)]:
        assert target.is_file()
    else:
        raise AssertionError('Unexpected privileged call: ' + repr(args))
elif name == 'launchctl':
    raise AssertionError('Direct launchctl is forbidden')
elif name == 'plutil':
    if os.environ.get('REAL_PLUTIL'):
        os.execv(os.environ['REAL_PLUTIL'], ['plutil', *args])
    source = pathlib.Path(args[-1])
    try:
        value = plistlib.loads(source.read_bytes())
    except Exception:
        sys.exit(1)
    if args[0] == '-lint':
        sys.exit(0)
    if args[:2] == ['-remove', 'ProgramArguments.0']:
        assert args[2] == '-o'
        del value['ProgramArguments'][0]
        pathlib.Path(args[3]).write_bytes(plistlib.dumps(value))
    elif args[:2] == ['-insert', 'ProgramArguments.0']:
        assert args[2] == '-string'
        value['ProgramArguments'].insert(0, args[3])
        source.write_bytes(plistlib.dumps(value))
    elif args[:2] == ['-convert', 'xml1']:
        assert args[2] == '-o'
        pathlib.Path(args[3]).write_bytes(plistlib.dumps(value))
    elif args[:3] == ['-extract', 'ProgramArguments.0', 'raw']:
        assert args[3:5] == ['-o', '-']
        print(value['ProgramArguments'][0])
    else:
        raise AssertionError('Unexpected plist call: ' + repr(args))
else:
    raise AssertionError('Unexpected command: ' + name)
'''


class RexMacDaemonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home & user"
        self.home.mkdir()
        self.system_app = self.base / "Applications/Rex Beta.app"
        self.target = self.base / "LaunchDaemons/com.ezra.rex-nas.plist"
        self.target.parent.mkdir()
        self.repo = self.base / "repo"
        self.install = self.repo / "setup-scripts/install"
        self.install.mkdir(parents=True)
        self.log = self.base / "commands.jsonl"
        for name in ("rex-nas-macos-daemon.sh", "rex-nas-macos-plist.sh", "rex-nas-setup.sh"):
            source = (ROOT / "setup-scripts/install" / name).read_text()
            source = source.replace("target=/Library/LaunchDaemons/com.ezra.rex-nas.plist", f'target="{self.target}"')
            source = source.replace("'/Applications/Rex Beta.app'", f'"{self.system_app}"')
            (self.install / name).write_text(source)
        self.template = self.repo / "resources/rex/com.ezra.rex-nas.plist"
        self.template.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "resources/rex/com.ezra.rex-nas.plist", self.template)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for name in ("uname", "hostname", "id", "codesign", "plutil", "sudo", "launchctl"):
            command = self.bin / name
            command.write_text(f"#!{sys.executable}\n" + MOCK)
            command.chmod(0o755)
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(self.base),
            "TEST_LOG": str(self.log),
            "TEST_TARGET": str(self.target),
        }
        if sys.platform == "darwin":
            self.env["REAL_PLUTIL"] = "/usr/bin/plutil"

    def app(self, system: bool = False) -> Path:
        app = self.system_app if system else self.home / "Applications/Rex Beta.app"
        helper = app / HELPER
        helper.parent.mkdir(parents=True)
        helper.write_text(
            f"#!{sys.executable}\nimport json, os, sys\n"
            "with open(os.environ['TEST_LOG'], 'a') as log:\n"
            "    log.write(json.dumps(['rex', *sys.argv[1:]]) + '\\n')\n"
            "sys.exit(0 if os.environ.get('PERSONAL_SERVER') == '1' else 1)\n"
        )
        helper.chmod(0o755)
        return app

    def calls(self, name: str) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [call[1:] for line in self.log.read_text().splitlines() if (call := json.loads(line))[0] == name]

    def run_script(self, setup: bool = False) -> subprocess.CompletedProcess[str]:
        name = "rex-nas-setup.sh" if setup else "rex-nas-macos-daemon.sh"
        args = ["--update-existing"] if setup else []
        return subprocess.run(["/bin/sh", str(self.install / name), *args], env=self.env, capture_output=True, text=True)

    def expected(self, app: Path) -> dict:
        value = plistlib.loads(self.template.read_bytes())
        value["ProgramArguments"][0] = str(app / HELPER)
        return value

    def existing(self, app: Path, drift: str | None = None) -> bytes:
        value = self.expected(app)
        if drift == "executable":
            value["ProgramArguments"][0] = "/old/rex"
        elif drift == "arguments":
            value["ProgramArguments"][-1] = "/old/state"
        # Different whitespace and key order must not imply configuration drift.
        self.target.write_bytes(plistlib.dumps(value, sort_keys=False).replace(b"\t", b"  "))
        return self.target.read_bytes()

    def assert_no_registration(self) -> None:
        self.assertEqual(self.calls("sudo"), [])
        self.assertEqual(self.calls("launchctl"), [])
        self.assertEqual(self.calls("rex"), [])

    def test_initial_registration_uses_actual_path_and_preserves_identity(self) -> None:
        for system in (False, True):
            with self.subTest(system=system):
                app = self.app(system)
                before = (app / HELPER).read_bytes()
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(app))
                self.assertEqual((app / HELPER).read_bytes(), before)
                self.assertEqual(self.calls("codesign")[-1], ["--verify", "--deep", "--strict", "-R", REQUIREMENT, str(app)])
                self.assertEqual(self.calls("rex")[-1], ["--autostart=false", "whoami"])
                sudo = self.calls("sudo")[-3:]
                self.assertEqual(sudo[0][:7], ["install", "-o", "root", "-g", "wheel", "-m", "0644"])
                self.assertEqual(sudo[1], ["/bin/link", sudo[0][-1], str(self.target)])
                self.assertEqual(sudo[2], ["launchctl", "bootstrap", "system", str(self.target)])
                self.assertFalse(Path(sudo[0][-1]).exists(), "temporary plist was not cleaned up")
                self.target.unlink()
                shutil.rmtree(app)

    def test_home_app_takes_precedence(self) -> None:
        home_app = self.app()
        self.app(system=True)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plistlib.loads(self.target.read_bytes()), self.expected(home_app))

    def test_missing_or_invalid_app_fails_without_registration(self) -> None:
        for invalid in ("missing", "not-directory", "missing-helper", "not-executable", "signature", "dangling-link"):
            with self.subTest(invalid=invalid):
                app = self.home / "Applications/Rex Beta.app"
                if invalid != "missing":
                    app.parent.mkdir(parents=True, exist_ok=True)
                    if invalid == "not-directory":
                        app.touch()
                    elif invalid == "dangling-link":
                        app.symlink_to(self.base / "missing")
                    else:
                        self.app()
                        if invalid == "missing-helper":
                            (app / HELPER).unlink()
                        elif invalid == "not-executable":
                            (app / HELPER).chmod(0o644)
                        else:
                            self.env["BAD_SIGNATURE"] = str(app)
                    self.app(system=True)  # An invalid preferred app must not silently fall back.
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.target.exists())
                self.assert_no_registration()
                self.env.pop("BAD_SIGNATURE", None)
                if app.is_symlink() or app.is_file():
                    app.unlink()
                elif app.exists():
                    shutil.rmtree(app)
                if self.system_app.exists():
                    shutil.rmtree(self.system_app)

    def test_existing_daemon_is_never_changed_or_probed(self) -> None:
        for setup in (False, True):
            for system in (False, True):
                for drift in (None, "executable", "arguments", "invalid-plist"):
                    with self.subTest(setup=setup, system=system, drift=drift):
                        app = self.app(system)
                        before = self.existing(app, drift)
                        if drift == "invalid-plist":
                            self.target.write_text("invalid plist\n")
                            before = self.target.read_bytes()
                        result = self.run_script(setup)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual("restart explicitly" in result.stdout, drift is not None, result.stdout)
                        self.assertEqual(self.target.read_bytes(), before)
                        self.assert_no_registration()
                        self.target.unlink()
                        shutil.rmtree(app)

    def test_existing_daemon_survives_invalid_signature(self) -> None:
        app = self.app()
        before = self.existing(app)
        self.env["BAD_SIGNATURE"] = str(app)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), before)
        self.assert_no_registration()

    def test_broken_target_symlink_is_preserved(self) -> None:
        self.app()
        destination = self.base / "missing.plist"
        self.target.symlink_to(destination)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("restart explicitly", result.stdout)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(self.target.readlink(), destination)
        self.assertFalse(destination.exists())
        self.assert_no_registration()

    def test_running_personal_server_blocks_initial_registration(self) -> None:
        self.app()
        self.env["PERSONAL_SERVER"] = "1"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("personal Rex server is already running", result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls("sudo"), [])

    def test_update_without_daemon_skips_app_checks_and_registration(self) -> None:
        result = self.run_script(setup=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.calls("codesign"), [])
        self.assertEqual(self.calls("plutil"), [])
        self.assert_no_registration()

    def test_concurrent_daemon_is_not_overwritten_or_bootstrapped(self) -> None:
        self.app()
        directory = self.base / "existing-directory"
        directory.mkdir()
        self.env["TEST_RACE_DIRECTORY"] = str(directory)
        for race in ("1", "symlink-directory", "directory"):
            with self.subTest(race=race):
                self.env["RACE_TARGET"] = race
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("existing definitions are never replaced", result.stderr)
                if race == "1":
                    self.assertEqual(self.target.read_text(), "concurrent daemon\n")
                elif race == "symlink-directory":
                    self.assertEqual(self.target.readlink(), directory)
                    self.assertEqual(list(directory.iterdir()), [])
                else:
                    self.assertTrue(self.target.is_dir())
                    self.assertEqual(list(self.target.iterdir()), [])
                self.assertFalse(any(call[0] == "launchctl" for call in self.calls("sudo")))
                if self.target.is_symlink() or self.target.is_file():
                    self.target.unlink()
                else:
                    self.target.rmdir()

    def test_wrong_host_or_account_stops_before_app_checks(self) -> None:
        for key, value in (("MOCK_UNAME", "Linux"), ("MOCK_HOSTNAME", "other"), ("MOCK_ID", "other")):
            with self.subTest(key=key):
                self.env[key] = value
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Run as server on DriehuisNAS", result.stderr)
                self.assertEqual(self.calls("codesign"), [])
                self.assert_no_registration()
                del self.env[key]


if __name__ == "__main__":
    unittest.main()
