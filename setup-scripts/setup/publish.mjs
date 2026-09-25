#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { ensureRepository, withRepositoryLock, SourceDeferred } from '../lib/source-repo.mjs';

export const EXPECTED_REPOSITORY = 'EzraCerpac/dotfiles';
export const DISCLOSURE = `> [!NOTE]\n> **${process.env.DOTS_PUBLISH_MODEL || 'dots publish'}** is writing on behalf of Ezra.`;

const DEFAULT_BASE = 'main';

function commandError(command, args, result) {
  const detail = String(result?.stderr || result?.stdout || '').trim();
  return new Error(`${command} ${args.join(' ')} failed${detail ? `: ${detail}` : ''}`);
}

function invoke(run, command, args, cwd) {
  let result;
  try {
    result = run(command, args, {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    throw new Error(`Could not run ${command}: ${error.message}`);
  }
  if (!result || result.error || result.status !== 0) throw result?.error || commandError(command, args, result);
  return { stdout: String(result.stdout || ''), stderr: String(result.stderr || '') };
}

function outputText(output, value) {
  output.write(String(value));
}

function jjOutput(run, root, args) {
  return invoke(run, 'jj', ['--no-pager', ...args], root).stdout;
}

function commitIdFor(run, root, revision) {
  const commitId = jjOutput(run, root, [
    'log', '--no-graph', '--color=never', '-r', revision, '-T', 'commit_id',
  ]).trim();
  if (!commitId) throw new Error(`could not pin revision ${revision}`);
  return commitId;
}

function unpublishedCommits(run, root, revision) {
  return revisionList(run, root, `main@origin..${revision}`);
}

function revisionList(run, root, revset) {
  return jjOutput(run, root, [
    'log', '--no-graph', '--color=never', '-r', revset, '-T', 'commit_id ++ "\\n"',
  ]).split('\n').map(line => line.trim()).filter(Boolean);
}

function emptyRevision(run, root, revision) {
  return jjOutput(run, root, [
    'log', '--no-graph', '--color=never', '-r', revision, '-T', 'if(empty, "yes", "no")',
  ]).trim() === 'yes';
}

function allRevision(run, root) {
  let revision = '@';
  while (emptyRevision(run, root, revision) && !descriptionFor(run, root, revision)) {
    const parents = revisionList(run, root, `${revision}-`);
    if (parents.length !== 1) break;
    revision = parents[0];
  }
  return revision;
}

function hasConflicts(run, root, revision) {
  return revisionList(run, root, `${revision} & conflicts()`).length > 0;
}

function requireSingleDefaultChange(run, root) {
  const commits = unpublishedCommits(run, root, '@');
  if (commits.length !== 1) {
    throw new Error('default publishing requires exactly one unpublished working change directly above main@origin; use --bookmark wip/... for an existing private stack');
  }
  return '@';
}

function verifyPrivateBookmark(bookmark) {
  if (!/^wip\/[A-Za-z0-9][A-Za-z0-9._/-]*$/.test(bookmark)) {
    throw new Error('--bookmark must name an existing private wip/... bookmark');
  }
}

function verifyBookmark(run, root, bookmark) {
  const listed = jjOutput(run, root, ['bookmark', 'list', '-r', bookmark, '--color=never']);
  if (!listed.trim()) throw new Error(`bookmark does not exist: ${bookmark}`);
}

function descriptionFor(run, root, revision) {
  return jjOutput(run, root, [
    'log', '--no-graph', '--color=never', '-r', revision, '-T', 'description',
  ]).trim();
}

function proposedChanges(run, root, revision) {
  return unpublishedCommits(run, root, revision).map(commit => ({
    commit,
    description: descriptionFor(run, root, commit),
    diff: invoke(run, 'jj', ['--no-pager', 'diff', '--git', '--color=never', '-r', commit], root).stdout,
  }));
}

function previewChanges(output, revision, changes) {
  outputText(output, `Proposed diff for ${revision}, commit by commit (from main@origin):\n`);
  for (const change of changes) {
    outputText(output, `\nCommit ${change.commit.slice(0, 12)} — ${change.description || '(no description)'}\n`);
    outputText(output, `${change.diff}${change.diff.endsWith('\n') ? '' : '\n'}`);
  }
}

function allPullRequest(changes) {
  const included = [...changes].reverse().filter(change => change.diff.trim() && change.description !== 'Merge main into unpublished setup stack');
  const title = included.length === 1 && included[0].description
    ? titleFor(included[0].description)
    : `Publish ${included.length} setup changes`;
  const lines = included.map(change => `- ${change.description?.split(/\r?\n/, 1)[0] || `Undescribed change ${change.commit.slice(0, 12)}`}`);
  return { title, body: `${DISCLOSURE}\n\nChanges:\n${lines.join('\n')}` };
}

function shortChangeId(run, root, revision) {
  return jjOutput(run, root, [
    'log', '--no-graph', '--color=never', '-r', revision, '-T', 'change_id.short()',
  ]).trim().replace(/[^A-Za-z0-9]/g, '').slice(0, 12) || 'change';
}

function timestamp(now) {
  return now().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
}

function makeBody(description) {
  return `${DISCLOSURE}\n\n${description.trim()}`;
}

function titleFor(description) {
  const title = description.split(/\r?\n/, 1)[0].trim();
  if (!title) throw new Error('the publish description needs a non-empty first line');
  return title.slice(0, 72);
}

function readTerminalLine(input) {
  if (!input.isTTY || typeof input.fd !== 'number') return '';
  const buffer = Buffer.alloc(4096);
  const deadline = Date.now() + 10 * 60 * 1000;
  for (;;) {
    try {
      const size = fs.readSync(input.fd, buffer, 0, buffer.length, null);
      return buffer.subarray(0, size).toString('utf8').split(/\r?\n/, 1)[0].trim();
    } catch (error) {
      if (error?.code !== 'EAGAIN' && error?.code !== 'EWOULDBLOCK') throw error;
      if (Date.now() >= deadline) return '';
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
  }
}

function confirmDefault(question, { input = process.stdin, output = process.stdout } = {}) {
  outputText(output, `${question} [y/N] `);
  return /^y(?:es)?$/i.test(readTerminalLine(input));
}

function descriptionPromptDefault(question, { input = process.stdin, output = process.stdout } = {}) {
  outputText(output, `${question}: `);
  return readTerminalLine(input);
}

function findPullRequest(run, root, bookmark) {
  const result = invoke(run, 'gh', [
    'pr', 'list', '--repo', EXPECTED_REPOSITORY, '--head', bookmark, '--state', 'all', '--json', 'number,url,state',
  ], root);
  let entries;
  try { entries = JSON.parse(result.stdout); } catch { throw new Error('could not parse the existing pull request lookup'); }
  if (!Array.isArray(entries)) throw new Error('existing pull request lookup returned an unexpected shape');
  if (entries.length > 1) throw new Error(`multiple pull requests already use head ${bookmark}; refusing to choose one`);
  return entries[0] || null;
}

function publishPullRequest(run, root, bookmark, title, body, existing) {
  const bodyDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-publish-'));
  const bodyFile = path.join(bodyDirectory, 'pull-request.md');
  try {
    fs.writeFileSync(bodyFile, body, { mode: 0o600 });
    if (existing) {
      if (String(existing.state || '').toUpperCase() !== 'OPEN') {
        throw new Error(`refusing to edit ${String(existing.state || 'closed').toLowerCase()} pull request ${existing.number} for ${bookmark}; choose a new bookmark`);
      }
      const result = invoke(run, 'gh', [
        'pr', 'edit', String(existing.number), '--repo', EXPECTED_REPOSITORY, '--title', title, '--body-file', bodyFile,
      ], root);
      return { url: existing.url, existing: true, result };
    }
    const result = invoke(run, 'gh', [
      'pr', 'create', '--repo', EXPECTED_REPOSITORY, '--head', bookmark, '--base', DEFAULT_BASE,
      '--title', title, '--body-file', bodyFile,
    ], root);
    const url = result.stdout.trim().split(/\s+/).find(value => /^https?:\/\//.test(value));
    if (!url) throw new Error('gh pr create succeeded but did not return a pull request URL');
    return { url, existing: false, result };
  } finally {
    fs.rmSync(bodyDirectory, { recursive: true, force: true });
  }
}

function defaultBookmark(run, root, now, revision) {
  return `wip/dotfiles-${timestamp(now)}-${shortChangeId(run, root, revision)}`;
}

function existingAllPullRequest(run, root, revision) {
  const names = [...new Set(jjOutput(run, root, [
    'bookmark', 'list', '-r', `::${revision}`, '--color=never', '-T', 'name ++ "\\n"',
  ]).split('\n').map(line => line.trim()).filter(name => /^wip\/dotfiles-all-/.test(name)))];
  const open = [];
  for (const name of names) {
    const request = findPullRequest(run, root, name);
    if (String(request?.state || '').toUpperCase() === 'OPEN') open.push({ name, request });
  }
  if (open.length > 1) throw new Error('multiple open aggregate pull requests are ancestors of this stack; use --bookmark to choose one');
  return open[0] || null;
}

function publishAll({ root, run, now, output, confirm, descriptionPrompt }) {
  let revision = allRevision(run, root);
  const pinnedCommit = commitIdFor(run, root, revision);
  const workingCommit = commitIdFor(run, root, '@');
  const baseCommit = commitIdFor(run, root, 'main@origin');
  if (hasConflicts(run, root, revision)) throw new SourceDeferred('the current stack has conflicts; resolve them and rerun dots publish --all');
  let changes = proposedChanges(run, root, revision);
  if (!changes.some(change => change.diff.trim())) throw new Error(`${revision} has no actual file changes above main@origin`);
  previewChanges(output, revision, changes);

  let requestedDescription = '';
  if (revision === '@' && !descriptionFor(run, root, revision)) {
    requestedDescription = descriptionPrompt('Enter a one-line description for the working change');
    if (!requestedDescription) throw new Error('publication requires a one-line description for the working change');
    changes = changes.map(change => change.commit === pinnedCommit ? { ...change, description: requestedDescription } : change);
  } else if (!descriptionFor(run, root, revision)) {
    throw new Error(`the ${revision} change has no description; describe it before publishing`);
  }

  const mainAdvanced = revisionList(run, root, `main@origin ~ ::${revision}`).length > 0;
  if (mainAdvanced) {
    if (!confirm('Merge main@origin into the current unpublished stack before publishing?')) {
      throw new Error('publication cancelled; nothing was changed or pushed');
    }
    if (commitIdFor(run, root, revision) !== pinnedCommit || commitIdFor(run, root, '@') !== workingCommit || commitIdFor(run, root, 'main@origin') !== baseCommit) {
      throw new Error('the source revision changed while the preview was open; review the new diff and try again');
    }
    if (requestedDescription) invoke(run, 'jj', ['--no-pager', 'describe', '-m', requestedDescription], root);
    revision = requestedDescription ? '@' : revision;
    invoke(run, 'jj', ['--no-pager', 'new', '-m', 'Merge main into unpublished setup stack', revision, 'main@origin'], root);
    revision = '@';
    if (hasConflicts(run, root, revision)) {
      throw new SourceDeferred('merging main created conflicts in @; resolve them and rerun dots publish --all; nothing was pushed');
    }
    changes = proposedChanges(run, root, revision);
    previewChanges(output, revision, changes);
  }

  const finalDiff = invoke(run, 'jj', [
    '--no-pager', 'diff', '--git', '--color=never', '--from', 'main@origin', '--to', revision,
  ], root).stdout;
  if (!finalDiff.trim()) throw new Error('the current stack has no file changes compared with main@origin');
  outputText(output, `Final pull request diff against main@origin:\n${finalDiff}`);

  const { title, body } = allPullRequest(changes);
  const prior = existingAllPullRequest(run, root, revision);
  const finalCommit = commitIdFor(run, root, revision);
  const finalWorkingCommit = commitIdFor(run, root, '@');
  outputText(output, `Proposed pull request title: ${title}\nProposed pull request description:\n${body}\n`);
  if (!confirm(`Publish the current stack to ${EXPECTED_REPOSITORY}?`)) throw new Error('publication cancelled; nothing was pushed');

  // The preview and approval cover this exact source and base, including any merge.
  if (commitIdFor(run, root, revision) !== finalCommit || commitIdFor(run, root, '@') !== finalWorkingCommit ||
      commitIdFor(run, root, 'main@origin') !== baseCommit || hasConflicts(run, root, revision)) {
    throw new Error('the source revision changed while the preview was open; review the new diff and try again');
  }
  if (!mainAdvanced && requestedDescription) invoke(run, 'jj', ['--no-pager', 'describe', '-m', requestedDescription], root);
  const chosenBookmark = prior?.name || `wip/dotfiles-all-${timestamp(now)}-${shortChangeId(run, root, revision)}`;
  if (prior) invoke(run, 'jj', ['--no-pager', 'bookmark', 'move', chosenBookmark, '--to', revision], root);
  else invoke(run, 'jj', ['--no-pager', 'bookmark', 'create', chosenBookmark, '-r', revision], root);
  invoke(run, 'jj', ['--no-pager', 'git', 'push', '--bookmark', chosenBookmark], root);
  const pullRequest = publishPullRequest(run, root, chosenBookmark, title, body, prior?.request);
  if (revision === '@') invoke(run, 'jj', ['--no-pager', 'new'], root);
  outputText(output, `Published ${chosenBookmark}: ${pullRequest.url}\n`);
  return { bookmark: chosenBookmark, url: pullRequest.url, existing: pullRequest.existing, title };
}

function parseArgs(args) {
  if (!args.length) throw new Error('Usage: publish.mjs ROOT [--all | --bookmark NAME]');
  const root = path.resolve(args.shift());
  let bookmark;
  let all = false;
  while (args.length) {
    const flag = args.shift();
    if (flag === '--bookmark' && args.length) {
      if (bookmark) throw new Error('--bookmark may only be supplied once');
      bookmark = args.shift();
    } else if (flag === '--all' && !all) all = true;
    else throw new Error('Usage: publish.mjs ROOT [--all | --bookmark NAME]');
  }
  if (all && bookmark) throw new Error('--all and --bookmark cannot be used together');
  return { root, bookmark, all };
}

export function publish({
  root,
  bookmark,
  all = false,
  run = spawnSync,
  now = () => new Date(),
  output = process.stdout,
  confirm = (question) => confirmDefault(question, { input: process.stdin, output }),
  descriptionPrompt = (question) => descriptionPromptDefault(question, { input: process.stdin, output }),
  ensure = ensureRepository,
  lock = withRepositoryLock,
} = {}) {
  if (!root) throw new Error('A source repository root is required');
  if (all && bookmark) throw new Error('--all and --bookmark cannot be used together');
  if (bookmark) verifyPrivateBookmark(bookmark);

  return lock(root, () => {
    const repository = ensure(root);
    if (!repository || !repository.gitDir) throw new Error('source repository helper did not return gitDir');
    invoke(run, 'jj', ['--no-pager', 'git', 'fetch', '--remote', 'origin', '--branch', 'main'], root);

    if (all) return publishAll({ root, run, now, output, confirm, descriptionPrompt });

    const explicit = Boolean(bookmark);
    const revision = explicit ? bookmark : requireSingleDefaultChange(run, root);
    if (explicit) verifyBookmark(run, root, bookmark);
    const pinnedCommit = commitIdFor(run, root, revision);
    const workingCommit = commitIdFor(run, root, '@');
    let description = descriptionFor(run, root, revision);
    if (!description && explicit) throw new Error(`the ${revision} change has no description; describe it before publishing`);
    const changes = proposedChanges(run, root, revision);
    if (!changes.length) throw new Error(`${revision} has no unpublished commits above main@origin`);
    if (!changes.some(change => change.diff.trim())) {
      throw new Error(`${revision} has no actual file changes above main@origin`);
    }
    previewChanges(output, revision, changes);
    outputText(output, `Proposed pull request description:\n${description ? makeBody(description) : '(one-line description will be requested for this undescribed working change)'}\n`);
    const hadDescription = Boolean(description);
    if (!description) {
      description = descriptionPrompt('Enter a one-line description for the working change');
      if (!description) throw new Error('publication requires a one-line description');
      outputText(output, `Proposed pull request description:\n${makeBody(description)}\n`);
    }
    const title = titleFor(description);
    const body = makeBody(description);
    let existing;
    if (explicit) {
      existing = findPullRequest(run, root, bookmark);
      if (existing && String(existing.state || '').toUpperCase() !== 'OPEN') {
        throw new Error(`refusing to edit ${String(existing.state || 'closed').toLowerCase()} pull request ${existing.number} for ${bookmark}; choose a new bookmark`);
      }
    }
    if (!confirm(`Publish ${revision} to ${EXPECTED_REPOSITORY}?`)) throw new Error('publication cancelled; nothing was pushed');

    if (commitIdFor(run, root, revision) !== pinnedCommit || (!explicit && commitIdFor(run, root, '@') !== workingCommit)) {
      throw new Error('the source revision changed while the preview was open; review the new diff and try again');
    }
    if (!explicit && !hadDescription) invoke(run, 'jj', ['--no-pager', 'describe', '-m', description], root);
    let chosenBookmark = bookmark;
    if (!explicit) {
      chosenBookmark = defaultBookmark(run, root, now, revision);
      invoke(run, 'jj', ['--no-pager', 'bookmark', 'create', chosenBookmark, '-r', revision], root);
    }
    invoke(run, 'jj', ['--no-pager', 'git', 'push', '--bookmark', chosenBookmark], root);
    const pullRequest = publishPullRequest(run, root, chosenBookmark, title, body, existing);
    if (!explicit) invoke(run, 'jj', ['--no-pager', 'new'], root);
    outputText(output, `Published ${chosenBookmark}: ${pullRequest.url}\n`);
    return { bookmark: chosenBookmark, url: pullRequest.url, existing: pullRequest.existing, description, title };
  });
}

export function main(argv = process.argv.slice(2)) {
  try {
    const options = parseArgs([...argv]);
    publish(options);
  } catch (error) {
    if (error instanceof SourceDeferred || error?.code === 3) {
      console.error(`publish: ${error.message}`);
      process.exitCode = 3;
    } else {
      console.error(`publish: ${error.message}`);
      process.exitCode = 1;
    }
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
