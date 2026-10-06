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
        self.uv_log = self.base / 'uv-calls.jsonl'
        self.mise = self.base / 'mise'
        self.mise.write_text('#!/usr/bin/env python3\nimport os,sys,json\nwith open(os.environ["CALL_LOG"],"a") as f: f.write(json.dumps({"args":sys.argv[1:],"env":os.environ.get("MISE_ENV"),"root":os.environ.get("MISE_CONFIG_DIR"),"automatic":{k:os.environ.get(k) for k in ["MISE_AUTO_INSTALL","MISE_EXEC_AUTO_INSTALL","MISE_AUTO_UPDATE","MISE_NO_HOOKS"]}})+"\\n")\nif "get" in sys.argv: print("workstation")\nsys.exit(int(os.environ.get("FAIL_USE","0")) if "use" in sys.argv else 0)\n')
        self.mise.chmod(0o755)
        self.bin_dir = self.base / 'bin'
        self.bin_dir.mkdir()
        self.uv = self.bin_dir / 'uv'
        self.uv.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["UV_CALL_LOG"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
status = int(os.environ.get("UV_EXIT", "0"))
if status:
    sys.exit(status)
args = sys.argv[1:]
if "--script" in args and "remove.py" in args[args.index("--script") + 1]:
    sys.exit(0)
url = args[args.index("resolve") + 1]
if url.startswith("http://"):
    sys.exit(2)
repo = "/".join(url.removesuffix(".git").rstrip("/").split("/")[-2:])
asset = args[args.index("--asset") + 1] if "--asset" in args else None
print(f"github:{repo}" + (f"[asset_pattern={asset}]" if asset else ""))
''')
        self.uv.chmod(0o755)
        helper = self.root / 'setup-scripts/lib/dots-package-add.sh'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/usr/bin/env bash\n"$1" -C "$2" PACKAGE_HELPER "$3" "${@:4}"\n')
        tool_helper = helper.with_name('dots-tool-add.sh')
        tool_helper.write_text('#!/usr/bin/env bash\nset -e\nfor request in "${@:4}"; do "$1" -C "$2" use --path "$3" "$request"; printf "%s\\n" "$request" >> "$3"; done\n')
        bootstrap = self.root / 'setup-scripts/bootstrap'
        bootstrap.mkdir()
        for name in ('launch', 'remote'):
            shutil.copy2(SOURCE.parents[3] / 'setup-scripts/bootstrap' / name, bootstrap / name)
        self.env = dict(os.environ, DOTS_ROOT=str(self.root), DOTS_MISE_BIN=str(self.mise), CALL_LOG=str(self.log), UV_CALL_LOG=str(self.uv_log), PATH=f'{self.bin_dir}:{os.environ["PATH"]}', MISE_ENV='thesis', MISE_CONFIG_DIR=str(self.project))

    def run_dots(self, *args, **env):
        return subprocess.run(['bash', str(SOURCE), *args], cwd=self.project, env=dict(self.env, **env), text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def uv_calls(self):
        return [json.loads(line) for line in self.uv_log.read_text().splitlines()] if self.uv_log.exists() else []

    def install_calls(self):
        return [call for call in self.calls() if 'use' in call['args'] or 'PACKAGE_HELPER' in call['args']]

    def test_short_update_is_rooted_and_drops_project_selector(self):
        result = self.run_dots('up')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.calls()[0]
        self.assertEqual(call['args'], ['-C', str(self.root), 'run', 'setup:update'])
        self.assertIsNone(call['env'])
        self.assertEqual(call['root'], str(self.root))
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_update_alias_and_mas_opt_in_are_rooted(self):
        for command, flags in [('update', []), ('up', ['--mas']), ('update', ['--mas'])]:
            with self.subTest(command=command, flags=flags):
                result = self.run_dots(command, *flags)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = self.calls()[-1]
                self.assertEqual(call['args'], ['-C', str(self.root), 'run', 'setup:update', *flags])
                self.assertIsNone(call['env'])
                self.assertEqual(call['root'], str(self.root))

    def test_update_rejects_other_options_before_dispatch(self):
        for command in ('up', 'update'):
            for flags in (['--dry-run'], ['--mas', '--dry-run'], ['mas'], ['--mas=true']):
                with self.subTest(command=command, flags=flags):
                    result = self.run_dots(command, *flags)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn('accepts only --mas', result.stderr)
        for command in ('sync', 'status', 'backup', 'plan'):
            self.assertEqual(self.run_dots(command, '--mas').returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_update_help_describes_mas_opt_in_without_dispatch(self):
        for args in (['--help'], ['up', '--help'], ['update', '-h']):
            result = self.run_dots(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('dots up [--mas]', result.stdout)
            self.assertIn('skips Mac App Store updates by default', result.stdout)
        self.assertEqual(self.calls(), [])

    def test_source_routes_are_rooted_when_called_from_an_unrelated_project(self):
        expected = {
            'sync': ['-C', str(self.root), 'exec', '--', 'node', str(self.root / 'setup-scripts/lib/source-repo.mjs'), 'sync', str(self.root)],
            'publish': ['-C', str(self.root), 'exec', '--', 'node', str(self.root / 'setup-scripts/setup/publish.mjs'), str(self.root)],
            'atuin-bundle': ['-C', str(self.root), 'exec', '--', 'bash', str(self.root / 'setup-scripts/bootstrap/atuin-bundle')],
            'atuin-login': ['-C', str(self.root), 'exec', '--', 'uv', 'run', '--no-project', 'python', str(self.root / 'setup-scripts/bootstrap/atuin.py'), 'enroll', '--root', str(self.root)],
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

    def test_source_only_sync_forwards_one_explicit_option(self):
        result = self.run_dots('sync', '--source-only', MISE_AUTO_INSTALL='1', MISE_EXEC_AUTO_INSTALL='1', MISE_AUTO_UPDATE='1', MISE_NO_HOOKS='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.calls()[0]
        self.assertEqual(call['args'], ['-C', str(self.root), 'exec', '--', 'node',
                                      str(self.root / 'setup-scripts/lib/source-repo.mjs'), 'sync', str(self.root), '--source-only'])
        self.assertIsNone(call['env'])
        self.assertEqual(call['automatic'], {'MISE_AUTO_INSTALL': '0', 'MISE_EXEC_AUTO_INSTALL': '0', 'MISE_AUTO_UPDATE': '0', 'MISE_NO_HOOKS': '1'})
        for flags in (['--source-only', '--source-only'], ['--source-only', '--mas'], ['--dry-run']):
            with self.subTest(flags=flags):
                self.assertEqual(self.run_dots('sync', *flags).returncode, 2)
        self.assertEqual(len(self.calls()), 1)

    def test_bare_tool_defaults_to_role_and_native_latest_resolution(self):
        result = self.run_dots('add', 'watchexec')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'], ['-C', str(self.root), 'use', '--path', str(self.root/'config.workstation.toml'), 'watchexec'])

    def test_source_only_commit_pin_is_captured_before_mise_environment_selection(self):
        expected = 'a' * 40
        result = self.run_dots('sync', '--source-only', DOTS_EXPECTED_MAIN=expected)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'][-3:], ['--source-only', '--expected-main', expected])
        self.assertEqual(self.run_dots('sync', '--source-only', DOTS_EXPECTED_MAIN='invalid').returncode, 2)
        self.assertEqual(len(self.calls()), 1)

    def test_target_overrides_and_backend_versions(self):
        for flags, target in [(['--base'], self.root/'config.toml'), (['--profile','nas'], self.root/'config.nas.toml'), (['--path','local.toml'], self.project/'local.toml')]:
            result = self.run_dots('add', *flags, 'npm:prettier@3', 'cargo:hexyl')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls()[-2]['args'][-2:], [str(target), 'npm:prettier@3'])
            self.assertEqual(self.calls()[-1]['args'][-2:], [str(target), 'cargo:hexyl'])

    def test_package_routing(self):
        result = self.run_dots('add', '--base', 'brew:libmagic')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'][-3:], ['PACKAGE_HELPER', str(self.root/'config.toml'), 'brew:libmagic'])

    def test_github_release_is_resolved_from_the_setup_root(self):
        url = 'https://github.com/jaskirat1616/mactap-app'
        result = self.run_dots('add', url)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls(), [[
            'run', '--script', str(self.root/'setup-scripts/lib/dots-github.py'), 'resolve', url,
        ]])
        self.assertEqual(self.calls()[-1]['args'], [
            '-C', str(self.root), 'use', '--path', str(self.root/'config.workstation.toml'),
            'github:jaskirat1616/mactap-app',
        ])
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_github_asset_glob_is_preserved_for_resolver_and_install(self):
        pattern = 'MacTap-*-macos-arm64.zip'
        result = self.run_dots('add', '--asset', pattern, 'https://github.com/jaskirat1616/mactap-app')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls()[0][-2:], ['--asset', pattern])
        self.assertEqual(self.calls()[-1]['args'][-1], f'github:jaskirat1616/mactap-app[asset_pattern={pattern}]')

    def test_remove_and_uninstall_route_through_setup_helper(self):
        for command in ('remove', 'uninstall'):
            result = self.run_dots(command, '--dry-run', '--keep-installed', 'npm:prettier')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.uv_calls()[-1], [
                'run', '--script', str(self.root/'setup-scripts/lib/dots-remove.py'),
                str(self.mise), str(self.root), '--dry-run', '--keep-installed', 'npm:prettier',
            ])
            self.assertEqual(self.calls(), [])
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_remove_passes_config_selectors_and_resolves_relative_path_from_caller(self):
        result = self.run_dots('remove', '--base', 'ripgrep')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls()[-1][-2:], ['--base', 'ripgrep'])
        result = self.run_dots('uninstall', '--profile', 'nas', 'jq')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls()[-1][-3:], ['--profile', 'nas', 'jq'])
        result = self.run_dots('remove', '--path', 'local.toml', 'watchexec')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls()[-1][-3:], ['--path', str(self.project/'local.toml'), 'watchexec'])
        result = self.run_dots('remove', '--path=relative/config.toml', 'watchexec')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uv_calls()[-1][-3:], ['--path', str(self.project/'relative/config.toml'), 'watchexec'])
        self.assertEqual(self.calls(), [])
        self.assertEqual((self.project/'mise.toml').read_text(), '[tools]\nnode="20"\n')

    def test_remove_path_without_value_fails_before_dispatch(self):
        for command in ('remove', 'uninstall'):
            result = self.run_dots(command, '--path')
            self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(self.run_dots('remove', '--path=').returncode, 0)
        self.assertEqual(self.uv_calls(), [])
        self.assertEqual(self.calls(), [])

    def test_github_resolver_failure_stops_install_and_leaves_target_untouched(self):
        target = self.root/'config.workstation.toml'
        before = target.read_text()
        result = self.run_dots('add', 'https://github.com/jaskirat1616/mactap-app', UV_EXIT='23')
        self.assertEqual(result.returncode, 23)
        self.assertEqual(len(self.uv_calls()), 1)
        self.assertEqual(self.install_calls(), [])
        self.assertEqual(target.read_text(), before)

    def test_later_url_failure_keeps_earlier_tool_recorded(self):
        result = self.run_dots('add', 'watchexec', 'https://github.com/missing/repo', 'cargo:hexyl', UV_EXIT='23')
        self.assertEqual(result.returncode, 23)
        self.assertEqual([c['args'][-1] for c in self.install_calls()], ['watchexec'])
        self.assertEqual((self.root/'config.workstation.toml').read_text(), 'watchexec\n')

    def test_earlier_install_failure_does_not_resolve_later_url(self):
        result = self.run_dots('add', 'watchexec', 'https://github.com/owner/repo', FAIL_USE='7')
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.uv_calls(), [])
        self.assertEqual((self.root/'config.workstation.toml').read_text(), '')

    def test_mixed_requests_install_in_argument_order(self):
        result = self.run_dots('add', 'brew:libmagic', 'https://github.com/owner/repo', 'watchexec', 'brew-cask:firefox')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c['args'][-1] for c in self.install_calls()], ['brew:libmagic', 'github:owner/repo', 'watchexec', 'brew-cask:firefox'])

    def test_asset_requires_one_github_url_and_one_asset_option(self):
        invalid = [
            ('add', '--asset', 'app.zip', 'watchexec'),
            ('add', '--asset', 'app.zip', 'https://github.com/one/repo', 'https://github.com/two/repo'),
            ('add', '--asset', 'first.zip', '--asset', 'second.zip', 'https://github.com/one/repo'),
            ('add', '--asset', 'https://github.com/one/repo'),
            ('add', '--asset'),
        ]
        for args in invalid:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_dots(*args).returncode, 0)
        self.assertEqual(self.uv_calls(), [])
        self.assertEqual(self.install_calls(), [])

    def test_http_github_url_fails_in_resolver_without_install(self):
        result = self.run_dots('add', 'http://github.com/owner/repo')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.uv_calls()), 1)
        self.assertEqual(self.install_calls(), [])

    def test_test_runs_the_setup_suite_with_suite_arguments(self):
        result = self.run_dots('test', 'python', 'shell')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1]['args'], ['-C', str(self.root), 'run', 'setup:test', 'python', 'shell'])
        self.assertIsNone(self.calls()[-1]['env'])

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
