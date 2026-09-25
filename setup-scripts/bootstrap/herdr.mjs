#!/usr/bin/env node
// Reconcile Herdr after tools exist, without changing the account login shell.
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { resolveMiseBin } from '../lib/source-repo.mjs';

export function applyHerdr({ home, mise, invoke }) {
  const requireCommand = (args, message) => {
    if (mise(args).status !== 0) throw new Error(message);
  };
  requireCommand(['bootstrap', 'dotfiles', 'apply', '--yes', path.join(home, '.config/herdr/config.toml')],
    'Could not apply the Herdr shell configuration');
  const server = invoke('herdr', ['status', 'server'], true);
  if (server.error?.code === 'ENOENT') return 'Configured for when Herdr is installed';
  if (server.status !== 0) throw new Error('Herdr configuration applied; could not inspect the running server');
  if (/^status: running$/m.test(server.stdout)) {
    const reload = invoke('herdr', ['server', 'reload-config']);
    if (reload.status !== 0) throw new Error('Herdr configuration applied; reload-config needs attention');
    return 'Reloaded configuration; existing panes preserved';
  }
  return 'Configured for the next Herdr server start';
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const root = path.resolve(process.argv[2]);
  const home = process.env.HOME;
  const miseBin = resolveMiseBin();
  const invoke = (command, args, capture = false) => spawnSync(command, args, {
    cwd: root, env: { ...process.env, MISE_CONFIG_DIR: root }, encoding: 'utf8',
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
  });
  const mise = (args, capture = false) => invoke(miseBin, ['-C', root, ...args], capture);
  try {
    const prepare = mise(['exec', '--', 'bash', path.join(root, 'setup-scripts/local/shell-select.sh'), '--prepare-only']);
    if (prepare.status !== 0) throw new Error('Fish preparation failed; Herdr configuration was not applied');
    console.log(applyHerdr({ home, mise, invoke }));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
