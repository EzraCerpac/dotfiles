import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { ensureRepository, withRepositoryLock } from '../manager/lib/source-repo.mjs';
import { publish } from '../manager/tasks/publish.mjs';
import { requires } from './lib/prereq.mjs';

// Every fixture is a real colocated JJ repository.
const needsJj = requires('jj');

function command(root, bin, args) {
  const result = spawnSync(bin, args, { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, `${bin} ${args.join(' ')}\n${result.stderr}`);
  return result.stdout;
}

function setupRepository({ stack = 1, description = 'Sync public setup', bookmark = '' } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-publish-jj-'));
  const origin = path.join(directory, 'origin.git');
  const root = path.join(directory, 'source');
  fs.mkdirSync(root);
  command(directory, 'git', ['init', '--bare', '--initial-branch=main', origin]);
  command(root, 'git', ['init', '-q', '--initial-branch=main']);
  command(root, 'git', ['config', 'user.name', 'Dots Test']);
  command(root, 'git', ['config', 'user.email', 'dots-test@example.invalid']);
  fs.writeFileSync(path.join(root, 'config.toml'), 'min_version = "2026.1.0"\n');
  command(root, 'git', ['add', 'config.toml']);
  command(root, 'git', ['commit', '-qm', 'Initial setup']);
  command(root, 'git', ['branch', '-M', 'main']);
  command(root, 'git', ['remote', 'add', 'origin', origin]);
  command(root, 'git', ['push', '-q', 'origin', 'main']);
  command(root, 'jj', ['git', 'init', '--colocate', root]);

  const jj = (...args) => command(root, 'jj', args);
  jj('new', 'main@origin');
  for (let index = 0; index < stack; index += 1) {
    fs.writeFileSync(path.join(root, `public-${index}.txt`), `change ${index}\n`);
    jj('describe', '-m', index === stack - 1 ? description : `Private base ${index}`);
    if (index + 1 < stack) jj('new');
  }
  if (bookmark) jj('bookmark', 'create', bookmark, '-r', '@');
  return { directory, origin, root, jj };
}

function cleanup(fixture) {
  fs.rmSync(fixture.directory, { recursive: true, force: true });
}

// scan: a gitleaks exit status to simulate, 'missing' for an absent scanner,
// or 'real' to run the installed gitleaks.
function publisher(fixture, { prs = [], lookupFailure = false, pushStatus = 0, scan = 0, descriptionPrompt, confirm = () => true } = {}) {
  const calls = [];
  const bodyFiles = [];
  const run = (bin, args, options) => {
    calls.push([bin, args]);
    if (bin === 'jj' && args.includes('push')) return { status: pushStatus, stdout: '', stderr: pushStatus ? 'push failed' : '' };
    if (bin === 'gitleaks' && scan !== 'real') {
      if (scan === 'missing') return { error: Object.assign(new Error('spawnSync gitleaks ENOENT'), { code: 'ENOENT' }) };
      return { status: scan, stdout: scan ? 'Finding: ghp_REDACTED\n' : '', stderr: '' };
    }
    if (bin === 'gh' && args[0] === 'pr' && args[1] === 'list') {
      if (lookupFailure) return { status: 1, stdout: '', stderr: 'GitHub unavailable' };
      return { status: 0, stdout: JSON.stringify(prs), stderr: '' };
    }
    if (bin === 'gh' && args[0] === 'pr' && (args[1] === 'create' || args[1] === 'edit')) {
      const bodyPath = args[args.indexOf('--body-file') + 1];
      bodyFiles.push({ path: bodyPath, content: fs.readFileSync(bodyPath, 'utf8') });
      return { status: 0, stdout: args[1] === 'create' ? 'https://github.com/EzraCerpac/dotfiles/pull/17\n' : '', stderr: '' };
    }
    return spawnSync(bin, args, options);
  };
  const output = { text: '', write(value) { this.text += value; } };
  const options = {
    root: fixture.root,
    run,
    output,
    confirm,
    descriptionPrompt: descriptionPrompt || (() => ''),
    ensure: root => ensureRepository(root, { expectedRemote: fixture.origin }),
    lock: withRepositoryLock,
    now: () => new Date('2026-09-20T12:34:56.000Z'),
  };
  return { calls, bodyFiles, output, options };
}

function hasCall(calls, bin, ...parts) {
  return calls.some(([actual, args]) => actual === bin && parts.every(part => args.includes(part)));
}

test('default publication scans exactly the unpublished commits before asking', needsJj, () => {
  const fixture = setupRepository();
  try {
    const base = fixture.jj('log', '--no-graph', '-r', 'main@origin', '-T', 'commit_id').trim();
    const head = fixture.jj('log', '--no-graph', '-r', '@', '-T', 'commit_id').trim();
    let scannedBeforeConfirm = false;
    const state = publisher(fixture, { confirm: () => { scannedBeforeConfirm = hasCall(state.calls, 'gitleaks', 'git'); return true; } });
    publish(state.options);
    assert(scannedBeforeConfirm);
    assert(hasCall(state.calls, 'gitleaks', 'git', '--redact', `--log-opts=--diff-merges=first-parent ${base}..${head}`, fixture.root));
    assert.match(state.output.text, /Secret scan: gitleaks found nothing/);
  } finally { cleanup(fixture); }
});

test('the real gitleaks refuses a token committed and then removed', requires('jj', 'gitleaks'), () => {
  const fixture = setupRepository({ stack: 0 });
  try {
    // Assembled at runtime so this source file never contains a token-shaped string.
    const token = ['ghp', 'R8tq3LwVn5Xk2Jc9Hy7Pd4Mb6Fz1Sa0Gu3Ee'].join('_');
    fs.writeFileSync(path.join(fixture.root, 'token.txt'), `github_token = "${token}"\n`);
    fixture.jj('describe', '-m', 'Add a token');
    fixture.jj('new');
    fs.rmSync(path.join(fixture.root, 'token.txt'));
    fixture.jj('describe', '-m', 'Remove the token');
    fixture.jj('bookmark', 'create', 'wip/token', '-r', '@');
    const state = publisher(fixture, { scan: 'real' });
    assert.throws(() => publish({ ...state.options, bookmark: 'wip/token' }), /gitleaks found potential secrets/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    const finding = state.output.text.slice(state.output.text.indexOf('Finding:'));
    assert.match(finding, /RuleID:\s+github-pat/);
    assert(!finding.includes(token), 'the scanner report must redact the token');
  } finally { cleanup(fixture); }
});

test('the real gitleaks scans content that only a merge resolution adds', requires('jj', 'gitleaks'), () => {
  const fixture = setupRepository({ stack: 0 });
  try {
    const sides = ['left', 'right'].map(side => {
      fixture.jj('new', 'main@origin', '-m', `Add ${side}`);
      fs.writeFileSync(path.join(fixture.root, `${side}.txt`), `${side}\n`);
      return fixture.jj('log', '--no-graph', '-r', '@', '-T', 'change_id').trim();
    });
    // Neither parent has the token; `git log -p` omits merge diffs by default.
    fixture.jj('new', ...sides, '-m', 'Merge both sides');
    const token = ['ghp', 'R8tq3LwVn5Xk2Jc9Hy7Pd4Mb6Fz1Sa0Gu3Ee'].join('_');
    fs.writeFileSync(path.join(fixture.root, 'token.txt'), `github_token = "${token}"\n`);
    fixture.jj('bookmark', 'create', 'wip/merge', '-r', '@');
    const state = publisher(fixture, { scan: 'real' });
    assert.throws(() => publish({ ...state.options, bookmark: 'wip/merge' }), /gitleaks found potential secrets/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
  } finally { cleanup(fixture); }
});

test('default publication refuses a private stack above main@origin', needsJj, () => {
  const fixture = setupRepository({ stack: 2 });
  try {
    const state = publisher(fixture);
    assert.throws(() => publish(state.options), /exactly one unpublished working change/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert(!hasCall(state.calls, 'gh', 'edit'));
  } finally { cleanup(fixture); }
});
