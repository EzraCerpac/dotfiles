import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { writeBundle, unlockBundle, applyPrivateFiles } from '../tasks/bootstrap/bundle.mjs';

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-bundle-test-'));
const miseBin = process.env.SETUP_MISE_BIN || path.join(os.homedir(), '.local/bin/mise');
const home = path.join(temporary, 'different-home');
fs.mkdirSync(home);
const key = path.join(temporary, 'identity');
const wrongKey = path.join(temporary, 'wrong-identity');
const secrets = {
  wakatime_config: '[settings]\napi_key = fixture-secret-with-"quotes"\n',
  himalaya_config: '[accounts.fixture]\nemail = "fixture@example.invalid"\n',
};
try {
  for (const filename of [key, wrongKey]) {
    assert.equal(spawnSync('age-keygen', ['-o', filename]).status, 0);
  }
  const recipient = spawnSync('age-keygen', ['-y', key], { encoding: 'utf8' }).stdout.trim();
  const bundle = path.join(temporary, 'bootstrap.age');
  writeBundle({ document: { version: 1, secrets }, outputPath: bundle, recipient });
  assert(!fs.readFileSync(bundle).includes(Buffer.from('fixture-secret')));
  assert.throws(() => unlockBundle(bundle, wrongKey), /Cannot decrypt/);
  const unlocked = unlockBundle(bundle, key);
  assert.deepEqual(unlocked.secrets, secrets);
  assert.throws(() => writeBundle({ document: { version: 1, secrets }, outputPath: bundle, recipient }), /already exists/);
  for (let pass = 0; pass < 2; pass++) applyPrivateFiles(unlocked.secrets, { home, miseBin });
  const target = path.join(home, '.wakatime.cfg');
  assert.equal(fs.readFileSync(target, 'utf8'), secrets.wakatime_config);
  assert.equal(fs.statSync(target).mode & 0o777, 0o600);
  fs.writeFileSync(target, '[settings]\napi_key = independent-change\n');
  assert.throws(() => applyPrivateFiles(secrets, { home, miseBin }), /differs/);
  assert(fs.readFileSync(target, 'utf8').includes('independent-change'));
  fs.unlinkSync(target);
  fs.symlinkSync(path.join(temporary, 'outside'), target);
  assert.throws(() => applyPrivateFiles(secrets, { home, miseBin }), /symlink/);
  console.log('Bundle: encryption, wrong key, native rendering, permissions, reapply, drift and symlink checks passed.');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
