import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { syncSource, SourceDeferred } from '../setup-scripts/lib/source-repo.mjs';
import { requires } from './lib/prereq.mjs';

const available = requires('git', 'gitleaks', 'jj');
function run(bin, args, cwd) {
  const r = spawnSync(bin, args, { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0, `${bin} ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}
const git = (cwd, ...args) => run('git', args, cwd);
function fixture(t, useJj = false) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-dev-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const oldEnv = { ...process.env };
  t.after(() => { for (const k of Object.keys(process.env)) if (!(k in oldEnv)) delete process.env[k]; Object.assign(process.env, oldEnv); });
  const config = path.join(dir, 'gitconfig');
  fs.writeFileSync(config, '[user]\nname = Fixture\nemail = fixture@example.invalid\n');
  process.env.GIT_CONFIG_GLOBAL = config;
  process.env.GIT_CONFIG_NOSYSTEM = '1';
  const jjConfig = path.join(dir, 'jj.toml');
  fs.writeFileSync(jjConfig, '[user]\nname = "Fixture"\nemail = "fixture@example.invalid"\n');
  process.env.JJ_CONFIG = jjConfig;
  const origin = path.join(dir, 'origin.git'), a = path.join(dir, 'a'), b = path.join(dir, 'b');
  git(dir, 'init', '--bare', '--initial-branch=main', origin);
  git(dir, 'clone', origin, a);
  fs.writeFileSync(path.join(a, 'config.toml'), '# initial\n');
  fs.writeFileSync(path.join(a, 'text'), 'first\nmiddle\nlast\n');
  fs.writeFileSync(path.join(a, '.gitignore'), '/config.local.toml\n/miserc.toml\n/config.host-*.toml\n/mise.lock\n/mise.nas.lock\n/mise.workstation.lock\n/.setup-state/\n/locks/\n');
  fs.copyFileSync(new URL('../.gitleaks.toml', import.meta.url), path.join(a, '.gitleaks.toml'));
  git(a, 'add', '.'); git(a, 'commit', '-m', 'Initial'); git(a, 'push', '-u', 'origin', 'main');
  git(dir, 'clone', origin, b);
  if (useJj) for (const root of [a, b]) { run('jj', ['git', 'init', '--colocate', root], dir); }
  const miseBin = path.join(dir, 'mise');
  fs.writeFileSync(miseBin, `#!/bin/sh
set -eu
case "$*" in
  *'config ls'*)
    if [ -n "\${DEV_TEST_MUTATE:-}" ]; then echo late > "$DEV_TEST_MUTATE"; fi
    if grep -q INVALID "$2/config.toml"; then exit 1; fi ;;
esac
`);
  fs.chmodSync(miseBin, 0o755);
  const sync = root => syncSource(root, { expectedRemote: origin, miseBin });
  const write = (root, file, contents, time) => {
    fs.writeFileSync(path.join(root, file), contents);
    if (time) fs.utimesSync(path.join(root, file), time / 1000, time / 1000);
  };
  const head = root => git(root, 'rev-parse', 'refs/heads/dev');
  const metadata = root => JSON.parse(Buffer.from(git(root, 'show', '-s', '--format=%B', head(root)).split('\n').find(l => l.startsWith('Dots-Saves: ')).slice(12), 'base64').toString());
  return { dir, a, b, origin, sync, write, head, metadata };
}

test('dirty public capture pushes dev, keeps main and private overlays', available, t => {
  const f = fixture(t); const main = git(f.a, 'rev-parse', 'main');
  f.write(f.a, 'new', 'ordinary public edit\n');
  f.write(f.a, 'config.local.toml', '[env]\nPRIVATE="yes"\n');
  f.sync(f.a);
  assert.equal(git(f.origin, 'rev-parse', 'dev'), f.head(f.a));
  assert.equal(git(f.a, 'rev-parse', 'main'), main);
  assert(!git(f.a, 'ls-tree', '-r', '--name-only', 'dev').includes('config.local.toml'));
  assert.equal(f.metadata(f.a).new.time, null, 'first import must not invent save provenance');
  f.sync(f.b); assert.equal(fs.readFileSync(path.join(f.b, 'new'), 'utf8'), 'ordinary public edit\n');
  assert.equal(fs.existsSync(path.join(f.a, '.jj')), false);
});

test('late offline edit loses to newer save; losing version and inherited times survive', available, t => {
  const f = fixture(t, true); f.sync(f.a); f.sync(f.b);
  const old = Date.now() - 100000, fresh = old + 50000;
  f.write(f.a, 'text', 'old offline edit\n', old);
  f.write(f.b, 'text', 'newer saved edit\n', fresh); f.sync(f.b);
  const newer = f.head(f.b);
  f.sync(f.a);
  assert.equal(fs.readFileSync(path.join(f.a, 'text'), 'utf8'), 'newer saved edit\n');
  assert.equal(f.metadata(f.a).text.time, fresh);
  const parents = git(f.a, 'show', '-s', '--format=%P', 'dev').split(' ');
  assert.equal(parents.length, 2); assert(parents.includes(newer));
  assert(parents.some(p => git(f.a, 'show', `${p}:text`) === 'old offline edit'));
  f.sync(f.a); assert.equal(f.metadata(f.a).text.time, fresh, 'receiving is not saving');
});

test('compatible two-writer changes merge and ordinary deletion propagates', available, t => {
  const f = fixture(t); f.sync(f.a); f.sync(f.b);
  f.write(f.a, 'text', 'FIRST\nmiddle\nlast\n');
  f.write(f.b, 'text', 'first\nmiddle\nLAST\n'); f.sync(f.b); f.sync(f.a);
  assert.equal(fs.readFileSync(path.join(f.a, 'text'), 'utf8'), 'FIRST\nmiddle\nLAST\n');
  fs.unlinkSync(path.join(f.a, 'text')); f.sync(f.a); f.sync(f.b);
  assert(!fs.existsSync(path.join(f.b, 'text')));
});

test('offline push queues locally and retries on next sync', available, t => {
  const f = fixture(t); f.sync(f.a);
  fs.renameSync(f.origin, `${f.origin}.offline`);
  f.write(f.a, 'text', 'saved offline\n'); f.sync(f.a);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.a, '.git/dots-dev.json'))).pending, true);
  fs.renameSync(`${f.origin}.offline`, f.origin); f.sync(f.a);
  assert.equal(git(f.origin, 'rev-parse', 'dev'), f.head(f.a));
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.a, '.git/dots-dev.json'))).pending, false);
});

test('secret stays local and outside snapshot ancestry', available, t => {
  const f = fixture(t, true); f.sync(f.a); const before = f.head(f.a);
  const token = ['ghp', 'R8tq3LwVn5Xk2Jc9Hy7Pd4Mb6Fz1Sa0Gu3Ee'].join('_');
  f.write(f.a, 'token', `github_token = "${token}"\n`);
  assert.throws(() => f.sync(f.a), SourceDeferred);
  assert.equal(f.head(f.a), before); assert.equal(git(f.origin, 'rev-parse', 'dev'), before);
  assert(fs.existsSync(path.join(f.a, 'token')));
});

test('invalid candidate stays queued without adoption or push', available, t => {
  const f = fixture(t); f.sync(f.a); const before = f.head(f.a);
  f.write(f.a, 'config.toml', 'INVALID\n'); assert.throws(() => f.sync(f.a));
  assert.equal(f.head(f.a), before); assert.equal(git(f.origin, 'rev-parse', 'dev'), before);
  assert.notEqual(git(f.a, 'rev-parse', 'refs/dots/queue'), before);
  f.write(f.a, 'config.toml', '# fixed\n'); f.sync(f.a);
});

test('concurrent source edit during preview is retained', available, t => {
  const f = fixture(t); f.sync(f.a); const before = f.head(f.a);
  f.write(f.a, 'text', 'captured\n'); process.env.DEV_TEST_MUTATE = path.join(f.a, 'text');
  assert.throws(() => f.sync(f.a), /changed during sync/);
  assert.equal(fs.readFileSync(path.join(f.a, 'text'), 'utf8'), 'late\n'); assert.equal(f.head(f.a), before);
});

test('overlap resolution preserves compatible edits outside the winning hunk', available, t => {
  const f = fixture(t); f.sync(f.a); f.sync(f.b);
  const initial = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\n';
  f.write(f.a, 'text', initial); f.sync(f.a); f.sync(f.b);
  f.write(f.a, 'text', initial.replace('one', 'older conflict').replace('nine', 'compatible tail'), Date.now() - 10000);
  f.write(f.b, 'text', initial.replace('one', 'newer conflict'), Date.now() - 1000);
  f.sync(f.b); f.sync(f.a);
  const result = fs.readFileSync(path.join(f.a, 'text'), 'utf8');
  assert(result.startsWith('newer conflict\n')); assert(result.endsWith('compatible tail\n'));
});

test('one bounded push retry merges a writer racing the first push', available, t => {
  const f = fixture(t); f.sync(f.a); f.sync(f.b);
  const hook = path.join(f.a, '.git/hooks/pre-push');
  fs.writeFileSync(hook, `#!/bin/sh
set -eu
unset GIT_INDEX_FILE
rm "$0"
printf 'raced\\n' > '${f.b}/raced'
git -C '${f.b}' add raced
git -C '${f.b}' commit -m Race >/dev/null
git -C '${f.b}' push origin HEAD:dev >/dev/null
`);
  fs.chmodSync(hook, 0o755);
  f.write(f.a, 'local', 'local\n'); f.sync(f.a);
  assert.equal(git(f.origin, 'rev-parse', 'dev'), f.head(f.a));
  assert.equal(fs.readFileSync(path.join(f.a, 'raced'), 'utf8'), 'raced\n');
  assert.equal(fs.readFileSync(path.join(f.a, 'local'), 'utf8'), 'local\n');
});

test('explicit first adoption imports an older inspected parent and preserves observed mtime', available, t => {
  const f = fixture(t); const inspected = git(f.a, 'rev-parse', 'HEAD');
  f.write(f.b, 'remote', 'later main\n'); git(f.b, 'add', '.'); git(f.b, 'commit', '-m', 'Later main'); git(f.b, 'push', 'origin', 'main');
  git(f.a, 'fetch', 'origin'); f.write(f.a, 'text', 'existing live edit\n', 1600000000000);
  assert.throws(() => f.sync(f.a), /explicit adoption/);
  process.env.DOTS_ADOPT_DEV_PARENT = inspected; f.sync(f.a); delete process.env.DOTS_ADOPT_DEV_PARENT;
  assert.equal(f.metadata(f.a).text.time, null);
  assert.equal(f.metadata(f.a).text.observedTime, 1600000000000);
  assert.equal(git(f.origin, 'show', 'dev:text'), 'existing live edit');
});

test('unchanged failed candidate reuses the queued capture', available, t => {
  const f = fixture(t); f.sync(f.a); f.write(f.a, 'config.toml', 'INVALID\n');
  assert.throws(() => f.sync(f.a)); const first = git(f.a, 'rev-parse', 'refs/dots/queue');
  assert.throws(() => f.sync(f.a)); assert.equal(git(f.a, 'rev-parse', 'refs/dots/queue'), first);
});

for (const useJj of [false, true]) test(`reverting a rejected capture cancels queued edits (${useJj ? 'JJ' : 'Git'})`, available, t => {
  const f = fixture(t, useJj); f.sync(f.a);
  f.write(f.a, 'config.toml', 'INVALID\n');
  f.write(f.a, 'cancelled', 'queued addition\n');
  assert.throws(() => f.sync(f.a));
  f.write(f.a, 'config.toml', '# initial\n');
  fs.unlinkSync(path.join(f.a, 'cancelled'));
  f.sync(f.a);
  assert.equal(fs.readFileSync(path.join(f.a, 'config.toml'), 'utf8'), '# initial\n');
  assert(!fs.existsSync(path.join(f.a, 'cancelled')));
  assert.equal(git(f.origin, 'show', 'dev:config.toml'), '# initial');
  assert(!git(f.origin, 'ls-tree', '--name-only', 'dev').split('\n').includes('cancelled'));
});

test('a save during Git advancement survives and can sync on retry', available, t => {
  const f = fixture(t); f.sync(f.a); f.sync(f.b);
  const before = f.head(f.a);
  f.write(f.b, 'text', 'incoming remote edit\n'); f.sync(f.b);
  const hook = path.join(f.a, '.git/hooks/reference-transaction');
  fs.writeFileSync(hook, `#!/bin/sh
set -eu
[ "$1" = committed ] || exit 0
while read -r old new ref; do
  if [ "$ref" = refs/heads/dev ]; then
    rm "$0"
    printf 'late local save\\n' > '${f.a}/text'
  fi
done
`);
  fs.chmodSync(hook, 0o755);
  assert.throws(() => f.sync(f.a), SourceDeferred);
  assert.equal(fs.readFileSync(path.join(f.a, 'text'), 'utf8'), 'late local save\n');
  assert.equal(f.head(f.a), before);
  f.sync(f.a);
  assert.equal(git(f.origin, 'show', 'dev:text'), 'late local save');
});

test('a tracked dev fast-forward is adopted while private ref moves are preserved', available, t => {
  const f = fixture(t, true); f.sync(f.a); f.sync(f.b);
  const applied = f.head(f.a);
  run('jj', ['bookmark', 'track', 'dev@origin'], f.a);
  f.write(f.b, 'remote', 'incoming shared change\n'); f.sync(f.b);
  const incoming = f.head(f.b);
  git(f.a, 'fetch', 'origin');
  run('jj', ['git', 'import'], f.a);
  assert.equal(f.head(f.a), incoming);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.a, '.git/dots-dev.json'))).applied, applied);
  f.sync(f.a);
  assert.equal(fs.readFileSync(path.join(f.a, 'remote'), 'utf8'), 'incoming shared change\n');
  const privateMove = git(f.a, '-c', 'commit.gpgsign=false', 'commit-tree', `${incoming}^{tree}`, '-p', incoming, '-m', 'Private dev work');
  git(f.a, 'update-ref', 'refs/heads/dev', privateMove);
  assert.throws(() => f.sync(f.a), /Local dev moved concurrently/);
  assert.equal(f.head(f.a), privateMove);
  assert.equal(git(f.origin, 'rev-parse', 'dev'), incoming);
});
