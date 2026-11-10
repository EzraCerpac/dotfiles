// Locate optional test prerequisites so Node suites skip instead of crashing.
// Mirrors tests/lib/prereq.py: an explicit SETUP_TEST_MISE wins, then PATH,
// then the official installer location.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function isExecutable(candidate) {
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return fs.statSync(candidate).isFile();
  } catch {
    return false;
  }
}

export function onPath(tool) {
  for (const directory of (process.env.PATH || '').split(path.delimiter)) {
    if (directory && isExecutable(path.join(directory, tool))) return path.join(directory, tool);
  }
  return null;
}

export function miseBinary() {
  for (const variable of ['SETUP_TEST_MISE', 'MISE_TEST_BINARY', 'SETUP_MISE_BIN']) {
    if (process.env[variable]) return process.env[variable];
  }
  const installed = path.join(os.homedir(), '.local/bin/mise');
  return onPath('mise') || (isExecutable(installed) ? installed : null);
}

// Test options for node:test: `test(name, requires('jj'), callback)`.
export function requires(...tools) {
  const missing = tools.filter(tool => (tool === 'mise' ? miseBinary() : onPath(tool)) === null);
  return missing.length ? { skip: `requires ${missing.join(', ')}` } : {};
}
