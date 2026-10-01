import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {validate, createOperations} from '../setup-scripts/local/concierge-nas.mjs';
const example = JSON.parse(fs.readFileSync(new URL('../resources/concierge/runtime.example.json', import.meta.url)));
for (const [i,s] of example.services.entries()) if (s.kind === 'tunnel') s.tunnelID = 'tunnel_' + String(i).repeat(32);
function fixture() {
  const home = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'concierge-test-')));
  const config = structuredClone(example), calls = [], loaded = new Set();
  const expand = p => p.replace(/^~\//, home + '/');
  const write = (p, value = '', mode = 0o600) => { fs.mkdirSync(path.dirname(p), {recursive: true, mode: 0o700}); fs.writeFileSync(p, value, {mode}); };
  config.expectedHost = 'fixture';
  for (const key of ['node', 'uv', 'wacli', 'tunnelClient']) {config[key] = '~/bin/' + key;write(expand(config[key]), '', 0o700);}
  write(expand(config.python), '', 0o700);
  const project = expand(config.projectDir);
  for (const name of ['icloud-pilot', 'icloud-dav']) for (const file of ['uv.lock', 'pyproject.toml']) write(path.join(project, 'integrations', name, file));
  write(path.join(project, 'integrations/mail-read/requirements.lock'), 'IMAPClient==4.1.0 --hash=sha256:' + 'a'.repeat(64));
  for (const file of ['whatsapp-read/wacli/mcp.mjs', 'mail-read/maintained_mcp.py', 'icloud-pilot/mcp_stdio.py']) write(path.join(project, 'integrations', file));
  for (const s of config.services.filter(s => s.kind === 'tunnel')) for (const k of ['keyFile', 'facadeConfig', 'accountsFile']) if (s[k]) write(expand(s[k]),k === 'keyFile' ? 'PRIVATE_KEY_FIXTURE' : '{}');
  let ops;
  const run = (bin, args, options = {}) => {
    calls.push({bin,args,options});
    if (bin === '/usr/bin/plutil') {
      if (process.platform === 'darwin' && !process.env.CONCIERGE_TEST_PORTABLE_PLIST) return execFileSync(bin,args,{encoding:'utf8'});
      return execFileSync('python3', ['-c', 'import json, plistlib, sys; print(json.dumps(plistlib.load(open(sys.argv[1], "rb"))))', args.at(-1)], {encoding:'utf8'});
    }
    if (bin === '/usr/bin/pgrep') {
      if (run.collectorProbeError) throw Object.assign(Error('probe failed'),{status:2});
      if (run.collectorExists) return '991\n';
      throw Object.assign(Error('absent'),{status:1});
    }
    if (bin === '/bin/launchctl') {
      if (args[0] === 'print') {if (!loaded.has(args[1].split('/').at(-1))) throw Error('absent');return 'state = running\npid = 42';}
      if (args[0] === 'bootstrap') loaded.add(path.basename(args[2],'.plist'));
    }
    if (args[0] === 'init') {
      const s = config.services.find(s => s.profile === args[args.indexOf('--profile')+1]);
      write(ops.profileFile(s), `control_plane:\n  tunnel_id: ${JSON.stringify(s.tunnelID)}\n  api_key: ${JSON.stringify('file:'+expand(s.keyFile))}\nmcp:\n  commands:\n    - channel: main\n      command: ${JSON.stringify(ops.mcpCommand(s))}\n`);
    }
    if (args[0] === 'venv') write(expand(config.mailPython), '', 0o700);
    return '';
  };
  ops = createOperations(config,{home,run});
  return {home,config,ops,calls,loaded,run,expand,write,cleanup:()=>fs.rmSync(home,{recursive:true,force:true})};
}
test('only the four fixed services and matching backend kinds are allowed',()=>{
  validate(example,example.expectedHost,'darwin');
  for (const mutate of [c=>c.services.push(c.services[0]),c=>c.services[0].label='com.ezra.dottie.other',c=>c.services[1].backend='mail',c=>c.services[1].tunnelID='contains spaces',c=>c.services[1].healthViaEnvironment=true]) {
    const c=structuredClone(example);mutate(c);assert.throws(()=>validate(c,c.expectedHost,'darwin'));
  }
  assert.throws(()=>validate(example,'another-host','darwin'));assert.throws(()=>validate(example,example.expectedHost,'linux'));
});
test('collector preserves quiet, unlimited retention and no media; derived bridge argv and health policy',()=>{
  const f=fixture();try {
    const collector=f.ops.definition(f.config.services[0]);
    assert.deepEqual(collector.ProgramArguments.slice(-10),['--follow','--presence-mode','quiet','--download-media=false','--max-messages','0','--max-db-size','0','--max-reconnect','5m']);
    assert.deepEqual(collector.ProgramArguments.slice(0,9),['/usr/bin/env','-u','WACLI_READONLY','-u','WACLI_STORE_DIR','-u','WACLI_SYNC_MAX_MESSAGES','-u','WACLI_SYNC_MAX_DB_SIZE']);
    assert.ok(collector.ProgramArguments.includes('--download-media=false'));
    assert.equal(collector.ProgramArguments[collector.ProgramArguments.indexOf('--max-messages')+1],'0');
    assert.equal(collector.ProgramArguments[collector.ProgramArguments.indexOf('--max-db-size')+1],'0');
    assert.equal(collector.Umask,63);assert.equal(collector.ThrottleInterval,30);
    assert.equal(f.ops.definition(f.config.services[1]).EnvironmentVariables,undefined);
    assert.deepEqual(Object.keys(f.ops.definition(f.config.services[2]).EnvironmentVariables),['HEALTH_URL_FILE']);
    assert.ok(f.ops.mcpArgv(f.config.services[1])[1].endsWith('/wacli/mcp.mjs'));
    assert.deepEqual(f.ops.mcpArgv(f.config.services[3]).slice(-2),['--with-create','--with-dav']);
    assert.ok(f.ops.mcpArgv(f.config.services[2]).includes('--state-dir'));
  } finally {f.cleanup();}
});
test('stage and rebuild are idempotent, use locked environments, and never restart loaded services',()=>{
  const f=fixture();try {
    const files=f.ops.stage();const bytes=files.map(p=>fs.readFileSync(p,'utf8'));f.ops.stage();assert.deepEqual(files.map(p=>fs.readFileSync(p,'utf8')),bytes);
    f.ops.rebuild();assert.equal(f.loaded.size,4);
    assert.equal(f.calls.filter(c=>c.args[0]==='init').length,3);
    for (const s of f.config.services.filter(s=>s.kind==='tunnel')) {
      assert.equal(f.ops.profileMatches(s),true);
      const call=f.calls.find(c=>c.args[0]==='init'&&c.args.includes(s.profile));
      assert.equal(call.args[call.args.indexOf('--control-plane-api-key-ref')+1],'file:'+f.expand(s.keyFile));
      assert.equal(call.args[call.args.indexOf('--sample')+1],'sample_mcp_stdio_local');
      fs.chmodSync(path.join(f.home,'Library/LaunchAgents',s.label+'.plist'),0o644);
    }
    const sync=f.calls.filter(c=>c.args[0]==='sync');assert.equal(sync.length,2);assert.ok(sync.every(c=>c.args.includes('--locked')&&c.options.env.UV_PROJECT_ENVIRONMENT.endsWith('/.venv')));
    const install=f.calls.find(c=>c.args[0]==='pip');assert.ok(install.args.includes('--require-hashes'));assert.ok(install.args.includes('--only-binary=:all:'));
    f.calls.length=0;f.ops.rebuild();assert.ok(!f.calls.some(c=>['init','bootstrap','kickstart','bootout','venv'].includes(c.args[0])));
    assert.ok(!f.calls.some(c=>c.bin.includes('npm')||c.args.includes('--force')));
  } finally {f.cleanup();}
});
test('semantic plist equality accepts formatting but refuses drift before dependency mutation',()=>{
  const f=fixture();try {
    const [file]=f.ops.stage();fs.writeFileSync(file,fs.readFileSync(file,'utf8').replaceAll('</key>','</key>\n'));
    f.ops.stage();fs.writeFileSync(file,fs.readFileSync(file,'utf8').replace('<integer>30</integer>','<integer>31</integer>'));
    f.calls.length=0;assert.throws(()=>f.ops.rebuild());assert.ok(!f.calls.some(c=>c.args[0]==='sync'));
  } finally {f.cleanup();}
});
test('profile binding drift and missing private auth block before mutations; external collector skips duplicate',()=>{
  const f=fixture();try {
    const s=f.config.services[1];fs.unlinkSync(f.expand(s.keyFile));assert.equal(f.ops.rebuild().blocked,'missing-auth');assert.ok(!f.calls.some(c=>c.args[0]==='sync'));
    f.write(f.expand(s.keyFile));f.run.collectorExists=true;const result=f.ops.rebuild();assert.equal(result.skipped[0].reason,'existing-collector');assert.equal(f.loaded.size,3);
    f.write(f.ops.profileFile(s), 'tunnel_id: WRONG\ncommand: WRONG\nkey_ref: WRONG\n');f.calls.length=0;assert.throws(()=>f.ops.rebuild());assert.ok(!f.calls.some(c=>c.args[0]==='sync'));
  } finally {f.cleanup();}
});

test('Mail rebuild preserves the dedicated environment and also supports the project environment',()=>{
  for (const mailPython of ['~/.local/share/dottie-mail/venv/bin/python','~/Projects/personal-concierge/integrations/mail-read/.venv/bin/python']) {
    const f=fixture();try {
      f.config.mailPython=mailPython;f.write(f.expand(mailPython),'',0o700);
      f.ops.rebuild();
      assert.ok(!f.calls.some(c=>c.args[0]==='venv'));
      const install=f.calls.find(c=>c.args[0]==='pip');
      assert.equal(install.args[install.args.indexOf('--python')+1],f.expand(mailPython));
    } finally {f.cleanup();}
  }
  const f=fixture();try {
    f.config.mailPython='/usr/bin/python3';assert.throws(()=>f.ops.rebuild());
    assert.ok(!f.calls.some(c=>c.args[0]==='sync'||c.args[0]==='venv'));
  } finally {f.cleanup();}
});

test('fresh project environments use pinned managed Python and two locked syncs',()=>{
  const f=fixture();try {
    fs.unlinkSync(f.expand(f.config.python));
    f.ops.rebuild();
    const sync=f.calls.filter(c=>c.args[0]==='sync');
    assert.equal(sync.length,2);
    assert.ok(sync.every(c=>c.args.includes('--locked')&&c.options.env.UV_PYTHON==='3.13.15'&&c.options.env.UV_PYTHON_DOWNLOADS==='automatic'));
    const venv=f.calls.find(c=>c.args[0]==='venv');
    assert.equal(venv.args[venv.args.indexOf('--python')+1],'3.14.7');
    assert.equal(venv.options.env.UV_PYTHON_DOWNLOADS,'automatic');
  } finally {f.cleanup();}
});

// Mail accounts.json is a public definition containing credential references;
// actual key/session files retain strict private ownership/mode checks.
test('nonsecret Mail definition permits 644 but rejects writable definitions and public runtime keys',()=>{
  const f=fixture();try {
    const mail=f.config.services.find(s=>s.backend==='mail');
    fs.chmodSync(f.expand(mail.accountsFile),0o644);assert.deepEqual(f.ops.preflight(),[]);
    fs.chmodSync(f.expand(mail.accountsFile),0o666);assert.throws(()=>f.ops.preflight());
    fs.chmodSync(f.expand(mail.accountsFile),0o644);fs.chmodSync(f.expand(mail.keyFile),0o644);assert.throws(()=>f.ops.preflight());
  } finally {f.cleanup();}
});

test('Reminders edits are opt-in and only change the iCloud argv',()=>{
  const f=fixture();try {
    const icloud=f.config.services.find(s=>s.backend==='icloud');
    const others=f.config.services.filter(s=>s.backend&&s.backend!=='icloud');
    const oldOthers=others.map(s=>f.ops.mcpArgv(s));
    delete f.config.remindersEdits;
    const original=f.ops.mcpArgv(icloud);
    assert.deepEqual(original.slice(-2),['--with-create','--with-dav']);
    f.config.remindersEdits=false;assert.deepEqual(f.ops.mcpArgv(icloud),original);
    f.config.remindersEdits=true;assert.deepEqual(f.ops.mcpArgv(icloud),[...original,'--with-edit']);
    assert.deepEqual(others.map(s=>f.ops.mcpArgv(s)),oldOthers);
    for (const invalid of ['true',1,null,{}]) {
      f.config.remindersEdits=invalid;assert.throws(()=>validate(f.config,'fixture','darwin'));
    }
  } finally {f.cleanup();}
});
test('doctor extracts Node versions with a leading v without exposing raw output',()=>{
  const f=fixture();try {
    const ops=createOperations(f.config,{home:f.home,run:(bin,args,options)=>args[0]==='--version' ? 'v26.10.0\n' : f.run(bin,args,options)});
    const doctor=ops.doctor();
    assert.equal(doctor.checks.find(c=>c.check==='node').version,'26.10.0');
    assert.ok(!JSON.stringify(doctor).includes('v26.10.0'));
  } finally {f.cleanup();}
});


test('profile drift checks require the key reference in the actual control-plane field',()=>{
  const f=fixture();try {
    f.ops.rebuild();
    const s=f.config.services[1], file=f.ops.profileFile(s), original=fs.readFileSync(file,'utf8');
    const expected=JSON.stringify('file:'+f.expand(s.keyFile));
    for (const changed of [
      original.replace('  api_key: '+expected, '  api_key: "file:/wrong-key"\n  unused: '+expected),
      original.replace('  api_key: '+expected, 'other:\n  api_key: '+expected),
      original+'control_plane:\n  api_key: '+expected+'\n'
    ]) {
      fs.writeFileSync(file,changed);f.calls.length=0;
      assert.equal(f.ops.profileMatches(s),false);
      assert.throws(()=>f.ops.rebuild());
      assert.ok(!f.calls.some(c=>['sync','pip','init','bootstrap'].includes(c.args[0])));
    }
  } finally {f.cleanup();}
});
test('missing LaunchAgents cannot be installed through a symlink or writable directory',()=>{
  for (const unsafe of ['symlink','writable']) {
    const f=fixture();try {
      const target=path.join(f.home,'Library/LaunchAgents');
      fs.mkdirSync(path.dirname(target),{recursive:true});
      if (unsafe==='symlink') {
        const redirected=path.join(f.home,'redirected');fs.mkdirSync(redirected);
        fs.symlinkSync(redirected,target);
      } else {fs.mkdirSync(target);fs.chmodSync(target,0o777);}
      assert.throws(()=>f.ops.rebuild());
      assert.deepEqual(f.calls,[]);
      assert.deepEqual(fs.readdirSync(target),[]);
    } finally {f.cleanup();}
  }
});

test('private paths reject writable ancestors, including above a missing destination',()=>{
  for (const mode of [0o770,0o707,0o777]) {
    const f=fixture();try {
      const key=f.expand(f.config.services[1].keyFile), parent=path.dirname(key);
      fs.chmodSync(parent,mode);
      assert.throws(()=>f.ops.privatePath(key));
      assert.throws(()=>f.ops.privatePath(path.join(parent,'missing/key')));
      assert.throws(()=>f.ops.rebuild());
      assert.deepEqual(f.calls,[]);
    } finally {f.cleanup();}
  }
  const f=fixture();try {
    fs.chmodSync(path.join(f.home,'.local'),0o777);
    assert.throws(()=>f.ops.rebuild());assert.deepEqual(f.calls,[]);
  } finally {f.cleanup();}
});
test('private paths reject foreign-owned ancestors while allowing safe traversable directories',t=>{
  for (const relative of ['.local/share/dottie-whatsapp/tunnel','.local', '.']) {
    const f=fixture();try {
      const key=f.expand(f.config.services[1].keyFile), foreign=path.resolve(f.home,relative);
      fs.chmodSync(foreign,0o755);
      assert.equal(f.ops.privatePath(key),true);
      const lstat=fs.lstatSync;
      t.mock.method(fs,'lstatSync',(file,...args)=>{
        const st=lstat(file,...args);
        if (path.resolve(file)===foreign) Object.defineProperty(st,'uid',{value:process.getuid()+1});
        return st;
      });
      assert.throws(()=>f.ops.privatePath(key));
      assert.throws(()=>f.ops.privatePath(path.join(foreign,'missing/key')));
      assert.throws(()=>f.ops.rebuild());assert.deepEqual(f.calls,[]);
    } finally {t.mock.restoreAll();f.cleanup();}
  }
});
test('external collector is skipped without installing a login auto-start plist',()=>{
  const f=fixture();try {
    const label=f.config.services[0].label, installed=path.join(f.home,'Library/LaunchAgents',label+'.plist');
    f.run.collectorExists=true;
    for (let i=0;i<2;i++) {
      const result=f.ops.rebuild();
      assert.deepEqual(result.skipped,[{label,reason:'existing-collector'}]);
      assert.equal(fs.existsSync(installed),false);
      assert.equal(result.serviceFiles.includes(installed),false);
      assert.equal(f.loaded.has(label),false);
      assert.ok(!f.calls.some(c=>c.args[0]==='bootstrap'&&c.args[2]===installed));
    }
    f.run.collectorExists=false;
    f.ops.rebuild();assert.equal(fs.existsSync(installed),true);assert.equal(f.loaded.has(label),true);
    f.run.collectorExists=true;f.calls.length=0;
    assert.deepEqual(f.ops.rebuild().skipped,[]);
    assert.ok(!f.calls.some(c=>c.bin==='/usr/bin/pgrep'||c.args[0]==='bootstrap'));
  } finally {f.cleanup();}
});
test('an existing unloaded collector plist is preserved and reported for manual reconciliation',()=>{
  const f=fixture();try {
    f.ops.rebuild();
    const label=f.config.services[0].label, installed=path.join(f.home,'Library/LaunchAgents',label+'.plist');
    const original=fs.readFileSync(installed);
    f.loaded.delete(label);f.run.collectorExists=true;f.calls.length=0;
    assert.deepEqual(f.ops.rebuild().skipped,[{label,reason:'existing-collector-and-agent-requires-reconciliation'}]);
    assert.deepEqual(fs.readFileSync(installed),original);
    assert.equal(f.loaded.has(label),false);
    assert.ok(!f.calls.some(c=>['bootstrap','bootout','kickstart'].includes(c.args[0])));
  } finally {f.cleanup();}
});
test('profile binding requires exactly one command under mcp.commands on channel main',()=>{
  const f=fixture();try {
    f.ops.rebuild();
    const s=f.config.services[1],file=f.ops.profileFile(s),original=fs.readFileSync(file,'utf8');
    for (const changed of [
      original.replace('channel: main','channel: unrelated'),
      original.replace('  commands:','  ignored:'),
      original.replace('    - channel: main\n',''),
      original+'    - channel: other\n      command: "/usr/bin/false"\n',
      original+'      channel: other\n',
      original+'      command: "/usr/bin/false"\n',
      original+'  server_urls:\n    - url: "https://example.invalid/mcp"\n',
      original+'mcp: {commands: []}\n',
      original+'"mcp": {commands: []}\n',
      original.replace('mcp:\n','mcp: &commands\n'),
      original.replace('  commands:','  commands: *other'),
      original+'---\nmcp: {}\n',
      original+'unexpected: [bad\n',
      original.replace('control_plane:\n','control_plane:\n  unexpected: true\n'),
      original+'health:\n  listen_addr: [bad\n',
      original+'log:\n  level: info\n  level: debug\n',
      original.replace('control_plane:\n','control_plane:\n  base_url: https://example.invalid\n'),
      original.replace('control_plane:\n','control_plane:\n  url_path: /unexpected\n'),
      original+'health:\n  listen_addr: 0.0.0.0:8080\n',
      original+'health:\n  url_file: /tmp/unexpected\n',
      original+'admin_ui:\n  open_browser: true\n',
      original+'log:\n  level: debug\n'
    ]) {
      fs.writeFileSync(file,changed);f.calls.length=0;
      assert.equal(f.ops.profileMatches(s),false);
      assert.throws(()=>f.ops.rebuild());
      assert.ok(!f.calls.some(c=>['sync','pip','init','bootstrap'].includes(c.args[0])));
    }
    fs.writeFileSync(file,original.replace('channel: main','channel: "main"').replace('mcp:\n','mcp:\n  # Generated sample\n\n').replaceAll('\n','\r\n'));
    assert.equal(f.ops.profileMatches(s),true);
  } finally {f.cleanup();}
});

test('collector probe failure cannot install or bootstrap the collector',()=>{
  const f=fixture();try {
    f.run.collectorProbeError=true;
    assert.throws(()=>f.ops.rebuild(),/collector ownership/);
    assert.equal(fs.existsSync(path.join(f.home,'Library/LaunchAgents',f.config.services[0].label+'.plist')),false);
    assert.equal(f.loaded.size,0);
  } finally {f.cleanup();}
});
