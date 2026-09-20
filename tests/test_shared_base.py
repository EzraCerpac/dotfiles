import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SharedBaseTests(unittest.TestCase):
    def test_everyday_tools_and_editor_are_shared_without_compiler(self):
        base = tomllib.loads((ROOT/'config.toml').read_text())
        tools = base['tools']
        expected = {'age','atuin','bat','carapace','delta','fd','fzf','gh','jj','jq','ripgrep','starship','tmux','uv','zoxide','aqua:neovim/neovim','aqua:modem-dev/hunk','aqua:dlvhdr/diffnav','vfox:jdx/vfox-eza'}
        self.assertTrue(expected <= tools.keys())
        self.assertEqual(tools['uv'], {'version': 'latest', 'os': ['macos/arm64', 'macos/x64', 'linux/x64', 'linux/arm64']})
        self.assertNotIn('rust', tools)
        self.assertFalse(any(key.startswith('cargo:') for key in tools))
        for role in ('workstation','nas'):
            profile=tomllib.loads((ROOT/f'config.{role}.toml').read_text())
            self.assertFalse(tools.keys() & profile.get('tools',{}).keys())
            self.assertFalse(base['dotfiles'].keys() & profile.get('dotfiles',{}).keys())
        for path in ('~/.config/fish/config.fish','~/.config/jj/config.toml','~/.config/git/config','~/.config/nvim/init.lua','~/.local/bin/dots'):
            self.assertIn(path, base['dotfiles'])
        self.assertIn('github:fish-shell/fish-shell', tools)
        for package in ('fish','git'):
            self.assertIn(f'brew:{package}', base['bootstrap']['packages'])
        # NAS maintenance must not acquire ownership of its system packages.
        self.assertFalse(any(key.startswith(('apt:', 'dnf:', 'pacman:'))
                             for key in base['bootstrap']['packages']))
        workstation=tomllib.loads((ROOT/'config.workstation.toml').read_text())
        for manager in ('apt','dnf','pacman'):
            self.assertIn(f'{manager}:git', workstation['bootstrap']['packages'])

    def test_retired_selector_fails_before_bootstrap_hooks(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture=Path(tmp)
            for name in ('config.toml','config.workstation.toml','config.delftblue.toml'):
                (fixture/name).write_text((ROOT/name).read_text())
            env=dict(os.environ, MISE_TRUSTED_CONFIG_PATHS=str(fixture), MISE_AUTO_INSTALL='0')
            for key in ('CONFIG','DATA','STATE','CACHE'):
                env[f'MISE_{key}_DIR']=str(fixture if key=='CONFIG' else fixture/key.lower())
            for selection in ('delftblue','delftblue,workstation'):
                result=subprocess.run([str(Path.home()/'.local/bin/mise'),'-C',str(fixture),'-E',selection,'bootstrap','--dry-run'],env=env,text=True,capture_output=True,timeout=30)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('delftblue profile is retired',result.stderr)
                self.assertNotIn('bootstrap: pre-packages',result.stdout)

if __name__=='__main__': unittest.main()
