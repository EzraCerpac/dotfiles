import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FISH = shutil.which('fish')


@unittest.skipUnless(FISH, 'Fish required')
class FishHistoryTests(unittest.TestCase):
    def test_question_mark_opens_ai_only_at_an_empty_prompt(self):
        bindings = Path(__file__).resolve().parents[1] / 'dotfiles/.config/fish/functions/fish_user_key_bindings.fish'
        script = r'''
source $argv[1]
function commandline
    switch $argv[1]
        case -b
            printf '%s' "$buffer"
        case -i
            set -g buffer "$buffer$argv[2]"
    end
end
function _atuin_ai_question_mark
    echo AI_OPENED
end
set -g fish_key_bindings fish_vi_key_bindings
set -g buffer ''
__dots_atuin_question_mark
set -g buffer 'echo '
__dots_atuin_question_mark
printf '%s\n' "$buffer"
'''
        result = subprocess.run([FISH, '--no-config', '-c', script, str(bindings)],
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, 'AI_OPENED\necho ?\n')

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
