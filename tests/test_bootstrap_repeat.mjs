import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { complete } from '../tasks/bootstrap/complete.mjs';
import { writeBundle } from '../tasks/bootstrap/bundle.mjs';

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-repeat-'));
try {
  const home = path.join(temporary, 'home');
  const root = path.join(home, '.config/mise');
  fs.mkdirSync(path.join(root, 'encrypted'), { recursive: true });
  fs.writeFileSync(path.join(root, 'config.local.toml'), '');
  const externalKey = path.join(temporary, 'recovery-key');
  assert.equal(spawnSync('age-keygen', ['-o', externalKey]).status, 0);
  const recipient = spawnSync('age-keygen', ['-y', externalKey], { encoding: 'utf8' }).stdout.trim();
  writeBundle({ document: { version: 1, secrets: { tailscale_auth_key: 'fixture-enrollment-key' } },
    outputPath: path.join(root, 'encrypted/bootstrap.json.age'), recipient });
  const local = { 'env.SETUP_PROFILE': 'nas', 'env.SETUP_MACHINE_ID': 'fixture-host' };
  const calls = [];
  const run = (command, args, options) => {
    calls.push({ command, args, key: options.env.SETUP_TAILSCALE_AUTH_KEY });
    if (command === 'age-keygen') return spawnSync(command, args, { encoding: 'utf8' });
    const text = args.join(' ');
    if (text.includes('config get')) {
      const key = args.at(-1);
      return { status: key in local ? 0 : 1, stdout: local[key] || '' };
    }
    if (text.includes('config set')) local[args.at(-2)] = args.at(-1);
    if (text.includes('tasks/bootstrap/enroll-history')) {
      local['env.SETUP_AGE_IDENTITY'] = args[args.indexOf('--identity') + 1];
    }
    if (text.includes('dot status --json')) return { status: 0, stdout: '{"history":{"watcher":"running"}}' };
    return { status: 0, stdout: '' };
  };
  const env = { HOME: home, SETUP_PROFILE: 'nas', SETUP_AGE_IDENTITY: externalKey,
    SETUP_BOOTSTRAP_BUNDLE: path.join(root, 'encrypted/bootstrap.json.age'),
    XDG_STATE_HOME: path.join(home, 'state'), SETUP_TAILSCALE_AUTH_KEY: 'inherited-key' };
  assert.equal(complete({ root, home, miseBin: '/fixture/mise', env, run }), 0);
  const hostKey = local['env.SETUP_AGE_IDENTITY'];
  assert.notEqual(hostKey, externalKey);
  assert(fs.existsSync(hostKey));
  assert.equal(local['vars.bootstrap_bundle_identity'], externalKey);
  // A normal second invocation loads the host identity persisted by enrollment.
  // The bundle still needs the independent external identity from the first run.
  assert.equal(complete({ root, home, miseBin: '/fixture/mise',
    env: { ...env, SETUP_AGE_IDENTITY: hostKey }, run }), 0);
  const enrollments = calls.filter(c => c.args.some(a => a.endsWith('/tasks/bootstrap/tailnet')));
  assert.equal(enrollments.length, 2);
  assert(enrollments.every(c => c.key === 'fixture-enrollment-key'));
  assert(calls.filter(c => !enrollments.includes(c)).every(c => c.key === undefined));
  const historyEnrollments = calls.filter(c => c.args.some(a => a.endsWith('/tasks/bootstrap/enroll-history')));
  assert.equal(historyEnrollments.length, 2);
  assert(historyEnrollments.every(c => c.args.includes(recipient)), 'Both passes retain the external recovery recipient');
  console.log('Repeat bootstrap preserves bundle identity and isolates enrollment credentials.');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
