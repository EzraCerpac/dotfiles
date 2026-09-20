"""Exercise recovery/service ordering without touching the user's home or services."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NODE = shutil.which('node')
RUNNER = r'''
const { complete } = await import(process.env.COMPLETE_MODULE);
const calls = [];
const run = (command, args, options) => {
  calls.push({ command, args });
  const text = args.join(' ');
  if (text.includes('config get')) {
    const key = args.at(-1);
    const values = {'env.SETUP_PROFILE':'nas', 'env.SETUP_MACHINE_ID':'fixture-host'};
    return {status: key in values ? 0 : 1, stdout: values[key] || ''};
  }
  if (command === 'age-keygen') return {status:0, stdout:'age1fixturepublicrecipient\n'};
  if (text.includes('dot status --json')) return {status:0, stdout:JSON.stringify({history:{watcher:process.env.WATCHER_STATE || 'running'}})};
  if (text.includes('tasks/setup/restore') && process.env.FAIL_RESTORE) return {status:1};
  if (text.includes('tasks/bootstrap/tailnet')) return {status:3};
  return {status:0, stdout:''};
};
const result = complete({root:process.env.TEST_ROOT,home:process.env.HOME,miseBin:'/fixture/mise',env:process.env,run});
console.log('RESULT_JSON='+JSON.stringify({result,calls}));
'''


@unittest.skipUnless(NODE, 'Node required')
class CompleteTests(unittest.TestCase):
    def run_fixture(self, **overrides):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            root = home / '.config/mise'
            root.mkdir(parents=True)
            (root / 'config.local.toml').write_text('')
            identity = home / '.config/age/keys.txt'
            identity.parent.mkdir()
            identity.write_text('fixture identity')
            env = dict(os.environ, HOME=str(home), TEST_ROOT=str(root),
                       COMPLETE_MODULE=(ROOT / 'tasks/bootstrap/complete.mjs').as_uri(),
                       SETUP_PROFILE='nas', SETUP_RESTORE_MACHINE_ID='fixture-host',
                       SETUP_AGE_IDENTITY=str(identity), XDG_STATE_HOME=str(home / 'state'))
            env.pop('SETUP_BOOTSTRAP_BUNDLE', None)
            env.update(overrides)
            result = subprocess.run([NODE, '--input-type=module', '-e', RUNNER], env=env,
                                    text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(next(line.removeprefix('RESULT_JSON=') for line in result.stdout.splitlines() if line.startswith('RESULT_JSON=')))
            report = json.loads((home / 'state/mise/bootstrap/last-run.json').read_text())
            return data, report

    def test_restore_precedes_enrollment_and_watcher(self):
        data, report = self.run_fixture()
        calls = [' '.join(c['args']) for c in data['calls']]
        restore = next(i for i,c in enumerate(calls) if 'tasks/setup/restore' in c)
        enroll = next(i for i,c in enumerate(calls) if 'tasks/bootstrap/enroll-history' in c)
        services = next(i for i,c in enumerate(calls) if 'bootstrap services apply' in c)
        self.assertLess(restore, enroll)
        self.assertLess(enroll, services)
        self.assertFalse(any('dot sync' in c or 'dotfiles sync' in c for c in calls))
        self.assertEqual(data['result'], 0)
        self.assertEqual(report['stages'][-1]['status'], 'deferred')

    def test_failed_restore_never_starts_watcher(self):
        data, report = self.run_fixture(FAIL_RESTORE='1')
        self.assertEqual(data['result'], 1)
        self.assertFalse(any('bootstrap services apply' in ' '.join(c['args']) for c in data['calls']))
        self.assertTrue(any(s['stage']=='Restore private settings' and s['status']=='failed' for s in report['stages']))

    def test_unavailable_user_service_is_deferred(self):
        data, report = self.run_fixture(WATCHER_STATE='stopped')
        self.assertEqual(data['result'], 0)
        self.assertEqual(next(s['status'] for s in report['stages'] if s['stage']=='Encrypted local history'), 'deferred')


if __name__ == '__main__':
    unittest.main()
