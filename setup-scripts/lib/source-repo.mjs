#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export class SourceDeferred extends Error { constructor(message) { super(message); this.code = 3; } }
const lockfiles = ['mise.lock', 'mise.nas.lock', 'mise.workstation.lock'];
const isLocalConfig = name => name === 'config.local.toml' || name === 'miserc.toml' || /^config\.host-[a-z0-9-]+\.toml$/.test(name);
const isLocalConfigPath = name => isLocalConfig(name.split('/')[0].toLowerCase());
const origins = new Set(['https://github.com/EzraCerpac/dotfiles', 'https://github.com/EzraCerpac/dotfiles.git', 'git@github.com:EzraCerpac/dotfiles.git', 'git@github.com:EzraCerpac/dotfiles', 'ssh://git@github.com/EzraCerpac/dotfiles.git']);
const command = (bin, args, root, options = {}) => {
  const { trimOutput = true, ...spawnOptions } = options;
  const result = spawnSync(bin, args, { cwd: root, encoding: 'utf8', ...spawnOptions });
  if (result.error || result.status !== 0) throw new Error(`${bin} failed: ${result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`}`);
  return trimOutput ? result.stdout?.trim() || '' : result.stdout || '';
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

function validateMiseVersion(root, config, miseBin, parsedMinimum) {
  const minimum = parsedMinimum === undefined ? config.match(/^min_version\s*=\s*"([\d.]+)"/m)?.[1] : parsedMinimum;
  if (!minimum) return;
  const version = command(miseBin, ['--version'], root).match(/\d+\.\d+\.\d+/)?.[0];
  if (!version) throw new Error('Cannot determine the installed mise version');
  const a = version.split('.').map(Number), b = minimum.split('.').map(Number);
  const difference = a.map((n, i) => n - b[i]).find(n => n !== 0) || 0;
  if (difference < 0) throw new SourceDeferred(`Incoming configuration requires mise ${minimum}; update standalone mise before source sync`);
}

function publicMinimumVersion(config, miseBin) {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-source-toml-'));
  try {
    const input = path.join(work, 'input.toml'), empty = path.join(work, 'empty.toml');
    fs.writeFileSync(input, config, { mode: 0o600 });
    fs.writeFileSync(empty, '', { mode: 0o600 });
    const env = { ...process.env };
    for (const key of Object.keys(env)) if (key.startsWith('MISE_') || key.startsWith('__MISE_')) delete env[key];
    Object.assign(env, { HOME: work, MISE_CONFIG_DIR: work, MISE_GLOBAL_CONFIG_FILE: empty,
      MISE_GLOBAL_CONFIG_ROOT: work, MISE_SYSTEM_CONFIG_DIR: work, MISE_CEILING_PATHS: work,
      MISE_DATA_DIR: path.join(work, 'data'), MISE_CACHE_DIR: path.join(work, 'cache'), MISE_STATE_DIR: path.join(work, 'state'),
      MISE_ENV: '', MISE_AUTO_ENV: '0', MISE_NO_ENV: '1', MISE_NO_HOOKS: '1', MISE_AUTO_INSTALL: '0',
      MISE_EXEC_AUTO_INSTALL: '0', MISE_AUTO_UPDATE: '0', MISE_TRUSTED_CONFIG_PATHS: work, NO_COLOR: '1' });
    const get = key => {
      const result = spawnSync(miseBin, ['config', 'get', '--file', input, key], { cwd: work, env, encoding: 'utf8' });
      if (result.error) throw new Error('Cannot parse incoming public TOML');
      if (result.status === 0) return result.stdout.replace(/\r?\n$/, '');
      if (result.status === 1 && result.stderr.startsWith(`mise ERROR Key not found: ${key} in `)) return null;
      throw new Error('Incoming public TOML could not be parsed');
    };
    const value = get('min_version');
    if (value === null) return null;
    if (/^\d+\.\d+\.\d+$/.test(value)) return value;
    const hard = get('min_version.hard');
    const soft = get('min_version.soft');
    if (soft !== null && !/^\d+\.\d+\.\d+$/.test(soft)) throw new Error('Incoming soft minimum must be a full numeric version');
    if (hard === null) {
      if (soft !== null) return null;
      throw new Error('Incoming min_version must be a version string or hard/soft table');
    }
    if (!/^\d+\.\d+\.\d+$/.test(hard)) throw new Error('Incoming hard minimum must be a full numeric version');
    return hard;
  } finally { fs.rmSync(work, { recursive: true }); }
}

function localFileMetadata(root) {
  const names = fs.readdirSync(root).filter(name => isLocalConfigPath(name) || lockfiles.includes(name.toLowerCase())).sort();
  return names.map(name => {
    const stat = fs.lstatSync(path.join(root, name), { bigint: true });
    if (!stat.isFile()) throw new Error(`Local setup configuration must be a regular file: ${name}`);
    return [name, ...['dev', 'ino', 'mode', 'uid', 'gid', 'size', 'mtimeNs', 'ctimeNs'].map(key => String(stat[key]))];
  });
}

function validateIncomingIgnores(root, gitDir, incoming, incomingFiles, local) {
  const preview = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-source-ignore-'));
  try {
    if (incomingFiles.has('.gitignore')) {
      const entry = command('git', [`--git-dir=${gitDir}`, 'ls-tree', incoming, '--', '.gitignore'], root);
      if (!/^100(?:644|755) blob [a-f0-9]+\t\.gitignore$/.test(entry)) throw new Error('Incoming .gitignore must be a regular source file');
      const ignore = command('git', [`--git-dir=${gitDir}`, 'show', `${incoming}:.gitignore`], root, { trimOutput: false, encoding: null });
      fs.writeFileSync(path.join(preview, '.gitignore'), ignore, { mode: 0o600 });
    }
    // An isolated Git index checks only public incoming rules. No private files,
    // global excludes, or repository-local excludes are copied into the preview.
    command('git', ['init', '--quiet', '--template=', preview], root);
    const names = [...new Set(['config.local.toml', 'miserc.toml', 'config.host-source-only.toml', ...lockfiles, ...local.map(([name]) => name)])];
    const result = spawnSync('git', ['-c', `core.excludesFile=${os.devNull}`, 'check-ignore', '--no-index', '-z', '--stdin'], {
      cwd: preview, encoding: 'utf8', input: names.join('\0') + '\0',
    });
    if (result.error || ![0, 1].includes(result.status)) throw new Error(`Cannot validate incoming ignore rules: ${result.error?.message || result.stderr?.trim()}`);
    const ignored = new Set(result.stdout.split('\0').filter(Boolean));
    if (names.some(name => !ignored.has(name))) throw new SourceDeferred('Incoming ignore rules would expose local settings or lockfiles; preserving the current source');
  } finally { fs.rmSync(preview, { recursive: true }); }
}

function restoreSourceAfterRace(root, inspectedRevision, incoming) {
  // Keep any concurrent public edits and their revision. Recovery is safe only
  // while the newly created child is still empty and has the expected parent.
  const parents = revisions(root, '@-');
  if (parents.length !== 1 || parents[0] !== incoming || lines(jj(root, ['diff', '-r', '@', '--summary'])).length) {
    throw new SourceDeferred('Local settings changed during advancement; concurrent source work prevents automatic recovery. All edits are retained; reconcile the source before retrying');
  }
  const expected = lines(command('jj', ['--ignore-working-copy', '-R', root, 'log', '-r', '@ & empty()', '--no-graph', '-T', 'commit_id ++ "\\n"'], root));
  if (expected.length !== 1) throw new SourceDeferred('Source changed before recovery; current source and settings are retained for reconciliation');
  // edit snapshots and resolves this gate within the same JJ operation. A public
  // write or JJ move after the checks makes the target empty instead of replacing
  // the writer's checkout. The prior child belongs to children of base ancestors.
  const target = `${inspectedRevision} & children(ancestors(@ & ${expected[0]} & empty()))`;
  try { jj(root, ['edit', target]); }
  catch { throw new SourceDeferred('Source changed before recovery; current source and settings are retained for reconciliation'); }
  throw new SourceDeferred('Local settings changed during advancement; restored the prior source revision and retained the changed settings. Rerun sync when ready');
}

function syncSourceOnly(root, gitDir, incoming, base, incomingFiles, inspectedRevision, changed, miseBin) {
  if ([...incomingFiles].some(isLocalConfigPath)) throw new Error('Incoming source must not track private setup selectors');
  const local = localFileMetadata(root);
  const previousFiles = new Set(lines(command('git', [`--git-dir=${gitDir}`, 'ls-tree', '-r', '--name-only', base], root)));
  if ([...previousFiles].some(isLocalConfigPath)) throw new SourceDeferred('Tracked private selectors require manual reconciliation; source-only sync preserves local settings');
  if ([...incomingFiles, ...previousFiles].some(name => lockfiles.includes(name.split('/')[0].toLowerCase()))) {
    throw new SourceDeferred('Tracked lockfiles require ordinary dots sync; source-only sync preserves local files without migration');
  }
  const entry = command('git', [`--git-dir=${gitDir}`, 'ls-tree', incoming, '--', 'config.toml'], root);
  if (!/^100(?:644|755) blob [a-f0-9]+\tconfig\.toml$/.test(entry)) throw new Error('Incoming config.toml must be a regular source file');
  const config = command('git', [`--git-dir=${gitDir}`, 'show', `${incoming}:config.toml`], root, { trimOutput: false, encoding: null });
  validateIncomingIgnores(root, gitDir, incoming, incomingFiles, local);
  validateMiseVersion(root, config, miseBin, publicMinimumVersion(config, miseBin));
  if (revisions(root, '@')[0] !== inspectedRevision || JSON.stringify(localFileMetadata(root)) !== JSON.stringify(local)) {
    throw new SourceDeferred('Source or local settings changed during validation; preserving them. Rerun sync when ready');
  }
  const advances = base !== incoming || changed.length;
  if (advances) {
    // new snapshots and resolves the target within one native JJ operation.
    // Late public edits change @ and make this guarded target empty.
    const target = `${incoming} & descendants(parents(@ & ${inspectedRevision} & empty()))`;
    try { jj(root, ['new', target]); }
    catch { throw new SourceDeferred('Source changed before advancement or JJ could not advance; current source is retained. Rerun sync when ready'); }
  }
  let settingsChanged;
  try { settingsChanged = JSON.stringify(localFileMetadata(root)) !== JSON.stringify(local); }
  catch (error) {
    if (advances) restoreSourceAfterRace(root, inspectedRevision, incoming);
    throw error;
  }
  if (settingsChanged) {
    if (advances) restoreSourceAfterRace(root, inspectedRevision, incoming);
    throw new SourceDeferred('Local settings changed during source-only synchronization; preserving the current source and changed settings');
  }
  console.log(`Source synchronized to ${incoming.slice(0, 12)} (source only; dotfiles not applied).`);
  return incoming;
}

function validateIncoming(root, gitDir, commit, miseBin) {
  const preview = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-source-preview-'));
  try {
    const archive = spawnSync('git', [`--git-dir=${gitDir}`, 'archive', commit], { maxBuffer: 64 * 1024 * 1024 });
    if (archive.status !== 0) throw new Error('Could not prepare the incoming source preview');
    command('tar', ['-xf', '-', '-C', preview], root, { input: archive.stdout });
    const config = fs.readFileSync(path.join(preview, 'config.toml'), 'utf8');
    validateMiseVersion(root, config, miseBin);
    for (const name of fs.readdirSync(root).filter(isLocalConfig)) {
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

export function syncSource(root, { miseBin, expectedRemote, sourceOnly = false, expectedMain } = {}) {
  if (expectedMain && (!sourceOnly || !/^[a-f0-9]{40}$/.test(expectedMain))) throw new Error('expectedMain requires source-only mode and a full lowercase commit ID');
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
    if (expectedMain && incoming[0] !== expectedMain) throw new SourceDeferred('origin/main changed after review; preserving the current source');
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
    if (sourceOnly) return syncSourceOnly(root, gitDir, incoming[0], base[0], incomingFiles, inspectedRevision, changed, miseBin);
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

export function parseSourceArguments(args) {
  const [action, root, ...options] = args;
  if (!root || !['init', 'sync', 'status'].includes(action)
      || (options.length && (action !== 'sync' || options[0] !== '--source-only'
        || ![1, 3].includes(options.length) || (options.length === 3 && (options[1] !== '--expected-main' || !/^[a-f0-9]{40}$/.test(options[2])))))) {
    throw new Error('Usage: source-repo.mjs init|status ROOT, or sync ROOT [--source-only [--expected-main COMMIT]]');
  }
  return { action, root, sourceOnly: options.length > 0, ...(options.length === 3 ? { expectedMain: options[2] } : {}) };
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { action, root, sourceOnly, expectedMain } = parseSourceArguments(process.argv.slice(2));
    if (action === 'status') {
      const info = metadata(root);
      const remote = command('git', [`--git-dir=${info.gitDir}`, 'config', '--get', 'remote.origin.url'], root);
      if (!origins.has(remote)) throw new Error('Origin is not EzraCerpac/dotfiles');
      console.log(`Source: ${info.hasJj ? 'JJ workspace' : 'Git checkout; JJ initialization pending'}`);
      console.log('Shared source: origin/main; publication is explicit.');
      if (!info.hasJj) process.exitCode = 3;
    }
    else if (action === 'init') withRepositoryLock(root, () => ensureRepository(root));
    else syncSource(root, { sourceOnly, expectedMain });
  } catch (error) {
    console.error(`${error.code === 3 ? 'Source sync deferred' : 'Source operation failed'}: ${error.message}`);
    process.exitCode = error.code === 3 ? 3 : 1;
  }
}
