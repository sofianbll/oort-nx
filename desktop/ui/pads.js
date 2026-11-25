/* One controller's outline and the place of each of its buttons, by kind: the Mac app's own drawings (ControllerShape).
   Half the pad's width is 1 and its middle the origin. No page here: tests/nav.test.mjs. */
import { brand } from './nav.js';

export const KINDS = ['xbox', 'playstation', 'switchPro', 'joyConPair', 'joyConLeft', 'joyConRight'];
/* Product names, the same in every language. */
export const KIND_NAMES = { xbox: 'Xbox', playstation: 'PlayStation', switchPro: 'Switch Pro', joyConPair: 'Joy-Con', joyConLeft: 'Joy-Con (L)', joyConRight: 'Joy-Con (R)' };
/* Whose button names a kind has (ButtonNameStyle). */
export const kindNames = kind => kind === 'xbox' || kind === 'playstation' ? kind : 'nintendo';
/* A controller of no known family is drawn as an Xbox one, whose places most of them follow. */
export const padKind = (name = '') => {
  const family = brand(name);
  if (family !== 'nintendo') return family;
  if (!/joy-?con|2006|2007|200e/i.test(name)) return 'switchPro';
  return /\(l\)|product: 2006/i.test(name) ? 'joyConLeft' : /\(r\)|product: 2007/i.test(name) ? 'joyConRight' : 'joyConPair';
};

const part = (button, x, y, radius, figure, mark = '') => ({ button, x, y, radius, figure, mark });
const faces = (x, y, reach, radius, marks) => [['y', 0, -1], ['x', -1, 0], ['b', 1, 0], ['a', 0, 1]].map(([place, dx, dy], i) => part(marks[i][0] || place, x + dx * reach, y + dy * reach, radius, 'face', marks[i][1]));
/* Top, left, right, bottom. */
const XBOX = [['y', 'Y'], ['x', 'X'], ['b', 'B'], ['a', 'A']], PLAYSTATION = [['y', '△'], ['x', '□'], ['b', '○'], ['a', '✕']], NINTENDO = [['x', 'X'], ['y', 'Y'], ['a', 'A'], ['b', 'B']];
const cross = (x, y, radius) => part('up', x, y, radius, 'cross');
const shoulders = (outer, inner, low, high) => [['l', 'zl', -1], ['r', 'zr', 1]].flatMap(([bumper, trigger, side]) => [
  { button: bumper, from: [side * outer, low], to: [side * inner, high], rows: 2 },
  { button: trigger, from: [side * (outer + .01), low - .085], to: [side * inner, high - .085], rows: 4 }]);
/* Held sideways, the rail on top. */
const rail = [{ button: 'l', from: [-.44, -.3], to: [-.14, -.3], rows: 2 }, { button: 'r', from: [.44, -.3], to: [.14, -.3], rows: 2 }];
const SIDEWAYS = ['M 56 96 L 364 96 L 364 148 C 364 194 338 212 296 212 L 124 212 C 82 212 56 194 56 148 Z'];

const DATA = {
  xbox: {
    outline: ['M 104 48 C 134 38 150 46 168 46 L 252 46 C 270 46 286 38 316 48 C 352 58 372 108 390 178 C 406 244 390 286 356 280 C 326 274 308 226 278 214 C 262 208 158 208 142 214 C 112 226 94 274 64 280 C 30 286 14 244 30 178 C 48 108 68 58 104 48 Z'],
    parts: [cross(-.215, .06, .115), ...faces(.455, -.225, .12, .058, XBOX), part('l3', -.45, -.22, .135, 'stick'), part('r3', .22, .06, .125, 'stick'), part('view', -.105, -.235, .042, 'small', '❐'), part('menu', .105, -.235, .042, 'small', '☰'), part('capture', 0, -.15, .032, 'small'), part('home', 0, -.365, .06, 'small')],
    shoulders: shoulders(.66, .3, -.36, -.545),
  },
  playstation: {
    outline: ['M 92 46 C 118 36 132 42 146 42 L 274 42 C 288 42 302 36 328 46 C 358 56 378 108 394 182 C 406 246 402 290 366 288 C 336 286 322 238 302 212 C 296 204 290 204 280 204 L 140 204 C 130 204 124 204 118 212 C 98 238 84 286 54 288 C 18 290 14 246 26 182 C 42 108 62 56 92 46 Z'],
    // Here View is Create; the touchpad, pressed, does the same.
    parts: [cross(-.505, -.215, .125), ...faces(.505, -.215, .128, .056, PLAYSTATION), part('l3', -.245, .06, .12, 'stick'), part('r3', .245, .06, .12, 'stick'), part('touchpad', 0, -.29, .18, 'pad'), part('view', -.345, -.42, .028, 'pill'), part('menu', .345, -.42, .028, 'pill'), part('home', 0, .06, .044, 'small')],
    shoulders: shoulders(.66, .37, -.39, -.545),
  },
  switchPro: {
    outline: ['M 112 50 C 150 42 270 42 308 50 C 350 58 372 108 390 188 C 406 252 384 284 352 272 C 318 258 304 216 272 208 C 240 202 180 202 148 208 C 116 216 102 258 68 272 C 36 284 14 252 30 188 C 48 108 70 58 112 50 Z'],
    parts: [cross(-.215, .07, .115), ...faces(.46, -.205, .12, .058, NINTENDO), part('l3', -.46, -.2, .13, 'stick'), part('r3', .22, .07, .125, 'stick'), part('view', -.2, -.36, .038, 'small', '−'), part('menu', .2, -.36, .038, 'small', '+'), part('capture', -.09, -.235, .034, 'square'), part('home', .09, -.235, .04, 'small')],
    shoulders: shoulders(.66, .28, -.36, -.53),
  },
  joyConPair: {
    outline: ['M 176 30 L 134 30 C 90 30 74 56 74 96 L 74 214 C 74 254 90 280 134 280 L 176 280 Z', 'M 244 30 L 286 30 C 330 30 346 56 346 96 L 346 214 C 346 254 330 280 286 280 L 244 280 Z'],
    parts: [...faces(-.41, .09, .115, .052, [['up', '▴'], ['left', '◂'], ['right', '▸'], ['down', '▾']]), ...faces(.41, -.25, .115, .052, NINTENDO), part('view', -.23, -.46, .036, 'small', '−'), part('l3', -.41, -.27, .125, 'stick'), part('capture', -.27, .41, .034, 'square'), part('menu', .23, -.46, .036, 'small', '+'), part('r3', .41, .11, .125, 'stick'), part('home', .27, .41, .042, 'small')],
    shoulders: shoulders(.62, .24, -.47, -.63),
  },
  // The printed marks turn with a Joy-Con held sideways, the places do not.
  joyConLeft: {
    outline: SIDEWAYS,
    parts: [...faces(.2, .03, .115, .052, [['x', '▸'], ['y', '▴'], ['a', '▾'], ['b', '◂']]), part('menu', -.63, -.17, .036, 'small', '−'), part('capture', .62, -.16, .034, 'square'), part('l3', -.43, .04, .125, 'stick')],
    shoulders: rail,
  },
  joyConRight: {
    outline: SIDEWAYS,
    parts: [...faces(.2, .03, .115, .052, [['x', 'Y'], ['y', 'B'], ['a', 'X'], ['b', 'A']]), part('menu', .62, -.16, .036, 'small', '+'), part('home', -.63, -.17, .042, 'small'), part('l3', -.43, .04, .125, 'stick')],
    shoulders: rail,
  },
};

const covers = (p, [x, y]) => {
  const dx = Math.abs(x - p.x), dy = Math.abs(y - p.y), r = p.radius;
  if (p.figure === 'cross') return dx < r * 1.1 && dy < r * .46 || dy < r * 1.1 && dx < r * .46;
  if (p.figure === 'pill') return dx < r * 1.1 && dy < r * 2.2;
  if (p.figure === 'square') return dx < r * 1.25 && dy < r * 1.25;
  if (p.figure === 'pad') return dx < .285 && dy < r * 1.1;
  return Math.hypot(dx, dy) < r * 1.18;
};
/* Absolute M, C, L and Z, as points close enough to be a line. */
const flat = text => {
  const words = text.split(' '), out = []; let i = 0, command = 'M';
  const number = () => +words[i++];
  while (i < words.length) {
    if (/[MCLZ]/.test(words[i])) { command = words[i++]; if (command === 'Z') out.push(out[0]); continue; }
    if (command !== 'C') { out.push([number(), number()]); continue; }
    const [p, a, b, c] = [out.at(-1), [number(), number()], [number(), number()], [number(), number()]];
    for (let k = 1; k <= 24; k++) { const t = k / 24, u = 1 - t; out.push([0, 1].map(n => u * u * u * p[n] + 3 * u * u * t * a[n] + 3 * u * t * t * b[n] + t * t * t * c[n])); }
  }
  return out;
};
const inside = (line, x, y) => { let odd = false; for (let i = 0, k = line.length - 1; i < line.length; k = i++) { const [ax, ay] = line[i], [bx, by] = line[k]; if (ay > y !== by > y && x < (bx - ax) * (y - ay) / (by - ay) + ax) odd = !odd; } return odd; };
const along = (line, count) => {
  const reach = [0]; for (let i = 1; i < line.length; i++) reach.push(reach[i - 1] + Math.hypot(line[i][0] - line[i - 1][0], line[i][1] - line[i - 1][1]));
  const out = []; let k = 1;
  for (let n = 0; n < count; n++) { const d = (n + .5) / count * reach.at(-1); while (reach[k] < d) k++; const t = (d - reach[k - 1]) / (reach[k] - reach[k - 1] || 1); out.push([0, 1].map(c => line[k - 1][c] + (line[k][c] - line[k - 1][c]) * t)); }
  return out;
};
const cell = ([x, y]) => [(x - 210) / 210, (y - 150) / 210];
const STEP = 6.8, made = new Map();
/* { parts, shoulders, body, rim: dots, anchors: where a line from a button's label ends } */
export const SHAPES = kind => {
  if (made.has(kind)) return made.get(kind);
  const data = DATA[kind], lines = data.outline.map(flat), anchors = {}, body = [];
  for (const p of data.parts) anchors[p.button] = { middle: [p.x, p.y], radius: p.radius * 1.12 };
  for (const s of data.shoulders) anchors[s.button] = { middle: [(s.from[0] + s.to[0]) / 2, s.to[1] + (s.from[1] - s.to[1]) * .22], radius: 0 };
  for (let row = 0, y = 0; y < 310; row++, y = row * STEP * .866) for (let x = row % 2 * STEP / 2; x < 420; x += STEP) if (lines.some(l => inside(l, x, y))) { const c = cell([x, y]); if (!data.parts.some(p => covers(p, c))) body.push(c); }
  const shape = { ...data, kind, body, rim: lines.flatMap(l => along(l, lines.length > 1 ? 110 : 190).map(cell)), anchors };
  made.set(kind, shape);
  return shape;
};

/* The drawn buttons a controller's state presses. */
export const pressed = ({ name, b }) => {
  const N = brand(name) === 'nintendo', roles = { [N ? 'e' : 's']: 'a', [N ? 's' : 'e']: 'b', [N ? 'n' : 'w']: 'x', [N ? 'w' : 'n']: 'y', l1: 'l', r1: 'r', l2: 'zl', r2: 'zr', minus: 'view', plus: 'menu', l: 'l3', r: 'r3', h: 'home', up: 'up', down: 'down', left: 'left', right: 'right' };
  return new Set(Object.keys(roles).filter(k => b[k]).map(k => roles[k]));
};
/* What the hands do now: what is held, what still fades, how the sticks lean. Wakes its listeners only on a change. */
const FADE = 360, LEAN = .08;
export const liveOf = (clock = () => performance.now()) => {
  const released = new Map(), listeners = new Set();
  const live = {
    held: new Set(), left: [0, 0], right: [0, 0],
    listen(f) { listeners.add(f); return () => listeners.delete(f); },
    light(button, quiet) { if (live.held.has(button)) return 1; const t = clock() - (released.get(button) ?? -FADE); return quiet || t >= FADE ? 0 : 1 - t / FADE; },
    awake: () => live.held.size > 0 || [...live.left, ...live.right].some(Boolean) || [...released.values()].some(t => clock() - t < FADE),
    feed(s) {
      const now = s ? pressed(s) : new Set(), rest = v => Math.abs(v) < LEAN ? 0 : v, sticks = s ? s.ax.map(rest) : [0, 0, 0, 0];
      let changed = false;
      for (const b of live.held) if (!now.has(b)) { if (s) released.set(b, clock()); changed = true; }
      for (const b of now) if (!live.held.has(b)) changed = true;
      if ([...live.left, ...live.right].some((v, i) => v !== sticks[i])) changed = true;
      live.held = now; live.left = sticks.slice(0, 2); live.right = sticks.slice(2);
      if (changed) for (const f of listeners) f();
    },
  };
  return live;
};

const turn = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
export const crosses = (a, b, c, d) => turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0;
/* Labels on the left and on the right, so that no two of their lines cross. `row`: a label's height, in half pads. */
export const sides = (buttons, shape, row) => {
  const list = buttons.filter(b => shape.anchors[b]), x = b => shape.anchors[b].middle[0], y = b => shape.anchors[b].middle[1];
  const left = list.filter(b => x(b) < -.01), right = list.filter(b => x(b) > .01);
  for (const b of list) if (Math.abs(x(b)) <= .01) (left.length <= right.length ? left : right).push(b);
  return [[left, -1.15], [right, 1.15]].map(([side, edge]) => {
    side.sort((a, b) => y(a) - y(b));
    const at = i => [edge, (i - (side.length - 1) / 2) * row - .05], n = side.length;
    // Swapping the two ends of a crossing shortens the lines, so this stops; the bound is for rounding.
    for (let k = 0, swapped = true; swapped && k < n * n; k++) { swapped = false; for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) if (crosses(shape.anchors[side[i]].middle, at(i), shape.anchors[side[j]].middle, at(j))) { [side[i], side[j]] = [side[j], side[i]]; swapped = true; } }
    return side;
  });
};
