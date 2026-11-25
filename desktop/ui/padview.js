/* The pad in the player's hands, in the cloud's dots: what is pressed lights up, the sticks lean. Then the same with a
   line from each button to what it does (the Mac app's OortControllerView and OortControllerMap). */
import { SHAPES, sides } from './pads.js';

/* SeleneTokens.Alpha */
const NEAR = .92, STRONG = .75, MUTED = .6, VEIL = .55, HALF = .45, MIST = .3, LINE = .22;
const TAU = Math.PI * 2, HEIGHT = .74, MIDDLE = .395, LEAN = .045;
/* Canvas units of the map: the pad, a label's height, the room between a label and the pad, and how a line bends. */
const PAD = 460, ROW = 46, GAP = 54, BEND = 28, END = 8, LEAST = 150;

/* A pad of `size` points wide, its middle at (cx, cy). */
export const drawPad = (x, shape, live, { size, cx, cy, mark, lit, ink, font, quiet }) => {
  const unit = size / 2, zoom = size / 420, light = b => live.light(b, quiet);
  const dot = (px, py, r, color, alpha) => { x.globalAlpha = Math.max(0, Math.min(1, alpha)); x.fillStyle = color; x.beginPath(); x.arc(cx + px * unit, cy + py * unit, Math.max(.4, r * zoom), 0, TAU); x.fill(); };
  const ring = (px, py, radius, r, color, alpha) => { const n = Math.max(6, Math.floor(radius * 300)); for (let i = 0; i < n; i++) dot(px + Math.cos(i / n * TAU) * radius, py + Math.sin(i / n * TAU) * radius, r, color, alpha); };
  const disc = (px, py, radius, amount) => { if (amount <= .04) return; for (let t = 0; t <= radius * .9; t += .017) { const n = Math.max(1, Math.floor(t * 340)); for (let i = 0; i < n; i++) dot(px + Math.cos(i / n * TAU) * t, py + Math.sin(i / n * TAU) * t, 1 + amount * 1.5, lit, amount); } };
  const line = (a, b, r, color, alpha) => { const n = Math.max(1, Math.floor(Math.hypot(b[0] - a[0], b[1] - a[1]) / .0185)); for (let i = 0; i < n; i++) dot(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, r, color, alpha); };
  const outline = (px, py, points, color) => points.forEach(([a, b], i) => { const [c, d] = points[(i + 1) % points.length]; line([px + a, py + b], [px + c, py + d], 1.05, color, NEAR); });
  for (const [a, b] of shape.body) { const shade = .4 + .5 * Math.max(0, .5 + a * .5 - b * .4); dot(a, b, .55 + shade, mark, .14 + shade * .46); }
  for (const [a, b] of shape.rim) dot(a, b, 1.15, mark, STRONG);
  for (const p of shape.parts) {
    const amount = light(p.button === 'touchpad' ? 'view' : p.button), color = amount > .04 ? lit : mark, { x: px, y: py, radius: r } = p;
    if (p.figure === 'face' || p.figure === 'small') {
      disc(px, py, r, amount * MUTED); ring(px, py, r, 1.1 + amount * .6, color, NEAR);
      if (p.mark) { x.globalAlpha = 1; x.fillStyle = ink; x.font = `600 ${('▴▾◂▸'.includes(p.mark) ? r * 1.5 : r * 1.05) * unit}px ${font}`; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(p.mark, cx + px * unit, cy + py * unit + r * .06 * unit); }
    } else if (p.figure === 'stick') {
      const s = p.button === 'l3' ? live.left : live.right, dx = px + s[0] * LEAN, dy = py + s[1] * LEAN;
      ring(px, py, r, 1.1, mark, NEAR); disc(dx, dy, r * .66, amount); ring(dx, dy, r * .66, 1.2, color, NEAR);
      for (let t = 0; t < r * .5; t += .026) ring(dx, dy, t, .75, mark, HALF);
    } else if (p.figure === 'cross') {
      const a = r * .36;
      for (const [b, dx, dy] of [['up', 0, -1], ['down', 0, 1], ['left', -1, 0], ['right', 1, 0]]) disc(px + dx * r * .66, py + dy * r * .66, a, light(b));
      outline(px, py, [[-a, -r], [a, -r], [a, -a], [r, -a], [r, a], [a, a], [a, r], [-a, r], [-a, a], [-r, a], [-r, -a], [-a, -a]], mark);
    } else if (p.figure === 'pill') { disc(px, py, r, amount); outline(px, py, [[-r, -r * 1.4], [0, -r * 2], [r, -r * 1.4], [r, r * 1.4], [0, r * 2], [-r, r * 1.4]], color); }
    else if (p.figure === 'square') { const s = r * .82; outline(px, py, [[-s, -s], [s, -s], [s, s], [-s, s]], color); ring(px, py, r * .34, .9 + amount, color, NEAR); }
    else { for (let c = -11; c <= 11; c++) for (let k = -6; k <= 6; k++) dot(px + c * .0205, py + k * .0255, .6 + amount, color, LINE + amount * .6); outline(px, py, [[-.27, -r], [.27, -r], [.235, r], [-.235, r]], color); }
  }
  for (const s of shape.shoulders) {
    const amount = light(s.button);
    for (let k = 0; k < s.rows; k++) for (let i = 0; i <= 26; i++) { const t = i / 26; dot(s.from[0] + (s.to[0] - s.from[0]) * t, s.from[1] + (s.to[1] - s.from[1]) * (1 - Math.pow(1 - t, 2.2)) + k * .018, 1.05 + amount * .9, amount > .04 ? lit : mark, VEIL + .4 * t * (1 - amount) + amount); }
  }
  x.globalAlpha = 1;
};

const held = (live, button) => button === 'up' ? ['up', 'down', 'left', 'right'].some(b => live.held.has(b)) : live.held.has(button);

/* `entries`: { button, name, title, hold }. Labels sit at the sides; where there is no room for them, under the pad. */
export const padMap = ({ kind, entries, live, label, quiet }) => {
  const shape = SHAPES(kind), el = document.createElement('div'), canvas = document.createElement('canvas'), list = document.createElement('ul'), unit = document.createElement('i'), x = canvas.getContext('2d');
  el.className = 'padmap'; canvas.setAttribute('aria-hidden', 'true'); unit.setAttribute('aria-hidden', 'true'); list.setAttribute('aria-label', label);
  const labels = new Map(entries.filter(e => shape.anchors[e.button]).map(e => {
    const li = document.createElement('li'), name = document.createElement('b'), words = document.createElement('span');
    name.textContent = e.name; words.textContent = e.title;
    if (e.hold) { const small = document.createElement('small'); small.textContent = e.hold; words.append(small); }
    li.append(name, words); list.append(li);
    return [e.button, li];
  }));
  el.append(unit, canvas, list);
  let placed = null, frame = 0, was = false;
  const place = () => {
    const W = el.clientWidth, u = unit.getBoundingClientRect().width / 100;
    if (!W || !u) return;
    const pad = Math.min(PAD * u, W), k = pad / PAD, column = Math.floor((W - pad) / 2 - GAP * k), row = Math.max(ROW * u, 30), narrow = column < LEAST;
    const both = sides([...labels.keys()], shape, row / (pad / 2)), H = narrow ? pad * HEIGHT : Math.max(...both.map(s => s.length), 7) * row;
    const height = Math.max(H, pad * HEIGHT), d = Math.min(devicePixelRatio || 1, 2);
    el.classList.toggle('narrow', narrow);
    el.style.setProperty('--h', height + 'px');
    canvas.style.height = height + 'px'; canvas.width = W * d; canvas.height = height * d; x.setTransform(d, 0, 0, d, 0, 0);
    const rows = new Map();
    both.forEach((side, n) => side.forEach((b, i) => { const y = height / 2 + (i - (side.length - 1) / 2) * row, li = labels.get(b); rows.set(b, { y, side: n ? 1 : -1 }); li.className = n ? 'r' : 'l'; li.style.cssText = narrow ? '' : `top:${y - row / 2}px;width:${column}px;height:${row}px`; }));
    placed = { W, height, pad, k, column, rows, narrow, top: (height - pad * HEIGHT) / 2 }; draw();
  };
  const draw = () => {
    if (!placed) return;
    const { W, height, pad, k, column, rows, narrow, top } = placed, at = getComputedStyle(document.documentElement), look = getComputedStyle(el), lit = at.getPropertyValue('--focus').trim(), ink = look.color, cx = W / 2, cy = top + pad * MIDDLE;
    x.clearRect(0, 0, W, height);
    drawPad(x, shape, live, { size: pad, cx, cy, mark: at.getPropertyValue('--glyph').trim(), lit, ink, font: look.fontFamily, quiet });
    for (const [button, { y, side }] of rows) {
      const on = held(live, button); labels.get(button).classList.toggle('on', on);
      if (narrow) continue;
      const { middle, radius } = shape.anchors[button], m = [cx + middle[0] * pad / 2, cy + middle[1] * pad / 2], end = cx + side * (W / 2 - column - END * k), bend = [end - side * BEND * k, y];
      const length = Math.max(1, Math.hypot(bend[0] - m[0], bend[1] - m[1])), reach = radius * pad / 2 / length, start = [m[0] + (bend[0] - m[0]) * reach, m[1] + (bend[1] - m[1]) * reach];
      x.strokeStyle = x.fillStyle = on ? lit : ink; x.lineCap = x.lineJoin = 'round'; x.lineWidth = on ? 2 : 1;
      x.globalAlpha = on ? 1 : MIST; x.beginPath(); x.moveTo(...start); x.lineTo(...bend); x.lineTo(end, y); x.stroke();
      x.globalAlpha = on ? 1 : STRONG; x.beginPath(); x.arc(...start, on ? 3.5 : 2, 0, TAU); x.fill();
    }
    x.globalAlpha = 1;
  };
  const tick = () => { frame = 0; if (!el.isConnected) return; draw(); if (live.awake()) frame = requestAnimationFrame(tick); };
  const deaf = live.listen(() => { if (el.isConnected) was = true; else if (was) { deaf(); sized.disconnect(); return; } if (!frame) frame = requestAnimationFrame(tick); });
  const sized = new ResizeObserver(() => { was = true; requestAnimationFrame(place); }); sized.observe(el);
  document.fonts.ready.then(draw);
  return el;
};
