#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const scope = {'com.ezra.dottie.whatsapp.collector': 'collector', 'com.ezra.dottie.whatsapp.read-bridge': 'whatsapp', 'com.ezra.dottie.mail.bridge': 'mail', 'com.ezra.dottie.reminders.bridge': 'icloud'};
const fail = message => { throw new Error(message); };
const xml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const quote = value => /^[A-Za-z0-9_./:@=-]+$/.test(value) ? value : `'${value.replaceAll("'", "'\\''")}'`;
const canonical = value => JSON.stringify(Array.isArray(value) ? value.map(v => JSON.parse(canonical(v))) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, JSON.parse(canonical(value[k]))])) : value);
const defaultRun = (bin, args, options = {}) => {
  try { return execFileSync(bin, args, {encoding: 'utf8', input: options.input, env: {...process.env, ...options.env}, stdio: ['pipe', options.capture ? 'pipe' : 'ignore', 'ignore']}) || ''; }
  catch { fail('A concierge command failed. Private output withheld.'); }
};

export function validate(config, hostname = os.hostname(), platform = process.platform) {
  if (config.schemaVersion !== 1 || config.expectedHost !== hostname || platform !== 'darwin') fail('Runtime must be the explicitly configured macOS NAS host.');
  for (const key of ['projectDir', 'node', 'uv', 'python', 'mailPython', 'tunnelClient', 'wacli']) {
    if (typeof config[key] !== 'string' || !/^(~\/|\/)/.test(config[key]) || config[key].includes('\n')) fail('Explicit binary and project paths required.');
  }
  if (config.remindersEdits !== undefined && typeof config.remindersEdits !== 'boolean') fail('Reminders edits must be an explicit boolean.');
  if (config.pythonVersion !== '3.13.15' || config.mailPythonVersion !== '3.14.7') fail('Pinned iCloud and Mail Python versions required.');
  if (!Array.isArray(config.services) || config.services.length !== 4) fail('Exactly four controlled services required.');
  const labels = new Set(), profiles = new Set();
  for (const s of config.services) {
    if (!Object.hasOwn(scope, s.label) || labels.has(s.label)) fail('Invalid or duplicate controlled label.');
    labels.add(s.label);
    if (scope[s.label] === 'collector' ? s.kind !== 'wacli-collector' : s.kind !== 'tunnel' || s.backend !== scope[s.label]) fail('Service backend differs from controlled scope.');
    if (s.kind === 'tunnel') {
      if (!/^[a-z][a-z0-9-]+$/.test(s.profile) || profiles.has(s.profile) || !/^tunnel_[0-9a-f]{32}$/.test(s.tunnelID)) fail('Invalid profile or tunnel ID reference.');
      profiles.add(s.profile);
      if (s.healthViaEnvironment !== undefined && typeof s.healthViaEnvironment !== 'boolean') fail('Invalid health environment policy.');
    }
    const keys = s.kind === 'wacli-collector' ? ['store'] : ['profileDir', 'keyFile', ...(s.healthViaEnvironment ? ['healthURLFile'] : []), ...(s.backend === 'whatsapp' ? ['facadeConfig'] : s.backend === 'mail' ? ['accountsFile', 'mailStateDir'] : [])];
    for (const key of keys) if (typeof s[key] !== 'string' || !s[key].startsWith('~/') || s[key].includes('\n')) fail('Private paths must be home-relative references.');
    if (s.healthViaEnvironment && s.backend === 'whatsapp') fail('WhatsApp health environment is unsupported.');
    if (s.readinessFiles !== undefined && (!Array.isArray(s.readinessFiles) || s.readinessFiles.some(v => typeof v !== 'string' || !v.startsWith('~/')))) fail('Invalid readiness references.');
  }
  return config;
}

export function createOperations(config, options = {}) {
  const home = options.home || os.homedir(), uid = options.uid ?? process.getuid();
  const run = options.run || defaultRun, expand = value => {
    if (!value.startsWith('~/')) return value;
    const expanded = path.resolve(home, value.slice(2));
    if (!expanded.startsWith(home + path.sep)) fail('Home-relative path escapes private home.');
    return expanded;
  };
  const project = expand(config.projectDir), stageDir = path.join(home, '.local/state/dottie-concierge-stage');
  function privatePath(target, directory = false, publicDefinition = false) {
    let current = target;
    while (current !== path.dirname(current)) {
      if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) fail('Refusing a symlinked private path.');
      current = path.dirname(current);
    }
    if (!fs.existsSync(target)) return false;
    const st = fs.statSync(target);
    if (st.uid !== uid || (st.mode & (publicDefinition ? 0o022 : 0o077)) || (directory ? !st.isDirectory() : !st.isFile())) fail('Private path ownership, type or mode is unsafe.');
    return true;
  }
  const mcpArgv = s => s.backend === 'whatsapp'
    ? [expand(config.node), path.join(project, 'integrations/whatsapp-read/wacli/mcp.mjs'), expand(s.facadeConfig)]
    : s.backend === 'mail' ? [expand(config.mailPython), path.join(project, 'integrations/mail-read/maintained_mcp.py'), '--config', expand(s.accountsFile), '--state-dir', expand(s.mailStateDir)]
    : [expand(config.python), path.join(project, 'integrations/icloud-pilot/mcp_stdio.py'), '--with-create', '--with-dav', ...(config.remindersEdits === true ? ['--with-edit'] : [])];
  const mcpCommand = s => mcpArgv(s).map(quote).join(' ');
  const definition = s => ({Label: s.label, ProgramArguments: s.kind === 'tunnel'
    ? [expand(config.tunnelClient), 'run', '--profile', s.profile, '--profile-dir', expand(s.profileDir), '--health.listen-addr', '127.0.0.1:0']
    : ['/usr/bin/env', '-u', 'WACLI_READONLY', '-u', 'WACLI_STORE_DIR', '-u', 'WACLI_SYNC_MAX_MESSAGES', '-u', 'WACLI_SYNC_MAX_DB_SIZE', expand(config.wacli), '--store', expand(s.store), 'sync', '--follow', '--presence-mode', 'quiet', '--download-media=false', '--max-messages', '0', '--max-db-size', '0', '--max-reconnect', '5m'],
    WorkingDirectory: project, ...(s.healthViaEnvironment ? {EnvironmentVariables: {HEALTH_URL_FILE: expand(s.healthURLFile)}} : {}),
    RunAtLoad: true, KeepAlive: true, ThrottleInterval: 30, Umask: 63, ProcessType: 'Background', StandardOutPath: '/dev/null', StandardErrorPath: '/dev/null'});
  function render(value) {
    if (Array.isArray(value)) return `<array>${value.map(render).join('')}</array>`;
    if (typeof value === 'object') return `<dict>${Object.entries(value).map(([k,v]) => `<key>${xml(k)}</key>${render(v)}`).join('')}</dict>`;
    return typeof value === 'boolean' ? `<${value}/>` : typeof value === 'number' ? `<integer>${value}</integer>` : `<string>${xml(value)}</string>`;
  }
  const plist = s => `<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">${render(definition(s))}</plist>\n`;
  const profileFile = s => path.join(expand(s.profileDir), `${s.profile}.yaml`);
  function profileMatches(s) {
    if (!privatePath(profileFile(s))) return null;
    // Accept only scalar fields emitted by the official local stdio sample.
    const text = fs.readFileSync(profileFile(s), 'utf8');
    function scalar(section, key, indent) {
      const sections = [...text.matchAll(new RegExp(`^${section}:[ \t]*(?:#.*)?$`, 'gm'))];
      if (sections.length !== 1) return null;
      const tail = text.slice(sections[0].index + sections[0][0].length);
      const boundary = tail.search(/^[^\s#]/m);
      const body = boundary < 0 ? tail : tail.slice(0, boundary);
      const matches = [...body.matchAll(new RegExp(`^ {${indent}}${key}:[ \t]*(.*?)[ \t]*$`, 'gm'))];
      if (matches.length !== 1) return null;
      const v = matches[0][1];
      if (v.startsWith('"')) { try { return JSON.parse(v); } catch { return null; } }
      if (v.startsWith("'")) return v.endsWith("'") ? v.slice(1, -1).replaceAll("''", "'") : null;
      return v.replace(/\s+#.*$/, '');
    }
    return scalar('control_plane', 'tunnel_id', 2) === s.tunnelID && scalar('mcp', 'command', 6) === mcpCommand(s) && scalar('control_plane', 'api_key', 2) === `file:${expand(s.keyFile)}`;
  }
  function plistMatches(file, s) {
    if (!fs.existsSync(file)) return null;
    privatePath(file, false, !file.startsWith(stageDir + path.sep));
    const parsed = JSON.parse(run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', file], {capture: true}));
    return canonical(parsed) === canonical(definition(s));
  }
  function status(s) {
    try {
      const raw = run('/bin/launchctl', ['print', `gui/${uid}/${s.label}`], {capture: true});
      return {loaded: true, running: /state = running/.test(raw), pid: Number(raw.match(/\bpid = (\d+)/)?.[1]) || null};
    } catch { return {loaded: false, running: false, pid: null}; }
  }
  const files = config.services.map(s => ({service: s, staged: path.join(stageDir, `${s.label}.plist`), installed: path.join(home, 'Library/LaunchAgents', `${s.label}.plist`)}));
  function preflight() {
    privatePath(stageDir, true);
    privatePath(path.join(home, 'Library/LaunchAgents'), true, true);
    const missing = [];
    for (const f of files) {
      if (plistMatches(f.staged, f.service) === false || plistMatches(f.installed, f.service) === false) fail('Existing LaunchAgent definition differs.');
      const s = f.service;
      if (s.kind === 'tunnel') {
        privatePath(expand(s.profileDir), true);
        if (profileMatches(s) === false) fail('Existing profile binding differs.');
        for (const key of ['keyFile', ...(s.backend === 'whatsapp' ? ['facadeConfig'] : s.backend === 'mail' ? ['accountsFile'] : [])]) if (!privatePath(expand(s[key]), false, key === 'accountsFile')) missing.push(expand(s[key]));
        for (const key of ['facadeConfig', 'accountsFile']) if (s[key] && fs.existsSync(expand(s[key]))) JSON.parse(fs.readFileSync(expand(s[key]), 'utf8'));
        if (s.healthURLFile) privatePath(expand(s.healthURLFile));
        if (s.mailStateDir) privatePath(expand(s.mailStateDir), true);
      } else privatePath(expand(s.store), true);
      for (const reference of s.readinessFiles || []) if (!privatePath(expand(reference))) missing.push(expand(reference));
    }
    return [...new Set(missing)];
  }
  function stage() {
    preflight();
    fs.mkdirSync(stageDir, {recursive: true, mode: 0o700});
    for (const f of files) if (!fs.existsSync(f.staged)) fs.writeFileSync(f.staged, plist(f.service), {mode: 0o600, flag: 'wx'});
    return files.map(f => f.staged);
  }
  function dependencies(checkOnly = false) {
    for (const key of ['node', 'uv', 'tunnelClient', 'wacli']) fs.accessSync(expand(config[key]), fs.constants.X_OK);
    for (const name of ['icloud-pilot', 'icloud-dav']) {
      const dir = path.join(project, 'integrations', name);
      fs.accessSync(path.join(dir, 'uv.lock'));
      fs.accessSync(path.join(dir, 'pyproject.toml'));
    }
    if (expand(config.python) !== path.join(project, 'integrations/icloud-pilot/.venv/bin/python')) fail('iCloud Python must use its project environment.');
    if (![path.join(project, 'integrations/mail-read/.venv/bin/python'), path.join(home, '.local/share/dottie-mail/venv/bin/python')].includes(expand(config.mailPython))) fail('Mail Python must use an approved user environment.');
    const lock = path.join(project, 'integrations/mail-read/requirements.lock');
    const lockText = fs.readFileSync(lock, 'utf8');
    if (!/IMAPClient==4\.1\.0\s+\\?\s*--hash=sha256:[a-f0-9]{64}/i.test(lockText)) fail('Mail requires the hash-pinned IMAPClient lock.');
    if (checkOnly) return;
    for (const name of ['icloud-pilot', 'icloud-dav']) {
      const dir = path.join(project, 'integrations', name);
      run(expand(config.uv), ['sync', '--locked', '--project', dir], {env: {UV_PROJECT_ENVIRONMENT: path.join(dir, '.venv'), UV_PYTHON_DOWNLOADS: 'automatic', UV_PYTHON: config.pythonVersion}});
    }
    if (!fs.existsSync(expand(config.mailPython))) run(expand(config.uv), ['venv', '--python', config.mailPythonVersion, path.dirname(path.dirname(expand(config.mailPython)))], {env: {UV_PYTHON_DOWNLOADS: 'automatic'}});
    run(expand(config.uv), ['pip', 'install', '--require-hashes', '--only-binary=:all:', '--python', expand(config.mailPython), '-r', lock]);
  }
  function rebuild() {
    const missing = preflight();
    if (missing.length) return {action: 'rebuild', blocked: 'missing-auth', readinessFiles: missing};
    // Check all source contracts before the first mutation.
    for (const s of config.services.filter(s => s.kind === 'tunnel')) fs.accessSync(mcpArgv(s)[1]);
    dependencies(true);
    stage();
    dependencies();
    for (const s of config.services.filter(s => s.kind === 'tunnel')) if (profileMatches(s) === null) {
      fs.mkdirSync(expand(s.profileDir), {recursive: true, mode: 0o700});
      run(expand(config.tunnelClient), ['init', '--sample', 'sample_mcp_stdio_local', '--profile', s.profile, '--profile-dir', expand(s.profileDir), '--tunnel-id', s.tunnelID, '--control-plane-api-key-ref', `file:${expand(s.keyFile)}`, '--mcp-command', mcpCommand(s), '--health-listen-addr', '127.0.0.1:0']);
      if (profileMatches(s) !== true) fail('Initialized profile binding did not match.');
    }
    fs.mkdirSync(path.join(home, 'Library/LaunchAgents'), {recursive: true, mode: 0o700});
    for (const f of files) if (!fs.existsSync(f.installed)) fs.copyFileSync(f.staged, f.installed, fs.constants.COPYFILE_EXCL);
    const skipped = [];
    for (const f of files) {
      if (status(f.service).loaded) continue;
      if (f.service.kind === 'wacli-collector') {
        let pids = '';
        try { pids = run('/usr/bin/pgrep', ['-x', 'wacli'], {capture: true}); } catch {}
        if (/^\d+$/m.test(pids)) { skipped.push({label: f.service.label, reason: 'existing-collector'}); continue; }
      }
      run('/bin/launchctl', ['bootstrap', `gui/${uid}`, f.installed]);
    }
    return {action: 'rebuild', serviceFiles: files.map(f => f.installed), skipped, cloudInvocationVerified: false};
  }
  function version(key) {
    try { return run(expand(config[key]), ['--version'], {capture: true}).match(/(?:^|\s)v?(\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?)(?=\s|$)/)?.[1] || null; } catch { return null; }
  }
  function doctor() {
    const checks = ['projectDir', 'node', 'uv', 'python', 'mailPython', 'tunnelClient', 'wacli'].map(key => ({check: key, path: expand(config[key]), exists: fs.existsSync(expand(config[key])), ...(key === 'projectDir' ? {} : {version: version(key)})}));
    for (const f of files) checks.push({check: f.service.label, ...status(f.service), plistMatches: plistMatches(f.installed, f.service), ...(f.service.kind === 'tunnel' ? {profilePath: profileFile(f.service), profileMatches: profileMatches(f.service), keyReferencePresent: privatePath(expand(f.service.keyFile))} : {})});
    return {action: 'doctor', checks, cloudInvocationVerified: false, rebootBeforeLoginVerified: false};
  }
  return {privatePath, mcpArgv, mcpCommand, definition, plist, profileFile, profileMatches, plistMatches, preflight, stage, rebuild, doctor, serviceFiles: files.map(f => f.staged)};
}

export function plist(config, service) { return createOperations(config).plist(service); }
export async function main(argv = process.argv.slice(2)) {
  const [action = 'plan', file = path.join(os.homedir(), '.config/dottie/runtime.json')] = argv;
  if (action === 'example' && argv.length === 1) { process.stdout.write(fs.readFileSync(path.join(root, 'resources/concierge/runtime.example.json'))); return; }
  if (!['plan', 'stage', 'doctor', 'rebuild'].includes(action) || argv.length > 2) fail('Use plan|stage|doctor|rebuild [private runtime.json], or example.');
  const configFile = file.startsWith('~/') ? path.join(os.homedir(), file.slice(2)) : file;
  const config = validate(JSON.parse(fs.readFileSync(configFile, 'utf8'))), ops = createOperations(config);
  ops.privatePath(configFile);
  if ((fs.statSync(configFile).mode & 0o777) !== 0o600) fail('Runtime configuration must have mode 600.');
  const result = action === 'doctor' ? ops.doctor() : action === 'rebuild' ? ops.rebuild() : {action, serviceFiles: action === 'stage' ? ops.stage() : ops.serviceFiles, readinessFiles: ops.preflight(), installsOrStartsServices: false};
  console.log(JSON.stringify(result, null, 2));
}
if (process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(() => { console.error('Concierge NAS operation failed; check host, references, prerequisites and definition drift. Private details withheld.'); process.exitCode = 1; });
