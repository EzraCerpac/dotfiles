#!/usr/bin/env node
// The final native bootstrap task: private recovery precedes enrollment.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { unlockBundle, applyPrivateFiles } from './bundle.mjs';
import { dotsVar, dotsList } from '../lib/source-repo.mjs';

class Deferred extends Error {}

// The configuration hooks in DIRECTORY that apply to PROFILE, in name order,
// as [{ label, path }]. lib/dots-hooks owns the naming contract (shared with
// the updater); an invalid hook name throws its message.
function listHooks(dotsHome, directory, profile, profiles) {
  const result = spawnSync('bash', [path.join(dotsHome, 'lib/dots-hooks'), directory, profile, ...profiles], { encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error(String(result.stderr || result.error?.message || 'could not list hooks').trim());
  return result.stdout.split('\n').filter(Boolean).map(line => {
    const tab = line.indexOf('\t');
    return { label: line.slice(0, tab), path: line.slice(tab + 1) };
  });
}

// Hook exit statuses: 0 completed, 3 deferred (needs attention), 4 skipped.
export const hookStatus = code => code === 0 ? 'completed' : code === 3 ? 'deferred' : code === 4 ? 'skipped' : 'failed';

export function complete({ root, dotsHome, home, miseBin, env = process.env, run = spawnSync }) {
  const report = [];
  const local = path.join(root, 'config.local.toml');
  const childEnv = { ...env, HOME: home, MISE_CONFIG_DIR: root, DOTS_ROOT: root, ...(dotsHome ? { DOTS_HOME: dotsHome } : {}) };
  let tailscaleAuthKey = childEnv.SETUP_TAILSCALE_AUTH_KEY;
  delete childEnv.SETUP_TAILSCALE_AUTH_KEY;
  const invoke = (command, args, capture = false) => run(command, args, {
    cwd: root, env: childEnv, encoding: 'utf8',
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
  });
  const mise = (args, capture = false) => invoke(miseBin, ['-C', root, ...args], capture);
  const readLocal = (key) => {
    const result = mise(['config', 'get', '--file', local, key], true);
    return result.status === 0 ? result.stdout.trim() : '';
  };
  const setLocal = (key, value, type) => {
    const args = ['config', 'set', '--file', local];
    if (type) args.push('--type', type);
    args.push(key, value);
    if (mise(args, true).status !== 0) throw new Error(`Could not configure ${key}`);
    fs.chmodSync(local, 0o600);
  };
  const record = (stage, status, detail) => {
    report.push({ stage, status, detail });
    console.log(`${status}: ${stage}${detail ? ` — ${detail}` : ''}`);
  };
  const stage = (label, fn) => {
    try {
      const detail = fn();
      record(label, 'completed', detail || '');
      return true;
    } catch (error) {
      record(label, error instanceof Deferred ? 'deferred' : 'failed', error.message);
      return false;
    }
  };
  const requireCommand = (args, message) => {
    const result = mise(args);
    if (result.status !== 0) throw new Error(message);
  };
  // Configuration scripts are named from the setup root; manager scripts are
  // absolute paths under DOTS_HOME.
  const scriptResult = (name, args = []) => mise(
    ['exec', '--', 'bash', path.resolve(root, name), ...args]);
  const script = (name, args = []) => {
    const result = scriptResult(name, args);
    if (result.status !== 0) throw new Error(`${path.isAbsolute(name) ? path.relative(dotsHome, name) : name} needs attention; rerun after resolving its message`);
    return result;
  };
  const manager = (name) => path.join(dotsHome, name);
  const setting = (name) => dotsVar(root, name, { miseBin, run });
  // Private settings history lives in the GitHub repository [vars] dots_state_repo.
  const defaultHistoryOrigin = () => `https://github.com/${setting('dots_state_repo')}.git`;
  const role = childEnv.SETUP_PROFILE || readLocal('env.SETUP_PROFILE');
  const machineId = readLocal('env.SETUP_MACHINE_ID') || childEnv.SETUP_MACHINE_ID;
  if (!dotsList(setting('dots_profiles')).includes(role) || !/^[a-z0-9][a-z0-9-]*$/.test(machineId || '')) {
    throw new Error('Persist the role and machine identity before completing bootstrap');
  }
  Object.assign(childEnv, { SETUP_PROFILE: role, DOTS_PROFILE: role, SETUP_MACHINE_ID: machineId });
  const expand = (value) => value.startsWith('~/') ? path.join(home, value.slice(2)) : path.resolve(value);
  const recoveryIdentity = expand(childEnv.SETUP_AGE_IDENTITY || readLocal('env.SETUP_AGE_IDENTITY') || path.join(home, '.config/age/keys.txt'));
  const persistedBundleIdentity = readLocal('vars.bootstrap_bundle_identity');
  const explicitBundle = childEnv.SETUP_BOOTSTRAP_BUNDLE || '';
  const explicitBundleIdentity = childEnv.SETUP_BUNDLE_IDENTITY || '';
  // Workstation keeps the historical implicit bundle. NAS only considers the
  // bundle when the caller or an earlier explicit enrollment selected it;
  // otherwise a workstation-only bundle cannot block NAS history recovery.
  const bundleRequested = role === 'workstation' || Boolean(explicitBundle || persistedBundleIdentity || explicitBundleIdentity);
  const bundleIdentityValue = explicitBundleIdentity || persistedBundleIdentity || (bundleRequested ? recoveryIdentity : '');
  const bundleIdentity = bundleIdentityValue ? expand(bundleIdentityValue) : '';
  const bundleValue = explicitBundle || (bundleRequested ? path.join(root, 'encrypted/bootstrap.json.age') : '');
  const bundle = bundleValue ? expand(bundleValue) : '';
  let secrets = {};
  let recipients = [];
  let privateReady = true;
  if (fs.existsSync(bundle) && fs.existsSync(bundleIdentity)) {
    privateReady = stage('Unlock private inputs', () => {
      const unlocked = unlockBundle(bundle, bundleIdentity, { ageBin: childEnv.SETUP_AGE_BIN || 'age' });
      // History enrollment selects a host key later. Keep the bundle's
      // external decryption identity independent across repeated bootstraps.
      setLocal('vars.bootstrap_bundle_identity', bundleIdentity);
      secrets = unlocked.secrets;
      recipients = unlocked.recipients || [];
      if (secrets.github_token) {
        childEnv.GH_TOKEN = secrets.github_token;
        // Git does not read GH_TOKEN itself. Scope its credential helper to
        // GitHub for these child processes without persisting a credential.
        const count = Number(childEnv.GIT_CONFIG_COUNT || 0);
        if (!Number.isSafeInteger(count) || count < 0) throw new Error('Invalid inherited Git configuration count');
        for (const [offset, helper] of ['', '!gh auth git-credential'].entries()) {
          childEnv[`GIT_CONFIG_KEY_${count + offset}`] = 'credential.https://github.com.helper';
          childEnv[`GIT_CONFIG_VALUE_${count + offset}`] = helper;
        }
        childEnv.GIT_CONFIG_COUNT = String(count + 2);
      }
      if (secrets.tailscale_auth_key) tailscaleAuthKey = secrets.tailscale_auth_key;
    });
  } else if (bundleRequested) {
    record('Private inputs', 'deferred', 'Supply the encrypted bundle and an external age identity with dots bootstrap --bundle FILE --identity FILE');
    // An explicit or persisted bundle selection is part of this run's
    // contract. A missing implicit workstation bundle remains optional.
    if (childEnv.SETUP_BOOTSTRAP_BUNDLE || childEnv.SETUP_BUNDLE_IDENTITY || persistedBundleIdentity || fs.existsSync(bundle)) privateReady = false;
  } else {
    record('Private inputs', 'completed', 'No bootstrap bundle requested for this NAS host');
  }

  stage('Source repository', () => requireCommand(
    ['exec', '--', 'node', manager('lib/source-repo.mjs'), 'init', root],
    'Source repository initialization needs attention'));

  const restoreId = childEnv.SETUP_RESTORE_MACHINE_ID;
  let historyReady = privateReady;
  if (restoreId) {
    historyReady = privateReady && stage('Restore private settings', () => {
      if (restoreId !== machineId) throw new Error('Restore identity does not match the selected host');
      if (!fs.existsSync(recoveryIdentity)) throw new Error('Restoration requires the existing recovery identity');
      const origin = readLocal('env.SETUP_HISTORY_ORIGIN') || defaultHistoryOrigin();
      setLocal('env.SETUP_HISTORY_ORIGIN', origin);
      setLocal('settings.age.identity_files', recoveryIdentity, 'list');
      Object.assign(childEnv, { SETUP_HISTORY_ORIGIN: origin, SETUP_AGE_IDENTITY: recoveryIdentity });
      // The restore task archives an unconnected local store before replacing it.
      // It fetches and restores; it never publishes defaults.
      script(manager('tasks/restore'), ['--initialize-history']);
    });
  }
  if (privateReady && historyReady && role === 'workstation' && Object.keys(secrets).length) {
    privateReady = stage('Private configuration', () => applyPrivateFiles(secrets, { home, miseBin, root }));
  }
  stage('Installer exceptions', () => script(manager('tasks/exceptions')));

  // Configuration hooks (dots/hooks/bootstrap.d) run after installer
  // exceptions, in name order, each as its own stage. They learn whether
  // private recovery is complete and whether this run restored settings.
  const hookEnv = {
    ...childEnv,
    DOTS_PRIVATE_READY: privateReady && historyReady ? '1' : '0',
    DOTS_RESTORED: restoreId ? '1' : '0',
  };
  let hooks = [];
  try { hooks = listHooks(dotsHome, path.join(root, 'dots/hooks/bootstrap.d'), role, dotsList(setting('dots_profiles'))); }
  catch (error) { record('Bootstrap hooks', 'failed', error.message); }
  for (const hook of hooks) {
    const result = run(miseBin, ['-C', root, 'exec', '--', hook.path], { cwd: root, env: hookEnv, encoding: 'utf8', stdio: 'inherit' });
    const status = result.error ? 'failed' : hookStatus(result.status);
    record(hook.label, status,
      status === 'failed' ? `dots/hooks/bootstrap.d/${path.basename(hook.path)} needs attention; rerun after resolving its message`
        : status === 'deferred' ? 'See its message above; rerun dots bootstrap after resolving it' : '');
  }
  stage('Atuin', () => {
    const result = mise(['exec', '--', 'uv', 'run', '--no-project', 'python', manager('bootstrap/atuin.py'), 'enroll', '--root', root, '--identity', recoveryIdentity]);
    if (result.status === 3) throw new Deferred('Atuin enrollment needs credentials or account approval; rerun dots bootstrap after the displayed step');
    if (result.status !== 0) throw new Error('Atuin enrollment failed; inspect the reported recovery step');
  });

  if (privateReady && historyReady && fs.existsSync(recoveryIdentity)) {
    historyReady = stage('Encrypted local history', () => {
      const hostIdentity = path.join(home, '.config/age/keys.txt');
      if (!fs.existsSync(hostIdentity)) {
        fs.mkdirSync(path.dirname(hostIdentity), { recursive: true, mode: 0o700 });
        // Each new host gets its own identity; another machine's private key is never copied.
        const generated = invoke('age-keygen', [], true);
        if (generated.status !== 0 || !generated.stdout.includes('AGE-SECRET-KEY-')) throw new Error('Could not generate this host’s age identity');
        fs.writeFileSync(hostIdentity, generated.stdout, { flag: 'wx', mode: 0o600 });
      }
      const publicKey = invoke('age-keygen', ['-y', fs.existsSync(bundle) ? bundleIdentity : recoveryIdentity], true);
      if (publicKey.status !== 0) throw new Error('Could not read the recovery public recipient');
      recipients = [...new Set([...recipients, ...publicKey.stdout.trim().split(/\s+/)])];
      const origin = readLocal('env.SETUP_HISTORY_ORIGIN') || defaultHistoryOrigin();
      const args = ['--profile', role, '--machine-id', machineId, '--identity', hostIdentity, '--origin', origin, '--refresh'];
      for (const recipient of recipients) args.push('--recipient', recipient);
      script(manager('bootstrap/enroll-history'), args);
      // Configuration of the origin remains local. First publication remains dots backup.
      setLocal('history.origin.url', origin);
      setLocal('settings.history.sync', 'manual');
      setLocal('bootstrap.services.mise-history.builtin', 'history-watch');
      requireCommand(['bootstrap', 'services', 'apply', '--yes'], 'Could not activate the native history service');
      const state = mise(['dot', 'status', '--json'], true);
      if (state.status !== 0) throw new Error('Could not verify history watcher state');
      if (JSON.parse(state.stdout).history?.watcher !== 'running') {
        throw new Deferred('History enrolled; no running user watcher. Use dots backup for explicit snapshots on this host');
      }
      return 'Local snapshots enabled; network publication remains explicit';
    });
  } else {
    record('Encrypted local history', 'deferred', 'Complete private recovery and provide an age identity before enrollment');
  }
  const tailscaleEnv = { ...childEnv };
  if (tailscaleAuthKey) tailscaleEnv.SETUP_TAILSCALE_AUTH_KEY = tailscaleAuthKey;
  const tailscale = run('bash', [manager('bootstrap/tailnet')], {
    cwd: root, env: tailscaleEnv, encoding: 'utf8', stdio: 'inherit',
  });
  const noLinuxSupervisor = process.platform === 'linux' && !fs.existsSync('/run/systemd/system');
  record('Tailscale', tailscale.status === 0 ? 'completed' : tailscale.status === 3 || (tailscale.status === 23 && noLinuxSupervisor) ? 'deferred' : 'failed',
    tailscale.status === 0 ? '' : 'See the enrollment message above; rerun dots bootstrap');

  const reportDir = path.join(childEnv.XDG_STATE_HOME || path.join(home, '.local/state'), 'mise/bootstrap');
  fs.mkdirSync(reportDir, { recursive: true, mode: 0o700 });
  const reportPath = path.join(reportDir, 'last-run.json');
  const temporary = `${reportPath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify({ machineId, profile: role, completedAt: new Date().toISOString(), stages: report }, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
  fs.renameSync(temporary, reportPath);
  const skipped = report.filter(r => r.status === 'skipped').length;
  console.log(`\nBootstrap result: ${report.filter(r => r.status === 'completed').length} completed, ${report.filter(r => r.status === 'deferred').length} deferred, ${report.filter(r => r.status === 'failed').length} failed${skipped ? `, ${skipped} skipped` : ''}.`);
  return report.some(r => r.status === 'failed') ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    // dots passes the configuration root and its own home; never guess them here.
    const root = process.env.DOTS_ROOT;
    const dotsHome = process.env.DOTS_HOME;
    if (!root || !dotsHome) throw new Error('run through dots internal complete (DOTS_ROOT and DOTS_HOME are required)');
    const standalone = path.join(os.homedir(), '.local/bin/mise');
    const miseBin = process.env.SETUP_MISE_BIN || process.env.MISE_BIN || (fs.existsSync(standalone) ? standalone : 'mise');
    process.exitCode = complete({ root, dotsHome, home: process.env.HOME || os.homedir(), miseBin });
  } catch (error) {
    console.error(`bootstrap: ${error.message}`);
    process.exitCode = 1;
  }
}
