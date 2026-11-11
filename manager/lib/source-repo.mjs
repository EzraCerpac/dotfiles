#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { syncDev } from './source-dev.mjs';

const isLocalConfig = name => name === 'config.local.toml' || name === 'miserc.toml' || /^config\.host-[a-z0-9-]+\.toml$/.test(name);
const dotsVars = new Map();

// Read one [vars] dots_* setting from ROOT/config.toml through mise, once per
// process. A missing required setting fails with a message naming it.
export function dotsVar(root, name, { miseBin, optional = false, run = spawnSync } = {}) {
  const file = path.join(root, 'config.toml');
  if (!dotsVars.has(file + '\0' + name)) {
    const result = run(miseBin || resolveMiseBin(), ['-C', root, 'config', 'get', '--file', file, `vars.${name}`],
      { cwd: root, encoding: 'utf8', env: { ...process.env, MISE_AUTO_INSTALL: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
    dotsVars.set(file + '\0' + name, !result.error && result.status === 0 ? String(result.stdout).trim() : undefined);
  }
  const value = dotsVars.get(file + '\0' + name);
  if (value === undefined && !optional) throw new Error(`missing setting: add ${name} to [vars] in ${file}`);
  return value ?? '';
}

// A list setting is one string of space-separated words (mise [vars] values
// must be strings): dots_profiles = "workstation nas".
export const dotsList = value => String(value).split(/\s+/).filter(Boolean);

// The GitHub OWNER/NAME of the configuration repository ([vars] dots_source_repo).
export function sourceRepository(root, options = {}) {
  const repository = dotsVar(root, 'dots_source_repo', options);
  if (!/^[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/.test(repository)) throw new Error(`dots_source_repo must be OWNER/NAME, not ${repository}`);
  return repository;
}

export const githubOrigins = repository => new Set([`https://github.com/${repository}`, `https://github.com/${repository}.git`,
  `git@github.com:${repository}.git`, `git@github.com:${repository}`, `ssh://git@github.com/${repository}.git`]);

function requireOrigin(root, remote, expectedRemote, prefix = 'Refusing source operations: origin', repository) {
  if (expectedRemote) {
    if (remote !== expectedRemote) throw new Error(`${prefix} is not ${expectedRemote}`);
    return;
  }
  repository ||= sourceRepository(root);
  if (!githubOrigins(repository).has(remote)) throw new Error(`${prefix} is not ${repository}`);
}
const command = (bin, args, root, options = {}) => {
  const { trimOutput = true, ...spawnOptions } = options;
  const result = spawnSync(bin, args, { cwd: root, encoding: 'utf8', timeout: 30000, ...spawnOptions });
  if (result.error || result.status !== 0) throw new Error(`${bin} failed: ${result.error?.message || String(result.stderr || '').trim() || `exit ${result.status}`}`);
  return trimOutput ? result.stdout?.trim() || '' : result.stdout || '';
};
// The sync guide explains the checkout shape and how to convert an older one.
export const SYNC_DOC = fileURLToPath(new URL('../docs/sync.md', import.meta.url));
const fatal = message => Object.assign(new Error(message), { fatal: true });

function metadata(root) {
  root = fs.realpathSync(root);
  const result = spawnSync('git', ['rev-parse', '--show-toplevel', '--absolute-git-dir', '--git-common-dir'], { cwd: root, encoding: 'utf8' });
  if (result.status !== 0) throw fatal(`${root} is not a Git repository`);
  const [top, gitDir, common] = result.stdout.trim().split('\n');
  if (fs.realpathSync(top) !== root) throw fatal(`${root} is not the root of its Git repository`);
  return { root, gitDir: fs.realpathSync(gitDir), commonDir: fs.realpathSync(path.resolve(root, common)) };
}

// Repository and origin checks shared by sync, status and publish.
// REPOSITORY (OWNER/NAME) checks another checkout against this configuration's.
export function ensureRepository(root, { expectedRemote, repository } = {}) {
  const info = metadata(root);
  const remote = spawnSync('git', ['config', '--get', 'remote.origin.url'], { cwd: info.root, encoding: 'utf8' });
  if (remote.status !== 0) throw fatal('this checkout has no origin remote');
  try { requireOrigin(info.root, remote.stdout.trim(), expectedRemote, undefined, repository); }
  catch (error) { throw fatal(error.message); }
  return info;
}

// The one shape sync works on: plain Git with HEAD on dev and no legacy state.
// Converting an older checkout is a one-time manual step (SYNC_DOC).
export function shapeProblem({ root, gitDir }) {
  if (fs.existsSync(path.join(root, '.jj'))) return 'a JJ workspace (.jj) is present';
  if (fs.existsSync(path.join(gitDir, 'dots-dev.json'))) return 'legacy sync state (.git/dots-dev.json) is present';
  const head = spawnSync('git', ['symbolic-ref', '-q', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout?.trim();
  if (head !== 'refs/heads/dev') return head ? `HEAD is on ${head.replace(/^refs\/heads\//, '')}, not dev` : 'HEAD is detached, not on dev';
  if (spawnSync('git', ['rev-parse', '--verify', '-q', 'HEAD'], { cwd: root }).status !== 0) return 'dev has no commits';
  return null;
}

// One source operation per repository. A lock left by a dead process on this
// host is reclaimed; a live one makes the caller skip.
export function withRepositoryLock(root, callback) {
  const { commonDir } = metadata(root);
  const directory = path.join(commonDir, 'dots-source.lock');
  const owner = path.join(directory, 'owner.json');
  const take = () => fs.mkdirSync(directory, { mode: 0o700 });
  try { take(); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    let holder = {};
    try { holder = JSON.parse(fs.readFileSync(owner, 'utf8')); } catch { /* being written or empty */ }
    let alive = true;
    if (holder.host === os.hostname() && Number.isInteger(holder.pid)) {
      try { process.kill(holder.pid, 0); } catch (probe) { alive = probe.code !== 'ESRCH'; }
    }
    if (alive) throw Object.assign(new Error(`another source operation is running (pid ${holder.pid ?? 'unknown'}); lock ${directory}`), { locked: true });
    fs.rmSync(directory, { recursive: true, force: true });
    take();
  }
  try {
    fs.writeFileSync(owner, JSON.stringify({ pid: process.pid, host: os.hostname(), started: new Date().toISOString() }), { mode: 0o600 });
    return callback();
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
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
  if (difference < 0) throw new Error(`incoming configuration requires mise ${minimum}; update standalone mise`);
}

export function validateIncomingIgnores(root, gitDir, incoming, incomingFiles, local) {
  const preview = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-source-ignore-'));
  try {
    if (incomingFiles.has('.gitignore')) {
      const entry = command('git', [`--git-dir=${gitDir}`, 'ls-tree', incoming, '--', '.gitignore'], root);
      if (!/^100(?:644|755) blob [a-f0-9]+\t\.gitignore$/.test(entry)) throw new Error('Incoming .gitignore must be a regular source file');
      const ignore = command('git', [`--git-dir=${gitDir}`, 'show', `${incoming}:.gitignore`], root, { trimOutput: false, encoding: null });
      const rules = ignore.toString('utf8').split(/\r?\n/);
      const hostRule = rules.findLastIndex(rule => rule === '/config.host-*.toml' || rule === 'config.host-*.toml');
      if (hostRule < 0) throw new Error('incoming ignore rules must protect every config.host-*.toml selector');
      // Conservatively reject later root-file negations whose literal prefix can
      // overlap the host namespace. Directory-only and other literal namespaces
      // cannot unignore a root selector. One probe cannot cover future host IDs.
      for (const rule of rules.slice(hostRule + 1)) {
        if (!rule.startsWith('!')) continue;
        let pattern = rule.slice(1);
        if (pattern.endsWith('/')) continue;
        if (pattern.startsWith('/')) pattern = pattern.slice(1);
        while (/^\*{2,}\//.test(pattern)) pattern = pattern.replace(/^\*{2,}\//, '');
        if (pattern.includes('/')) continue;
        let length = 0;
        while (length < pattern.length && !['*', '?', '[', '\\'].includes(pattern[length])) length++;
        const prefix = pattern.slice(0, length), namespace = 'config.host-';
        if (namespace.startsWith(prefix) || prefix.startsWith(namespace)) throw new Error('incoming ignore negations could expose a future host selector');
      }
      fs.writeFileSync(path.join(preview, '.gitignore'), ignore, { mode: 0o600 });
    }
    // An isolated Git index checks only public incoming rules. No private files,
    // global excludes, or repository-local excludes are copied into the preview.
    command('git', ['init', '--quiet', '--template=', preview], root);
    const names = [...new Set(['config.local.toml', 'miserc.toml', 'config.host-probe.toml', ...local])];
    const result = spawnSync('git', ['-c', `core.excludesFile=${os.devNull}`, 'check-ignore', '--no-index', '-z', '--stdin'], {
      cwd: preview, encoding: 'utf8', input: names.join('\0') + '\0',
    });
    if (result.error || ![0, 1].includes(result.status)) throw new Error(`Cannot validate incoming ignore rules: ${result.error?.message || result.stderr?.trim()}`);
    const ignored = new Set(result.stdout.split('\0').filter(Boolean));
    if (names.some(name => !ignored.has(name))) throw new Error('incoming ignore rules would expose local settings or lockfiles');
  } finally { fs.rmSync(preview, { recursive: true }); }
}

export function validateIncoming(root, gitDir, commit, miseBin) {
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

function sourceEvent(value) {
  const event = JSON.stringify(value);
  try {
    if (process.env.DOTS_UP_STREAM_NONCE) process.stdout.write(`\x1edots-up/1:${process.env.DOTS_UP_STREAM_NONCE}:${event}\x1f`);
    else if (process.env.DOTS_UP_EVENT_FD) fs.writeSync(Number(process.env.DOTS_UP_EVENT_FD), `${event}\n`);
  } catch { /* Progress must not change the source operation. */ }
}

function sourceChanged(before, after) {
  if (before && after && before !== after) sourceEvent({ v: 1, kind: 'change', stage: 'source-sync', item: 'Configuration source', action: 'updated', before, after });
}

const IN_PROGRESS = ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'BISECT_LOG'];

// Run one sync and print one block. Only a missing or foreign repository and a
// checkout in the wrong shape are fatal (exit 1); every other outcome exits 0.
export function syncSource(root, { expectedRemote, miseBin, gitleaks, print = console.log } = {}) {
  let info;
  try {
    info = ensureRepository(root, { expectedRemote });
    const problem = shapeProblem(info);
    if (problem) throw fatal(`${problem}. Sync needs a plain Git checkout on dev; convert this machine once by hand: see ${SYNC_DOC}`);
  } catch (error) {
    print(`dots sync: stopped · ${error.message}`);
    return 1;
  }
  // Sync merges with `git merge-tree --write-tree -X theirs` (Git 2.40 or newer).
  if (spawnSync('git', ['merge-tree', '--write-tree', '-X', 'theirs', 'HEAD', 'HEAD'], { cwd: info.root }).status !== 0) {
    const version = spawnSync('git', ['--version'], { encoding: 'utf8' }).stdout?.trim();
    print(`dots sync: skipped · ${version || 'git'} cannot merge-tree -X; install Git 2.40 or newer`);
    return 0;
  }
  const marker = IN_PROGRESS.find(name => fs.existsSync(path.join(info.gitDir, name)));
  if (marker) {
    print(`dots sync: skipped · a Git operation is in progress (${marker}); finish or abort it, then rerun`);
    return 0;
  }
  let result;
  try {
    result = withRepositoryLock(info.root, () => syncDev(info.root, { gitDir: info.gitDir, miseBin: miseBin || resolveMiseBin(), gitleaks }));
  } catch (error) {
    print(error.locked ? `dots sync: skipped · ${error.message}` : `dots sync: failed · ${error.message}`);
    return error.locked ? 0 : 1;
  }
  print([result.header, ...result.lines.map(line => `  ${line}`)].join('\n'));
  // After the block, so a framed event never prefixes the header line.
  sourceChanged(result.before, result.after);
  return 0;
}

// Bootstrap: put a fresh, clean clone (on main) onto dev. Anything else is left
// alone; an older checkout is converted by hand (SYNC_DOC).
export function initSource(root) {
  const info = ensureRepository(root);
  const problem = shapeProblem(info);
  if (!problem) return;
  const git = (...args) => spawnSync('git', args, { cwd: info.root, encoding: 'utf8' });
  if (problem !== 'HEAD is on main, not dev' || git('status', '--porcelain').stdout.trim()) throw new Error(`${problem}; see ${SYNC_DOC}`);
  const remote = git('rev-parse', '--verify', '-q', 'refs/remotes/origin/dev').status === 0;
  const result = git('switch', '--quiet', ...(remote ? ['-c', 'dev', 'refs/remotes/origin/dev'] : ['-c', 'dev']));
  if (result.status !== 0) throw new Error(`could not switch to dev: ${result.stderr.trim()}`);
  console.log(`Source checkout is on dev${remote ? ' (from origin/dev)' : ''}.`);
}

export function sourceStatus(root) {
  const info = ensureRepository(root);
  const git = (...args) => spawnSync('git', args, { cwd: info.root, encoding: 'utf8' }).stdout?.trim() || '';
  const problem = shapeProblem(info);
  const revision = git('rev-parse', '--verify', '-q', 'HEAD');
  const unpushed = Number(git('rev-list', '--count', 'HEAD', ...(git('rev-parse', '--verify', '-q', 'refs/remotes/origin/dev') ? ['^refs/remotes/origin/dev'] : []))) || 0;
  return { workspace: 'git', branch: git('symbolic-ref', '-q', '--short', 'HEAD'), base_revision: revision, unpushed, problem, shared: 'origin/dev', publication: 'automatic; main reviewed' };
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [action, root, ...options] = process.argv.slice(2);
  const usage = 'Usage: source-repo.mjs init|sync|status ROOT, status ROOT --json';
  if (!root || !(['init', 'sync', 'status'].includes(action)) || options.length > (action === 'status' ? 1 : 0) || (options.length && options[0] !== '--json')) {
    console.error(usage);
    process.exitCode = 2;
  } else if (action === 'sync') process.exitCode = syncSource(root);
  else if (action === 'init') {
    try { initSource(root); } catch (error) { console.error(`Source init failed: ${error.message}`); process.exitCode = 1; }
  } else {
    try {
      const status = sourceStatus(root);
      if (options.length) console.log(JSON.stringify(status));
      else {
        console.log(`Source: Git checkout${status.branch ? ` on ${status.branch}` : ' (detached)'} at ${status.base_revision.slice(0, 12)}; ${status.unpushed} commits not on origin/dev as of the last fetch`);
        if (status.problem) console.log(`Attention: ${status.problem}; see ${SYNC_DOC}`);
      }
    } catch (error) {
      console.error(`Source status failed: ${error.message}`);
      process.exitCode = 1;
    }
  }
}
