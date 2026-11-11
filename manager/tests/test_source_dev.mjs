import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { syncSource } from '../lib/source-repo.mjs';
import { requires } from './lib/prereq.mjs';

const available = requires('git');
function run(bin, args, cwd, options = {}) {
  const r = spawnSync(bin, args, { cwd, encoding: 'utf8', ...options });
  assert.equal(r.status, 0, `${bin} ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}
const git = (cwd, ...args) => run('git', args, cwd);
const read = (root, file) => fs.readFileSync(path.join(root, file), 'utf8');

// Flags any added line containing FAKE_SECRET, reported like gitleaks' JSON.
const FAKE_GITLEAKS = `#!/usr/bin/env node
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const args = process.argv.slice(2);
const report = args[args.indexOf('--report-path') + 1];
const opts = args.find(a => a.startsWith('--log-opts=')).slice(11).split(' ');
const root = args[args.length - 1];
const log = spawnSync('git', ['log', '-p', '--format=commit %H', ...opts], { cwd: root, encoding: 'utf8' }).stdout;
const findings = [];
let commit, file, line;
for (const text of log.split('\\n')) {
  if (text.startsWith('commit ')) commit = text.slice(7);
  else if (text.startsWith('+++ ')) file = text.slice(6);
  else if (text.startsWith('@@')) line = Number(text.match(/\\+(\\d+)/)[1]);
  else if (text.startsWith('+')) { if (text.includes('FAKE_SECRET')) findings.push({ File: file, StartLine: line, RuleID: 'fake-rule', Commit: commit }); line++; }
  else if (text.startsWith(' ')) line++;
}
fs.writeFileSync(report, JSON.stringify(findings));
process.exit(findings.length ? 1 : 0);
`;

function fixture(t) {
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'dots-sync-test-')));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const oldEnv = { ...process.env };
  t.after(() => { for (const k of Object.keys(process.env)) if (!(k in oldEnv)) delete process.env[k]; Object.assign(process.env, oldEnv); });
  fs.writeFileSync(path.join(dir, 'gitconfig'), '[user]\nname = Fixture\nemail = fixture@example.invalid\n[init]\ndefaultBranch = main\n');
  process.env.GIT_CONFIG_GLOBAL = path.join(dir, 'gitconfig');
  process.env.GIT_CONFIG_NOSYSTEM = '1';
  const origin = path.join(dir, 'origin.git'), a = path.join(dir, 'a'), b = path.join(dir, 'b');
  git(dir, 'init', '--bare', '--initial-branch=main', origin);
  git(dir, 'clone', '-q', origin, a);
  fs.writeFileSync(path.join(a, 'config.toml'), '# initial\n');
  fs.writeFileSync(path.join(a, 'text'), 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n');
  fs.writeFileSync(path.join(a, '.gitignore'), '/config.local.toml\n/miserc.toml\n/config.host-*.toml\n/mise.lock\n/.setup-state/\n/locks/\n');
  git(a, 'add', '.'); git(a, 'commit', '-qm', 'Initial'); git(a, 'push', '-q', 'origin', 'main');
  git(a, 'switch', '-qc', 'dev'); git(a, 'push', '-q', 'origin', 'dev');
  git(dir, 'clone', '-q', '--branch', 'dev', origin, b);
  const miseBin = path.join(dir, 'mise');
  fs.writeFileSync(miseBin, `#!/bin/sh
set -eu
case "$*" in
  *'config ls'*)
    if [ -n "\${DEV_TEST_MUTATE:-}" ]; then echo late > "$DEV_TEST_MUTATE"; fi
    if grep -q INVALID "$2/config.toml"; then echo 'invalid config' >&2; exit 1; fi ;;
esac
`);
  fs.chmodSync(miseBin, 0o755);
  const gitleaks = path.join(dir, 'gitleaks');
  fs.writeFileSync(gitleaks, FAKE_GITLEAKS);
  fs.chmodSync(gitleaks, 0o755);
  const sync = (root, options = {}) => {
    const lines = [];
    const code = syncSource(root, { expectedRemote: origin, miseBin, gitleaks, print: text => lines.push(text), ...options });
    return { code, text: lines.join('\n') };
  };
  const write = (root, file, contents) => { fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); fs.writeFileSync(path.join(root, file), contents); };
  const dev = root => git(root, 'rev-parse', 'refs/heads/dev');
  const remote = () => git(origin, 'rev-parse', 'dev');
  const clean = root => assert.equal(git(root, 'status', '--porcelain'), '', `${root} has uncommitted changes`);
  return { dir, a, b, origin, sync, write, dev, remote, clean, gitleaks };
}

test('a clean checkout syncs as a no-op', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  const { code, text } = f.sync(f.a);
  assert.equal(code, 0);
  assert.equal(text, 'dots sync: no local changes · pulled dev +0, main +0 · nothing to push');
  assert.equal(f.dev(f.a), before); assert.equal(f.remote(), before);
});

test('a local edit is shared and private files stay local', available, t => {
  const f = fixture(t);
  f.write(f.a, 'new', 'ordinary public edit\n');
  f.write(f.a, 'config.local.toml', '[env]\nPRIVATE="yes"\n');
  const { text } = f.sync(f.a);
  assert.match(text, /^dots sync: shared 1 file · pulled dev \+0, main \+0 · pushed [0-9a-f]{7}$/);
  assert.equal(f.remote(), f.dev(f.a));
  assert.equal(git(f.a, 'symbolic-ref', 'HEAD'), 'refs/heads/dev');
  assert(!git(f.a, 'ls-tree', '-r', '--name-only', 'dev').includes('config.local.toml'));
  assert.match(git(f.a, 'log', '-1', '--format=%s', 'dev'), /^Save local setup \(/);
  f.clean(f.a);
});

test('a remote change arrives on disk', available, t => {
  const f = fixture(t);
  f.write(f.b, 'remote', 'from b\n'); f.sync(f.b);
  const { text } = f.sync(f.a);
  assert.match(text, /^dots sync: no local changes · pulled dev \+1, main \+0 · nothing to push\n {2}changed on disk: 1 file changed/);
  assert.equal(read(f.a, 'remote'), 'from b\n');
  assert.equal(f.dev(f.a), f.remote()); f.clean(f.a);
});

test('dots up sees the configuration source move as one change event', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  f.write(f.b, 'remote', 'from b\n'); f.sync(f.b);
  const events = path.join(f.dir, 'events');
  const fd = fs.openSync(events, 'w');
  process.env.DOTS_UP_EVENT_FD = String(fd);
  try { f.sync(f.a); f.sync(f.a); } finally { delete process.env.DOTS_UP_EVENT_FD; fs.closeSync(fd); }
  const changes = fs.readFileSync(events, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(changes, [{ v: 1, kind: 'change', stage: 'source-sync', item: 'Configuration source', action: 'updated', before, after: f.dev(f.a) }]);
});

test('non-conflicting edits on both sides merge', available, t => {
  const f = fixture(t);
  f.write(f.a, 'text', 'ONE\ntwo\nthree\nfour\nfive\nsix\nseven\n');
  f.write(f.b, 'text', 'one\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n'); f.sync(f.b);
  const { text } = f.sync(f.a);
  assert.doesNotMatch(text, /CONFLICT/);
  assert.equal(read(f.a, 'text'), 'ONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n');
  assert.equal(git(f.origin, 'show', 'dev:text'), 'ONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN');
  f.sync(f.b); assert.equal(read(f.b, 'text'), read(f.a, 'text'));
});

test('a conflicting hunk keeps the published side and the loser stays recoverable', available, t => {
  const f = fixture(t);
  f.write(f.a, 'text', 'mine\ntwo\nthree\nfour\nfive\nsix\nmy tail\n');
  f.write(f.b, 'text', 'theirs\ntwo\nthree\nfour\nfive\nsix\nseven\n'); f.sync(f.b);
  const { code, text } = f.sync(f.a);
  assert.equal(code, 0);
  assert.equal(read(f.a, 'text'), 'theirs\ntwo\nthree\nfour\nfive\nsix\nmy tail\n');
  const match = text.match(/CONFLICT kept published: text {2}\(yours: git show ([0-9a-f]{12}):text\)/);
  assert(match, text);
  assert.equal(git(f.a, 'show', `${match[1]}:text`).split('\n')[0], 'mine');
  git(f.origin, 'merge-base', '--is-ancestor', match[1], 'dev');
  f.clean(f.a);
});

test('a binary conflict takes the published file whole', available, t => {
  const f = fixture(t);
  f.write(f.a, 'blob.bin', Buffer.from([0, 1, 2, 3])); f.sync(f.a); f.sync(f.b);
  f.write(f.a, 'blob.bin', Buffer.from([0, 9, 9, 9]));
  f.write(f.b, 'blob.bin', Buffer.from([0, 7, 7, 7])); f.sync(f.b);
  const { text } = f.sync(f.a);
  assert.deepEqual([...fs.readFileSync(path.join(f.a, 'blob.bin'))], [0, 7, 7, 7]);
  assert.match(text, /CONFLICT kept published: blob\.bin/);
});

test('a file/directory conflict keeps the published side at its own path', available, t => {
  for (const [published, local] of [['collision', 'collision/child'], ['collision/child', 'collision']]) {
    const f = fixture(t);
    f.write(f.b, published, 'published\n'); f.sync(f.b);
    f.write(f.a, local, 'local\n');
    const { text } = f.sync(f.a);
    assert.equal(git(f.origin, 'ls-tree', '-r', '--name-only', 'dev', '--', 'collision'), published);
    assert.equal(read(f.a, published), 'published\n');
    const match = text.match(/CONFLICT kept published: collision {2}\(yours: git show ([0-9a-f]{12}):collision\)/);
    assert(match, text);
    assert.equal(git(f.a, 'show', `${match[1]}:${local}`), 'local');
    f.clean(f.a);
  }
});

test('reviewed main merges into dev', available, t => {
  const f = fixture(t);
  const c = path.join(f.dir, 'c'); git(f.dir, 'clone', '-q', f.origin, c);
  f.write(c, 'reviewed', 'merged PR\n'); git(c, 'add', '.'); git(c, 'commit', '-qm', 'Reviewed'); git(c, 'push', '-q', 'origin', 'main');
  const { text } = f.sync(f.a);
  assert.match(text, /pulled dev \+0, main \+1 · pushed/);
  assert.equal(read(f.a, 'reviewed'), 'merged PR\n');
  git(f.origin, 'merge-base', '--is-ancestor', 'main', 'dev');
});

test('offline work is queued as origin/dev..dev and pushed next time', available, t => {
  const f = fixture(t);
  fs.renameSync(f.origin, `${f.origin}.offline`);
  f.write(f.a, 'text', 'saved offline\n');
  const offline = f.sync(f.a);
  assert.equal(offline.code, 0);
  assert.match(offline.text, /^dots sync: saved 1 file locally · offline · not pushed\n {2}OFFLINE: 1 commits unpushed, retried next run$/);
  assert.equal(git(f.a, 'rev-list', '--count', 'origin/dev..dev'), '1'); f.clean(f.a);
  fs.renameSync(`${f.origin}.offline`, f.origin);
  const online = f.sync(f.a);
  assert.match(online.text, /^dots sync: no local changes · pulled dev \+0, main \+0 · pushed/);
  assert.equal(f.remote(), f.dev(f.a));
});

test('a push race is merged and retried', available, t => {
  const f = fixture(t);
  const hook = path.join(f.a, '.git/hooks/pre-push');
  fs.writeFileSync(hook, `#!/bin/sh
set -eu
rm "$0"
printf 'raced\\n' > '${f.b}/raced'
git -C '${f.b}' add raced
git -C '${f.b}' commit -qm Race
git -C '${f.b}' push -q origin HEAD:dev
`);
  fs.chmodSync(hook, 0o755);
  f.write(f.a, 'local', 'local\n');
  const { text } = f.sync(f.a);
  assert.match(text, /· pushed/);
  assert.equal(f.remote(), f.dev(f.a));
  assert.equal(read(f.a, 'raced'), 'raced\n'); assert.equal(read(f.a, 'local'), 'local\n');
});

test('a push retry merges main again over a racing dev change to the same hunk', available, t => {
  const f = fixture(t);
  const c = path.join(f.dir, 'c'); git(f.dir, 'clone', '-q', f.origin, c);
  f.write(c, 'text', 'reviewed\ntwo\nthree\nfour\nfive\nsix\nseven\n'); git(c, 'commit', '-qam', 'Reviewed'); git(c, 'push', '-q', 'origin', 'main');
  const hook = path.join(f.a, '.git/hooks/pre-push');
  fs.writeFileSync(hook, `#!/bin/sh
set -eu
rm "$0"
printf 'raced\\ntwo\\nthree\\nfour\\nfive\\nsix\\nseven\\n' > '${f.b}/text'
git -C '${f.b}' commit -qam Race
git -C '${f.b}' push -q origin HEAD:dev
`);
  fs.chmodSync(hook, 0o755);
  f.write(f.a, 'local', 'local\n');
  const { text } = f.sync(f.a);
  assert.match(text, /· pushed/);
  assert.equal(git(f.origin, 'show', 'dev:text').split('\n')[0], 'reviewed');
  assert.equal(read(f.a, 'text').split('\n')[0], 'reviewed'); f.clean(f.a);
});

test('a flagged new file stays local while other edits are shared', available, t => {
  const f = fixture(t);
  f.write(f.a, 'token', 'safe line\nkey = FAKE_SECRET\n');
  f.write(f.a, 'fine', 'harmless\n');
  const { text } = f.sync(f.a);
  assert.match(text, /^dots sync: shared 1 file · .* · pushed/);
  assert.match(text, /NOT SHARED \(gitleaks fake-rule\): token:2/);
  assert.doesNotMatch(text, /FAKE_SECRET/);
  const shared = git(f.origin, 'ls-tree', '-r', '--name-only', 'dev').split('\n');
  assert(shared.includes('fine')); assert(!shared.includes('token'));
  assert.equal(git(f.a, 'status', '--porcelain'), '?? token');
  assert.equal(git(f.a, 'log', '--all', '--format=%H', '--', 'token'), '', 'no ref reaches the flagged file');
});

test('a missing scanner shares and pushes nothing', available, t => {
  const f = fixture(t); const before = f.remote();
  f.write(f.a, 'text', 'edited\n');
  const { code, text } = f.sync(f.a, { gitleaks: path.join(f.dir, 'missing-gitleaks') });
  assert.equal(code, 0);
  assert.match(text, /^dots sync: no local changes · pulled dev \+0, main \+0 · not pushed\n {2}NOT SHARED: gitleaks is not installed; local edits kept on disk, nothing pushed$/);
  assert.equal(f.remote(), before); assert.equal(read(f.a, 'text'), 'edited\n');
  assert.equal(git(f.a, 'status', '--porcelain'), 'M text');
  assert.match(f.sync(f.a).text, /shared 1 file/);
});

test('a flagged existing commit blocks the push', available, t => {
  const f = fixture(t); const before = f.remote();
  f.write(f.a, 'leak', 'FAKE_SECRET\n'); git(f.a, 'add', 'leak'); git(f.a, 'commit', '-qm', 'Oops');
  const { text } = f.sync(f.a);
  assert.match(text, /not pushed\n {2}NOT PUSHED \(gitleaks fake-rule\): commit [0-9a-f]{12} leak:1/);
  assert.equal(f.remote(), before);
});

test('the real gitleaks reports a token by file and line only', requires('git', 'gitleaks'), t => {
  const f = fixture(t);
  fs.copyFileSync(new URL('../init/gitleaks.toml', import.meta.url), path.join(f.a, '.gitleaks.toml'));
  const token = ['ghp', 'R8tq3LwVn5Xk2Jc9Hy7Pd4Mb6Fz1Sa0Gu3Ee'].join('_');
  f.write(f.a, 'nested/token', `\ngithub_token = "${token}"\n`);
  const { text } = f.sync(f.a, { gitleaks: 'gitleaks' });
  assert.match(text, /NOT SHARED \(gitleaks github-pat\): nested\/token:2/);
  assert(!text.includes(token));
  assert(!git(f.origin, 'ls-tree', '-r', '--name-only', 'dev').includes('nested/token'));
});

test('an invalid merged config is neither pushed nor applied', available, t => {
  const f = fixture(t); const before = f.remote();
  f.write(f.b, 'remote', 'from b\n'); f.sync(f.b); const shared = f.remote();
  f.write(f.a, 'config.toml', 'INVALID\n');
  const { code, text } = f.sync(f.a);
  assert.equal(code, 0);
  assert.match(text, /^dots sync: saved 1 file locally · fetched dev \+1, main \+0 \(not applied\) · not pushed\n {2}INVALID merged config: .*; nothing pushed or applied$/);
  assert.notEqual(shared, before); assert.equal(f.remote(), shared);
  assert(!fs.existsSync(path.join(f.a, 'remote')));
  assert.equal(git(f.a, 'show', 'dev:config.toml'), 'INVALID'); f.clean(f.a);
  f.write(f.a, 'config.toml', '# fixed\n');
  assert.match(f.sync(f.a).text, /pushed/);
  assert.equal(read(f.a, 'remote'), 'from b\n'); assert.equal(f.remote(), f.dev(f.a));
});

test('a file edited during advancement is not overwritten', available, t => {
  const f = fixture(t);
  f.write(f.b, 'text', 'incoming remote edit\n'); f.sync(f.b);
  f.write(f.a, 'local', 'local\n');
  process.env.DEV_TEST_MUTATE = path.join(f.a, 'text');
  const { code, text } = f.sync(f.a);
  delete process.env.DEV_TEST_MUTATE;
  assert.equal(code, 0);
  assert.match(text, /fetched dev \+1, main \+0 \(not applied\) · pushed/);
  assert.match(text, /LATE EDIT: text not updated; rerun/);
  assert.equal(read(f.a, 'text'), 'late\n');
  assert.equal(git(f.origin, 'show', 'dev:local'), 'local');
  const again = f.sync(f.a);
  assert.match(again.text, /CONFLICT kept published: text/);
  assert.equal(read(f.a, 'text'), 'incoming remote edit\n'); f.clean(f.a);
});

test('a locked Git index leaves the files and dev alone', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  f.write(f.b, 'remote', 'from b\n'); f.sync(f.b);
  const lock = path.join(f.a, '.git/index.lock');
  fs.writeFileSync(lock, '');
  const { code, text } = f.sync(f.a);
  assert.equal(code, 0);
  assert.match(text, /^dots sync: no local changes · fetched dev \+1, main \+0 \(not applied\) · nothing to push\n {2}NOT APPLIED: the Git index is locked \(\.git\/index\.lock\); files not updated, rerun$/);
  assert(fs.existsSync(lock), 'the lock held by someone else stays');
  assert(!fs.existsSync(path.join(f.a, 'remote')));
  assert.equal(f.dev(f.a), before);
  fs.rmSync(lock); f.clean(f.a);
  f.sync(f.a);
  assert.equal(read(f.a, 'remote'), 'from b\n'); f.clean(f.a);
});

test('a failed index install releases the index lock and leaves dev alone', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  f.write(f.a, 'text', 'edited\n');
  const copy = fs.copyFileSync;
  fs.copyFileSync = (from, to, ...rest) => {
    if (String(to).endsWith('.install')) throw Object.assign(new Error('ENOSPC: no space left on device'), { code: 'ENOSPC' });
    return copy(from, to, ...rest);
  };
  let result;
  try { result = f.sync(f.a); } finally { fs.copyFileSync = copy; }
  assert.equal(result.code, 0);
  assert.match(result.text, /^dots sync: failed · ENOSPC/);
  assert(!fs.existsSync(path.join(f.a, '.git/index.lock')), 'the index lock is released');
  assert.equal(f.dev(f.a), before);
  assert.equal(git(f.a, 'status', '--porcelain'), 'M text');
});

test('local edits are not reported saved when dev or the index cannot be recorded', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  f.write(f.a, 'config.toml', 'INVALID\n');
  for (const name of ['refs/heads/dev.lock', 'index.lock']) {
    const lock = path.join(f.a, '.git', name);
    fs.writeFileSync(lock, '');
    const { code, text } = f.sync(f.a);
    fs.rmSync(lock);
    assert.equal(code, 0);
    assert.match(text, /^dots sync: no local changes · [^\n]*\n {2}NOT SAVED: [^\n]*; local edits kept on disk, rerun$/);
    assert.equal(f.dev(f.a), before, name);
    assert.equal(git(f.a, 'status', '--porcelain'), 'M config.toml', `${name}: the original index stays`);
  }
});

test('a commit pushed to origin/dev from another worktree is merged, not reverted', available, t => {
  const f = fixture(t);
  const wt = path.join(f.dir, 'task');
  git(f.a, 'worktree', 'add', '-q', '--detach', wt, 'origin/dev');
  f.write(wt, 'task-file', 'from the task worktree\n');
  f.write(wt, 'text', 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n');
  git(wt, 'add', '.'); git(wt, 'commit', '-qm', 'Task change'); git(wt, 'push', '-q', 'origin', 'HEAD:dev');
  const task = git(wt, 'rev-parse', 'HEAD');
  f.write(f.a, 'text', 'ONE\ntwo\nthree\nfour\nfive\nsix\nseven\n');
  const { text } = f.sync(f.a);
  assert.match(text, /pulled dev \+1, main \+0 · pushed/);
  git(f.origin, 'merge-base', '--is-ancestor', task, 'dev');
  assert.equal(git(f.origin, 'show', 'dev:task-file'), 'from the task worktree');
  assert.equal(git(f.origin, 'show', 'dev:text'), 'ONE\ntwo\nthree\nfour\nfive\nsix\nseven\neight');
  assert.equal(git(f.origin, 'diff', '--name-only', task, 'dev'), 'text', 'only the local edit differs from the task commit');
  f.clean(f.a);
});

test('another worktree cannot quietly move dev under the live files', available, t => {
  const f = fixture(t);
  const wt = path.join(f.dir, 'task');
  git(f.a, 'worktree', 'add', '-q', '--detach', wt, 'dev');
  f.write(wt, 'moved', 'dev moved\n'); git(wt, 'add', '.'); git(wt, 'commit', '-qm', 'Move dev');
  const moved = git(wt, 'rev-parse', 'HEAD');
  git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/elsewhere');
  assert.notEqual(spawnSync('git', ['fetch', '-q', 'origin', 'elsewhere:dev'], { cwd: wt }).status, 0, 'fetch into the checked-out dev is refused');
  assert.notEqual(spawnSync('git', ['branch', '-f', 'dev', moved], { cwd: wt }).status, 0, 'branch -f on the checked-out dev is refused');
  git(wt, 'update-ref', 'refs/heads/dev', moved); // plumbing still can
  f.write(f.a, 'text', 'local edit\n');
  const { text } = f.sync(f.a);
  assert.match(text, /dev moved outside sync/);
  assert.equal(git(f.origin, 'show', 'dev:moved'), 'dev moved');
  assert.equal(git(f.origin, 'show', 'dev:text'), 'local edit');
  assert.equal(read(f.a, 'moved'), 'dev moved\n'); f.clean(f.a);
});

test('files follow dev when it moved outside sync and nothing changed locally', available, t => {
  const f = fixture(t);
  const wt = path.join(f.dir, 'task');
  git(f.a, 'worktree', 'add', '-q', '--detach', wt, 'dev');
  f.write(wt, 'moved', 'dev moved\n'); git(wt, 'add', '.'); git(wt, 'commit', '-qm', 'Move dev');
  git(wt, 'update-ref', 'refs/heads/dev', git(wt, 'rev-parse', 'HEAD'));
  const { text } = f.sync(f.a);
  assert.match(text, /dev moved outside sync/);
  assert.equal(read(f.a, 'moved'), 'dev moved\n'); f.clean(f.a);
});

test('an index staged to match an older commit loses no file content', available, t => {
  const f = fixture(t);
  f.write(f.a, 'text', 'changed\n'); f.sync(f.a);
  git(f.a, 'checkout', 'HEAD~1', '--', 'text'); // hand-staged revert: index tree equals HEAD~1's
  f.write(f.a, 'other', 'unstaged edit\n');
  const { text } = f.sync(f.a);
  // The staged revert reads as a stale base: it is reported and undone, but every file on disk is shared.
  assert.match(text, /the index was staged to match [0-9a-f]{12}; local files were merged onto dev, not reverted/);
  assert.equal(git(f.origin, 'show', 'dev:other'), 'unstaged edit');
  assert.equal(read(f.a, 'text'), 'changed\n'); f.clean(f.a);
});

test('a checkout in the wrong shape stops with one message pointing at the sync guide', available, t => {
  const f = fixture(t);
  const before = f.remote();
  const expect = (problem, prepare, undo) => {
    prepare();
    const { code, text } = f.sync(f.a);
    assert.equal(code, 0);
    assert.equal(text.split('\n').length, 1);
    assert.match(text, new RegExp(`^dots sync: stopped · ${problem}\\. .*/docs/sync\\.md$`));
    undo();
  };
  expect('HEAD is detached, not on dev', () => git(f.a, 'switch', '-q', '--detach'), () => git(f.a, 'switch', '-q', 'dev'));
  expect('HEAD is on main, not dev', () => git(f.a, 'switch', '-q', 'main'), () => git(f.a, 'switch', '-q', 'dev'));
  expect('a JJ workspace \\(\\.jj\\) is present', () => fs.mkdirSync(path.join(f.a, '.jj')), () => fs.rmdirSync(path.join(f.a, '.jj')));
  expect('legacy sync state \\(\\.git/dots-dev\\.json\\) is present', () => f.write(f.a, '.git/dots-dev.json', '{}'), () => fs.rmSync(path.join(f.a, '.git/dots-dev.json')));
  assert.equal(f.remote(), before);
  const foreign = [];
  assert.equal(syncSource(f.a, { expectedRemote: '/elsewhere', print: text => foreign.push(text) }), 0);
  assert.deepEqual(foreign, ['dots sync: stopped · Refusing source operations: origin is not /elsewhere']);
});

test('an unexpected error prints one failed line and exits 0', available, t => {
  const f = fixture(t); const before = f.dev(f.a);
  fs.writeFileSync(process.env.GIT_CONFIG_GLOBAL, '[user]\nuseConfigOnly = true\n');
  for (const key of ['EMAIL', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL']) delete process.env[key];
  f.write(f.a, 'text', 'needs a commit\n');
  const { code, text } = f.sync(f.a);
  assert.equal(code, 0);
  assert.match(text, /^dots sync: failed · git [^\n]* failed: Author identity unknown$/);
  assert.equal(f.dev(f.a), before); assert.equal(read(f.a, 'text'), 'needs a commit\n');
});

test('a concurrent run is skipped and a dead run\'s lock is reclaimed', available, t => {
  const f = fixture(t);
  const lock = path.join(f.a, '.git/dots-source.lock');
  fs.mkdirSync(lock);
  fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ pid: process.pid, host: os.hostname() }));
  f.write(f.a, 'text', 'waiting\n');
  const busy = f.sync(f.a);
  assert.equal(busy.code, 0);
  assert.match(busy.text, /^dots sync: skipped · another source operation is running \(pid \d+\)/);
  assert.equal(git(f.a, 'status', '--porcelain'), 'M text');
  const dead = spawnSync(process.execPath, ['-e', 'process.stdout.write(String(process.pid))'], { encoding: 'utf8' }).stdout;
  fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({ pid: Number(dead), host: os.hostname() }));
  assert.match(f.sync(f.a).text, /shared 1 file/);
  assert(!fs.existsSync(lock));
});
