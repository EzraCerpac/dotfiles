import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'dotfiles/.local/bin/dots'

class DotsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / 'setup'
        self.project = self.base / 'project'
        self.root.mkdir()
        self.project.mkdir()
        for name in ('config.toml', 'config.workstation.toml', 'config.nas.toml', 'config.local.toml'):
            (self.root / name).write_text('')
        (self.project / 'mise.toml').write_text('[tools]\nnode="20"\n')
        self.log = self.base / 'calls.jsonl'
        self.mise = self.base / 'mise'
        self.mise.write_text('#!/usr/bin/env python3\nimport os,sys,json\nwith open(os.environ["CALL_LOG"],"a") as f: f.write(json.dumps({"args":sys.argv[1:],"env":os.environ.get("MISE_ENV"),"root":os.environ.get("MISE_CONFIG_DIR")})+"\\n")\nif "get" in sys.argv: print("workstation")\nsys.exit(int(os.environ.get("FAIL_USE","0")) if "use" in sys.argv else 0)\n')
        self.mise.chmod(0o755)
        helper = self.root / 'tasks/lib/dots-package-add.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/usr/bin/env bash\n"$1" -C "$2" PACKAGE_HELPER "$3" "${@:4}"\n')
        bootstrap = self.root / 'tasks/bootstrap'
        bootstrap.mkdir()
        for name in ('launch', 'remote'):
            shutil.copy2(SOURCE.parents[3] / 'tasks/bootstrap' / name, bootstrap / name)
        self.env = dict(os.environ, DOTS_ROOT=str(self.root), DOTS_MISE_BIN=str(self.mise), CALL_LOG=str(self.log), MISE_ENV='thesis', MISE_CONFIG_DIR=str(self.project))

    def run_dots(self, *args, **env):
        return subprocess.run(['bash', str(SOURCE), *args], cwd=self.project, env=dict(self.env, **env), text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_short_update_is_rooted_and_drops_project_selector(self):
        result = self.run_dots('up')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.calls()[0]
        self.assertEqual(call['args'], ['-C', str(self.root), 'run', 'setup:update'])
        self.assertIsNone(call['env'])
        self.assertEqual(call['root'], str(self.root))
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_source_routes_are_rooted_when_called_from_an_unrelated_project(self):
        expected = {
            'sync': ['-C', str(self.root), 'exec', '--', 'node', str(self.root / 'tasks/lib/source-repo.mjs'), 'sync', str(self.root)],
            'publish': ['-C', str(self.root), 'exec', '--', 'node', str(self.root / 'tasks/setup/publish.mjs'), str(self.root)],
            'atuin-bundle': ['-C', str(self.root), 'exec', '--', 'bash', str(self.root / 'tasks/bootstrap/atuin-bundle')],
            'atuin-login': ['-C', str(self.root), 'exec', '--', 'uv', 'run', '--no-project', 'python', str(self.root / 'tasks/bootstrap/atuin.py'), 'enroll', '--root', str(self.root)],
        }
        for command, args in expected.items():
            result = self.run_dots(command)
            self.assertEqual(result.returncode, 0, result.stderr)
            call = self.calls()[-1]
            self.assertEqual(call['args'], args)
            self.assertIsNone(call['env'])
            self.assertEqual(call['root'], str(self.root))
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_atuin_identity_is_relative_to_the_callers_directory(self):
        for flags in (['--identity', 'keys/age.txt'], ['--identity=keys/age.txt']):
            result = self.run_dots('atuin-login', *flags, '--browser')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls()[-1]['args'][-3:],
                             ['--identity', str(self.project / 'keys/age.txt'), '--browser'])
        result = self.run_dots('atuin-login', '--identity', '/external/key.txt')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'][-2:], ['--identity', '/external/key.txt'])

    def test_bare_tool_defaults_to_role_and_native_latest_resolution(self):
        result = self.run_dots('add', 'watchexec')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'], ['-C', str(self.root), 'use', '--path', str(self.root/'config.workstation.toml'), 'watchexec'])

    def test_target_overrides_and_backend_versions(self):
        for flags, target in [(['--base'], self.root/'config.toml'), (['--profile','nas'], self.root/'config.nas.toml'), (['--path','local.toml'], self.project/'local.toml')]:
            result = self.run_dots('add', *flags, 'npm:prettier@3', 'cargo:hexyl')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls()[-1]['args'][-3:], [str(target), 'npm:prettier@3', 'cargo:hexyl'])

    def test_package_routing(self):
        result = self.run_dots('add', '--base', 'brew:libmagic')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'][-3:], ['PACKAGE_HELPER', str(self.root/'config.toml'), 'brew:libmagic'])

    def test_plan_is_rooted_and_remote_keeps_durable_config(self):
        self.assertEqual(self.run_dots('plan').returncode, 0)
        self.assertEqual(self.calls()[-1]['args'], ['-C', str(self.root), 'bootstrap', 'plan'])
        result = self.run_dots('remote', 'new-box', '--profile', 'nas', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'], ['-C', str(self.root), 'bootstrap', 'remote', '--host', 'new-box', '--adopt', 'EzraCerpac/dotfiles', '--remote-env', 'nas', '--install-mise', '--dry-run'])

    def test_restore_skips_early_services_and_requires_complete_bootstrap(self):
        result = self.run_dots('bootstrap', '--restore', 'old-mac', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'][-3:], ['--dry-run', '--skip', 'services'])
        self.assertNotEqual(self.run_dots('bootstrap', '--restore', 'old-mac', '--only', 'packages').returncode, 0)

    def test_remote_rejects_implicit_roles_and_source_archives(self):
        self.assertNotEqual(self.run_dots('remote', 'new-box').returncode, 0)
        self.assertNotEqual(self.run_dots('remote', 'new-box', '--profile', 'nas', '--source', '.').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_invalid_arguments_do_not_call_mise(self):
        for args in [('add',), ('add','--base','--profile','nas','jq'), ('add','--profile','delftblue','jq'), ('up','--dry-run'), ('add','--path')]:
            self.assertNotEqual(self.run_dots(*args).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_failure_is_preserved_and_stops_later_installs(self):
        result = self.run_dots('add', 'watchexec', 'brew:libmagic', FAIL_USE='7')
        self.assertEqual(result.returncode, 7)
        self.assertFalse(any('PACKAGE_HELPER' in call['args'] for call in self.calls()))

if __name__ == '__main__':
    unittest.main()
