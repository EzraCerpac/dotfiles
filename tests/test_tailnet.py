import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TASK = Path(__file__).resolve().parents[1] / 'tasks/bootstrap/enroll-tailscale'

class TailnetTests(unittest.TestCase):
    def fixture(self, state, failure=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = root / 'tailscale'
            cli.write_text('''#!/bin/bash
set -eu
[[ -z "${SETUP_TAILSCALE_AUTH_KEY:-}" ]] || exit 90
printf '%s\\n' "$*" >> "$CALL_LOG"
if [[ $1 == status ]]; then
  if [[ $STATE == broken ]]; then echo 'daemon unavailable' >&2; exit 1; fi
  printf '{"BackendState":"%s"}\\n' "$STATE"; exit 0
fi
[[ $1 == up && $2 == --auth-key=file:* ]] || exit 91
keyfile=${2#--auth-key=file:}
[[ $(cat "$keyfile") == tskey-fixture-secret ]] || exit 92
case $(uname -s) in
  Darwin) mode=$(stat -f '%Lp' "$keyfile") ;;
  *) mode=$(stat -c '%a' "$keyfile") ;;
esac
[[ $mode == 600 ]] || exit 93
printf '%s' "$keyfile" > "$KEY_PATH"
if [[ -n $FAILURE ]]; then printf '%s\\n' "$FAILURE" >&2; exit 1; fi
''')
            cli.chmod(0o755)
            log, key_path = root / 'calls', root / 'key-path'
            env = dict(os.environ, TAILSCALE_CLI=str(cli), STATE=state, FAILURE=failure,
                       CALL_LOG=str(log), KEY_PATH=str(key_path), SETUP_TAILSCALE_AUTH_KEY='tskey-fixture-secret',
                       SETUP_NONINTERACTIVE='1', TMPDIR=str(root))
            result = subprocess.run(['bash', str(TASK)], env=env, text=True, capture_output=True)
            calls = log.read_text()
            self.assertNotIn('tskey-fixture-secret', result.stdout + result.stderr + calls)
            if key_path.exists(): self.assertFalse(Path(key_path.read_text()).exists())
            return result, calls

    def test_connected_does_not_change_preferences(self):
        result, calls = self.fixture('Running')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.strip(), 'status --json')

    def test_key_is_private_and_removed(self):
        result, calls = self.fixture('NeedsLogin')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('up --auth-key=file:', calls)

    def test_expired_key_defers_browser_login(self):
        result, _ = self.fixture('NeedsLogin', 'auth key expired')
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_broken_backend_does_not_attempt_enrollment(self):
        result, calls = self.fixture('broken')
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(calls.strip(), 'status --json')

if __name__ == '__main__': unittest.main()
