/* Runs a script of desktop/tests in the page without any window: Chromium's headless shell (the engine of WebView2), the
   real oort-core, and a stand-in for the host. Nothing is shown and no key reaches the machine: keys, mouse and fingers
   are the browser's own. Node 22, no package.
   usage: headless.mjs <oort-core> <headless shell> <script.js> <pictures> run=<fixtures> key=value…
   keys: data, tag, size (WxH), language, system (windows|linux), zoom (device pixels), touch (1) */
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { createInterface } from 'node:readline';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { hands } from './hands.mjs';

const [coreFile, shell, script, out, ...pairs] = process.argv.slice(2), o = Object.fromEntries(pairs.map(p => [p.slice(0, p.indexOf('=')), p.slice(p.indexOf('=') + 1)]));
const here = import.meta.dirname, ui = path.join(here, '..', 'ui'), wait = ms => new Promise(r => setTimeout(r, ms));
const [width, height] = (o.size || '1440x900').split('x').map(Number), system = o.system || 'linux', temp = mkdtempSync(path.join(tmpdir(), 'oort-headless-'));
mkdirSync(out, { recursive: true });

// The core, with folders of its own.
const home = path.join(temp, 'home'), data = o.data || path.join(temp, 'data');
mkdirSync(home, { recursive: true });
const core = spawn(coreFile, ['--data', data, '--resources', path.join(here, '../src-tauri'), '--system', system, '--home', home, '--documents', path.join(home, 'Documents'), '--local', path.join(home, 'local'), '--config', path.join(home, 'config'), '--languages', o.language || 'fr'], { env: { PATH: '/usr/bin:/bin', HOME: home, CFFIXED_USER_HOME: home }, stdio: ['pipe', 'pipe', 'inherit'] });
let number = 0; const asked = new Map();
createInterface({ input: core.stdout }).on('line', line => { const m = JSON.parse(line); asked.get(m.id)?.(m); asked.delete(m.id); });
const ask = (method, params = {}) => new Promise((done, fail) => { const id = ++number; asked.set(id, m => 'error' in m ? fail(m.error) : done(m.result)); core.stdin.write(JSON.stringify({ id, method, params }) + '\n'); });

// What the window's host does, for the page; what it was asked to do is kept.
const did = [], state = { abilities: (o.abilities || 'fullscreen,hide,restart,quit').split(',') };
// One sound is made for all: a debug core takes its time, and nothing is heard.
let sound = null;
const invoke = {
  core: ({ method, params }) => method === 'sound' ? sound ??= ask(method, params) : ask(method, params), pads: () => (o.pads || '').split(',').filter(Boolean), abilities: () => state.abilities,
  quit: () => { did.push('quit'); if (o.stays) return null; end?.(null); return null; },
};
const kinds = { js: 'text/javascript', css: 'text/css', html: 'text/html', woff2: 'font/woff2', ttf: 'font/ttf' };
const csp = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-src 'none'";
const server = createServer(async (q, r) => {
  const url = new URL(q.url, 'http://x');
  try {
    if (url.pathname === '/invoke') {
      let body = ''; for await (const c of q) body += c;
      const { name, args } = JSON.parse(body); if (name !== 'core') did.push([name, args]);
      const result = await (invoke[name] || (() => null))(args || {});
      return r.end(JSON.stringify({ result: result ?? null }));
    }
    if (url.pathname.startsWith('/art/')) {
      const [id, kind] = decodeURIComponent(url.pathname.slice(5)).split('/'), file = await ask('game.art', { id, kind }).catch(() => null);
      if (!file || !existsSync(file)) return r.writeHead(404).end();
      return r.writeHead(200, { 'Cache-Control': 'max-age=60' }).end(readFileSync(file));
    }
    const file = path.join(ui, url.pathname === '/' ? 'index.html' : url.pathname);
    if (!file.startsWith(ui) || !existsSync(file)) return r.writeHead(404).end();
    r.writeHead(200, { 'Content-Type': kinds[file.split('.').pop()] || 'application/octet-stream', 'Content-Security-Policy': csp }).end(readFileSync(file));
  } catch (e) { r.end(JSON.stringify({ error: String(e) })); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = spawn(shell, ['--remote-debugging-port=0', `--user-data-dir=${path.join(temp, 'browser')}`, '--no-first-run', '--mute-audio', '--disable-background-networking', '--autoplay-policy=no-user-gesture-required', '--hide-scrollbars', ...(o.touch ? ['--touch-events=enabled'] : []), 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
let end; const finished = new Promise(r => { end = r; });
const leave = async code => { browser.kill(); core.stdin.end(); server.close(); await wait(300); try { rmSync(temp, { recursive: true, force: true, maxRetries: 3 }); } catch { } process.exit(code); };
const limit = setTimeout(() => { console.log('FAIL the script took too long'); leave(1); }, +(o.limit || 240) * 1000);
const port = await new Promise((r, no) => { createInterface({ input: browser.stderr }).on('line', l => { const m = /ws:\/\/127\.0\.0\.1:(\d+)/.exec(l); if (m) r(m[1]); }); browser.on('exit', () => no(new Error('the browser left'))); });
const target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find(t => t.type === 'page');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r, e) => { socket.onopen = r; socket.onerror = e; });
let n = 0, failures = 0; const waiting = new Map();
const send = (method, params = {}) => new Promise((resolve, reject) => { const id = ++n; waiting.set(id, m => m.error ? reject(new Error(method + ': ' + m.error.message)) : resolve(m.result)); socket.send(JSON.stringify({ id, method, params })); });
const keyNames = { 13: 'Enter', 27: 'Escape', 37: 'ArrowLeft', 38: 'ArrowUp', 39: 'ArrowRight', 40: 'ArrowDown', 122: 'F11', 93: 'ContextMenu' };
const commands = {
  report: line => { console.log(line); if (/^(FAIL|ERROR|REJECTED|THROWN)/.test(line)) failures++; },
  shot: async name => { const { data } = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(path.join(out, `${o.tag || ''}${name}.png`), Buffer.from(data, 'base64')); },
  front: () => true, did: () => did.splice(0), abilities: list => { state.abilities = list; },
  key: async code => { const key = keyNames[code] || String.fromCharCode(code).toLowerCase(), text = key.length === 1 ? key : code === 13 ? '\r' : undefined; await send('Input.dispatchKeyEvent', { type: text ? 'keyDown' : 'rawKeyDown', key, windowsVirtualKeyCode: code, text }); await send('Input.dispatchKeyEvent', { type: 'keyUp', key, windowsVirtualKeyCode: code }); },
  ...hands(send, wait),
};
socket.onmessage = async e => {
  const m = JSON.parse(e.data);
  if (m.id) { const done = waiting.get(m.id); waiting.delete(m.id); return done?.(m); }
  if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error' && !/404/.test(m.params.entry.text)) { failures++; console.log('ERROR', m.params.entry.text); }
  if (m.method !== 'Runtime.bindingCalled' || m.params.name !== 'oortHost') return;
  const { id, command, args } = JSON.parse(m.params.payload);
  let result = null; try { result = await commands[command](...args) ?? null; } catch (err) { console.log('host', command, err.message); }
  send('Runtime.evaluate', { expression: `window.hostReply(${id},${JSON.stringify(result)})` }).catch(() => {});
};
for (const domain of ['Runtime', 'Page', 'Log']) await send(domain + '.enable');
await send('Runtime.addBinding', { name: 'oortHost' });
await send('Emulation.setFocusEmulationEnabled', { enabled: true });
await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: +(o.zoom || 1), mobile: false });
if (o.touch) await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
// Tauri's own names, answered by the stand-in. No sound is made.
const tauri = `window.OUT=${JSON.stringify(out)};window.RUN=${JSON.stringify(o.run || '')};window.TAG=${JSON.stringify(o.tag || '')};window.HEADLESS=true;window.TOUCH=${!!o.touch};
(() => { const heard = new Map(); window.hear = (name, payload) => (heard.get(name) || []).forEach(f => f({ payload }));
window.__TAURI__ = { core: { convertFileSrc: p => '/art/' + encodeURIComponent(p), invoke: async (name, args) => { const r = await (await fetch('/invoke', { method: 'POST', body: JSON.stringify({ name, args }) })).json(); if ('error' in r) throw r.error; return r.result; } }, event: { listen: async (name, f) => { heard.set(name, [...(heard.get(name) || []), f]); return () => {}; } } }; })();\n`;
await send('Page.addScriptToEvaluateOnNewDocument', { source: tauri + readFileSync(path.join(here, 'lib.js'), 'utf8') + readFileSync(script, 'utf8') });
await send('Page.navigate', { url: origin });
await finished; clearTimeout(limit);
console.log(`${path.basename(script)} ${o.tag || ''}: ${failures} failures`);
await leave(failures ? 1 : 0);
