import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FISH = shutil.which('fish')


@unittest.skipUnless(FISH, 'Fish required')
class FishHistoryTests(unittest.TestCase):
    def test_session_recall_excludes_other_panes_and_preserves_existing_history(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory, XDG_DATA_HOME=f'{directory}/data')
            shared = Path(directory, 'data/fish/fish_history')
            shared.parent.mkdir(parents=True)
            original = '- cmd: echo OTHER_PANE\n  when: 1\n'
            shared.write_text(original)
            first = subprocess.run([FISH, '--no-config', '-c',
                "set -g fish_history ''; builtin history append -- 'echo THIS_PANE'; builtin history search"],
                env=env, text=True, capture_output=True, check=True)
            second = subprocess.run([FISH, '--no-config', '-c',
                "set -g fish_history ''; builtin history search"],
                env=env, text=True, capture_output=True, check=True)
            self.assertEqual(first.stdout.strip(), 'echo THIS_PANE')
            self.assertEqual(second.stdout, '')
            self.assertEqual(shared.read_text(), original)


if __name__ == '__main__':
    unittest.main()
