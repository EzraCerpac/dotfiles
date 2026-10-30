import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / 'setup-scripts/lib/dots-command-backend.py'


class StatusBridgeTests(unittest.TestCase):
    def test_structured_resources_and_attention_do_not_leak_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'mise'
            fake.write_text('''#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
if 'source-repo.mjs' in ' '.join(a):
 print(json.dumps({'workspace':'git','shared':'origin/main'})); sys.exit(3)
if 'atuin.py' in ' '.join(a):
 print('private diagnostic', file=sys.stderr); sys.exit(3)
if 'ls' in a:
 print(json.dumps({'jq':[{'active':True,'installed':True,'version':'1.0','requested_version':'latest'}]}))
elif 'dotfiles' in a:
 print(json.dumps({'files':[{'target':'~/.zshrc','state':'differs'}], 'history':{'enabled':True,'watcher':'service-not-watching','sync':{'last_error':'private secret'}}}))
else:
 print(json.dumps({'packages':{'brew':{'packages':[{'package':'foo','state':'missing'}]}},'files':[{'id':{'kind':'directory','name':'/fixture'},'action':'noop'}],'user_services':[{'name':'watcher','action':'noop'}],'macos_defaults':{'entries':[{'domain':'example','key':'setting','value':'private secret','state':'set'}]},'login_shell':{'state':'set'}}))
''')
            fake.chmod(0o755)
            env = {**os.environ, 'SETUP_PROFILE': 'workstation', 'DOTS_STATUS_IN_ENV': '1', 'DOTS_UP_STREAM_NONCE': 'fixture'}
            result = subprocess.run(['python3', str(BRIDGE), str(fake), str(root), 'status'], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('private', result.stdout + result.stderr)
            events = [json.loads(chunk.split(':', 2)[2]) for chunk in result.stdout.split('\x1e') if chunk for chunk in [chunk.rstrip('\x1f')]]
            items = {event['id']: event for event in events if event['kind'] == 'item_upsert'}
            self.assertEqual(items['source:repository']['status'], 'attention')
            self.assertEqual(items['inspection:Atuin']['status'], 'attention')
            self.assertEqual(items['packages:brew:foo']['status'], 'missing')
            self.assertEqual(items['files:~/.zshrc']['status'], 'drift')
            self.assertEqual(items['tools:jq@latest']['status'], 'ok')
            self.assertEqual(items['history:settings history']['status'], 'attention')
            self.assertEqual(items['history:watcher']['status'], 'attention')
            self.assertEqual(items['directories:/fixture']['status'], 'ok')
            self.assertEqual(items['user services:watcher']['status'], 'ok')
            self.assertEqual(items['macos defaults:example:setting']['status'], 'ok')
            self.assertEqual(items['login shell:login shell']['status'], 'ok')
            self.assertEqual(events[-1]['exit_code'], 0)


if __name__ == '__main__':
    unittest.main()
