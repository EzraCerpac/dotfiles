import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { ensureRepository, parseSourceArguments, resolveMiseBin, SourceDeferred, syncSource, withRepositoryLock } from '../setup-scripts/lib/source-repo.mjs';
import { requires } from './lib/prereq.mjs';

const testState = fs.mkdtempSync(path.join(os.tmpdir(), 'source-repo-tests-'));
const jjConfig = path.join(testState, 'jj.toml');
const gitConfig = path.join(testState, 'gitconfig');
fs.writeFileSync(jjConfig, '[user]\nname = "Source repo fixture"\nemail = "fixture@example.invalid"\n');
fs.writeFileSync(gitConfig, '[user]\n\tname = Source repo fixture\n\temail = fixture@example.invalid\n');

const inheritedEnvironment = { ...process.env };
for (const key of Object.keys(process.env)) if (key.startsWith('MISE_') || key.startsWith('__MISE_')) delete process.env[key];
process.env.JJ_CONFIG = jjConfig;
process.env.GIT_CONFIG_GLOBAL = gitConfig;
process.env.GIT_CONFIG_NOSYSTEM = '1';

function run(bin, args, cwd, { allowFailure = false, env = {}, input } = {}) {
  const result = spawnSync(bin, args, {
    cwd,
    env: { ...process.env, ...env },
    encoding: 'utf8',
    input,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (!allowFailure && (result.error || result.status !== 0)) {
    throw new Error(`${bin} ${args.join(' ')} failed: ${result.error?.message || result.stderr?.trim() || `exit ${result.status}`}`);
  }
  return result;
}

function git(cwd, ...args) { return run('git', args, cwd).stdout.trim(); }
function jj(cwd, ...args) { return run('jj', ['-R', cwd, ...args], cwd).stdout.trim(); }
function commit(cwd, message, { push = true } = {}) {
  run('git', ['add', '-A'], cwd);
  for (const name of ['mise.lock', 'mise.nas.lock', 'mise.workstation.lock']) {
    if (fs.existsSync(path.join(cwd, name))) run('git', ['add', '-f', name], cwd);
  }
  run('git', ['commit', '-m', message], cwd);
  if (push) run('git', ['push', 'origin', 'main'], cwd);
  return git(cwd, 'rev-parse', 'HEAD');
}

function makeFakeMise(state) {
  const bin = path.join(state, 'fake-mise');
  const log = path.join(state, 'mise.log');
  fs.writeFileSync(bin, `#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$FAKE_MISE_LOG"
printf 'env MISE_CONFIG_DIR=%s MISE_GLOBAL_CONFIG_FILE=%s args=%s\\n' "\${MISE_CONFIG_DIR-}" "\${MISE_GLOBAL_CONFIG_FILE-}" "$*" >> "$FAKE_MISE_LOG"
case "\${FAKE_MISE_MODE:-ok}:$*" in
  save-mutate:*" bootstrap dotfiles save"*) printf 'save mutation\\n' > config.toml ;;
  validate-fail:*" config ls "*) printf '%s\\n' 'fixture config validation failed' >&2; exit 17 ;;
  validate-fail:*" bootstrap dotfiles apply --dry-run "*) printf '%s\\n' 'fixture dry run failed' >&2; exit 18 ;;
  apply-fail:*" bootstrap dotfiles apply --yes"*) printf '%s\\n' 'fixture apply failed' >&2; exit 19 ;;
  version-mutate:--version) printf 'concurrent source edit\\n' > config.toml ;;
  version-private-mutate:--version) printf 'concurrent private edit\\n' >> config.local.toml ;;
esac
if [ "$#" -eq 1 ] && [ "$1" = '--version' ]; then printf '%s\\n' 'mise 2026.9.0'; fi
`);
  fs.chmodSync(bin, 0o755);
  return { bin, log };
}

function withEnvironment(values, callback) {
  const previous = {};
  for (const [key, value] of Object.entries(values)) {
    previous[key] = process.env[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try { return callback(); }
  finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function makeFixture({ files = { 'config.toml': 'min_version = "1.0.0"\nbase = "A"\n' }, ignored = [] } = {}) {
  const state = fs.mkdtempSync(path.join(testState, 'fixture-'));
  const origin = path.join(state, 'origin.git');
  const seed = path.join(state, 'seed');
  const root = path.join(state, 'root');
  run('git', ['init', '--bare', '--initial-branch=main', origin], state);
  run('git', ['init', '-b', 'main', seed], state);
  for (const [name, contents] of Object.entries(files)) {
    const target = path.join(seed, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, contents);
  }
  if (ignored.length) fs.writeFileSync(path.join(seed, '.gitignore'), `${ignored.join('\n')}\n`);
  commit(seed, 'initial', { push: false });
  run('git', ['remote', 'add', 'origin', origin], seed);
  run('git', ['push', '-u', 'origin', 'main'], seed);
  run('git', ['symbolic-ref', 'HEAD', 'refs/heads/main'], origin);
  run('git', ['clone', origin, root], state);
  const fakeMise = makeFakeMise(state);
  return {
    state,
    origin,
    seed,
    root,
    expectedRemote: origin,
    fakeMise,
    close() { fs.rmSync(state, { recursive: true, force: true }); },
  };
}

function updateRemote(fixture, name, contents) {
  const target = path.join(fixture.seed, name);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, contents);
  return commit(fixture.seed, `update ${name}`);
}

function sync(fixture, mode = 'ok', options = {}) {
  return withEnvironment({ FAKE_MISE_LOG: fixture.fakeMise.log, FAKE_MISE_MODE: mode }, () =>
    syncSource(fixture.root, { miseBin: fixture.fakeMise.bin, expectedRemote: fixture.expectedRemote, ...options }));
}

function assertDeferred(callback, pattern) {
  assert.throws(callback, error => {
    assert(error instanceof SourceDeferred || error?.code === 3);
    if (pattern) assert.match(error.message, pattern);
    return true;
  });
}

function parentRevision(fixture) { return jj(fixture.root, 'log', '-r', '@-', '--no-graph', '-T', 'commit_id ++ "\\n"'); }
// Fixtures are real JJ repositories; skip them where jj is unavailable.
const repoTest = (name, callback) => test(name, { concurrency: false, ...requires('jj') }, callback);

repoTest('Git-only initialization is idempotent and preserves dirty files and branch refs', () => {
  const fixture = makeFixture({ files: { 'config.toml': 'base = "A"\n', 'tracked.txt': 'before\n' } });
  try {
    run('git', ['switch', '-c', 'fixture-branch'], fixture.root);
    const branchTarget = git(fixture.root, 'rev-parse', 'refs/heads/fixture-branch');
    fs.writeFileSync(path.join(fixture.root, 'tracked.txt'), 'uncommitted\n');
    fs.writeFileSync(path.join(fixture.root, 'untracked.txt'), 'keep me\n');
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    assert.equal(git(fixture.root, 'rev-parse', 'refs/heads/fixture-branch'), branchTarget);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'tracked.txt'), 'utf8'), 'uncommitted\n');
    assert.equal(fs.readFileSync(path.join(fixture.root, 'untracked.txt'), 'utf8'), 'keep me\n');
    assert(fs.existsSync(path.join(fixture.root, '.jj')));
  } finally { fixture.close(); }
});

repoTest('initialization refuses a staged index, wrong origin, and active Git operations', () => {
  const staged = makeFixture({ files: { 'config.toml': 'base = "A"\n', 'tracked.txt': 'before\n' } });
  try {
    fs.writeFileSync(path.join(staged.root, 'tracked.txt'), 'staged\n');
    run('git', ['add', 'tracked.txt'], staged.root);
    assertDeferred(() => ensureRepository(staged.root, { expectedRemote: staged.expectedRemote }), /staged changes/);
    assert(!fs.existsSync(path.join(staged.root, '.jj')));
  } finally { staged.close(); }

  const wrongRemote = makeFixture();
  try {
    assert.throws(() => ensureRepository(wrongRemote.root, { expectedRemote: path.join(wrongRemote.state, 'other.git') }), /origin/);
    fs.writeFileSync(path.join(wrongRemote.root, '.git', 'MERGE_HEAD'), `${git(wrongRemote.root, 'rev-parse', 'HEAD')}\n`);
    assertDeferred(() => ensureRepository(wrongRemote.root, { expectedRemote: wrongRemote.expectedRemote }), /MERGE_HEAD/);
    fs.rmSync(path.join(wrongRemote.root, '.git', 'MERGE_HEAD'));
    fs.mkdirSync(path.join(wrongRemote.root, '.git', 'rebase-merge'));
    assertDeferred(() => ensureRepository(wrongRemote.root, { expectedRemote: wrongRemote.expectedRemote }), /rebase-merge/);
  } finally { wrongRemote.close(); }
});

repoTest('operation lock refusal is deferred and does not remove the existing lock', () => {
  const fixture = makeFixture();
  try {
    const lock = path.join(fixture.root, '.git', 'dots-source.lock');
    fs.mkdirSync(lock);
    fs.writeFileSync(path.join(lock, 'owner.json'), '{"pid":123}\n');
    assertDeferred(() => withRepositoryLock(fixture.root, () => 1), /Another source operation owns/);
    assert(fs.existsSync(path.join(lock, 'owner.json')));
  } finally { fixture.close(); }
});

repoTest('clean remote fast-forward syncs through the fake mise validation and apply', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const incoming = updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assert.equal(sync(fixture), incoming);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "B"\n');
    assert.match(fs.readFileSync(fixture.fakeMise.log, 'utf8'), /config ls --json/);
    assert.match(fs.readFileSync(fixture.fakeMise.log, 'utf8'), /bootstrap dotfiles save/);
    assert.match(fs.readFileSync(fixture.fakeMise.log, 'utf8'), /bootstrap dotfiles apply --yes/);
  } finally { fixture.close(); }
});

repoTest('sync resolves MISE_BIN and PATH when the standalone binary is absent', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    const pathBin = path.join(fixture.state, 'path-bin');
    fs.mkdirSync(pathBin);
    fs.copyFileSync(fixture.fakeMise.bin, path.join(pathBin, 'mise'));
    fs.chmodSync(path.join(pathBin, 'mise'), 0o755);

    withEnvironment({ HOME: fixture.state, FAKE_MISE_LOG: fixture.fakeMise.log, MISE_BIN: fixture.fakeMise.bin }, () => {
      assert.equal(resolveMiseBin(), fixture.fakeMise.bin);
      syncSource(fixture.root, { expectedRemote: fixture.expectedRemote });
    });
    assert.equal(parentRevision(fixture), git(fixture.seed, 'rev-parse', 'HEAD'));

    const second = makeFixture();
    try {
      ensureRepository(second.root, { expectedRemote: second.expectedRemote });
      updateRemote(second, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
      withEnvironment({
        HOME: second.state,
        FAKE_MISE_LOG: second.fakeMise.log,
        MISE_BIN: undefined,
        PATH: `${pathBin}${path.delimiter}${process.env.PATH}`,
      }, () => {
        assert.equal(resolveMiseBin(), path.join(pathBin, 'mise'));
        syncSource(second.root, { expectedRemote: second.expectedRemote });
      });
      assert.equal(parentRevision(second), git(second.seed, 'rev-parse', 'HEAD'));
    } finally { second.close(); }
  } finally { fixture.close(); }
});

repoTest('dirty source edits are deferred before validation or movement', () => {
  const fixture = makeFixture({ files: { 'config.toml': 'min_version = "1.0.0"\nbase = "A"\n', 'tracked.txt': 'A\n' } });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    fs.writeFileSync(path.join(fixture.root, 'tracked.txt'), 'local edit\n');
    assertDeferred(() => sync(fixture), /Local source edits/);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "A"\n');
    assert(!fs.existsSync(fixture.fakeMise.log));
  } finally { fixture.close(); }
});

repoTest('an unpublished empty-child ancestry is deferred', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    jj(fixture.root, 'new');
    jj(fixture.root, 'new');
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assertDeferred(() => sync(fixture), /unpublished or divergent history/);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "A"\n');
  } finally { fixture.close(); }
});

repoTest('fetch failure is deferred with code 3', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    fs.rmSync(fixture.origin, { recursive: true, force: true });
    assertDeferred(() => sync(fixture), /Could not fetch origin\/main/);
    assert(!fs.existsSync(path.join(fixture.root, '.git', 'dots-source.lock')));
  } finally { fixture.close(); }
});

repoTest('failed incoming validation leaves the current source before movement', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const before = parentRevision(fixture);
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assert.throws(() => sync(fixture, 'validate-fail'), /fixture (config validation|dry run) failed/);
    assert.equal(parentRevision(fixture), before);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "A"\n');
  } finally { fixture.close(); }
});

repoTest('a source edit made during mise save is deferred after recheck', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const before = parentRevision(fixture);
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assertDeferred(() => sync(fixture, 'save-mutate'), /Source changed during validation/);
    assert.equal(parentRevision(fixture), before);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'save mutation\n');
  } finally { fixture.close(); }
});

repoTest('an incoming config.local.toml symlink cannot replace an ignored local file', () => {
  const fixture = makeFixture({ files: {
    'config.toml': 'min_version = "1.0.0"\nbase = "A"\n',
    '.gitignore': 'config.local.toml\n',
  } });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const outside = path.join(fixture.state, 'outside-local.toml');
    fs.writeFileSync(outside, 'outside must remain\n');
    fs.writeFileSync(path.join(fixture.root, 'config.local.toml'), 'current local config\n');
    fs.symlinkSync(outside, path.join(fixture.seed, 'config.local.toml'));
    run('git', ['add', '-f', 'config.local.toml'], fixture.seed);
    const before = parentRevision(fixture);
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assert.throws(() => sync(fixture), /config\.local\.toml|EEXIST|already exists/);
    assert.equal(parentRevision(fixture), before);
    assert.equal(fs.readFileSync(outside, 'utf8'), 'outside must remain\n');
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.local.toml'), 'utf8'), 'current local config\n');
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "A"\n');
  } finally { fixture.close(); }
});

repoTest('fake mise validation receives only the disposable preview config', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    sync(fixture);
    const previewCalls = fs.readFileSync(fixture.fakeMise.log, 'utf8').split('\n')
      .filter(line => line.includes('args=') && (line.includes('config ls --json') || line.includes('apply --dry-run')));
    assert.equal(previewCalls.length, 2);
    for (const line of previewCalls) {
      assert.match(line, /MISE_GLOBAL_CONFIG_FILE= args=/);
      assert.match(line, /MISE_CONFIG_DIR=.*dots-source-preview-/);
    }
  } finally { fixture.close(); }
});

repoTest('failed final apply reports after the source has moved', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const incoming = updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    assert.throws(() => sync(fixture, 'apply-fail'), /failed: exit 19/);
    assert.equal(parentRevision(fixture), incoming);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "B"\n');
  } finally { fixture.close(); }
});

repoTest('lockfile migration preserves modified tracked locks and backs them up', () => {
  const fixture = makeFixture({ files: {
    'config.toml': 'min_version = "1.0.0"\nbase = "A"\n',
    'mise.lock': 'tracked A\n',
    'mise.nas.lock': 'tracked NAS A\n',
    'mise.workstation.lock': 'tracked workstation A\n',
    '.gitignore': '/.setup-state/\n',
  } });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    for (const name of ['mise.lock', 'mise.nas.lock', 'mise.workstation.lock']) assert.equal(git(fixture.root, 'ls-files', name), name);
    const localLocks = new Map([
      ['mise.lock', 'local tracked lock\n'],
      ['mise.nas.lock', 'local tracked NAS lock\n'],
      ['mise.workstation.lock', 'local tracked workstation lock\n'],
    ]);
    for (const [name, contents] of localLocks) fs.writeFileSync(path.join(fixture.root, name), contents);
    fs.appendFileSync(path.join(fixture.seed, '.gitignore'), '*.lock\n');
    for (const name of localLocks.keys()) fs.rmSync(path.join(fixture.seed, name));
    fs.appendFileSync(path.join(fixture.seed, '.gitignore'), 'mise.lock\nmise.nas.lock\nmise.workstation.lock\n');
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    sync(fixture);
    for (const [name, contents] of localLocks) assert.equal(fs.readFileSync(path.join(fixture.root, name), 'utf8'), contents);
    const backupRoot = path.join(fixture.root, '.setup-state', 'local-lockfiles');
    const backups = fs.readdirSync(backupRoot);
    assert.equal(backups.length, 1);
    for (const name of localLocks.keys()) assert.equal(fs.readFileSync(path.join(backupRoot, backups[0], name), 'utf8'), localLocks.get(name));
  } finally { fixture.close(); }
});

repoTest('unrelated JJ bookmarks survive source movement', () => {
  const fixture = makeFixture();
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const original = parentRevision(fixture);
    jj(fixture.root, 'bookmark', 'create', 'wip/unrelated', '-r', original);
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    const incoming = sync(fixture);
    assert.equal(jj(fixture.root, 'log', '-r', 'wip/unrelated', '--no-graph', '-T', 'commit_id ++ "\\n"'), original);
    assert.equal(incoming, parentRevision(fixture));
  } finally { fixture.close(); }
});

repoTest('ordinary ignored lockfiles do not count as source edits', () => {
  const fixture = makeFixture({ files: { 'config.toml': 'min_version = "1.0.0"\nbase = "A"\n', '.gitignore': '*.lock\n' } });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    fs.writeFileSync(path.join(fixture.root, 'mise.lock'), 'machine-local ignored lock\n');
    updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    sync(fixture);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'mise.lock'), 'utf8'), 'machine-local ignored lock\n');
    assert.equal(fs.readFileSync(path.join(fixture.root, 'config.toml'), 'utf8'), 'min_version = "1.0.0"\nbase = "B"\n');
  } finally { fixture.close(); }
});

test('source CLI accepts only the explicit sync option', () => {
  assert.deepEqual(parseSourceArguments(['sync', '/fixture', '--source-only']), { action: 'sync', root: '/fixture', sourceOnly: true });
  assert.deepEqual(parseSourceArguments(['sync', '/fixture']), { action: 'sync', root: '/fixture', sourceOnly: false });
  for (const args of [['sync'], ['sync', '/fixture', '--dry-run'], ['sync', '/fixture', '--source-only', '--source-only'], ['status', '/fixture', '--source-only'], ['init', '/fixture', '--source-only']]) {
    assert.throws(() => parseSourceArguments(args), /Usage/);
  }
});

repoTest('unknown direct CLI flags fail before source operations', () => {
  const fixture = makeFixture();
  try {
    const script = new URL('../setup-scripts/lib/source-repo.mjs', import.meta.url);
    const result = run(process.execPath, [script.pathname, 'sync', fixture.root, '--dry-run'], fixture.root, { allowFailure: true });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Usage/);
    assert(!fs.existsSync(path.join(fixture.root, '.jj')));
    assert(!fs.existsSync(path.join(fixture.root, '.git', 'dots-source.lock')));
  } finally { fixture.close(); }
});

repoTest('source-only advancement and current sync preserve private files without reading or copying them', () => {
  const policy = 'published canonical NAS policy\n';
  const fixture = makeFixture({ files: {
    'config.toml': 'min_version = "1.0.0"\nbase = "A"\n',
    'dotfiles/.codex/AGENTS.cerpacnas.md': policy,
  }, ignored: ['config.local.toml', 'miserc.toml', 'config.host-fixture.toml', '*.lock'] });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const original = parentRevision(fixture);
    jj(fixture.root, 'bookmark', 'create', 'wip/unrelated', '-r', original);
    const names = ['config.local.toml', 'miserc.toml', 'config.host-fixture.toml', 'mise.lock'];
    for (const name of names) fs.writeFileSync(path.join(fixture.root, name), `private fixture ${name}\n`, { mode: 0o600 });
    const before = names.map(name => fs.lstatSync(path.join(fixture.root, name), { bigint: true }));
    const denied = path.join(fixture.state, 'home', '.codex');
    fs.mkdirSync(path.dirname(denied), { recursive: true, mode: 0o700 });
    fs.mkdirSync(denied, { mode: 0o000 });
    const incoming = updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
    const read = fs.readFileSync, copy = fs.copyFileSync;
    const isPrivate = file => names.some(name => String(file) === path.join(fixture.root, name)) || String(file).startsWith(denied);
    fs.readFileSync = (file, ...args) => { assert(!isPrivate(file), `unexpected private read: ${file}`); return read(file, ...args); };
    fs.copyFileSync = (file, ...args) => { assert(!isPrivate(file), `unexpected private copy: ${file}`); return copy(file, ...args); };
    try {
      withEnvironment({ HOME: path.join(fixture.state, 'home') }, () => {
        assert.equal(sync(fixture, 'ok', { sourceOnly: true }), incoming);
        const current = jj(fixture.root, 'log', '-r', '@', '--no-graph', '-T', 'commit_id');
        assert.equal(sync(fixture, 'ok', { sourceOnly: true }), incoming);
        assert.equal(jj(fixture.root, 'log', '-r', '@', '--no-graph', '-T', 'commit_id'), current);
      });
    } finally { fs.readFileSync = read; fs.copyFileSync = copy; fs.chmodSync(denied, 0o700); }
    assert.equal(parentRevision(fixture), incoming);
    assert.equal(jj(fixture.root, 'log', '-r', 'wip/unrelated', '--no-graph', '-T', 'commit_id'), original);
    assert.equal(fs.readFileSync(path.join(fixture.root, 'dotfiles/.codex/AGENTS.cerpacnas.md'), 'utf8'), policy);
    assert.deepEqual(names.map(name => fs.lstatSync(path.join(fixture.root, name), { bigint: true })), before);
    assert(!fs.existsSync(path.join(fixture.root, '.setup-state')));
    const calls = fs.readFileSync(fixture.fakeMise.log, 'utf8').split('\n').filter(Boolean);
    assert(calls.every(line => line === '--version' || line.endsWith('args=--version')));
  } finally { fixture.close(); }
});

repoTest('source-only retains dirty and unpublished ancestry deferral', () => {
  for (const kind of ['dirty', 'unpublished']) {
    const fixture = makeFixture();
    try {
      ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
      if (kind === 'dirty') fs.writeFileSync(path.join(fixture.root, 'config.toml'), 'local edit\n');
      else { jj(fixture.root, 'new'); jj(fixture.root, 'new'); }
      updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
      const before = parentRevision(fixture);
      assertDeferred(() => sync(fixture, 'ok', { sourceOnly: true }), kind === 'dirty' ? /Local source edits/ : /unpublished or divergent/);
      assert.equal(parentRevision(fixture), before);
      assert(!fs.existsSync(fixture.fakeMise.log));
    } finally { fixture.close(); }
  }
});

repoTest('source-only refuses incoming private selectors and legacy tracked lock migration', () => {
  for (const name of ['config.local.toml', 'miserc.toml', 'config.host-fixture.toml', 'mise.lock']) {
    const fixture = makeFixture({ files: {
      'config.toml': 'min_version = "1.0.0"\nbase = "A"\n',
      ...(name === 'mise.lock' ? { 'mise.lock': 'legacy lock\n' } : {}),
    } });
    try {
      ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
      const before = parentRevision(fixture);
      if (name === 'mise.lock') fs.rmSync(path.join(fixture.seed, name));
      else fs.writeFileSync(path.join(fixture.seed, name), 'must remain private\n');
      updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
      assert.throws(() => sync(fixture, 'ok', { sourceOnly: true }), name === 'mise.lock' ? /Tracked lockfiles/ : /must not track private/);
      assert.equal(parentRevision(fixture), before);
      assert(!fs.existsSync(path.join(fixture.root, '.setup-state')));
    } finally { fixture.close(); }
  }
});

repoTest('source-only keeps minimum-version and source/private concurrency guards', () => {
  for (const mode of ['minimum', 'version-mutate', 'version-private-mutate']) {
    const fixture = makeFixture({ ignored: ['config.local.toml'] });
    try {
      ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
      fs.writeFileSync(path.join(fixture.root, 'config.local.toml'), 'private fixture\n');
      const before = parentRevision(fixture);
      updateRemote(fixture, 'config.toml', `min_version = "${mode === 'minimum' ? '2999.1.0' : '1.0.0'}"\nbase = "B"\n`);
      assertDeferred(() => sync(fixture, mode === 'minimum' ? 'ok' : mode, { sourceOnly: true }), mode === 'minimum' ? /requires mise/ : /changed during validation/);
      assert.equal(parentRevision(fixture), before);
      assert(!fs.readFileSync(fixture.fakeMise.log, 'utf8').includes('bootstrap'));
    } finally { fixture.close(); }
  }
});

repoTest('source-only rejects tracked selector removal and reserved directory/case collisions before advancement', () => {
  for (const name of ['config.local.toml', 'miserc.toml', 'config.host-fixture.toml', 'CONFIG.LOCAL.TOML', 'config.local.toml/nested', 'mise.lock']) {
    const removed = ['config.local.toml', 'miserc.toml', 'config.host-fixture.toml'].includes(name);
    const fixture = makeFixture({ files: {
      'config.toml': 'min_version = "1.0.0"\nbase = "A"\n',
      ...(removed ? { [name]: 'tracked private fixture\n' } : {}),
    } });
    try {
      ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
      const before = parentRevision(fixture);
      const privateBefore = removed ? fs.lstatSync(path.join(fixture.root, name), { bigint: true }) : undefined;
      if (removed) fs.rmSync(path.join(fixture.seed, name));
      else {
        const file = path.join(fixture.seed, name);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, 'incoming reserved file\n');
      }
      updateRemote(fixture, 'config.toml', 'min_version = "1.0.0"\nbase = "B"\n');
      assert.throws(() => sync(fixture, 'ok', { sourceOnly: true }), removed ? /Tracked private selectors/ : /private setup selectors|Tracked lockfiles/);
      assert.equal(parentRevision(fixture), before);
      if (removed) assert.deepEqual(fs.lstatSync(path.join(fixture.root, name), { bigint: true }), privateBefore);
      else assert(!fs.existsSync(path.join(fixture.root, name)));
      assert(!fs.existsSync(fixture.fakeMise.log));
    } finally { fixture.close(); }
  }
});

repoTest('source-only rejects incoming config.toml symlinks before source movement', () => {
  const fixture = makeFixture({ files: { 'config.toml': 'min_version = "1.0.0"\n', 'other.toml': 'public fixture\n' } });
  try {
    ensureRepository(fixture.root, { expectedRemote: fixture.expectedRemote });
    const before = parentRevision(fixture);
    fs.rmSync(path.join(fixture.seed, 'config.toml'));
    fs.symlinkSync('other.toml', path.join(fixture.seed, 'config.toml'));
    commit(fixture.seed, 'replace config with a symlink');
    assert.throws(() => sync(fixture, 'ok', { sourceOnly: true }), /config.toml must be a regular/);
    assert.equal(parentRevision(fixture), before);
    assert(!fs.existsSync(fixture.fakeMise.log));
  } finally { fixture.close(); }
});

test.after(() => {
  fs.rmSync(testState, { recursive: true, force: true });
  for (const key of Object.keys(process.env)) if (!(key in inheritedEnvironment)) delete process.env[key];
  for (const [key, value] of Object.entries(inheritedEnvironment)) process.env[key] = value;
});
