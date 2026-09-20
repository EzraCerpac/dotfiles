#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export class SourceDeferred extends Error { constructor(message) { super(message); this.code = 3; } }
const lockfiles = ['mise.lock', 'mise.nas.lock', 'mise.workstation.lock'];
const origins = new Set(['https://github.com/EzraCerpac/dotfiles', 'https://github.com/EzraCerpac/dotfiles.git', 'git@github.com:EzraCerpac/dotfiles.git', 'git@github.com:EzraCerpac/dotfiles', 'ssh://git@github.com/EzraCerpac/dotfiles.git']);
const command = (bin, args, root, options = {}) => {
  const result = spawnSync(bin, args, { cwd: root, encoding: 'utf8', ...options });
  if (result.error || result.status !== 0) throw new Error(`${bin} failed: ${result.error?.message || result.stderr?.trim() || `exit ${result.status}`}`);
  return result.stdout?.trim() || '';
};
const jj = (root, args) => command('jj', ['-R', root, ...args], root);
const lines = value => value.split('\n').map(x => x.trim()).filter(Boolean);
const revisions = (root, revset) => lines(jj(root, ['log', '-r', revset, '--no-graph', '-T', 'commit_id ++ "\\n"']));

function metadata(root) {
  root = fs.realpathSync(root);
  if (fs.existsSync(path.join(root, '.jj'))) {
    if (fs.realpathSync(command('jj', ['root'], root)) !== root) throw new Error('The setup directory must be the JJ workspace root');
    return { root, gitDir: fs.realpathSync(command('jj', ['git', 'root'], root)), hasJj: true };
  }
  const gitPath = path.join(root, '.git');
  if (!fs.existsSync(gitPath) || !fs.lstatSync(gitPath).isDirectory()) throw new Error('Expected an adopted Git checkout; linked Git worktrees are not automatically initialized');
  if (fs.realpathSync(command('git', ['rev-parse', '--show-toplevel'], root)) !== root) throw new Error('The setup directory must be the Git checkout root');
  const gitDir = fs.realpathSync(command('git', ['rev-parse', '--absolute-git-dir'], root));
  const common = fs.realpathSync(path.resolve(root, command('git', ['rev-parse', '--git-common-dir'], root)));
  if (gitDir !== common) throw new Error('Linked Git worktrees are not automatically initialized');
  return { root, gitDir, hasJj: false };
}

export function ensureRepository(root, { expectedRemote } = {}) {
  const info = metadata(root);
  const remote = command('git', [`--git-dir=${info.gitDir}`, 'config', '--get', 'remote.origin.url'], root);
  if (expectedRemote ? remote !== expectedRemote : !origins.has(remote)) throw new Error('Refusing source operations: origin is not EzraCerpac/dotfiles');
  for (const marker of ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'BISECT_LOG']) {
    if (fs.existsSync(path.join(info.gitDir, marker))) throw new SourceDeferred(`Finish the Git operation (${marker}) before syncing configuration`);
  }
  if (!info.hasJj) {
    // JJ does not preserve a distinct staged/unstaged split. Refuse rather than
    // silently losing an intermediate version from the Git index.
    if (command('git', ['diff', '--cached', '--name-only'], root)) throw new SourceDeferred('The Git index has staged changes; reconcile them before JJ initialization');
    command('jj', ['git', 'init', '--colocate', root], root);
    console.log('Initialized colocated JJ; existing files and Git branches were preserved.');
  }
  return { root: info.root, gitDir: info.gitDir };
}

export function withRepositoryLock(root, callback) {
  const { gitDir } = metadata(root);
  const directory = path.join(gitDir, 'dots-source.lock');
  try { fs.mkdirSync(directory, { mode: 0o700 }); }
  catch (error) {
    if (error.code === 'EEXIST') throw new SourceDeferred(`Another source operation owns ${directory}; inspect its owner.json before removing a stale lock`);
    throw error;
  }
  try {
    fs.writeFileSync(path.join(directory, 'owner.json'), JSON.stringify({ pid: process.pid, host: os.hostname(), started: new Date().toISOString() }), { mode: 0o600 });
    return callback();
  } finally { fs.rmSync(directory, { recursive: true }); }
}

function miseEnvironment(root) {
  const env = { ...process.env, MISE_CONFIG_DIR: root, MISE_AUTO_INSTALL: '0' };
  // An explicit global filename disables sibling environment/local discovery
  // when validating an archive outside ~/.config/mise.
  delete env.MISE_GLOBAL_CONFIG_FILE;
  delete env.MISE_ENV;
  for (const key of Object.keys(env)) if (key.startsWith('__MISE_')) delete env[key];
  return env;
}

function executable(candidate) {
  if (!candidate) return false;
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return fs.statSync(candidate).isFile();
  } catch {
    return false;
  }
}

function invalidMiseOverride(name, value) {
  throw new Error(`mise: ${name} is not executable: ${value}`);
}

export function resolveMiseBin({ env = process.env, home = os.homedir() } = {}) {
  if (env.DOTS_MISE_BIN) {
    if (executable(env.DOTS_MISE_BIN)) return env.DOTS_MISE_BIN;
    invalidMiseOverride('DOTS_MISE_BIN', env.DOTS_MISE_BIN);
  }
  if (env.SETUP_MISE_BIN) {
    if (executable(env.SETUP_MISE_BIN)) return env.SETUP_MISE_BIN;
    invalidMiseOverride('SETUP_MISE_BIN', env.SETUP_MISE_BIN);
  }
  if (env.MISE_BIN && executable(env.MISE_BIN)) return env.MISE_BIN;

  const standalone = path.join(home, '.local', 'bin', 'mise');
  if (executable(standalone)) return standalone;

  for (const directory of String(env.PATH || '').split(path.delimiter)) {
    const candidate = path.join(directory || '.', 'mise');
    if (executable(candidate)) return candidate;
  }
  throw new Error('mise: no executable found in DOTS_MISE_BIN, SETUP_MISE_BIN, MISE_BIN, ~/.local/bin, or PATH');
}

function validateIncoming(root, gitDir, commit, miseBin) {
  const preview = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-source-preview-'));
  try {
    const archive = spawnSync('git', [`--git-dir=${gitDir}`, 'archive', commit], { maxBuffer: 64 * 1024 * 1024 });
    if (archive.status !== 0) throw new Error('Could not prepare the incoming source preview');
    command('tar', ['-xf', '-', '-C', preview], root, { input: archive.stdout });
    const config = fs.readFileSync(path.join(preview, 'config.toml'), 'utf8');
    const minimum = config.match(/^min_version\s*=\s*"([\d.]+)"/m)?.[1];
    if (minimum) {
      const version = command(miseBin, ['--version'], root).match(/\d+\.\d+\.\d+/)?.[0];
      if (!version) throw new Error('Cannot determine the installed mise version');
      const a = version.split('.').map(Number), b = minimum.split('.').map(Number);
      const difference = a.map((n, i) => n - b[i]).find(n => n !== 0) || 0;
      if (difference < 0) throw new SourceDeferred(`Incoming configuration requires mise ${minimum}; update standalone mise before source sync`);
    }
    for (const name of fs.readdirSync(root).filter(name => name === 'config.local.toml' || name === 'miserc.toml' || /^config\.host-[a-z0-9-]+\.toml$/.test(name))) {
      const source = path.join(root, name);
      if (!fs.lstatSync(source).isFile()) throw new Error(`Local setup configuration must be a regular file: ${name}`);
      // Local selectors never belong to public source. Exclusive creation also
      // refuses archive-controlled symlinks instead of following their targets.
      fs.copyFileSync(source, path.join(preview, name), fs.constants.COPYFILE_EXCL);
      fs.chmodSync(path.join(preview, name), 0o600);
    }
    const env = { ...miseEnvironment(preview), MISE_TRUSTED_CONFIG_PATHS: preview };
    command(miseBin, ['-C', preview, 'config', 'ls', '--json'], preview, { env });
    // Preview links point into this temporary tree. Force only this dry run to
    // validate rendering without treating the temporary source path as drift.
    command(miseBin, ['-C', preview, 'bootstrap', 'dotfiles', 'apply', '--dry-run', '--force', '--yes'], preview, { env });
  } finally { fs.rmSync(preview, { recursive: true }); }
}

export function syncSource(root, { miseBin, expectedRemote } = {}) {
  miseBin ||= resolveMiseBin();
  if (!executable(miseBin)) invalidMiseOverride('miseBin', miseBin);
  miseBin = path.resolve(miseBin);
  root = fs.realpathSync(root);
  return withRepositoryLock(root, () => {
    const { gitDir } = ensureRepository(root, { expectedRemote });
    try { jj(root, ['git', 'fetch', '--remote', 'origin', '--branch', 'main']); }
    catch (error) { throw new SourceDeferred(`Could not fetch origin/main; keeping the current source. ${error.message}`); }
    const incoming = revisions(root, 'main@origin');
    if (incoming.length !== 1) throw new Error('origin/main must resolve to one revision');
    const base = revisions(root, '@-');
    if (base.length !== 1) throw new SourceDeferred('The working copy has multiple parents; reconcile the source manually');
    if (revisions(root, '@ & conflicts()').length) throw new SourceDeferred('The source has unresolved conflicts');
    if (!revisions(root, `${base[0]} & ancestors(${incoming[0]})`).length) throw new SourceDeferred('The current source contains unpublished or divergent history; preserving it');
    const inspectedRevision = revisions(root, '@')[0];
    const changed = lines(jj(root, ['diff', '-r', '@', '--summary']));
    const incomingFiles = new Set(lines(command('git', [`--git-dir=${gitDir}`, 'ls-tree', '-r', '--name-only', incoming[0]], root)));
    const migratesLocks = lockfiles.every(name => !incomingFiles.has(name));
    if (changed.length && !(migratesLocks && changed.every(line => /^M (mise(?:\.nas|\.workstation)?\.lock)$/.test(line)))) {
      throw new SourceDeferred('Local source edits need review; preserving them. Use dots publish when ready');
    }
    validateIncoming(root, gitDir, incoming[0], miseBin);
    const env = miseEnvironment(root);
    command(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'save'], root, { env });
    if (revisions(root, '@')[0] !== inspectedRevision) throw new SourceDeferred('Source changed during validation; preserving the new edits. Rerun sync when ready');
    const localLocks = new Map();
    for (const name of lockfiles) {
      const filename = path.join(root, name);
      if (fs.existsSync(filename)) {
        if (!fs.lstatSync(filename).isFile()) throw new Error(`Refusing unexpected lockfile path: ${name}`);
        localLocks.set(name, fs.readFileSync(filename));
      }
    }
    const previousFiles = new Set(lines(command('git', [`--git-dir=${gitDir}`, 'ls-tree', '-r', '--name-only', base[0]], root)));
    if (migratesLocks && localLocks.size && lockfiles.some(name => previousFiles.has(name))) {
      const backup = path.join(root, '.setup-state', 'local-lockfiles', `${Date.now()}-${process.pid}`);
      fs.mkdirSync(backup, { recursive: true, mode: 0o700 });
      for (const [name, content] of localLocks) fs.writeFileSync(path.join(backup, name), content, { mode: 0o600 });
    }
    if (base[0] !== incoming[0] || changed.length) {
      try { jj(root, ['new', incoming[0]]); }
      finally {
        if (migratesLocks) for (const [name, content] of localLocks) fs.writeFileSync(path.join(root, name), content, { mode: 0o600 });
      }
    }
    command(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'apply', '--yes'], root, { env, stdio: 'inherit' });
    console.log(`Source synchronized to ${incoming[0].slice(0, 12)}; dotfiles applied.`);
    return incoming[0];
  });
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [action, root] = process.argv.slice(2);
  try {
    if (!root || !['init', 'sync', 'status'].includes(action)) throw new Error('Usage: source-repo.mjs init|sync|status ROOT');
    if (action === 'status') {
      const info = metadata(root);
      const remote = command('git', [`--git-dir=${info.gitDir}`, 'config', '--get', 'remote.origin.url'], root);
      if (!origins.has(remote)) throw new Error('Origin is not EzraCerpac/dotfiles');
      console.log(`Source: ${info.hasJj ? 'JJ workspace' : 'Git checkout; JJ initialization pending'}`);
      console.log('Shared source: origin/main; publication is explicit.');
      if (!info.hasJj) process.exitCode = 3;
    }
    else if (action === 'init') withRepositoryLock(root, () => ensureRepository(root));
    else syncSource(root);
  } catch (error) {
    console.error(`${error.code === 3 ? 'Source sync deferred' : 'Source operation failed'}: ${error.message}`);
    process.exitCode = error.code === 3 ? 3 : 1;
  }
}
