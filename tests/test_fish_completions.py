import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FISH = shutil.which('fish')
CARAPACE = shutil.which('carapace')
HERDR = shutil.which('herdr')
TINY_MIST = shutil.which('tinymist')
YAZI = shutil.which('yazi')
YA = shutil.which('ya')


@unittest.skipUnless(FISH and HERDR, 'Fish and Herdr required')
class FishCompletionTests(unittest.TestCase):
    def test_herdr_uses_its_native_fish_generator(self):
        completion = ROOT / 'dotfiles/.config/fish/completions/herdr.fish'
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory)
            result = subprocess.run(
                [FISH, '--no-config', '-c',
                 f'source {completion}; complete -C "herdr "'],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertIn('completion', result.stdout)
        self.assertIn('workspace', result.stdout)

    @unittest.skipUnless(TINY_MIST, 'Tinymist required')
    def test_tinymist_uses_its_native_fish_generator(self):
        completion = ROOT / 'dotfiles/.config/fish/completions/tinymist.fish'
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory)
            result = subprocess.run(
                [FISH, '--no-config', '-c',
                 f'source {completion}; complete -C "tinymist "'],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertIn('completion', result.stdout)
        self.assertIn('preview', result.stdout)

    @unittest.skipUnless(FISH and YAZI and YA, 'Fish and Yazi required')
    def test_yazi_uses_bundled_fish_providers(self):
        helper = ROOT / 'dotfiles/.config/fish/functions/__mise_source_yazi_completion.fish'
        yazi_completion = ROOT / 'dotfiles/.config/fish/completions/yazi.fish'
        ya_completion = ROOT / 'dotfiles/.config/fish/completions/ya.fish'
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory)
            result = subprocess.run(
                [FISH, '--no-config', '-c',
                 f'source {helper}; source {yazi_completion}; source {ya_completion}; '
                 'complete -C "yazi --"; complete -C "ya "'],
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )
        self.assertIn('--cwd-file', result.stdout)
        self.assertIn('emit', result.stdout)

    @unittest.skipUnless(CARAPACE, 'Carapace required')
    def test_carapace_is_generated_for_fish(self):
        env = dict(os.environ, CARAPACE_BRIDGES='fish,bash,inshellisense')
        result = subprocess.run(
            [CARAPACE, 'eza', 'fish'],
            env=env,
            text=True,
            capture_output=True,
            check=True,
            timeout=10,
        )
        self.assertIn("complete -c 'eza'", result.stdout)

    def test_config_passes_fish_to_carapace(self):
        config = (ROOT / 'dotfiles/.config/fish/config.fish').read_text()
        self.assertIn('command carapace _carapace fish 2>/dev/null | source', config)


if __name__ == '__main__':
    unittest.main()
