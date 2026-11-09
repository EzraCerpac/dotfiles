// Automatic live-source exchange. Task worktrees never enter this path.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { SourceDeferred, validateIncoming, validateIncomingIgnores } from './source-repo.mjs';

const privatePath = name => /^(config\.local\.toml|miserc\.toml|config\.host-[^/]+\.toml|mise(?:\.[^/]+)?\.lock|locks|\.setup-state)(\/|$)/i.test(name);
const trailer = 'Dots-Saves: ';
const same = (a, b) => a?.blob === b?.blob && a?.mode === b?.mode;
const deferred = message => { throw new SourceDeferred(message); };

export function syncDev(root, { gitDir, hasJj, miseBin }) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-dev-'));
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never',
    GIT_SSH_COMMAND: 'ssh -oBatchMode=yes -oConnectTimeout=10' };
  const run = (bin, args, options = {}) => {
    const result = spawnSync(bin, args, { cwd: root, env, encoding: 'utf8', timeout: 30000, maxBuffer: 64 * 1024 * 1024, ...options });
    if (result.error || result.status !== 0) deferred(`${bin} operation deferred (exit ${result.status ?? 'timeout'}); source retained`);
    return options.encoding === null ? result.stdout : result.stdout?.trim() || '';
  };
  const git = (...args) => run('git', args);
  const optional = (...args) => {
    const result = spawnSync('git', args, { cwd: root, env, encoding: 'utf8', timeout: 30000 });
    return result.status === 0 ? result.stdout.trim() : null;
  };
  const jj = (...args) => run('jj', ['-R', root, ...args]);
  const tree = rev => {
    const entries = {};
    for (const line of run('git', ['ls-tree', '-rz', rev], { encoding: 'utf8' }).split('\0').filter(Boolean)) {
      const match = line.match(/^(\d+) blob ([a-f0-9]+)\t([\s\S]+)$/);
      if (!match) deferred('Unsupported source tree entry');
      const [, mode, blob, name] = match;
      if (privatePath(name)) deferred('Tracked private settings require manual reconciliation');
      entries[name] = { mode, blob, time: null, machine: '' };
    }
    const message = git('show', '-s', '--format=%B', rev);
    const encoded = message.split('\n').find(line => line.startsWith(trailer))?.slice(trailer.length);
    if (encoded) {
      let saves;
      try { saves = JSON.parse(Buffer.from(encoded, 'base64').toString()); }
      catch { deferred('Invalid saved-time metadata'); }
      for (const [name, entry] of Object.entries(entries)) if (same(entry, saves[name])) Object.assign(entry, saves[name]);
    }
    return entries;
  };
  const writeTree = entries => {
    const indexEnv = { ...env, GIT_INDEX_FILE: path.join(scratch, 'index') };
    run('git', ['read-tree', '--empty'], { env: indexEnv });
    run('git', ['update-index', '-z', '--index-info'], { env: indexEnv, input: Object.entries(entries).map(([name, e]) => `${e.mode} ${e.blob}\t${name}\0`).join('') });
    return run('git', ['write-tree'], { env: indexEnv });
  };
  const scanTree = entries => {
    const directory = path.join(scratch, 'scan');
    fs.rmSync(directory, { recursive: true, force: true });
    fs.mkdirSync(directory);
    // No source-controlled symlink is followed while preparing the scan.
    for (const [name, entry] of Object.entries(entries)) {
      const target = path.join(directory, name);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, run('git', ['cat-file', 'blob', entry.blob], { encoding: null }));
    }
    run('gitleaks', ['dir', '--no-banner', '--redact', '--config', path.join(root, '.gitleaks.toml'), '--gitleaks-ignore-path', path.join(root, '.gitleaksignore'), directory]);
  };
  const commit = (entries, parents, subject) => {
    scanTree(entries); // Never put flagged content in snapshot ancestry.
    return run('git', ['-c', 'commit.gpgsign=false', 'commit-tree', writeTree(entries), ...parents.flatMap(p => ['-p', p])],
      { input: `${subject}\n\n${trailer}${Buffer.from(JSON.stringify(entries)).toString('base64')}\n` });
  };
  const sourceRevision = () => hasJj
    ? jj('--ignore-working-copy', 'log', '-r', '@', '--no-graph', '-T', 'commit_id')
    : git('rev-parse', 'HEAD');
  const disk = previous => {
    const names = run('git', ['ls-files', '-cz', '--others', '--exclude-standard'], { env: { ...env, GIT_INDEX_FILE: path.join(gitDir, 'index') } }).split('\0').filter(Boolean);
    const entries = {};
    for (const name of new Set(names)) {
      if (privatePath(name)) continue;
      const filename = path.join(root, name);
      let stat;
      try { stat = fs.lstatSync(filename); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
      if (!stat.isFile() && !stat.isSymbolicLink()) deferred('Unsupported source file type');
      const content = stat.isSymbolicLink() ? Buffer.from(fs.readlinkSync(filename)) : fs.readFileSync(filename);
      const blob = run('git', ['hash-object', '-w', '--stdin'], { input: content });
      const mode = stat.isSymbolicLink() ? '120000' : stat.mode & 0o111 ? '100755' : '100644';
      const entry = { blob, mode, time: null, machine: '' };
      if (same(entry, previous[name])) Object.assign(entry, previous[name]);
      else if (state.applied) Object.assign(entry, { time: stat.mtimeMs, machine: state.machine });
      else entry.observedTime = stat.mtimeMs;
      // First adoption cannot distinguish an old save from an old checkout.
      entries[name] = entry;
    }
    return entries;
  };
  const localSignature = () => fs.readdirSync(root).filter(name => privatePath(name) && !['locks', '.setup-state'].includes(name)).sort().map(name => {
    const stat = fs.lstatSync(path.join(root, name), { bigint: true });
    return [name, String(stat.ino), String(stat.mtimeNs), String(stat.ctimeNs), String(stat.size)];
  });
  const plausible = entry => entry && Number.isFinite(entry.time) && entry.time >= 946684800000 && entry.time <= Date.now() + 300000;
  const newer = (a, b) => {
    if (!plausible(a) || !plausible(b)) deferred('Conflict has unknown or implausible save times; both versions retained');
    return a.time > b.time || (a.time === b.time && a.machine > b.machine) ? a : b;
  };
  const merge = (left, right) => {
    if (left === right || optional('merge-base', '--is-ancestor', right, left) !== null) return left;
    if (optional('merge-base', '--is-ancestor', left, right) !== null) return right;
    const base = optional('merge-base', left, right);
    if (!base) deferred('Shared dev has unrelated history');
    const ancestor = tree(base), ours = tree(left), theirs = tree(right), merged = {};
    for (const name of new Set([...Object.keys(ancestor), ...Object.keys(ours), ...Object.keys(theirs)])) {
      const a = ancestor[name], l = ours[name], r = theirs[name];
      let chosen;
      if (same(l, r)) chosen = l && (plausible(l) && plausible(r) ? newer(l, r) : l);
      else if (same(l, a)) chosen = r;
      else if (same(r, a)) chosen = l;
      else if (!l || !r) {
        chosen = l || r;
        console.log(`Kept edited content for ${name}; alternative retained in ${left} and ${right}.`);
      } else if (l.mode !== r.mode || l.mode === '120000') {
        deferred(`Type conflict for ${name}; alternatives retained in ${left} and ${right}`);
      } else {
        const filenames = [l, a, r].map((entry, i) => {
          const filename = path.join(scratch, `merge-${i}`);
          fs.writeFileSync(filename, entry ? run('git', ['cat-file', 'blob', entry.blob], { encoding: null }) : Buffer.alloc(0));
          return filename;
        });
        const result = spawnSync('git', ['merge-file', '-p', ...filenames], { encoding: null, timeout: 30000, maxBuffer: 64 * 1024 * 1024 });
        if (result.status === 0) {
          // A compatible merge inherits contributing saves, never merge time.
          const latest = plausible(l) && plausible(r) ? newer(l, r) : { time: null, machine: '' };
          chosen = { ...l, time: latest.time, machine: latest.machine,
            blob: run('git', ['hash-object', '-w', '--stdin'], { input: result.stdout }) };
        } else {
          const winner = newer(l, r);
          const resolved = spawnSync('git', ['merge-file', '-p', winner === l ? '--ours' : '--theirs', ...filenames], { encoding: null, timeout: 30000, maxBuffer: 64 * 1024 * 1024 });
          if (resolved.status !== 0) deferred(`Cannot resolve text conflict for ${name}; alternatives retained`);
          chosen = { ...winner, blob: run('git', ['hash-object', '-w', '--stdin'], { input: resolved.stdout }) };
          console.log(`Save time selected ${name}; recover either version from ${left} or ${right}.`);
        }
      }
      if (chosen) merged[name] = chosen;
    }
    return commit(merged, [left, right], 'Merge shared setup');
  };
  const statePath = path.join(gitDir, 'dots-dev.json');
  let state = { machine: randomUUID() };
  if (fs.existsSync(statePath)) state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  const persist = () => {
    const temporary = `${statePath}.${process.pid}`;
    fs.writeFileSync(temporary, JSON.stringify(state), { mode: 0o600 });
    fs.renameSync(temporary, statePath);
  };
  try {
    const revision = sourceRevision();
    // Only managed source history may be captured, never a task branch/stack.
    const base = hasJj ? jj('--ignore-working-copy', 'log', '-r', '@-', '--no-graph', '-T', 'commit_id') : revision;
    const adopt = process.env.DOTS_ADOPT_DEV_PARENT;
    if (adopt && (!/^[a-f0-9]{40}$/.test(adopt) || adopt !== base || state.applied)) deferred('One-time adoption requires the exact inspected source parent and an unmanaged source');
    if (!state.applied && !adopt && ![optional('rev-parse', '--verify', 'refs/remotes/origin/main'), optional('rev-parse', '--verify', 'refs/remotes/origin/dev')].includes(base)) deferred('Unpublished task history requires explicit adoption');
    if (state.applied && base !== state.applied) deferred('Source revision moved outside managed dev; preserving task work');
    if (!hasJj && run('git', ['diff', '--cached', '--name-only'], { env: { ...env, GIT_INDEX_FILE: path.join(gitDir, 'index') } })) deferred('Staged source requires manual reconciliation');
    const originalDev = optional('rev-parse', '--verify', 'refs/heads/dev');
    // JJ can advance a tracked bookmark when another checkout fetches origin.
    const followedRemote = Boolean(state.devRef && originalDev && originalDev !== state.devRef
      && originalDev === optional('rev-parse', '--verify', 'refs/remotes/origin/dev')
      && optional('merge-base', '--is-ancestor', state.devRef, originalDev) !== null);
    if (state.applied && originalDev !== state.devRef && !followedRemote) deferred('Local dev moved concurrently; preserving it');
    if (!state.applied && !adopt && originalDev && base !== originalDev) deferred('Existing dev needs explicit adoption');
    const captureBase = state.capture || state.applied || base;
    const previous = tree(captureBase);
    const captured = disk(previous);
    const capturedTree = writeTree(captured);
    const signature = JSON.stringify(captured), local = JSON.stringify(localSignature());
    let candidate = state.queued || base;
    if ((adopt || followedRemote) && originalDev) candidate = merge(candidate, originalDev);
    if (capturedTree !== git('rev-parse', `${captureBase}^{tree}`)) {
      // Compare with the last capture, so undoing a queued edit is a new save.
      state.capture = commit(captured, [captureBase], 'Save local setup');
      git('update-ref', 'refs/dots/capture', state.capture);
      state.pending = true;
      persist();
    }
    if (state.capture) candidate = merge(state.capture, candidate);
    // Durable private pointer survives offline runs and failed validation.
    git('update-ref', 'refs/dots/queue', candidate);
    state.queued = candidate;
    state.pending = true;
    persist();
    console.log(`Saved locally: ${candidate}; recovery: git show ${candidate}:PATH`);
    let fetched = false;
    optional('fetch', '--no-tags', 'origin', 'refs/heads/main:refs/remotes/origin/main');
    try {
      git('fetch', '--no-tags', 'origin', 'refs/heads/dev:refs/remotes/origin/dev');
      fetched = true;
    } catch {
      // Bootstrap dev only after a successful bounded remote listing.
      const listing = optional('ls-remote', '--heads', 'origin', 'dev');
      if (listing === '') fetched = true;
    }
    let remote = fetched ? optional('rev-parse', '--verify', 'refs/remotes/origin/dev') : null;
    if (remote) candidate = merge(candidate, remote);
    // Dev carries everything: reviewed main merges in on every sync.
    const main = optional('rev-parse', '--verify', 'refs/remotes/origin/main');
    if (main) candidate = merge(candidate, main);
    for (let attempt = 0; attempt < 2; attempt++) {
      const entries = tree(candidate);
      scanTree(entries);
      const outgoingBase = remote || optional('rev-parse', '--verify', 'refs/remotes/origin/main') || base;
      run('gitleaks', ['git', '--no-banner', '--redact', '--config', path.join(root, '.gitleaks.toml'), '--gitleaks-ignore-path', path.join(root, '.gitleaksignore'),
        `--log-opts=--diff-merges=first-parent ${outgoingBase}..${candidate}`, root]);
      validateIncomingIgnores(root, gitDir, candidate, new Set(Object.keys(entries)), localSignature());
      validateIncoming(root, gitDir, candidate, miseBin);
      if (sourceRevision() !== revision || JSON.stringify(disk(previous)) !== signature || JSON.stringify(localSignature()) !== local) deferred('Source or local settings changed during sync; saved queue retained');
      git('update-ref', 'refs/dots/queue', candidate);
      state.queued = candidate;
      persist();
      if (!fetched) break;
      try {
        git('push', 'origin', `${candidate}:refs/heads/dev`);
        state.pending = false;
        break;
      } catch {
        state.pending = true;
        if (attempt === 1) break;
        try { git('fetch', '--no-tags', 'origin', 'refs/heads/dev:refs/remotes/origin/dev'); }
        catch { break; }
        remote = git('rev-parse', 'refs/remotes/origin/dev');
        candidate = merge(candidate, remote);
      }
    }
    state.pending = !fetched || Boolean(state.pending);
    persist();
    run(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'save']);
    if (sourceRevision() !== revision || JSON.stringify(disk(previous)) !== signature || JSON.stringify(localSignature()) !== local) deferred('Concurrent edits retained; adoption deferred');
    // CAS protects the shared local ref; never move main or a task bookmark.
    git('update-ref', 'refs/heads/dev', candidate, originalDev || '0000000000000000000000000000000000000000');
    state.devRef = candidate;
    persist();
    try {
      if (hasJj) {
        // Snapshot only after scanning. Gate the native advancement on that exact
        // snapshot so a later edit cannot be overwritten by jj new.
        const inspected = jj('log', '-r', '@', '--no-graph', '-T', 'commit_id');
        if (JSON.stringify(disk(previous)) !== signature) deferred('Late edit retained; adoption deferred');
        jj('new', `${candidate} & descendants(parents(@ & ${inspected}))`);
      } else {
        // Native two-tree checkout refuses writes made after our last check.
        const indexEnv = { ...env, GIT_INDEX_FILE: path.join(scratch, 'checkout-index') };
        run('git', ['read-tree', capturedTree], { env: indexEnv });
        run('git', ['update-index', '--refresh'], { env: indexEnv });
        run('git', ['read-tree', '-m', '-u', capturedTree, candidate], { env: indexEnv });
        run('git', ['read-tree', candidate], { env: { ...env, GIT_INDEX_FILE: path.join(gitDir, 'index') } });
        git('symbolic-ref', 'HEAD', 'refs/heads/dev');
      }
    } catch (error) {
      // A failed checkout must not leave HEAD ahead of the applied baseline.
      const rollback = originalDev
        ? optional('update-ref', 'refs/heads/dev', originalDev, candidate)
        : optional('update-ref', '-d', 'refs/heads/dev', candidate);
      if (rollback !== null) { state.devRef = originalDev; persist(); }
      throw error;
    }
    state.applied = candidate;
    state.capture = candidate;
    persist();
    run(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'apply', '--yes']);
    console.log(`Shared dev: ${candidate}; ${state.pending ? 'Push pending; Saved locally' : 'pushed'}; parents retain all alternatives.`);
    return candidate;
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
}
