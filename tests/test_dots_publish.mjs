import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

import { ensureRepository, withRepositoryLock } from '../setup-scripts/lib/source-repo.mjs';
import { DISCLOSURE, publish } from '../setup-scripts/setup/publish.mjs';

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
  command(directory, 'git', ['init', '--bare', origin]);
  command(root, 'git', ['init', '-q']);
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

function setupRevertedSecret() {
  const fixture = setupRepository({ stack: 0 });
  fs.writeFileSync(path.join(fixture.root, 'temporary-secret.txt'), 'temporary-secret-value\n');
  fixture.jj('describe', '-m', 'Add temporary secret');
  fixture.jj('new');
  fs.rmSync(path.join(fixture.root, 'temporary-secret.txt'));
  fixture.jj('describe', '-m', 'Remove temporary secret');
  fixture.jj('bookmark', 'create', 'wip/private', '-r', '@');
  return fixture;
}

function advanceMain(fixture, { conflict = false } = {}) {
  const clone = path.join(fixture.directory, 'other');
  command(fixture.directory, 'git', ['clone', '-q', fixture.origin, clone]);
  command(clone, 'git', ['config', 'user.name', 'Dots Test']);
  command(clone, 'git', ['config', 'user.email', 'dots-test@example.invalid']);
  fs.writeFileSync(path.join(clone, conflict ? 'config.toml' : 'from-main.txt'), 'new main content\n');
  command(clone, 'git', ['add', '.']);
  command(clone, 'git', ['commit', '-qm', 'Advance main']);
  command(clone, 'git', ['push', '-q', 'origin', 'main']);
}

function publisher(fixture, { prs = [], lookupFailure = false, pushStatus = 0, descriptionPrompt, confirm = () => true } = {}) {
  const calls = [];
  const bodyFiles = [];
  const run = (bin, args, options) => {
    calls.push([bin, args]);
    if (bin === 'jj' && args.includes('push')) return { status: pushStatus, stdout: '', stderr: pushStatus ? 'push failed' : '' };
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

test('default publication previews main@origin, prompts for an undescribed change, and leaves an empty child', () => {
  const fixture = setupRepository({ description: '' });
  try {
    const state = publisher(fixture, { descriptionPrompt: () => 'Describe public setup' });
    const result = publish(state.options);

    assert.equal(result.bookmark, 'wip/dotfiles-20260920123456-' + result.bookmark.split('-').at(-1));
    assert.match(state.output.text, /main@origin/);
    assert.match(state.output.text, /diff --git/);
    assert.match(state.output.text, new RegExp(DISCLOSURE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    assert.equal(fixture.jj('log', '--no-graph', '-r', '@-', '-T', 'description').trim(), 'Describe public setup');
    assert.equal(fixture.jj('log', '--no-graph', '-r', '@', '-T', 'description').trim(), '');
    assert(hasCall(state.calls, 'jj', 'describe', '-m', 'Describe public setup'));
    assert(hasCall(state.calls, 'jj', 'git', 'push', '--bookmark', result.bookmark));
    assert(hasCall(state.calls, 'gh', 'create', '--body-file'));
    assert.equal(state.bodyFiles.length, 1);
    assert.match(state.bodyFiles[0].content, /Describe public setup/);
    assert(!fs.existsSync(state.bodyFiles[0].path));
  } finally { cleanup(fixture); }
});

test('default publication rejects an empty child above main@origin before prompting or mutating JJ', () => {
  const fixture = setupRepository({ stack: 0 });
  try {
    const before = fixture.jj('log', '--no-graph', '-r', '@', '-T', 'commit_id ++ "\\n"').trim();
    let confirmed = false;
    let prompted = false;
    const state = publisher(fixture, {
      confirm: () => { confirmed = true; return true; },
      descriptionPrompt: () => { prompted = true; return 'Should not publish'; },
    });
    assert.throws(() => publish(state.options), /no actual file changes above main@origin/);
    assert.equal(fixture.jj('log', '--no-graph', '-r', '@', '-T', 'commit_id ++ "\\n"').trim(), before);
    assert.equal(fixture.jj('log', '--no-graph', '-r', '@', '-T', 'description').trim(), '');
    assert(!confirmed);
    assert(!prompted);
    assert(!hasCall(state.calls, 'jj', 'describe'));
    assert(!hasCall(state.calls, 'jj', 'bookmark', 'create'));
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'list'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert(!hasCall(state.calls, 'gh', 'edit'));
  } finally { cleanup(fixture); }
});

test('default publication refuses a private stack above main@origin', () => {
  const fixture = setupRepository({ stack: 2 });
  try {
    const state = publisher(fixture);
    assert.throws(() => publish(state.options), /exactly one unpublished working change/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert(!hasCall(state.calls, 'gh', 'edit'));
  } finally { cleanup(fixture); }
});

test('rejected confirmation does not describe, bookmark, push, or contact GitHub', () => {
  const fixture = setupRepository({ description: 'Sync public setup' });
  try {
    const state = publisher(fixture, { confirm: () => false });
    assert.throws(() => publish(state.options), /publication cancelled/);
    assert(!hasCall(state.calls, 'jj', 'describe'));
    assert(!hasCall(state.calls, 'jj', 'bookmark', 'create'));
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert(!hasCall(state.calls, 'gh', 'edit'));
  } finally { cleanup(fixture); }
});

test('explicit bookmark reuses an open PR without disturbing unrelated working changes', () => {
  const fixture = setupRepository({ description: 'Private stack', bookmark: 'wip/private' });
  try {
    fixture.jj('new', 'main@origin');
    fs.writeFileSync(path.join(fixture.root, 'unrelated.txt'), 'leave this working change alone\n');
    const state = publisher(fixture, { prs: [{ number: 9, url: 'https://github.com/EzraCerpac/dotfiles/pull/9', state: 'OPEN' }] });
    state.options.bookmark = 'wip/private';
    const result = publish(state.options);

    assert.equal(result.bookmark, 'wip/private');
    assert(hasCall(state.calls, 'gh', 'list', '--head', 'wip/private'));
    assert(hasCall(state.calls, 'gh', 'edit', '9', '--body-file'));
    assert(hasCall(state.calls, 'jj', 'git', 'push', '--bookmark', 'wip/private'));
    assert(!hasCall(state.calls, 'jj', 'bookmark', 'create'));
    assert(!hasCall(state.calls, 'jj', 'new'));
    assert.equal(fs.readFileSync(path.join(fixture.root, 'unrelated.txt'), 'utf8'), 'leave this working change alone\n');
  } finally { cleanup(fixture); }
});

test('explicit preview shows every unpublished commit, including content reverted by a later commit', () => {
  const fixture = setupRevertedSecret();
  try {
    const state = publisher(fixture, { prs: [{ number: 9, url: 'https://github.com/EzraCerpac/dotfiles/pull/9', state: 'OPEN' }] });
    state.options.bookmark = 'wip/private';
    publish(state.options);

    assert.match(state.output.text, /Add temporary secret/);
    assert.match(state.output.text, /Remove temporary secret/);
    assert.match(state.output.text, /temporary-secret-value/);
  } finally { cleanup(fixture); }
});

test('revision changes after confirmation abort before describe, bookmark, or push', () => {
  const fixture = setupRepository({ description: '' });
  try {
    const state = publisher(fixture, {
      descriptionPrompt: () => 'Describe public setup',
      confirm: () => { fixture.jj('new', 'main@origin'); return true; },
    });
    assert.throws(() => publish(state.options), /source revision changed while the preview was open/);
    assert(!hasCall(state.calls, 'jj', 'describe'));
    assert(!hasCall(state.calls, 'jj', 'bookmark', 'create'));
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
  } finally { cleanup(fixture); }
});

test('closed existing PR is refused before an explicit bookmark is pushed', () => {
  const fixture = setupRepository({ description: 'Private stack', bookmark: 'wip/private' });
  try {
    const state = publisher(fixture, { prs: [{ number: 9, url: 'https://github.com/EzraCerpac/dotfiles/pull/9', state: 'MERGED' }] });
    state.options.bookmark = 'wip/private';
    assert.throws(() => publish(state.options), /refusing to edit merged pull request/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
  } finally { cleanup(fixture); }
});

test('failed explicit PR lookup refuses to push or create a duplicate', () => {
  const fixture = setupRepository({ description: 'Private stack', bookmark: 'wip/private' });
  try {
    const state = publisher(fixture, { lookupFailure: true });
    state.options.bookmark = 'wip/private';
    assert.throws(() => publish(state.options), /gh .*GitHub unavailable/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'create'));
  } finally { cleanup(fixture); }
});

test('push failure stops before PR lookup and leaves the private bookmark untouched', () => {
  const fixture = setupRepository({ description: 'Private stack', bookmark: 'wip/private' });
  try {
    const state = publisher(fixture, { pushStatus: 1 });
    state.options.bookmark = 'wip/private';
    assert.throws(() => publish(state.options), /jj .*push failed/);
    assert(hasCall(state.calls, 'jj', 'git', 'push', '--bookmark', 'wip/private'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert(!hasCall(state.calls, 'gh', 'edit'));
  } finally { cleanup(fixture); }
});

test('--all publishes the current stack through an empty child and ignores another head', () => {
  const fixture = setupRepository({ stack: 2 });
  try {
    const tip = fixture.jj('log', '-r', '@', '--no-graph', '-T', 'commit_id').trim();
    fixture.jj('new', 'main@origin');
    fs.writeFileSync(path.join(fixture.root, 'other-head.txt'), 'not in this PR\n');
    fixture.jj('describe', '-m', 'Unrelated head');
    fixture.jj('bookmark', 'create', 'wip/unrelated', '-r', '@');
    fixture.jj('new', tip);
    const state = publisher(fixture);
    state.options.all = true;
    const result = publish(state.options);

    assert.match(result.bookmark, /^wip\/dotfiles-all-/);
    assert.match(state.output.text, /Private base 0/);
    assert.match(state.output.text, /Sync public setup/);
    assert.doesNotMatch(state.output.text, /Unrelated head|other-head\.txt/);
    assert.match(state.output.text, /Final pull request diff against main@origin/);
    assert.match(state.bodyFiles[0].content, /- Private base 0\n- Sync public setup/);
    assert.equal(fixture.jj('log', '-r', result.bookmark, '--no-graph', '-T', 'commit_id').trim(), tip);
    assert.equal(fixture.jj('log', '-r', '@', '--no-graph', '-T', 'empty').trim(), 'true');
    assert(!hasCall(state.calls, 'jj', 'new'));
  } finally { cleanup(fixture); }
});

test('--all refuses a stack whose final tree matches main', () => {
  const fixture = setupRevertedSecret();
  try {
    const state = publisher(fixture);
    state.options.all = true;
    assert.throws(() => publish(state.options), /no file changes compared with main@origin/);
    assert.match(state.output.text, /temporary-secret-value/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
  } finally { cleanup(fixture); }
});

test('--all merges newer main, then previews the final PR diff', () => {
  const fixture = setupRepository({ stack: 2 });
  try {
    advanceMain(fixture);
    const questions = [];
    const state = publisher(fixture, { confirm: question => { questions.push(question); return true; } });
    state.options.all = true;
    const result = publish(state.options);

    assert.equal(questions.length, 2);
    assert.match(questions[0], /Merge main@origin/);
    assert.match(questions[1], /Publish the current stack/);
    assert.match(state.output.text, /Final pull request diff against main@origin:[\s\S]*public-1\.txt/);
    assert(hasCall(state.calls, 'jj', 'new', 'main@origin'));
    assert(hasCall(state.calls, 'jj', 'git', 'push', '--bookmark', result.bookmark));
    assert.equal(fixture.jj('log', '-r', `main@origin ~ ::${result.bookmark}`, '--no-graph', '-T', 'commit_id').trim(), '');
  } finally { cleanup(fixture); }
});

test('--all stops after a conflicted merge without pushing', () => {
  const fixture = setupRepository({ stack: 1 });
  try {
    fs.writeFileSync(path.join(fixture.root, 'config.toml'), 'local content\n');
    fixture.jj('describe', '-m', 'Change local config');
    advanceMain(fixture, { conflict: true });
    const state = publisher(fixture);
    state.options.all = true;
    assert.throws(() => publish(state.options), /merging main created conflicts/);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert(!hasCall(state.calls, 'gh', 'create'));
    assert.notEqual(fixture.jj('log', '-r', '@ & conflicts()', '--no-graph', '-T', 'commit_id').trim(), '');
  } finally { cleanup(fixture); }
});

test('--all cancellation before merging leaves JJ untouched', () => {
  const fixture = setupRepository({ stack: 1 });
  try {
    advanceMain(fixture);
    const before = fixture.jj('log', '-r', '@', '--no-graph', '-T', 'commit_id').trim();
    const state = publisher(fixture, { confirm: () => false });
    state.options.all = true;
    assert.throws(() => publish(state.options), /nothing was changed or pushed/);
    assert.equal(fixture.jj('log', '-r', '@', '--no-graph', '-T', 'commit_id').trim(), before);
    assert(!hasCall(state.calls, 'jj', 'new'));
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
  } finally { cleanup(fixture); }
});

test('--all cancellation after a clean merge leaves it local without pushing', () => {
  const fixture = setupRepository({ stack: 1 });
  try {
    advanceMain(fixture);
    let approvals = 0;
    const state = publisher(fixture, { confirm: () => ++approvals === 1 });
    state.options.all = true;
    assert.throws(() => publish(state.options), /nothing was pushed/);
    assert.equal(approvals, 2);
    assert(!hasCall(state.calls, 'jj', 'git', 'push'));
    assert.equal(fixture.jj('log', '-r', 'main@origin ~ ::@', '--no-graph', '-T', 'commit_id').trim(), '');
  } finally { cleanup(fixture); }
});

test('--all rerun updates the open aggregate PR and moves its bookmark forward', () => {
  const fixture = setupRepository({ stack: 1 });
  try {
    const first = publisher(fixture);
    first.options.all = true;
    const original = publish(first.options);
    fs.writeFileSync(path.join(fixture.root, 'later.txt'), 'later change\n');
    fixture.jj('describe', '-m', 'Later change');
    const second = publisher(fixture, { prs: [{ number: 17, url: original.url, state: 'OPEN' }] });
    second.options.all = true;
    const updated = publish(second.options);

    assert.equal(updated.bookmark, original.bookmark);
    assert(updated.existing);
    assert(hasCall(second.calls, 'jj', 'bookmark', 'move', original.bookmark));
    assert(hasCall(second.calls, 'gh', 'edit', '17', '--body-file'));
    assert(!hasCall(second.calls, 'gh', 'create'));
    assert.match(second.bodyFiles[0].content, /Later change/);
  } finally { cleanup(fixture); }
});

test('--all rejects --bookmark before changing source state', () => {
  const fixture = setupRepository({ stack: 1, bookmark: 'wip/private' });
  try {
    const state = publisher(fixture);
    state.options.all = true;
    state.options.bookmark = 'wip/private';
    assert.throws(() => publish(state.options), /cannot be used together/);
    assert.deepEqual(state.calls, []);
    const cli = spawnSync(process.execPath, [path.resolve('setup-scripts/setup/publish.mjs'), fixture.root, '--all', '--bookmark', 'wip/private'], { encoding: 'utf8' });
    assert.equal(cli.status, 1);
    assert.match(cli.stderr, /cannot be used together/);
  } finally { cleanup(fixture); }
});
