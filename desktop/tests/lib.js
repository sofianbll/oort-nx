/* Helpers for a script run inside the real window. */
(() => {
  // No controller but the script's own: one at hand on the machine must not press anything.
  window.PAD = null; navigator.getGamepads = () => window.PAD ? [window.PAD] : [];
  const wait = ms => new Promise(r => setTimeout(r, ms));
  const T = () => window.__TAURI__.core;
  const P = window.P = {
    wait, fails: 0,
    say: (...a) => T().invoke('report', { line: a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' ') }),
    async shot(name) { await wait(500); await T().invoke('shot', { path: `${window.OUT}/${window.TAG}${name}.tiff` }); },
    async until(f, ms = 8000, what = '') { const t0 = performance.now(); for (;;) { let v; try { v = await f(); } catch { } if (v) return v; if (performance.now() - t0 > ms) throw new Error('never: ' + (what || f)); await wait(40); } },
    ok(v, what) { if (!v) { P.fails++; P.say('FAIL', what); } else P.say('ok', what); },
    same(a, b, what) { P.ok(JSON.stringify(a) === JSON.stringify(b), `${what}: ${JSON.stringify(a)}${JSON.stringify(a) === JSON.stringify(b) ? '' : ' instead of ' + JSON.stringify(b)}`); },
    async key(k, o = {}) { (document.activeElement || document.body).dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...o })); await wait(90); },
    async press(name, n = 1) { for (let i = 0; i < n; i++) { window.oort.act(name); await wait(110); } },
    pad(id = 'Xbox Controller (STANDARD GAMEPAD)') { window.PAD = { id, mapping: 'standard', connected: true, timestamp: 1, buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })), axes: [0, 0, 0, 0] }; },
    async button(i, ms = 70) { window.PAD.buttons[i].pressed = true; await wait(ms); window.PAD.buttons[i].pressed = false; await wait(120); },
    text: s => document.querySelector(s)?.textContent.trim() ?? null,
    focus: () => document.activeElement?.textContent.trim().replace(/\s+/g, ' ').slice(0, 60),
    id: () => document.activeElement?.dataset.id ?? null,
    async end() { await P.say('END', P.fails, 'failures'); await wait(100); T().invoke('quit'); },
  };
  window.addEventListener('error', e => { P.fails++; P.say('ERROR', e.message, e.filename + ':' + e.lineno); });
  window.addEventListener('unhandledrejection', e => { P.fails++; P.say('REJECTED', String(e.reason && e.reason.stack || e.reason)); });
  window.probe = f => addEventListener('DOMContentLoaded', async () => { try { await P.until(() => document.documentElement.dataset.ready, 15000, 'ready'); await f(P); } catch (e) { P.fails++; await P.say('THROWN', String(e && e.message || e), window.oort && oort.layers.map(l => l.el.className + ':' + l.el.textContent.slice(0, 60)), document.activeElement && document.activeElement.outerHTML.slice(0, 160)); await P.shot('thrown').catch(() => {}); } await P.end(); });
})();
