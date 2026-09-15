"""Native dotfile fixtures; never apply repository targets to the real home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
MISE = os.environ.get('SETUP_TEST_MISE', 'mise')


class DotfileFixtures(unittest.TestCase):
    def test_profile_sources_and_native_link_lifecycle(self):
        for role in ('workstation', 'nas'):
            with self.subTest(role=role), tempfile.TemporaryDirectory(prefix='mise-dotfiles-') as tmp:
                fixture = Path(tmp)
                for directory in ('dotfiles', 'templates'):
                    shutil.copytree(ROOT / directory, fixture / directory, symlinks=True)
                base = (ROOT / 'config.toml').read_text().split('[tools]')[0]
                # Shared configuration precedes task/hook declarations.
                self.assertNotIn('[bootstrap.hooks]', base)
                base = base.replace('[vars]\n', f'[vars]\nprofile = "{role}"\n')
                profile = tomllib.loads((ROOT / f'config.{role}.toml').read_text())
                entries = {**tomllib.loads((ROOT / 'config.toml').read_text()).get('dotfiles', {}), **profile.get('dotfiles', {})}
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
                (fixture / 'config.toml').write_text('\n'.join(lines))
                env = os.environ.copy()
                for name in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
                    env[f'MISE_{name}_DIR'] = str(fixture if name == 'CONFIG' else fixture / name.lower())
                env.update(MISE_TRUSTED_CONFIG_PATHS=str(fixture), MISE_AUTO_INSTALL='0')
                def mise(*args):
                    result = subprocess.run([MISE, '-C', str(fixture), *args], env=env,
                                            text=True, capture_output=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    return result
                neighbor = fixture / 'destinations/.config/nvim/unmanaged-state.json'
                neighbor.parent.mkdir(parents=True, exist_ok=True)
                neighbor.write_text('{"keep":true}\n')
                mise('bootstrap', 'dotfiles', 'apply')
                before = [(t, t.read_bytes(), t.lstat().st_mtime_ns) for t, _, _ in targets]
                mise('bootstrap', 'dotfiles', 'apply')
                for target, content, mtime in before:
                    self.assertEqual(target.read_bytes(), content)
                    self.assertEqual(target.lstat().st_mtime_ns, mtime)
                self.assertEqual(neighbor.read_text(), '{"keep":true}\n')
                target, source, _ = next(e for e in targets if e[2] == 'symlink')
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
