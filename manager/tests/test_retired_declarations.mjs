import assert from 'node:assert/strict';
import test from 'node:test';
import { parseKey, parseRetiredList, retireDeclarations } from '../lib/retired-declarations.mjs';

const SOURCE = 'templates/.config/herdr/config.tera';
const entry = { table: 'dotfiles.herdr', key: ['dotfiles', 'herdr'], source: SOURCE };
const gone = () => false;
// The block an older setup script appended to config.local.toml.
const HERDR = `\n[dotfiles.herdr]\nsource = "${SOURCE}"\nmode = "template"\nvariants = [{ os = "macos", target = "~/.config/herdr/config.toml" }, { os = "linux", target = "~/.config/herdr/config.toml" }]\n`;
const BEFORE = '# this machine\n[env]\nSETUP_PROFILE = "laptop" # set by bootstrap\n\n[settings]\nhistory.sync = "manual"\n';
const retire = (text, entries = [entry], exists = gone) => retireDeclarations(text, entries, exists);
const unchanged = text => assert.deepEqual(retire(text), { text, removed: [] });

test('the exact declaration an older setup script wrote is removed byte for byte', () => {
  assert.deepEqual(retire(BEFORE + HERDR), { text: BEFORE, removed: [entry] });
  // In the middle of the file, the following table and its comment stay.
  const after = '\n# history\n[history]\norigin.url = "x"\n';
  assert.equal(retire(BEFORE + HERDR + after).text, BEFORE + after);
  assert.equal(retire(HERDR.slice(1) + '\n[env]\nX = "1"\n').text, '[env]\nX = "1"\n');
  // CRLF line ends and a missing final newline are kept.
  const crlf = '[env]\r\nX = "1"\r\n\r\n[dotfiles.herdr]\r\nsource = "' + SOURCE + '"\r\n\r\n[a]\r\nb = 1';
  assert.equal(retire(crlf).text, '[env]\r\nX = "1"\r\n\r\n[a]\r\nb = 1');
});

test('quoted spellings of the same table and source match', () => {
  for (const header of ['[dotfiles."herdr"]', "[ 'dotfiles' . herdr ]  # old", '[dotfiles.herdr] # appended by setup']) {
    assert.equal(retire(`${BEFORE}\n${header}\nsource = '${SOURCE}' # template\n`).text, BEFORE, header);
  }
});

test('a declaration pointing at another source is left alone', () => {
  unchanged(BEFORE + HERDR.replace(SOURCE, 'dotfiles/.config/herdr/mine.toml'));
  unchanged(BEFORE + '\n[dotfiles.herdr]\nmode = "template"\n');
  unchanged(BEFORE + '\n[dotfiles.herdr]\nsource = """' + SOURCE + '"""\n');
});

test('a source that still exists keeps the declaration', () => {
  assert.deepEqual(retire(BEFORE + HERDR, [entry], name => name === SOURCE), { text: BEFORE + HERDR, removed: [] });
});

test('similarly named, commented and nested tables are left alone', () => {
  unchanged(BEFORE + HERDR.replace('[dotfiles.herdr]', '[dotfiles.herdr-extra]'));
  unchanged(BEFORE + HERDR.replace('[dotfiles.herdr]', '# [dotfiles.herdr]'));
  unchanged(BEFORE + HERDR.replace('[dotfiles.herdr]', '[dotfiles.herdr.more]'));
  unchanged(BEFORE + HERDR.replace('[dotfiles.herdr]', '[[dotfiles.herdr]]'));
  // Only the real table goes; its similarly named neighbour stays.
  const extra = '\n[dotfiles.herdr-extra]\nsource = "x"\n';
  assert.equal(retire(BEFORE + HERDR + extra).text, BEFORE + extra);
});

test('a table also defined elsewhere, or a file it cannot read, is left alone', () => {
  unchanged(BEFORE + HERDR + '\n[dotfiles.herdr.extra]\nx = 1\n');
  unchanged('[dotfiles]\nherdr.mode = "copy"\n' + HERDR);
  unchanged('dotfiles.herdr.mode = "copy"\n' + HERDR);
  unchanged(BEFORE + HERDR + HERDR);
  unchanged(BEFORE + HERDR + '\n[broken\n');
  unchanged(BEFORE + HERDR + 'note = "unterminated\n');
  unchanged(BEFORE + HERDR + 'list = [\n');
});

test('a header inside a multi-line string or array is not a table', () => {
  const quoted = `note = """\n[dotfiles.herdr]\nsource = "${SOURCE}"\n"""\n`;
  unchanged(BEFORE + quoted);
  const array = `paths = [\n  "a",\n]\n${HERDR}`;
  assert.equal(retire(array).text, 'paths = [\n  "a",\n]\n');
});

test('a second run finds nothing', () => {
  const once = retire(BEFORE + HERDR).text;
  assert.deepEqual(retire(once), { text: once, removed: [] });
});

test('the list is TABLE<TAB>SOURCE rows under dotfiles, with comments', () => {
  assert.deepEqual(parseKey(' dotfiles . "her.dr" '), ['dotfiles', 'her.dr']);
  assert.equal(parseKey('dotfiles.'), null);
  const list = [
    '# comment', '', `dotfiles.herdr\t${SOURCE}`, `dotfiles."a b"\tdotfiles/x\r`,
    'dotfiles.only-a-table', `env.X\t${SOURCE}`, `dotfiles.a.b\t${SOURCE}`,
    'dotfiles.up\t../outside', 'dotfiles.abs\t/etc/passwd', `dotfiles.extra\t${SOURCE}\tmore`,
  ].join('\n');
  assert.deepEqual(parseRetiredList(list), [entry, { table: 'dotfiles."a b"', key: ['dotfiles', 'a b'], source: 'dotfiles/x' }]);
});
