"""Native dotfile fixtures; never apply repository targets to the real home."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import tomllib
import unittest

from lib.prereq import mise_binary, requires

ROOT = Path(__file__).resolve().parents[1]
MISE = mise_binary() or 'mise'


@requires('mise')
class DotfileFixtures(unittest.TestCase):
    def test_codex_policy_selects_one_role_and_os_source(self):
        shared = tomllib.loads((ROOT / 'config.toml').read_text())
        policies = {key: entry for key, entry in shared['dotfiles'].items()
                    if entry.get('source', '').startswith('dotfiles/.codex/AGENTS')}
        expected = {
            ('Darwin', 'workstation'): 'AGENTS.md',
            ('Linux', 'workstation'): 'AGENTS.linux.md',
            ('Darwin', 'nas'): 'AGENTS.driehuisnas.md',
            ('Linux', 'nas'): 'AGENTS.cerpacnas.md',
        }
        for role in ('workstation', 'nas', None):
            with self.subTest(role=role), tempfile.TemporaryDirectory(prefix='mise-codex-policy-') as tmp:
                fixture = Path(tmp).resolve()
                destination = fixture / 'home/.codex/AGENTS.md'
                lines = ['[settings]', 'dotfiles.root = ' + json.dumps(str(ROOT / 'dotfiles')), '[dotfiles]']
                for key, entry in policies.items():
                    target = str(destination) if key == '~/.codex/AGENTS.md' else key
                    variants = []
                    for variant in entry['variants']:
                        fields = {**variant}
                        if 'target' in fields:
                            fields['target'] = str(destination)
                        variants.append('{ ' + ', '.join(k + ' = ' + json.dumps(v) for k, v in fields.items()) + ' }')
                    lines.append(json.dumps(target) + ' = { source = ' + json.dumps(str(ROOT / entry['source']))
                                 + ', mode = "symlink", variants = [' + ', '.join(variants) + '] }')
                (fixture / 'config.toml').write_text('\n'.join(lines))
                env = {key: os.environ[key] for key in ('PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TMPDIR', 'TERM') if key in os.environ}
                for name in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
                    env[f'MISE_{name}_DIR'] = str(fixture if name == 'CONFIG' else fixture / name.lower())
                (fixture / 'empty-system-config').mkdir()
                env.update(MISE_TRUSTED_CONFIG_PATHS=str(fixture), MISE_SYSTEM_CONFIG_DIR=str(fixture / 'empty-system-config'),
                           MISE_CEILING_PATHS=str(fixture), MISE_ENV='', MISE_AUTO_ENV='0', MISE_NO_ENV='1',
                           MISE_AUTO_INSTALL='0', MISE_NO_HOOKS='1', MISE_AUTO_UPDATE='0')
                command = [MISE, '-C', str(fixture)]
                if role:
                    command += ['-E', role]
                status = subprocess.run(command + ['bootstrap', 'dotfiles', 'status', '--json'], env=env, cwd=fixture,
                                        text=True, capture_output=True, timeout=60)
                self.assertEqual(status.returncode, 0, status.stdout + status.stderr)
                files = json.loads(status.stdout)['files']
                self.assertEqual(len(files), 0 if role is None else 1)
                if role:
                    source = ROOT / 'dotfiles/.codex' / expected[(platform.system(), role)]
                    self.assertEqual(files[0]['target'], str(destination))
                    self.assertEqual(files[0]['origin']['source'], str(source))
                result = subprocess.run(command + ['bootstrap', 'dotfiles', 'apply'], env=env, cwd=fixture,
                                        text=True, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if role is None:
                    self.assertFalse(os.path.lexists(destination))
                else:
                    source = ROOT / 'dotfiles/.codex' / expected[(platform.system(), role)]
                    self.assertTrue(destination.is_symlink())
                    self.assertEqual(destination.resolve(), source.resolve())
                    self.assertEqual(destination.read_bytes(), source.read_bytes())
                    if platform.system() == 'Linux':
                        self.assertNotIn(b'macOS Keychain', destination.read_bytes())

    def test_profile_sources_and_native_link_lifecycle(self):
        for role in ('workstation', 'nas'):
            with self.subTest(role=role), tempfile.TemporaryDirectory(prefix='mise-dotfiles-') as tmp:
                fixture = Path(tmp).resolve()
                for directory in ('dotfiles', 'templates'):
                    shutil.copytree(ROOT / directory, fixture / directory, symlinks=True)
                base = (ROOT / 'config.toml').read_text().split('[tools]')[0]
                # Shared configuration precedes task/hook declarations.
                self.assertNotIn('[bootstrap.hooks]', base)
                base = base.replace('[vars]\n', f'[vars]\nprofile = "{role}"\n')
                shared = tomllib.loads((ROOT / 'config.toml').read_text())
                profile = tomllib.loads((ROOT / f'config.{role}.toml').read_text())
                entries = {**shared.get('dotfiles', {}), **profile.get('dotfiles', {})}
                lines = [base, '[dotfiles]']
                targets = []
                for target, entry in entries.items():
                    source = fixture / entry['source']
                    self.assertTrue(source.is_file(), str(source))
                    target = fixture / 'destinations' / target.removeprefix('~/')
                    targets.append((target, source, entry['mode']))
                    # Platform filtering is tested in the actual Linux matrix.
                    lines.append(json.dumps(str(target)) + ' = {source = ' + json.dumps(str(source))
                                 + ', mode = ' + json.dumps(entry['mode']) + '}')
                selected = shared['bootstrap']['dotfile_groups']
                lines += ['[bootstrap]', 'dotfile_groups = ' + json.dumps(selected)]
                for name in selected:
                    group = shared['dotfile_groups'][name]
                    source_root = fixture / 'dotfiles' / group['root']
                    target_root = fixture / 'destinations' / group['target'].removeprefix('~/')
                    added = source_root / '.group-fixture-new-file'
                    added.write_text('new group member\n')
                    lines += [f'[dotfile_groups.{name}]', 'root = ' + json.dumps(str(source_root)),
                              'target = ' + json.dumps(str(target_root)), 'mode = "symlink-each"', 'relative = false']
                    members = [source for source in source_root.rglob('*') if source.is_file()]
                    self.assertTrue(members)
                    targets.extend((target_root / source.relative_to(source_root), source, 'symlink') for source in members)
                (fixture / 'config.toml').write_text('\n'.join(lines))
                env = {key: os.environ[key] for key in ('PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TMPDIR', 'TERM') if key in os.environ}
                for name in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
                    env[f'MISE_{name}_DIR'] = str(fixture if name == 'CONFIG' else fixture / name.lower())
                (fixture / 'empty-system-config').mkdir()
                env.update(MISE_TRUSTED_CONFIG_PATHS=str(fixture), MISE_AUTO_INSTALL='0',
                           MISE_SYSTEM_CONFIG_DIR=str(fixture / 'empty-system-config'),
                           MISE_CEILING_PATHS=str(fixture), MISE_ENV='', MISE_AUTO_ENV='0',
                           MISE_NO_ENV='1', MISE_NO_HOOKS='1', MISE_AUTO_UPDATE='0')
                def mise(*args):
                    result = subprocess.run([MISE, '-C', str(fixture), *args], env=env, cwd=fixture,
                                            text=True, capture_output=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    return result
                neighbor = fixture / 'destinations/.config/nvim/unmanaged-state.json'
                neighbor.parent.mkdir(parents=True, exist_ok=True)
                neighbor.write_text('{"keep":true}\n')
                mise('bootstrap', 'dotfiles', 'apply')
                for target, source, mode in targets:
                    if mode == 'symlink':
                        self.assertTrue(target.is_symlink(), str(target))
                        self.assertEqual(target.resolve(), source.resolve())
                before = [(t, t.read_bytes(), t.lstat().st_mtime_ns) for t, _, _ in targets]
                mise('bootstrap', 'dotfiles', 'apply')
                for target, content, mtime in before:
                    self.assertEqual(target.read_bytes(), content)
                    self.assertEqual(target.lstat().st_mtime_ns, mtime)
                self.assertEqual(neighbor.read_text(), '{"keep":true}\n')
                target, source, _ = next(e for e in targets if e[1] == fixture / 'dotfiles/.config/nvim/init.lua')
                self.assertTrue(target.is_symlink())
                target.write_text('fixture change\n')
                self.assertEqual(source.read_text(), 'fixture change\n')
                target.unlink()
                self.assertTrue(source.exists())
                self.assertTrue(neighbor.exists())
                mise('bootstrap', 'dotfiles', 'apply')
                self.assertTrue(target.is_symlink())


if __name__ == '__main__':
    unittest.main()
