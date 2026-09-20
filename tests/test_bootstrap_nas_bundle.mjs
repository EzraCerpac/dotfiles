import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { complete } from '../tasks/bootstrap/complete.mjs';
import { writeBundle } from '../tasks/bootstrap/bundle.mjs';

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-nas-bundle-'));
try {
  const home = path.join(temporary, 'home');
  const root = path.join(home, '.config/mise');
  fs.mkdirSync(path.join(root, 'encrypted'), { recursive: true });
  fs.writeFileSync(path.join(root, 'config.local.toml'), '');
  const recoveryKey = path.join(temporary, 'nas-recovery-key');
  const workstationKey = path.join(temporary, 'workstation-bundle-key');
  assert.equal(spawnSync('age-keygen', ['-o', recoveryKey]).status, 0);
  assert.equal(spawnSync('age-keygen', ['-o', workstationKey]).status, 0);
  const workstationRecipient = spawnSync('age-keygen', ['-y', workstationKey], { encoding: 'utf8' }).stdout.trim();
  const hostIdentity = path.join(home, '.config/age/keys.txt');
  fs.mkdirSync(path.dirname(hostIdentity), { recursive: true });
  assert.equal(spawnSync('age-keygen', ['-o', hostIdentity]).status, 0);
  writeBundle({
    document: { version: 1, secrets: { tailscale_auth_key: 'workstation-only-fixture' } },
    outputPath: path.join(root, 'encrypted/bootstrap.json.age'),
    recipient: workstationRecipient,
  });

  const local = {
    'env.SETUP_PROFILE': 'nas',
    'env.SETUP_MACHINE_ID': 'fixture-host',
  };
  const calls = [];
  const run = (command, args, options) => {
    calls.push({ command, args });
    const text = args.join(' ');
    if (text.includes('config get')) {
      const key = args.at(-1);
      return { status: key in local ? 0 : 1, stdout: local[key] || '' };
    }
    if (text.includes('config set')) local[args.at(-2)] = args.at(-1);
    if (command === 'age-keygen') return { status: 0, stdout: 'age1fixturepublicrecipient\n' };
    if (text.includes('dot status --json')) return { status: 0, stdout: '{"history":{"watcher":"running"}}' };
    if (text.includes('tasks/bootstrap/tailnet')) return { status: 3 };
    return { status: 0, stdout: '' };
  };
  const env = {
    HOME: home,
    SETUP_PROFILE: 'nas',
    SETUP_AGE_IDENTITY: recoveryKey,
    XDG_STATE_HOME: path.join(home, 'state'),
  };
  assert.equal(complete({ root, home, miseBin: '/fixture/mise', env, run }), 0);
  assert(calls.some(({ args }) => args.some((arg) => arg.endsWith('/tasks/bootstrap/enroll-history'))),
    'NAS history enrollment should proceed without the implicit workstation bundle');
  assert(!calls.some(({ args }) => args.includes('workstation-only-fixture')),
    'workstation bundle contents must not enter NAS bootstrap');
  console.log('NAS bootstrap ignores an implicit workstation bundle and still enrolls history.');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
