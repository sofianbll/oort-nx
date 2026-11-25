/* The Oort cloud cut open, in 3D: the site's own piece (v4), kept still under Reduce motion and asleep when covered. */
const TAU = Math.PI * 2;
let seed = 5;
const rnd = () => (seed = seed * 16807 % 2147483647) / 2147483647;

const points = n => {
  const pts = [], GA = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < n; i++) { const y = 1 - 2 * (i + .5) / n, r = Math.sqrt(1 - y * y), a = i * GA, x = Math.cos(a) * r, z = Math.sin(a) * r; if (z > .1) continue; const k = .9 + .1 * rnd(); pts.push([x * k, y * k, z * k, x, y, z, 0]); }
  for (let j = 0; j < 9; j++) { const r = 1 - j * .0165, m = Math.round(330 - j * 16); for (let i = 0; i < m; i++) { const a = i / m * TAU + j * .02, th = Math.cos(a); if (th < .15 && j > 3 + th * 3 + 3) continue; pts.push([Math.cos(a) * r, Math.sin(a) * r, .1 - j * .003, 0, 0, 1, 1]); } }
  for (let k = 0; k < 30; k++) { const t = .16 + k * .0262, m = Math.round(t * 150), th = .004 + .085 * Math.pow(t, 2.8), ly = Math.max(1, Math.round(th / .016)); for (let j = 0; j < ly; j++) { const h = ly === 1 ? 0 : (j / (ly - 1) - .5) * 2 * th; for (let i = 0; i < m; i++) { const a = (i + (k + j) % 2 * .5) / m * TAU; pts.push([Math.cos(a) * t, h, Math.sin(a) * t, 0, Math.sign(h) || 1, 0, 2]); } } }
  return pts;
};

const dots = (x, list, color) => {
  x.fillStyle = color;
  const B = 10, q = Array.from({ length: B + 1 }, () => []);
  for (const d of list) if (d[2] > .2 && d[3] > .03) q[Math.round(Math.min(1, d[3]) * B)].push(d);
  for (let i = 1; i <= B; i++) { if (!q[i].length) continue; x.globalAlpha = i / B; x.beginPath(); for (const d of q[i]) { x.moveTo(d[0] + d[2], d[1]); x.arc(d[0], d[1], d[2], 0, TAU); } x.fill(); }
  x.globalAlpha = 1;
};

export const cloud = canvas => {
  const x = canvas.getContext('2d'), pts = points(9800);
  let w = 0, h = 0, tx = 0, ty = 0, px = 0, py = 0, mx = -9e3, my = -9e3, born = performance.now(), awake = true, moves = true, frame = 0, last = 0, colors = ['#afc3e6', '#f4ce8e', '#fff'];
  const api = { spent: 0, frames: 0 };
  const draw = t => {
    const R = Math.min(h * .5, w * .33), cx = w * .71, cy = h * .5;
    px += (tx - px) * .06; py += (ty - py) * .06;
    const ya = -.36 + px * .3 + (moves ? Math.sin(t * .00021) * .11 : 0), xa = .3 + py * .2 + (moves ? Math.sin(t * .00016) * .05 : 0);
    const ca = Math.cos(ya), sa = Math.sin(ya), cb = Math.cos(xa), sb = Math.sin(xa);
    const grow = moves ? Math.min(1, (performance.now() - born) / 1500) : 1, ez = 1 - Math.pow(1 - grow, 4);
    const turn = moves ? t * .00007 : 0, ct = Math.cos(turn), st = Math.sin(turn), L = [-.62, -.5, .6], back = [], front = [];
    x.clearRect(0, 0, w, h);
    for (const p of pts) {
      let X = p[0], Y = p[1], Z = p[2];
      const nx = p[3], ny = p[4], nz = p[5];
      if (p[6] === 2) { const q = X * ct - Z * st; Z = X * st + Z * ct; X = q; }
      if (ez < 1) { const g = 1 + (1 - ez) * (1.6 + ((X * 37 + Y * 91) % 1)); X *= g; Y *= g; Z *= g; }
      const a = X * ca + Z * sa; let c = -X * sa + Z * ca; const b = Y * cb - c * sb; c = Y * sb + c * cb;
      const pr = 3.4 / (3.4 - c), sx = cx + a * R * pr, sy = cy + b * R * pr;
      if (sx < -8 || sx > w + 8 || sy < -8 || sy > h + 8) continue;
      let lum, rad;
      if (p[6] === 0) { const na = nx * ca + nz * sa; let nc = -nx * sa + nz * ca; const nb = ny * cb - nc * sb; nc = ny * sb + nc * cb; lum = Math.max(0, -(na * L[0] + nb * L[1] + nc * L[2])) * .62 + .07 + .2 * Math.max(0, 1 - Math.hypot(X, Y, Z) * .2 - Math.abs(Y)); rad = .0034 + .0046 * lum; }
      else if (p[6] === 1) { const lit = .5 + .5 * (p[0] * .86 - p[1] * .25); lum = .35 + .65 * lit; rad = .0032 + .0058 * lit; }
      else { const d = Math.hypot(X, Z); lum = .16 + .5 * Math.max(0, 1 - d * .95) + .42 * Math.max(0, c * .9 + .12); rad = .0022 + .0026 * (1 - d * .4) + .0016 * Math.max(0, c); }
      const dm = Math.hypot(sx - mx, sy - my);
      if (dm < 120) { const k = 1 - dm / 120; lum += k * k * .55; rad += k * k * .0045; }
      // Quiet under the words: on the left, under the clock and under the hints.
      const fade = Math.min(1, Math.max(0, (sx - w * .38) / (w * .14))) * Math.min(1, Math.max(0, (sy - h * .05) / (h * .09)), Math.max(0, (h * .95 - sy) / (h * .1)));
      (p[6] === 2 && c > .02 ? front : back).push([sx, sy, Math.max(.5, rad * R * pr), Math.min(1, lum) * fade * ez]);
    }
    dots(x, back, colors[0]);
    x.globalAlpha = ez; x.fillStyle = colors[1]; x.beginPath(); x.arc(cx, cy, R * .052, 0, TAU); x.fill(); x.globalAlpha = 1;
    dots(x, front, colors[0]);
  };
  const tick = t => {
    frame = 0;
    if (!awake || document.hidden || !w) return;
    if (t - last >= 1000 / 40 - 1) { last = t; const t0 = performance.now(); draw(t); api.spent += performance.now() - t0; api.frames++; }
    if (moves) frame = requestAnimationFrame(tick);
  };
  const go = () => { if (!frame) frame = requestAnimationFrame(tick); };
  new ResizeObserver(() => { const r = canvas.getBoundingClientRect(), d = Math.min(devicePixelRatio || 1, 2); w = r.width; h = r.height; canvas.width = w * d; canvas.height = h * d; x.setTransform(d, 0, 0, d, 0, 0); last = 0; go(); }).observe(canvas);
  addEventListener('pointermove', e => { if (e.pointerType === 'mouse') { mx = e.clientX; my = e.clientY; tx = mx / w - .5; ty = my / h - .5; } }, { passive: true });
  document.addEventListener('visibilitychange', go);
  return Object.assign(api, {
    set(o) { if ('awake' in o) awake = o.awake; if ('moves' in o && o.moves !== moves) { moves = o.moves; born = 0; } if (o.colors) colors = o.colors; last = 0; go(); },
  });
};
