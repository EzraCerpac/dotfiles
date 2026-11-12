// Stateless live-source sync. Git refs and the files on disk are the only truth:
// unpushed work is exactly origin/dev..dev. Task worktrees never enter this path.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { validateIncoming, validateIncomingIgnores } from './source-repo.mjs';

export const privatePath = name => /^(config\.local\.toml|miserc\.toml|config\.host-[^/]+\.toml|mise(?:\.[^/]+)?\.lock|locks|\.setup-state)(\/|$)/i.test(name);
const ZERO = '0'.repeat(40);
const short = commit => commit.slice(0, 12);
const firstLine = text => String(text || '').split('\n').map(line => line.trim()).find(Boolean)?.slice(0, 160) || 'unknown error';

export function syncDev(root, { gitDir, miseBin, gitleaks = 'gitleaks', host = os.hostname().split('.')[0] }) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-sync-'));
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never', GIT_LITERAL_PATHSPECS: '1',
    GIT_SSH_COMMAND: process.env.GIT_SSH_COMMAND || 'ssh -oBatchMode=yes -oConnectTimeout=10' };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY']) delete env[key];
  const lines = [];
  const raw = (bin, args, options = {}) => spawnSync(bin, args, { cwd: root, env, encoding: 'utf8', timeout: 60000, maxBuffer: 64 * 1024 * 1024, ...options });
  const tryGit = (args, options) => raw('git', args, options);
  const git = (args, options) => {
    const result = tryGit(args, options);
    if (result.error || result.status !== 0) throw new Error(`git ${args[0]} failed: ${firstLine(result.stderr) || result.error?.message}`);
    return options?.encoding === null ? result.stdout : result.stdout.trim();
  };
  const withIndex = file => ({ env: { ...env, GIT_INDEX_FILE: file } });
  const rev = name => { const r = tryGit(['rev-parse', '--verify', '-q', `${name}^{commit}`]); return r.status === 0 ? r.stdout.trim() : null; };
  const tree = commit => git(['rev-parse', `${commit}^{tree}`]);
  const isAncestor = (a, b) => tryGit(['merge-base', '--is-ancestor', a, b]).status === 0;
  const count = range => Number(tryGit(['rev-list', '--count', ...range]).stdout?.trim() || 0);
  const commitTree = (treeId, parents, message) => git(['-c', 'commit.gpgsign=false', 'commit-tree', treeId, ...parents.flatMap(p => ['-p', p]), '-m', message]);
  const nul = text => text.split('\0').filter(Boolean);

  // gitleaks over a commit range, reported by file and line, never by content.
  const scan = range => {
    const report = path.join(scratch, `gitleaks-${Date.now()}.json`);
    const args = ['git', '--no-banner', '--redact', '--exit-code', '1', '--report-format', 'json', '--report-path', report,
      `--log-opts=--diff-merges=first-parent ${range.join(' ')}`];
    if (fs.existsSync(path.join(root, '.gitleaks.toml'))) args.push('--config', path.join(root, '.gitleaks.toml'));
    if (fs.existsSync(path.join(root, '.gitleaksignore'))) args.push('--gitleaks-ignore-path', path.join(root, '.gitleaksignore'));
    const result = raw(gitleaks, [...args, root], { timeout: 300000 });
    if (result.error) return { error: result.error.code === 'ENOENT' ? 'gitleaks is not installed' : result.error.message };
    if (result.status === 0) return { findings: [] };
    if (result.status !== 1) return { error: `gitleaks exited ${result.status}` };
    try {
      const findings = JSON.parse(fs.readFileSync(report, 'utf8')).map(f => ({ file: f.File, line: f.StartLine, rule: f.RuleID, commit: f.Commit }));
      return findings.length ? { findings } : { error: 'gitleaks reported findings it did not list' };
    } catch { return { error: 'gitleaks report unreadable' }; }
  };

  // Merge without touching live files. On a conflicting hunk the published side
  // (theirs) wins; binary, type and delete conflicts take its file whole. Both
  // parents stay in history, so the losing version remains recoverable.
  const merge = (ours, theirs, label) => {
    if (!theirs || ours === theirs || isAncestor(theirs, ours)) return ours;
    if (isAncestor(ours, theirs)) return theirs;
    // A file/directory conflict moves the file aside to PATH~COMMIT; resolve it at PATH.
    const original = name => name.replace(new RegExp(`~(?:${ours}|${theirs})(?:_\\d+)?$`), '');
    const conflicts = nul(tryGit(['merge-tree', '--write-tree', '-z', '--name-only', ours, theirs]).stdout || '').slice(1).map(original);
    const resolved = tryGit(['merge-tree', '--write-tree', '-z', '--name-only', '-X', 'theirs', ours, theirs]);
    if (resolved.status > 1 || resolved.error) throw new Error(`cannot merge ${label}: ${firstLine(resolved.stderr)}`);
    const [mergedTree, ...remaining] = resolved.stdout.split('\0\0')[0].split('\0').filter(Boolean);
    let result = mergedTree;
    if (resolved.status === 1) {
      const index = path.join(scratch, 'merge-index');
      git(['read-tree', mergedTree], withIndex(index));
      // Everything at or under each conflicted path becomes the published version.
      const paths = [...new Set(remaining.map(original))];
      const drop = [...remaining, ...nul(git(['ls-tree', '-r', '-z', '--name-only', '--full-tree', mergedTree, '--', ...paths]))];
      const published = nul(git(['ls-tree', '-r', '-z', '--full-tree', theirs, '--', ...paths])).map(entry => {
        const [meta, name] = entry.split('\t');
        const [mode, , oid] = meta.split(' ');
        return `${mode} ${oid}\t${name}\0`;
      });
      const input = drop.map(name => `0 ${ZERO}\t${name}\0`).join('') + published.join('');
      git(['update-index', '-z', '--index-info'], { ...withIndex(index), input });
      result = git(['write-tree'], withIndex(index));
    }
    const has = (commit, name) => tryGit(['cat-file', '-e', `${commit}:${name}`]).status === 0;
    for (const name of new Set(conflicts)) {
      const yours = has(ours, name);
      if (!yours && !has(theirs, name)) continue; // merge artifact
      lines.push(`CONFLICT kept published: ${name}  (yours: ${yours ? `git show ${short(ours)}:${name}` : `deleted in ${short(ours)}`})`);
    }
    return commitTree(result, [ours, theirs], `Merge ${label} (${host})`);
  };

  try {
    // Copied dotfiles flow back into the source before it is captured.
    const save = raw(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'save']);
    if (save.error || save.status !== 0) lines.push(`SAVE FAILED: mise bootstrap dotfiles save (exit ${save.status ?? 'error'}); copied dotfiles not captured`);

    // 2. The files' base is the commit the index was checked out from. It equals
    // HEAD unless something moved dev without updating the files.
    let dev = rev('HEAD');
    const start = dev;
    const indexTree = tryGit(['write-tree']).stdout?.trim();
    let base = dev;
    if (indexTree && indexTree !== tree(dev)) {
      const candidates = [['log', '--format=%H %T', '-n', '2000', 'HEAD'], ['log', '--format=%H %T', '-n', '500', 'refs/remotes/origin/dev'],
        ['log', '-g', '--format=%H %T', '-n', '200', 'refs/heads/dev'], ['log', '-g', '--format=%H %T', '-n', '200', 'HEAD']];
      for (const args of candidates) {
        const match = (tryGit(args).stdout || '').split('\n').find(line => line.endsWith(` ${indexTree}`));
        if (match) { base = match.split(' ')[0]; break; }
      }
      // A hand-staged index equal to an older commit looks the same; files on disk are still all captured.
      if (base !== dev) lines.push(`dev moved outside sync (now ${short(dev)}), or the index was staged to match ${short(base)}; local files were merged onto dev, not reverted`);
    }

    // 3-4. Snapshot every tracked or unignored file onto the base, leaving out
    // private files and anything gitleaks flags.
    const index = path.join(scratch, 'index');
    if (fs.existsSync(path.join(gitDir, 'index'))) {
      // Keep the index's own mtime: Git's racy-entry check compares against it.
      const stat = fs.statSync(path.join(gitDir, 'index'));
      fs.copyFileSync(path.join(gitDir, 'index'), index);
      fs.utimesSync(index, stat.atime, stat.mtime);
    }
    if (base !== dev || !indexTree) git(['read-tree', base], withIndex(index));
    git(['add', '-A', '--', '.'], withIndex(index));
    const baseEntries = new Map(nul(git(['ls-tree', '-r', '-z', '--full-tree', base])).map(entry => { const [meta, name] = entry.split('\t'); return [name, meta.split(' ')]; }));
    const restore = names => {
      if (!names.length) return;
      git(['update-index', '-z', '--index-info'], { ...withIndex(index), input: names.map(name => {
        const entry = baseEntries.get(name);
        return entry ? `${entry[0]} ${entry[2]}\t${name}\0` : `0 ${ZERO}\t${name}\0`;
      }).join('') });
    };
    const changed = () => nul(git(['diff-index', '--cached', '-z', '--name-only', base], withIndex(index)));
    restore(changed().filter(privatePath));
    let pushable = true;
    let snapshot = base, shared = 0;
    const snapshotTree = () => git(['write-tree'], withIndex(index));
    if (snapshotTree() !== tree(base)) {
      const tentative = commitTree(snapshotTree(), [base], `Save local setup (${host})`);
      const result = scan([`${base}..${tentative}`]);
      if (result.error) {
        restore(changed());
        pushable = false;
        lines.push(`NOT SHARED: ${result.error}; local edits kept on disk, nothing pushed`);
      } else {
        const flagged = [...new Set(result.findings.map(f => f.file))];
        for (const f of result.findings) lines.push(`NOT SHARED (gitleaks ${f.rule}): ${f.file}:${f.line}`);
        restore(flagged);
      }
      if (snapshotTree() !== tree(base)) {
        shared = changed().length;
        snapshot = tree(tentative) === snapshotTree() ? tentative : commitTree(snapshotTree(), [base], `Save local setup (${host})`);
      }
    }
    // Git's own lock protocol: never clobber an index another command holds.
    const indexLock = path.join(gitDir, 'index.lock');
    const lockIndex = () => { try { fs.closeSync(fs.openSync(indexLock, 'wx', 0o644)); return true; } catch { return false; } };
    const commitIndex = () => {
      const copy = `${index}.install`;
      fs.copyFileSync(index, copy);
      fs.utimesSync(copy, fs.statSync(index).atime, fs.statSync(index).mtime);
      fs.renameSync(copy, indexLock);
      fs.renameSync(indexLock, path.join(gitDir, 'index'));
    };
    const moveDev = (to, from) => tryGit(['update-ref', '-m', 'dots sync', 'refs/heads/dev', to, from]).status === 0;
    // Record the snapshot under the index lock: dev moves first, and the index
    // is installed only once dev points at the snapshot.
    const record = () => {
      if (!lockIndex()) return 'the Git index is locked (.git/index.lock)';
      let held = true;
      try {
        if (!moveDev(snapshot, dev)) return 'dev is locked or moved (refs/heads/dev)';
        try { commitIndex(); held = false; } catch (error) { moveDev(dev, snapshot); throw error; }
        return null;
      } finally { if (held) fs.rmSync(indexLock, { force: true }); }
    };
    if (base === dev && snapshot !== base) {
      const failure = record();
      if (!failure) dev = snapshot;
      else { lines.push(`NOT SAVED: ${failure}; local edits kept on disk, rerun`); snapshot = base; shared = 0; }
    }
    // Commits another worktree put on dev are dev material and win over local files.
    let local = base === dev ? snapshot : merge(snapshot, dev, 'local dev');

    // 5. Fetch; an unreachable origin means work continues offline.
    const fetch = () => {
      const both = ['+refs/heads/dev:refs/remotes/origin/dev', '+refs/heads/main:refs/remotes/origin/main'];
      if (tryGit(['fetch', '--no-tags', '--quiet', 'origin', ...both]).status === 0) return true;
      const listing = tryGit(['ls-remote', '--heads', 'origin']);
      if (listing.status !== 0) return false;
      const heads = new Set(listing.stdout.split('\n').map(line => line.split('\t')[1]).filter(Boolean));
      const wanted = both.filter(spec => heads.has(spec.slice(1).split(':')[0]));
      return !wanted.length || tryGit(['fetch', '--no-tags', '--quiet', 'origin', ...wanted]).status === 0;
    };
    let online = fetch();
    // A flagged existing commit blocks the push; local work still merges and applies.
    const published = () => ['refs/remotes/origin/dev', 'refs/remotes/origin/main'].filter(rev).map(ref => `^${ref}`);
    if (pushable && online && count([local, ...published()]) > 0) {
      // Every unpublished commit, not only the merged tip, must leave private files alone.
      let commit, leaked;
      for (const token of nul(git(['log', '--format=%x01%H', '--name-only', '-z', local, ...published()]))) {
        if (token.startsWith('\x01')) commit = token.slice(1);
        else if (privatePath(token.replace(/^\n/, ''))) leaked = [commit, token.replace(/^\n/, '')]; // oldest wins
      }
      const result = leaked ? { error: `commit ${short(leaked[0])} changes private setup file ${leaked[1]}; remove it from local history` } : scan([local, ...published()]);
      if (result.error) { pushable = false; lines.push(`NOT PUSHED: ${result.error}`); }
      else if (result.findings.length) {
        pushable = false;
        for (const f of result.findings) lines.push(`NOT PUSHED (gitleaks ${f.rule}): commit ${short(f.commit || '')} ${f.file}:${f.line}; remove it from local history`);
      }
    }

    // 6-8. Merge local with dev, then main; validate; push without force.
    // Every attempt starts again from local, so main still wins over a racing dev.
    let merged, pushed = false, valid = true, devNew = 0, mainNew = 0, rejected = false;
    const notices = lines.length;
    for (let attempt = 0; attempt <= 3; attempt++) {
      lines.length = notices; // only the last attempt's conflicts are reported
      const remoteDev = rev('refs/remotes/origin/dev'), remoteMain = rev('refs/remotes/origin/main');
      devNew = remoteDev ? count([remoteDev, `^${local}`]) : 0;
      merged = merge(local, remoteDev, 'shared dev');
      mainNew = remoteMain ? count([remoteMain, `^${merged}`]) : 0;
      merged = merge(merged, remoteMain, 'reviewed main');
      try {
        if (nul(git(['ls-tree', '-r', '-z', '--name-only', '--full-tree', merged])).some(privatePath)) throw new Error('it tracks private setup files');
        // A directory is probed as NAME/ so directory-only rules (/locks/) match it.
        const privateNames = fs.readdirSync(root, { withFileTypes: true }).map(e => e.name + (e.isDirectory() ? '/' : '')).filter(privatePath);
        validateIncomingIgnores(root, gitDir, merged, new Set(nul(git(['ls-tree', '-z', '--name-only', '--full-tree', merged]))), privateNames);
        validateIncoming(root, gitDir, merged, miseBin);
      } catch (error) {
        valid = false;
        lines.push(`INVALID merged config: ${firstLine(error.message)}; nothing pushed or applied`);
        break;
      }
      if (!online || !pushable || merged === remoteDev) break;
      if (tryGit(['push', '--quiet', 'origin', `${merged}:refs/heads/dev`]).status === 0) {
        pushed = true;
        tryGit(['update-ref', 'refs/remotes/origin/dev', merged]);
        break;
      }
      rejected = attempt === 3;
      if (!(online = fetch())) break;
    }
    if (rejected) lines.push('NOT PUSHED: origin/dev kept moving; retried next run');
    if (!online) lines.push(`OFFLINE: ${count(['refs/heads/dev', ...published()])} commits unpushed, retried next run`);

    // 9. Advance the live files from the snapshot to the merged commit. The
    // two-tree checkout refuses to overwrite a file edited meanwhile. Files
    // and dev move only while this run holds the real index lock, so the
    // index it installs always matches them.
    let applied = false;
    if (valid && (merged !== dev || merged !== snapshot)) {
      if (!lockIndex()) lines.push('NOT APPLIED: the Git index is locked (.git/index.lock); files not updated, rerun');
      else {
        let held = true;
        try {
          const checkout = index;
          git(['read-tree', snapshot], withIndex(checkout));
          tryGit(['update-index', '-q', '--refresh'], withIndex(checkout));
          if (tryGit(['read-tree', '-m', '-u', snapshot, merged], withIndex(checkout)).status === 0) {
            commitIndex(); held = false;
            if (moveDev(merged, dev)) { dev = merged; applied = true; }
            else lines.push('NOT RECORDED: dev moved during sync; files updated, rerun');
            const stat = tryGit(['diff', '--shortstat', snapshot, merged]).stdout?.trim();
            if (stat) lines.push(`changed on disk: ${stat}`);
          } else {
            const incoming = nul(git(['diff', '--name-only', '-z', snapshot, merged]));
            const dirty = new Set(nul(tryGit(['diff-files', '--name-only', '-z'], withIndex(checkout)).stdout || ''));
            const tracked = new Set(nul(git(['ls-tree', '-r', '-z', '--name-only', '--full-tree', snapshot])));
            const blocked = incoming.filter(name => dirty.has(name) || (!tracked.has(name) && fs.existsSync(path.join(root, name))));
            for (const name of blocked.length ? blocked : ['(unknown path)']) lines.push(`LATE EDIT: ${name} not updated; rerun`);
          }
        } finally { if (held) fs.rmSync(indexLock, { force: true }); }
      }
    } else if (valid) applied = true;
    if (applied) {
      const apply = raw(miseBin, ['-C', root, 'bootstrap', 'dotfiles', 'apply', '--yes']);
      if (apply.error || apply.status !== 0) lines.push(`APPLY FAILED: mise bootstrap dotfiles apply (exit ${apply.status ?? 'error'})`);
    }

    const files = `${shared} file${shared === 1 ? '' : 's'}`;
    const parts = [
      !shared ? 'no local changes'
        : pushed ? `shared ${files}`
        : tryGit(['merge-base', '--is-ancestor', snapshot, 'refs/heads/dev']).status === 0 ? `saved ${files} locally`
        : `kept ${files} on disk`,
      !online ? 'offline' : `${applied ? 'pulled' : 'fetched'} dev +${devNew}, main +${mainNew}${applied ? '' : ' (not applied)'}`,
      pushed ? `pushed ${merged.slice(0, 7)}` : (online && valid && pushable && merged === rev('refs/remotes/origin/dev') ? 'nothing to push' : 'not pushed'),
    ];
    return { header: `dots sync: ${parts.join(' · ')}`, lines, before: start, after: dev };
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
}
