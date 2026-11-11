import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { complete, hookStatus } from '../bootstrap/complete.mjs';
import { miseBinary, requires } from './lib/prereq.mjs';

const MANAGER = path.resolve(import.meta.dirname, '..');

function fixture() {
  const base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'dots-bootstrap-hooks-')));
  const root = path.join(base, 'config');
  const home = path.join(base, 'home');
  fs.mkdirSync(root, { recursive: true });
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(path.join(root, 'config.toml'), '# minimal configuration\n');
  const hook = (name, body, mode = 0o755) => {
    const file = path.join(root, 'dots/hooks/bootstrap.d', name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `#!/usr/bin/env bash\n${body}`, { mode });
    return file;
  };
  return { base, root, home, hook, cleanup: () => fs.rmSync(base, { recursive: true, force: true }) };
}

// A fake mise for complete(): answers [vars], runs `exec -- HOOK` for hooks in
// the fixture, and reports success for every other command without running it.
function fakeRun(root, calls, vars = { dots_profiles: 'laptop server' }) {
  return (command, args, options) => {
    calls.push([command, ...args]);
    const at = args.indexOf('exec');
    if (at >= 0 && args[at + 1] === '--' && args[at + 2]?.startsWith(path.join(root, 'dots/hooks/'))) {
      return spawnSync(args[at + 2], args.slice(at + 3), { ...options, stdio: ['ignore', 'pipe', 'pipe'] });
    }
    const variable = args.find(arg => arg.startsWith('vars.'));
    if (args.includes('get') && variable) {
      const value = vars[variable.slice('vars.'.length)];
      return value === undefined ? { status: 1, stdout: '', stderr: 'not found' } : { status: 0, stdout: `${value}\n`, stderr: '' };
    }
    if (args.includes('get')) return { status: 1, stdout: '', stderr: '' };
    return { status: 0, stdout: '', stderr: '' };
  };
}

function bootstrap(f, calls, env = {}, vars, miseBin = '/fixture/mise') {
  const log = console.log;
  const lines = [];
  console.log = line => lines.push(String(line));
  try {
    const code = complete({
      root: f.root, dotsHome: MANAGER, home: f.home, miseBin,
      env: { PATH: process.env.PATH, SETUP_PROFILE: 'laptop', SETUP_MACHINE_ID: 'fixture-host', XDG_STATE_HOME: path.join(f.base, 'state'), ...env },
      run: fakeRun(f.root, calls, vars),
    });
    return { code, lines, report: JSON.parse(fs.readFileSync(path.join(f.base, 'state/mise/bootstrap/last-run.json'), 'utf8')) };
  } finally {
    console.log = log;
  }
}

test('hook exit statuses map to completed, deferred, skipped and failed', () => {
  assert.deepEqual([0, 3, 4, 1, 2, 5].map(hookStatus), ['completed', 'deferred', 'skipped', 'failed', 'failed', 'failed']);
});

test('bootstrap runs hooks after installer exceptions with readiness facts', () => {
  const f = fixture();
  const out = path.join(f.base, 'env');
  try {
    f.hook('40-after-failure', `touch ${f.base}/after\n`);
    f.hook('30-broken', 'exit 7\n');
    f.hook('20-later', 'exit 3\n');
    f.hook('25-not-here', 'exit 4\n');
    f.hook('10-Facts', `printf '%s\\n' "$DOTS_ROOT" "$DOTS_HOME" "$DOTS_PROFILE" "$DOTS_PRIVATE_READY" "$DOTS_RESTORED" "$PWD" > ${out}\n`);
    f.hook('50-skipped-mode', 'exit 0\n', 0o644);
    f.hook('35-Laptop-only@laptop', 'exit 0\n');
    f.hook('36-Server-only@server', `touch ${f.base}/server\n`);
    const calls = [];
    const { code, report } = bootstrap(f, calls);
    assert.equal(code, 1);
    const stages = report.stages.map(({ stage, status }) => `${stage}:${status}`);
    const first = stages.indexOf('Facts:completed');
    assert.deepEqual(stages.slice(first - 1, first + 5), [
      'Installer exceptions:completed', 'Facts:completed', 'later:deferred', 'not here:skipped', 'broken:failed', 'Laptop only:completed',
    ]);
    assert.deepEqual(stages.slice(first + 5, first + 7), ['after failure:completed', 'Atuin:completed']);
    assert.ok(!fs.existsSync(path.join(f.base, 'server')), 'a hook for another profile ran');
    assert.ok(fs.existsSync(path.join(f.base, 'after')));
    assert.deepEqual(fs.readFileSync(out, 'utf8').trim().split('\n'),
      [f.root, MANAGER, 'laptop', '1', '0', f.root]);
    assert.ok(!stages.some(stage => stage.startsWith('skipped mode')));
  } finally {
    f.cleanup();
  }
});

test('an unknown profile suffix fails the hook stage and runs no hooks', () => {
  const f = fixture();
  try {
    f.hook('10-fine', `touch ${f.base}/ran\n`);
    f.hook('20-typo@labtop', 'exit 0\n');
    const { code, report } = bootstrap(f, []);
    assert.equal(code, 1);
    const failed = report.stages.find(stage => stage.stage === 'Bootstrap hooks');
    assert.equal(failed.status, 'failed');
    assert.match(failed.detail, /names unknown profile "labtop"; use one of: laptop server/);
    assert.ok(!fs.existsSync(path.join(f.base, 'ran')));
  } finally {
    f.cleanup();
  }
});

test('only a profile with its own bundle requests it implicitly', () => {
  for (const [profile, status, detail] of [
    ['laptop', 'deferred', /Supply the encrypted bundle/],
    ['server', 'completed', /No bootstrap bundle requested for this host/],
  ]) {
    const f = fixture();
    try {
      fs.mkdirSync(path.join(f.root, 'encrypted'));
      fs.writeFileSync(path.join(f.root, 'encrypted/bootstrap.laptop.json.age'), 'ciphertext\n');
      const { report } = bootstrap(f, [], { SETUP_PROFILE: profile });
      const inputs = report.stages.find(stage => stage.stage === 'Private inputs');
      assert.equal(inputs.status, status, profile);
      assert.match(inputs.detail, detail);
    } finally {
      f.cleanup();
    }
  }
});

test('an explicit bundle supplies private files without a profile bundle', requires('mise'), () => {
  const f = fixture();
  try {
    const wakatime = '[settings]\napi_key = fixture\n';
    const age = path.join(f.base, 'age');
    fs.writeFileSync(age, `#!/bin/sh\nprintf '%s' ${JSON.stringify(JSON.stringify({ version: 1, secrets: { wakatime_config: wakatime } }))}\n`, { mode: 0o755 });
    for (const name of ['bundle.age', 'identity']) fs.writeFileSync(path.join(f.base, name), 'fixture\n');
    fs.writeFileSync(path.join(f.root, 'config.local.toml'), '');
    const { report } = bootstrap(f, [], {
      SETUP_BOOTSTRAP_BUNDLE: path.join(f.base, 'bundle.age'), SETUP_BUNDLE_IDENTITY: path.join(f.base, 'identity'), SETUP_AGE_BIN: age,
    }, undefined, miseBinary());
    assert.equal(report.stages.find(stage => stage.stage === 'Private configuration')?.status, 'completed');
    assert.equal(fs.readFileSync(path.join(f.home, '.wakatime.cfg'), 'utf8'), wakatime);
  } finally {
    f.cleanup();
  }
});

test('bootstrap without a dots directory runs only core stages', () => {
  const f = fixture();
  try {
    const { report } = bootstrap(f, []);
    assert.deepEqual(report.stages.map(stage => stage.stage).slice(0, 4),
      ['Private inputs', 'Source repository', 'Installer exceptions', 'Atuin']);
  } finally {
    f.cleanup();
  }
});

test('bootstrap names a missing profiles setting and rejects unknown profiles', () => {
  // Settings are read once per process and root, so each case gets its own fixture.
  for (const [env, vars, message] of [
    [{}, {}, /missing setting: add dots_profiles to \[vars\]/],
    [{ SETUP_PROFILE: 'desktop' }, undefined, /Persist the role and machine identity/],
  ]) {
    const f = fixture();
    try {
      assert.throws(() => bootstrap(f, [], env, vars), message);
    } finally {
      f.cleanup();
    }
  }
});
