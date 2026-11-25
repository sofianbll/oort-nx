/* A controller, read as the page reads one, and how smooth it all stays. */
probe(async P => {
  if (!(await oort.ask('folders')).folders.length) await oort.ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20);
  P.same(document.hasFocus(), true, 'the window has the focus');
  const hint = () => document.querySelector('#hints').textContent;
  P.ok(hint().includes('⏎'), 'without a controller the hints are the keys of the keyboard');
  P.pad(); await P.until(() => hint().includes('A') && !hint().includes('⏎'), 3000, 'hints follow the controller'); P.say('ok hints follow the controller');
  const a = P.id(); await P.button(15); P.ok(P.id() !== a, 'the cross moves'); await P.button(14); P.same(P.id(), a, 'and back');
  PAD.axes[0] = 1; await P.wait(900); PAD.axes[0] = 0; await P.wait(200); const i = +document.activeElement.dataset.i; P.ok(i >= 5, 'a held stick repeats: tile ' + i);
  await P.button(13); P.same(P.id(), 'primary', 'down'); await P.button(1); P.ok(document.activeElement.matches('.tile'), 'B (Xbox) goes back');
  await P.button(5); await P.wait(400); P.same(document.querySelector('[role=tab][aria-selected=true]').textContent, document.querySelectorAll('[role=tab]')[1].textContent, 'RB turns the tab'); await P.button(4); await P.wait(400);
  await P.button(8); await P.until(() => document.querySelector('.grid')); P.say('ok View shows the grid'); await P.button(8); await P.wait(200);
  await P.button(8, 700); await P.until(() => document.querySelector('.find')); P.say('ok holding View searches'); await P.shot('30-search-pad');
  P.ok(document.activeElement.closest('.keyboard'), 'the keys on screen have the focus'); for (const c of 'harb') { [...document.querySelectorAll('.keyboard .key')].find(k => k.textContent === c).focus(); await P.button(0); await P.wait(120); }
  await P.until(() => document.querySelectorAll('.found .tile').length === 2); P.say('ok typed with the controller'); await P.shot('31-search-typed'); await P.button(1); await P.until(() => oort.layers.length === 1);
  await P.button(9); await P.until(() => document.querySelector('.shell')); P.say('ok Menu opens Settings'); await P.button(5); await P.button(5); P.ok(document.querySelector('.col h1').textContent.length, 'RB turns the settings'); await P.button(1); await P.until(() => oort.layers.length === 1);
  // A Nintendo pad: the same places, the other letters.
  P.pad('Pro Controller (STANDARD GAMEPAD Vendor: 057e Product: 2009)'); await P.until(() => /ZL|R3|−|\+/.test(hint()), 3000, 'Nintendo names'); await P.button(13); P.same(P.id(), 'primary', 'down'); await P.button(0); P.ok(document.activeElement.matches('.tile'), 'the bottom button is B there'); await P.shot('32-nintendo');
  P.pad('DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c)'); await P.until(() => /△|□|○|✕|Share|Create|Options/i.test(document.querySelector('#hints').textContent.replace('Options', '')), 3000, 'PlayStation names'); P.say('ok PlayStation names', hint()); await P.shot('33-playstation');
  PAD = null; await P.until(() => hint().includes('⏎'), 3000, 'back to keys'); P.say('ok back to the keyboard');
  // Not in front: the controller belongs to the game.
  // Smoothness: frames while the shelf moves, then while the cloud turns alone.
  const frames = async (ms, work) => { const d = []; let last = performance.now(), run = true; const f = t => { d.push(t - last); last = t; if (run) requestAnimationFrame(f); }; requestAnimationFrame(f); const until = performance.now() + ms; while (performance.now() < until) await work(); run = false; d.shift(); d.sort((x, y) => x - y); return { frames: d.length, fps: Math.round(1000 * d.length / d.reduce((x, y) => x + y, 0)), p50: +d[d.length >> 1].toFixed(1), p95: +d[Math.floor(d.length * .95)].toFixed(1), worst: +d.at(-1).toFixed(1), over50: d.filter(x => x > 50).length }; };
  await P.press('lt'); const c0 = { ...oort.cloud }, idle = await frames(3000, () => P.wait(100)); const c1 = { ...oort.cloud };
  P.say('SMOOTH cloud alone', idle, 'drawing', { perFrame: +((c1.spent - c0.spent) / Math.max(1, c1.frames - c0.frames)).toFixed(2) + ' ms', perSecond: Math.round((c1.frames - c0.frames) / 3) });
  let n = 0; const shelf = await frames(4000, async () => { oort.act(n++ < 24 ? 'right' : 'left'); if (n > 46) n = 0; await P.wait(110); }); P.say('SMOOTH shelf', shelf); P.ok(shelf.p95 < 34, 'the shelf: 95 % of frames under 34 ms');
  const times = []; for (let k = 0; k < 20; k++) { const t0 = performance.now(); oort.act(k % 2 ? 'left' : 'right'); await new Promise(r => requestAnimationFrame(r)); times.push(performance.now() - t0); await P.wait(60); } times.sort((x, y) => x - y); P.say('SMOOTH press to next frame', { p50: +times[10].toFixed(1), p95: +times[18].toFixed(1) }); P.ok(times[18] < 50, 'a press shows in the next frames');
  const m = []; for (let k = 0; k < 30; k++) { const t0 = performance.now(); await oort.ask('library', { tab: 'All games' }); m.push(performance.now() - t0); } m.sort((x, y) => x - y); P.say('SMOOTH core round trip', { p50: +m[15].toFixed(1), p95: +m[28].toFixed(1) });
  P.ok(oort.sounds.played > 10, 'sounds played: ' + oort.sounds.played);
});
