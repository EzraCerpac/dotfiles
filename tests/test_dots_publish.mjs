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
