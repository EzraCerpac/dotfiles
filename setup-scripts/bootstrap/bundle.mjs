#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const names = new Set(['wakatime_config', 'himalaya_config', 'tailscale_auth_key', 'github_token']);
const files = { wakatime_config: '.wakatime.cfg', himalaya_config: '.config/himalaya/config.toml' };
const quote = JSON.stringify;
const inputEnv = () => {
  const env = { ...process.env };
  delete env.SETUP_TAILSCALE_AUTH_KEY;
  return env;
};

export function validateBundle(value) {
  if (!value || value.version !== 1 || !value.secrets || typeof value.secrets !== 'object' || Array.isArray(value.secrets)) throw new Error('Expected a version 1 bootstrap bundle with a secrets object');
  if (Object.keys(value).some(k => !['version', 'secrets', 'recipients'].includes(k))) throw new Error('Unexpected bootstrap bundle field');
  for (const [name, secret] of Object.entries(value.secrets)) {
    if (!names.has(name) || typeof secret !== 'string' || !secret.length || secret.includes('\0')) throw new Error('Unsupported or invalid bootstrap secret');
  }
  const recipients = value.recipients || [];
  if (!Array.isArray(recipients) || recipients.some(r => typeof r !== 'string' || !/^age1[0-9a-z]+$/.test(r))) throw new Error('Invalid public recovery recipients');
  return { version: 1, secrets: value.secrets, recipients: [...new Set(recipients)] };
}

export function unlockBundle(bundle, identity, { ageBin = 'age' } = {}) {
  const result = spawnSync(ageBin, ['--decrypt', '--identity', identity, bundle], { env: inputEnv(), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  if (result.status !== 0) throw new Error('Cannot decrypt bootstrap bundle; check the bundle and age identity');
  let document;
  try { document = JSON.parse(result.stdout); } catch { throw new Error('Decrypted bootstrap bundle is not valid JSON'); }
  return validateBundle(document);
}

export function writeBundle({ inputPath, document, outputPath, recipient, ageBin = 'age' }) {
  let value = document;
  if (!value) {
    try { value = JSON.parse(fs.readFileSync(inputPath, 'utf8')); } catch { throw new Error('Cannot read the private bootstrap JSON input'); }
  }
  value = validateBundle(value);
  const recipients = Array.isArray(recipient) ? recipient : [recipient];
  if (!recipients.length || recipients.some(r => typeof r !== 'string' || !/^age1[0-9a-z]+$/.test(r))) throw new Error('Supply at least one age public recipient');
  const args = recipients.flatMap(r => ['--recipient', r]);
  const encrypted = spawnSync(ageBin, args, { env: inputEnv(), input: JSON.stringify(value), maxBuffer: 4 * 1024 * 1024 });
  if (encrypted.status !== 0 || !encrypted.stdout?.length) throw new Error('Could not encrypt the bootstrap bundle');
  if (fs.existsSync(outputPath)) throw new Error('Output already exists; use a new filename and review before replacing the bundle');
  fs.writeFileSync(outputPath, encrypted.stdout, { flag: 'wx', mode: 0o600 });
}

export function applyPrivateFiles(secrets, { home, miseBin, root }) {
  const selected = Object.entries(files).filter(([key]) => secrets[key] !== undefined);
  if (!selected.length) return 'No private file inputs supplied';
  const actualHome = fs.realpathSync(home);
  // Inspect every destination before invoking native apply. App-written changes win
  // until the user explicitly reconciles them with the bundle.
  for (const [key, relative] of selected) {
    const target = path.join(actualHome, relative);
    let cursor = target;
    while (cursor !== actualHome) {
      try {
        const info = fs.lstatSync(cursor);
        if (info.isSymbolicLink()) throw new Error('Private configuration contains a symlink; reconcile its owner first');
        if (cursor === target && !info.isFile()) throw new Error('Private destination is not a regular file');
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
      cursor = path.dirname(cursor);
    }
    if (fs.existsSync(target) && fs.readFileSync(target, 'utf8') !== secrets[key]) throw new Error(`Private configuration differs: ${relative}; reconcile it before applying the bundle`);
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'dots-private-'));
  fs.chmodSync(temp, 0o700);
  try {
    const env = { ...inputEnv(), HOME: actualHome, MISE_CONFIG_DIR: temp, MISE_ENV: '', MISE_TRUSTED_CONFIG_PATHS: temp,
      MISE_STATE_DIR: path.join(temp, 'state'), MISE_CACHE_DIR: path.join(temp, 'cache') };
    delete env.MISE_GLOBAL_CONFIG_FILE;
    for (const name of Object.keys(env)) if (name.startsWith('__MISE_')) delete env[name];
    const ini = secrets.wakatime_config;
    if (ini !== undefined && (!/^\s*\[settings\]\s*$/m.test(ini) || !/^\s*[\w.-]+\s*=.+$/m.test(ini))) throw new Error('WakaTime input is not an INI settings file');
    if (secrets.himalaya_config !== undefined) {
      const validation = path.join(temp, 'validate.toml');
      fs.writeFileSync(validation, secrets.himalaya_config, { mode: 0o600 });
      const result = spawnSync(miseBin, ['-C', temp, 'config', 'get', '--file', validation], { env, stdio: 'ignore' });
      if (result.status !== 0) throw new Error('Himalaya input is not valid TOML');
      fs.unlinkSync(validation);
    }
    let config = '[bootstrap.secrets]\n';
    for (const [key] of selected) {
      const variable = `SETUP_${key.toUpperCase()}`;
      config += `${key} = ${quote(variable)}\n`;
      env[variable] = secrets[key];
    }
    for (const [key, relative] of selected) {
      const parent = path.dirname(path.join(actualHome, relative));
      if (parent !== actualHome) config += `\n[bootstrap.directories.${quote(parent)}]\nmode = "0700"\n`;
      config += `\n[bootstrap.files.${quote(path.join(actualHome, relative))}]\ncontent = ${quote(`{{ secret(name="${key}") }}`)}\ntemplate = true\nmode = "0600"\n`;
    }
    fs.writeFileSync(path.join(temp, 'config.toml'), config, { mode: 0o600 });
    const result = spawnSync(miseBin, ['-C', temp, 'bootstrap', 'files', 'apply', '--yes'], { env, encoding: 'utf8' });
    if (result.status !== 0) throw new Error('Native private-file application failed; existing inputs remain encrypted in the bundle');
    return 'Private files applied with native mise secrets and file resources';
  } finally { fs.rmSync(temp, { recursive: true, force: true }); }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [action, ...args] = process.argv.slice(2);
    const options = { recipient: [] };
    while (args.length) {
      const flag = args.shift();
      if (flag === '--from-live') { options.fromLive = true; continue; }
      const key = { '--input': 'inputPath', '--output': 'outputPath', '--recipient': 'recipient', '--bundle': 'bundle', '--identity': 'identity' }[flag];
      if (!key || !args.length) throw new Error('Usage: dots bundle create --input PRIVATE.json --output BUNDLE.age --recipient age1...; or check --bundle BUNDLE.age --identity KEY');
      const value = args.shift();
      if (key === 'recipient') options.recipient.push(value); else options[key] = value;
    }
    if (action === 'create') {
      if (!options.outputPath || (!options.inputPath && !options.fromLive)) throw new Error('create requires --output and either --input or --from-live');
      if (options.fromLive) {
        if (options.inputPath) throw new Error('Choose either --from-live or --input');
        const secrets = {};
        for (const [key, relative] of Object.entries(files)) {
          const source = path.join(os.homedir(), relative);
          if (fs.existsSync(source)) {
            if (!fs.lstatSync(source).isFile()) throw new Error('Live private input must be a regular file');
            secrets[key] = fs.readFileSync(source, 'utf8');
          }
        }
        if (!Object.keys(secrets).length) throw new Error('No existing private application files to enroll');
        options.document = { version: 1, secrets, recipients: options.recipient };
      }
      writeBundle(options);
      console.log('Encrypted bootstrap bundle created; no plaintext was written.');
    } else if (action === 'check' && options.bundle && options.identity) {
      unlockBundle(options.bundle, options.identity);
      console.log('Bootstrap bundle decrypts and validates.');
    } else throw new Error('Choose bundle create or check; see README for examples');
  } catch (error) { console.error(`bundle: ${error.message}`); process.exitCode = 1; }
}
