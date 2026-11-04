import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "dotfiles/.local/bin/rex-project"
loader = importlib.machinery.SourceFileLoader("rex_project", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
project = importlib.util.module_from_spec(spec)
loader.exec_module(project)


class ProjectTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "project with spaces"
        self.folder.mkdir()
        self.rex = self.root / "rex"
        self.rex.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["FAKE_ROOT"])
log = root / "calls"
with log.open("a") as f: f.write(json.dumps(sys.argv[1:]) + "\\n")
if "ls" in sys.argv:
    print(json.dumps({"sessions": json.loads((root / "sessions").read_text()) if (root / "sessions").exists() else []}))
else:
    time.sleep(.1)
    print(json.dumps({"session_id": "session:new"}))
''')
        self.rex.chmod(0o755)
        self.env = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state"), "FAKE_ROOT": str(self.root)})
        self.env.start()
        self.addCleanup(self.env.stop)

    def calls(self):
        return [json.loads(x) for x in (self.root / "calls").read_text().splitlines()]

    def test_create_reuse_and_stale_replacement(self):
        path = str(self.folder)
        self.assertEqual(project.session_for(path, str(self.rex)), "session:new")
        registry = self.root / "state/rex/projects.json"
        self.assertEqual(json.loads(registry.read_text()), {path: "session:new"})
        self.assertEqual(registry.stat().st_mode & 0o777, 0o600)
        (self.root / "sessions").write_text(json.dumps([{"session_id": "session:new"}]))
        self.assertEqual(project.session_for(path, str(self.rex)), "session:new")
        (self.root / "sessions").write_text("[]")
        self.assertEqual(project.session_for(path, str(self.rex)), "session:new")
        self.assertEqual(sum("new" in c for c in self.calls()), 2)
        new = next(c for c in self.calls() if "new" in c)
        self.assertEqual(new[new.index("-c") + 1], path)

    def test_concurrent_launches_are_serialized(self):
        # Model an immediately visible created session for the next process.
        text = self.rex.read_text().replace('time.sleep(.1)\n    print', 'time.sleep(.1)\n    (root / "sessions").write_text(json.dumps([{"session_id": "session:new"}]))\n    print')
        self.rex.write_text(text)
        code = ("import runpy, types; "
                f"m=types.SimpleNamespace(**runpy.run_path({str(SOURCE)!r})); "
                f"print(m.session_for({str(self.folder)!r}, {str(self.rex)!r}))")
        processes = [subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        for proc in processes:
            out, err = proc.communicate(timeout=10)
            self.assertEqual(proc.returncode, 0, err)
            self.assertEqual(out.strip(), b"session:new")
        self.assertEqual(sum("new" in c for c in self.calls()), 1)

    def test_cancel_is_noop_and_symlink_is_canonical(self):
        alias = self.root / "alias"
        alias.symlink_to(self.folder)
        recent = subprocess.CompletedProcess([], 0, stdout=os.fsencode(alias) + b"\n")
        with patch.object(project, "command", side_effect=lambda name: name), patch.object(project, "run", return_value=recent), patch.object(project.subprocess, "run", return_value=subprocess.CompletedProcess([], 130, stdout=b"")):
            self.assertIsNone(project.choose_directory())
        with patch.object(project, "command", side_effect=lambda name: name), patch.object(project, "run", return_value=recent), patch.object(project.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=os.fsencode(alias) + b"\0")):
            self.assertEqual(project.choose_directory(), os.path.realpath(self.folder))
        self.assertFalse((self.root / "state").exists())

    def test_selection_uses_attached_client_and_selected_project(self):
        clients = subprocess.CompletedProcess([], 0, stdout=json.dumps({"clients": [{"client_id": "remote-app", "info": {"kind": "app"}}]}).encode())
        hostile = str(self.root / "name $(touch BAD) ; ' space")
        with patch.dict(os.environ, {"REX_SESSION": "session:picker"}), patch.object(sys, "argv", ["rex-project", "--previous-session", "session:original"]), patch.object(project, "choose_directory", return_value=hostile), patch.object(project, "command", return_value="rex"), patch.object(project, "session_for", return_value="session:project") as session_for, patch.object(project, "run", side_effect=[clients, None, None]) as run:
            project.main()
        session_for.assert_called_once_with(hostile, "rex")
        self.assertEqual(run.call_args_list[1].args[0], ["rex", "--autostart=false", "-C", "remote-app", "do", "session.select", "session_id=session:project"])
        self.assertEqual(run.call_args_list[2].args[0][-2:], ["kill", "session:picker"])

    def test_cancel_returns_original_session_and_closes_picker(self):
        clients = subprocess.CompletedProcess([], 0, stdout=json.dumps({"clients": [{"client_id": "remote-app", "info": {"kind": "app"}}]}).encode())
        with patch.dict(os.environ, {"REX_SESSION": "session:picker"}), patch.object(sys, "argv", ["rex-project", "--previous-session", "session:original"]), patch.object(project, "choose_directory", return_value=None), patch.object(project, "command", return_value="rex"), patch.object(project, "run", side_effect=[clients, None, None]) as run:
            project.main()
        self.assertEqual(run.call_args_list[1].args[0], ["rex", "--autostart=false", "-C", "remote-app", "do", "session.select", "session_id=session:original"])
        self.assertEqual(run.call_args_list[2].args[0], ["rex", "--autostart=false", "kill", "session:picker"])

    def test_ambiguous_clients_do_not_create_or_select(self):
        clients = subprocess.CompletedProcess([], 0, stdout=json.dumps({"clients": [{"client_id": "a", "info": {"kind": "app"}}, {"client_id": "b", "info": {"kind": "app"}}]}).encode())
        with patch.dict(os.environ, {"REX_SESSION": "session:picker"}), patch.object(sys, "argv", ["rex-project", "--previous-session", "session:original"]), patch.object(project, "choose_directory", return_value=str(self.folder)), patch.object(project, "command", return_value="rex"), patch.object(project, "run", return_value=clients) as run, patch.object(project, "session_for") as session_for:
            with self.assertRaises(RuntimeError): project.main()
            session_for.assert_not_called()
            self.assertEqual(run.call_count, 1)

    def test_invalid_picker_output_and_unavailable_server_do_not_create(self):
        recent = subprocess.CompletedProcess([], 0, stdout=os.fsencode(self.folder) + b"\n")
        with patch.object(project, "command", side_effect=lambda name: name), patch.object(project, "run", return_value=recent), patch.object(project.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=b"/bad\npath\0")):
            with self.assertRaises(RuntimeError): project.choose_directory()
        self.rex.write_text("#!/bin/sh\nexit 1\n")
        with self.assertRaises(subprocess.CalledProcessError): project.session_for(str(self.folder), str(self.rex))
        self.assertFalse((self.root / "state/rex/projects.json").exists())


if __name__ == "__main__": unittest.main()
