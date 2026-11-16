// Retired local declarations: [dotfiles.NAME] tables that a configuration's own
// setup scripts once wrote into machine-local config files, listed in
// dots/retired-declarations once their source is gone. Sync removes such a
// table only while it still points at exactly the listed source and that
// source no longer exists; anything it cannot read with confidence stays.

export const RETIRED_LIST = 'dots/retired-declarations';
// Machine-local mise config files that can carry declarations.
export const localDeclarationFile = name => /^config\.(?:local|host-[a-z0-9-]+)\.toml$/.test(name);

const BARE = '[A-Za-z0-9_-]+', BASIC = '"(?:[^"\\\\\\n]|\\\\.)*"', LITERAL = "'[^'\\n]*'";
const PART = `(?:${BARE}|${BASIC}|${LITERAL})`;
const KEY = `${PART}(?:[ \\t]*\\.[ \\t]*${PART})*`;
const COMMENT = '[ \\t]*(?:#.*)?';
const TABLE = new RegExp(`^[ \\t]*\\[[ \\t]*(${KEY})[ \\t]*\\]${COMMENT}$`);
const ARRAY = new RegExp(`^[ \\t]*\\[\\[[ \\t]*(${KEY})[ \\t]*\\]\\]${COMMENT}$`);
const ASSIGN = new RegExp(`^[ \\t]*(${KEY})[ \\t]*=[ \\t]*(.*)$`);
const STRING = new RegExp(`^(${BASIC}|${LITERAL})${COMMENT}$`);

// A TOML string or key part as its value, or null when it cannot be read.
function unquote(text) {
  if (text.startsWith("'")) return text.slice(1, -1);
  if (!text.startsWith('"')) return text;
  try { return JSON.parse(text); } catch { return null; }
}

// A dotted key as its parts, or null.
export function parseKey(text) {
  const parts = [...String(text).matchAll(new RegExp(`(${PART})[ \\t]*(?:\\.[ \\t]*|$)`, 'g'))].map(m => unquote(m[1]));
  return new RegExp(`^${KEY}$`).test(String(text).trim()) && parts.every(part => part !== null) ? parts : null;
}
const same = (a, b) => a.length === b.length && a.every((part, i) => part === b[i]);
const startsWith = (key, prefix) => key.length >= prefix.length && prefix.every((part, i) => key[i] === part);

// Rows of TABLE<TAB>SOURCE; anything else is ignored.
export function parseRetiredList(text) {
  const entries = [];
  for (const line of String(text).split(/\r?\n/)) {
    if (!line.trim() || line.startsWith('#')) continue;
    const fields = line.split('\t');
    const key = fields.length === 2 ? parseKey(fields[0]) : null;
    const source = fields[1];
    if (!key || key.length !== 2 || key[0] !== 'dotfiles' || !source || source.startsWith('/')
      || source.split('/').some(part => part === '..' || part === '')) continue;
    entries.push({ table: fields[0].trim(), key, source });
  }
  return entries;
}

// Physical lines (with their line ends), each marked whether it starts a
// statement: outside every string and bracket. Null when the text does not
// close every string and bracket, so its structure cannot be trusted.
function scan(text) {
  const lines = text.split(/(?<=\n)/);
  let open = null, depth = 0;
  const result = lines.map(raw => {
    const statement = !open && depth === 0;
    const line = raw.replace(/\r?\n$/, '');
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (open === '"""' || open === "'''") {
        if (line.startsWith(open, i)) { let j = i + 3; while (j < line.length && j < i + 5 && line[j] === open[0]) j++; i = j - 1; open = null; }
        else if (open === '"""' && c === '\\') i++;
      } else if (open) {
        if (open === '"' && c === '\\') i++;
        else if (c === open) open = null;
      } else if (c === '#') break;
      else if (line.startsWith('"""', i) || line.startsWith("'''", i)) { open = line.slice(i, i + 3); i += 2; }
      else if (c === '"' || c === "'") open = c;
      else if (c === '[' || c === '{') depth++;
      else if (c === ']' || c === '}') { if (--depth < 0) return null; }
    }
    if (open === '"' || open === "'") return null;
    return { raw, line, statement };
  });
  return open || depth || result.includes(null) ? null : result;
}

// Remove one retired table from TEXT when it is declared exactly as
// [TABLE] with source = SOURCE and nothing else defines that table.
// Returns the new text, or null to leave the file alone.
function removeTable(text, { key, source }) {
  const lines = scan(text);
  if (!lines) return null;
  let table = [], header = -1, end = lines.length, sources = [], foreign = false;
  for (const [index, { line, statement }] of lines.entries()) {
    if (!statement || !line.trim() || /^[ \t]*#/.test(line)) continue;
    let match;
    if (line.trimStart().startsWith('[')) {
      match = line.match(ARRAY) || line.match(TABLE);
      if (!match) return null;
      table = parseKey(match[1]);
      if (!table) return null;
      if (header >= 0 && end === lines.length) end = index;
      if (!line.match(ARRAY) && same(table, key) && header < 0) header = index;
      else if (startsWith(table, key)) foreign = true;
    } else if ((match = line.match(ASSIGN))) {
      const name = parseKey(match[1]);
      if (!name) return null;
      const full = [...table, ...name];
      if (header >= 0 && end === lines.length) { if (name[0] === 'source') sources.push(name.length === 1 ? match[2] : null); }
      else if (startsWith(full, key) || startsWith(key, full)) foreign = true;
    } else return null;
  }
  if (header < 0 || foreign || sources.length !== 1 || sources[0] === null) return null;
  const value = sources[0].match(STRING);
  if (!value || unquote(value[1]) !== source) return null;
  // The table runs to its last key or value line; comments and blank lines
  // after that belong to whatever follows. One separating blank line goes too.
  let last = end - 1;
  while (last > header && lines[last].statement && (!lines[last].line.trim() || /^[ \t]*#/.test(lines[last].line))) last--;
  let first = header;
  if (first > 0 && !lines[first - 1].line.trim()) first--;
  else if (last + 1 < lines.length && !lines[last + 1].line.trim()) last++;
  return [...lines.slice(0, first), ...lines.slice(last + 1)].map(l => l.raw).join('');
}

// The retired ENTRIES found in TEXT whose source EXISTS(source) denies, and
// TEXT without them.
export function retireDeclarations(text, entries, exists) {
  const removed = [];
  for (const entry of entries) {
    if (exists(entry.source)) continue;
    const next = removeTable(text, entry);
    if (next === null) continue;
    text = next;
    removed.push(entry);
  }
  return { text, removed };
}
