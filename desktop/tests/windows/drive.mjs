/* Drives the installed app, unchanged: the scripts of desktop/tests run in its page through the debugging port of
   WebView2. Node 22, no package. usage: drive.mjs <app.exe> <script.js> <pictures> key=value…
   keys: run (folder of fixtures.py), data (OORT_DATA), tag, size (WxH), language, desk (Desk.exe) */
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const [app, script, out, ...pairs] = process.argv.slice(2), o = Object.fromEntries(pairs.map(p => [p.slice(0, p.indexOf('=')), p.slice(p.indexOf('=') + 1)]));
const here = import.meta.dirname, port = 9333, wait = ms => new Promise(r => setTimeout(r, ms));
mkdirSync(out, { recursive: true });
const slash = p => p.replace(/\\/g, '/');
const desk = (...a) => execFileSync(o.desk, a.map(String), { encoding: 'utf8' }).trim();

// What a player's machine has, and nothing of the runner's tools.
const keep = ['SystemRoot', 'SystemDrive', 'windir', 'TEMP', 'TMP', 'USERPROFILE', 'USERNAME', 'APPDATA', 'LOCALAPPDATA', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)', 'CommonProgramFiles', 'COMSPEC', 'PATHEXT', 'HOMEDRIVE', 'HOMEPATH', 'PUBLIC', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'OS'];
const env = Object.fromEntries(keep.filter(k => process.env[k]).map(k => [k, process.env[k]]));
env.PATH = `${env.SystemRoot}\\System32;${env.SystemRoot}`;
env.WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = `--remote-debugging-port=${port} --remote-allow-origins=*`;
if (o.data) env.OORT_DATA = o.data;
if (o.language) env.OORT_LANGUAGE = o.language;

const child = spawn(app, [], { env, cwd: path.dirname(app), stdio: ['ignore', 'inherit', 'inherit'] });
let gone = null; child.on('exit', code => { gone = code ?? 'signal'; });
const fail = text => { console.log('FAIL ' + text); try { desk('shot', path.join(out, `${o.tag || ''}failed-desktop.png`)); } catch { } child.kill(); process.exit(1); };
const limit = setTimeout(() => fail('the script took too long'), +(o.limit || 240) * 1000);

let target;
for (let i = 0; i < 120 && !target; i++) {
  if (gone !== null) fail('the app left with ' + gone);
  await wait(250);
  target = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json()).then(l => l.find(t => t.type === 'page' && t.url.startsWith('http://tauri.localhost'))).catch(() => null);
}
if (!target) {
  const ps = c => { try { return execFileSync('powershell', ['-NoProfile', '-Command', c], { encoding: 'utf8' }); } catch (e) { return String(e.message); } };
  console.log(ps("Get-CimInstance Win32_Process -Filter \"Name='msedgewebview2.exe'\" | Where-Object { $_.CommandLine -match 'oort' -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.CommandLine }"));
  console.log(ps('Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 9333 | Format-Table -AutoSize'), await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.text()).catch(e => String(e.cause || e)));
  fail('no page to talk to');
}
console.log('page', target.url);
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r, e) => { socket.onopen = r; socket.onerror = e; });
let n = 0; const waiting = new Map();
const send = (method, params = {}, ms = 10000) => new Promise((resolve, reject) => {
  const id = ++n, timer = setTimeout(() => { waiting.delete(id); reject(new Error(method + ' did not answer')); }, ms);
  waiting.set(id, m => { clearTimeout(timer); m.error ? reject(new Error(m.error.message)) : resolve(m.result); });
  socket.send(JSON.stringify({ id, method, params }));
});

let end = null, failures = 0; const finished = new Promise(r => { end = r; });
const picture = async name => {
  // A minimized window draws nothing.
  const { data } = await send('Page.captureScreenshot', { format: 'png' }, 6000);
  writeFileSync(path.join(out, `${o.tag || ''}${name}.png`), Buffer.from(data, 'base64'));
};
const commands = {
  report: line => { console.log(line); if (/^(FAIL|ERROR|REJECTED|THROWN)/.test(line)) failures++; const m = /^END (\d+)/.exec(line); if (m) end(+m[1]); },
  shot: async name => { try { await picture(name); } catch (e) { console.log('no picture', name, e.message); } },
  desktop: name => desk('shot', path.join(out, `${o.tag || ''}${name}.png`)),
  state: () => JSON.parse(desk('state', child.pid)),
  front: () => { try { desk('front', child.pid); return true; } catch { return false; } },
  key: code => desk('key', code),
  count: folder => +desk('count', folder.replace(/\//g, '\\')),
  read: file => { try { return readFileSync(file, 'utf8'); } catch { return null; } },
};
socket.onmessage = async e => {
  const m = JSON.parse(e.data);
  if (m.id) { const done = waiting.get(m.id); waiting.delete(m.id); return done?.(m); }
  if (m.method !== 'Runtime.bindingCalled' || m.params.name !== 'oortHost') return;
  const { id, command, args } = JSON.parse(m.params.payload);
  let result = null; try { result = await commands[command](...args) ?? null; } catch (err) { console.log('host', command, err.message); }
  send('Runtime.evaluate', { expression: `window.hostReply(${id},${JSON.stringify(result)})` }).catch(() => {});
};
await send('Runtime.enable'); await send('Page.enable'); await send('Runtime.addBinding', { name: 'oortHost' });
// The app's own first load ends before its page is loaded again with the script.
for (let i = 0; ; i++) {
  const ready = await send('Runtime.evaluate', { expression: 'location.origin + " " + document.documentElement.dataset.ready' }).then(r => r.result.value).catch(() => '');
  if (ready === 'http://tauri.localhost 1') break;
  if (i > 120) fail('the app did not get ready: ' + ready);
  await wait(250);
}
console.log('ready by itself');
if (o.size) { desk('size', child.pid, ...o.size.split('x')); await wait(400); }
try { const said = desk('front', child.pid); if (said) console.log(said); } catch (e) { console.log(String(e.stdout || '').trim()); console.log('Windows kept another window in front'); }
console.log('window', JSON.stringify(commands.state()));
const first = `window.OUT=${JSON.stringify(slash(out))};window.RUN=${JSON.stringify(slash(o.run || ''))};window.TAG=${JSON.stringify(o.tag || '')};window.SYSTEM='windows';\n`;
await send('Page.addScriptToEvaluateOnNewDocument', { source: first + readFileSync(path.join(here, '..', 'lib.js'), 'utf8') + readFileSync(script, 'utf8') });
await send('Page.reload');
const left = await finished; clearTimeout(limit);
// The script's last act is the app's own Quit.
for (let i = 0; i < 40 && gone === null; i++) await wait(250);
if (gone === null) fail('the app did not quit');
console.log(`${path.basename(script)} ${o.tag || ''}: ${left} failures, the app left with ${gone}`);
process.exit(left || failures || gone !== 0 ? 1 : 0);
