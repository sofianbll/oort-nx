/* One focus, moved by keyboard, controller or pointer. The search for the nearest element and the reading of
   controllers are the site's (v4). */
export const still = matchMedia('(prefers-reduced-motion:reduce)');
const $$ = (s, r) => [...r.querySelectorAll(s)];

export const focusable = root => $$('button:not([disabled]):not([tabindex="-1"]),input,[tabindex="0"]', root).filter(e => { if (e.closest('[inert]')) return false; const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; });

/* The nearest element in a direction, weighed like the site: near first, aligned first. */
export const nearest = (from, list, dir) => {
  const V = dir === 'up' || dir === 'down', sg = dir === 'down' || dir === 'right' ? 1 : -1, A = from.getBoundingClientRect();
  let best = null, score = 1e9;
  for (const e of list) {
    if (e === from) continue;
    const R = e.getBoundingClientRect(), along = V ? (sg > 0 ? R.top - A.bottom : A.top - R.bottom) : (sg > 0 ? R.left - A.right : A.left - R.right);
    const centre = V ? (R.top + R.bottom - A.top - A.bottom) / 2 * sg : (R.left + R.right - A.left - A.right) / 2 * sg;
    if (centre < 6 || along < -Math.min(V ? A.height : A.width, V ? R.height : R.width) * .6) continue;
    const gap = V ? Math.max(0, R.left - A.right, A.left - R.right) : Math.max(0, R.top - A.bottom, A.top - R.bottom);
    const off = Math.abs(V ? (R.left + R.right - A.left - A.right) / 2 : (R.top + R.bottom - A.top - A.bottom) / 2);
    const s = Math.max(0, along) + gap * 2.4 + off * .12;
    if (s < score) { score = s; best = e; }
  }
  return best;
};

/* What a held direction repeats at: the Mac app's, and the site's. */
export const repeater = (fire, first = 340, next = 110) => { let held = null, at = 0; return (dir, now) => { if (!dir) held = null; else if (held !== dir) { held = dir; at = now + first; fire(dir); } else if (now > at) { at = now + next; fire(dir); } }; };

const nintendo = /057e|nintendo|switch|joy-?con|pro controller/i, sony = /054c|dualsense|dualshock|playstation|wireless controller/i;
export const brand = name => /xbox|045e/i.test(name) ? 'xbox' : nintendo.test(name) ? 'nintendo' : sony.test(name) ? 'playstation' : 'xbox';

const hat = v => { if (v === undefined || v > 1.05 || v < -1.05) return {}; const n = Math.round((v + 1) * 3.5); return { up: n === 7 || n < 2, right: n > 0 && n < 4, down: n > 2 && n < 6, left: n > 4 && n < 8 }; };
export const readPad = g => {
  const N = nintendo.test(g.id), B = i => !!g.buttons[i] && (g.buttons[i].pressed || g.buttons[i].value > .5), std = g.mapping === 'standard', h = std ? { up: B(12), down: B(13), left: B(14), right: B(15) } : hat(g.axes[9]);
  return { name: g.id, b: { s: B(0), e: B(1), w: B(2), n: B(3), l1: B(4), r1: B(5), l2: B(6), r2: B(7), minus: B(8), plus: B(9), l: B(10), r: B(11), h: B(std ? 16 : 12), ...h }, ax: [0, 1, 2, std || g.axes.length < 6 || N ? 3 : 5].map(k => g.axes[k] || 0) };
};
const strongest = () => { let g = null; try { for (const p of navigator.getGamepads ? navigator.getGamepads() : []) if (p && p.connected !== false && (!g || p.timestamp > g.timestamp)) g = p; } catch { } return g && readPad(g); };

/* `act(name)` gets a direction or a button by its role: a, b, x, y, lb, rb, lt, rt, view, menu, home, ls, rs. */
export const controller = ({ act, hold, found, scroll }) => {
  let sent, was = {}, name = null, menuAt = 0, viewAt = 0;
  const turn = repeater(act);
  const tick = now => {
    const s = document.hidden || !document.hasFocus() ? null : sent !== undefined ? sent : strongest();
    if (!s) { if (name !== null && document.hasFocus()) { name = null; found(null); } was = {}; return setTimeout(() => requestAnimationFrame(tick), 240); }
    if (name !== s.name) { name = s.name; was = s.b; found({ name, brand: brand(name) }); }
    const N = brand(name) === 'nintendo', b = s.b, ax = s.ax.map(v => Math.abs(v) < .35 ? 0 : v), dn = k => b[k] && !was[k], up = k => !b[k] && was[k];
    turn(b.up || ax[1] < -.55 ? 'up' : b.down || ax[1] > .55 ? 'down' : b.left || ax[0] < -.55 ? 'left' : b.right || ax[0] > .55 ? 'right' : null, now);
    const map = { a: N ? 'e' : 's', b: N ? 's' : 'e', x: N ? 'n' : 'w', y: N ? 'w' : 'n', lb: 'l1', rb: 'r1', lt: 'l2', rt: 'r2', ls: 'l', rs: 'r', home: 'h', menu: 'plus' };
    for (const k in map) if (dn(map[k])) act(k);
    if (dn('minus')) viewAt = now;
    if (viewAt && b.minus && now - viewAt > 450) { viewAt = 0; hold('view'); }
    if (up('minus') && viewAt) { viewAt = 0; act('view'); }
    if (ax[3]) scroll(ax[3] * 22);
    was = { ...b };
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  return { feed: s => { sent = s === null ? undefined : s; } };
};
