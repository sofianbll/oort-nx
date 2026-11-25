/* The same screens in every look, for the eye: dark, light, still, small, large, in English. Measures what a machine can. */
probe(async P => {
  if (!(await oort.ask('folders')).folders.length) await oort.ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20);
  const luminance = c => { const m = c.match(/[\d.]+/g).map(Number); const f = m.slice(0, 3).map(v => { v = c.startsWith('color(') ? v : v / 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }); return f[0] * .2126 + f[1] * .7152 + f[2] * .0722; };
  const ratio = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p); return (x + .05) / (y + .05); };
  const solid = (value, prop = 'color') => { const e = document.createElement('i'); e.style[prop] = value; document.body.append(e); const c = getComputedStyle(e)[prop]; e.remove(); return c; };
  const cut = where => { const bad = [...document.querySelectorAll('.layer:not([inert]) :is(.key,.row .what,.side button,.tabs button,h1,.chip,.say,.stats dd)')].filter(e => { const r = e.getBoundingClientRect(); return r.width && (e.scrollWidth > e.clientWidth + 2 && getComputedStyle(e).overflow !== 'visible' && !e.closest('.gridinfo') || r.right > innerWidth + 1 && !e.closest('.tabs,.shelf,.side')); }).map(e => e.textContent.slice(0, 30)); P.ok(!bad.length, `${where}: nothing cut ${bad.join(' | ')}`); };
  const small = where => { const sizes = [...document.querySelectorAll('.layer:not([inert]) *, #hints *')].filter(e => e.childNodes.length && [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()) && e.getBoundingClientRect().width && !e.closest('.sr')).map(e => [parseFloat(getComputedStyle(e).fontSize), e.className || e.tagName, e.textContent.slice(0, 20)]).sort((a, b) => a[0] - b[0]); P.ok(sizes[0][0] >= 11, `${where}: smallest text ${JSON.stringify(sizes[0])}`); };
  const padFits = where => { const bad = [...document.querySelectorAll('.layer:not([hidden]) .padmap li')].filter(li => { const p = li.closest('.padmap').getBoundingClientRect(), [a, b] = [...li.children].map(c => c.getBoundingClientRect()); return Math.min(a.left, b.left) < p.left - 1 || Math.max(a.right, b.right) > p.right + 1 || a.left < b.right - 1 && b.left < a.right - 1; }).map(li => li.textContent); P.ok(!bad.length, `${where}: every label of the pad fits ${bad.join(' | ')}`); };
  const visit = async name => {
    const set = async (tag) => { cut(`${name} ${tag}`); small(`${name} ${tag}`); await P.shot(`${name}-${tag}`); };
    const i = oort.library.games.findIndex(g => !g.hero && g.state === 'ready') + 2; await P.press('lt'); for (let k = 0; k < i; k++) { oort.act('right'); await P.wait(15); } await P.wait(400); await set('shelf');
    await P.press('view'); await P.wait(300); await set('grid'); await P.press('view');
    await P.settings(); await P.press('down'); await P.press('right'); await P.wait(200); await set('settings'); await P.press('b'); await P.press('b'); while (oort.layers.length > 1) await P.press('b');
    await P.press('home'); await P.until(() => document.querySelector('.menu')); await P.wait(250); await P.press('a'); await P.wait(200); await set('menu'); await P.press('home'); await P.until(() => oort.layers.length === 1);
    await P.settings(); document.querySelector('[data-id=c-controllers]').click(); await P.until(() => document.querySelector('.padmap')); await P.wait(300); await set('pads'); padFits(name); while (oort.layers.length > 1) await P.press('b');
    await P.press('x'); await P.until(() => document.querySelector('.detail')); await P.wait(200); await set('detail'); await P.press('b'); await P.until(() => oort.layers.length === 1);
  };
  const looks = { dark: {}, light: { colorThemeID: 'catppuccin-latte' }, white: { colorThemeID: 'white' }, still: { reduceMotion: true }, zoom80: { interfaceZoom: .8 }, zoom125: { interfaceZoom: 1.25 }, english: { appLanguage: 'en' } };
  // Every palette, by number.
  for (const b of (await import(new URL('gen/names.js', location.href).href)).PALETTES) { document.documentElement.dataset.palette = b[0]; const raised = solid('var(--p-raised)', 'backgroundColor'); const bad = [['var(--ink)', raised, 4.5], ['var(--quiet)', raised, 4.5], ['var(--ring-color)', raised, 3], ['var(--mark)', raised, 3], ['var(--on-focus)', solid('var(--key)', 'backgroundColor'), 4.5], ['var(--on-focus)', solid('color-mix(in srgb,var(--key),var(--glyph) 22%)', 'backgroundColor'), 4.5]].filter(([c, d, min]) => ratio(solid(c), d) < min - .02).map(([c, d]) => c + ' ' + ratio(solid(c), d).toFixed(2)); P.ok(!bad.length, 'palette ' + b[0] + ' ' + bad.join(', ')); }
  oort.apply(await oort.ask('view'));
  for (const [name, values] of Object.entries(looks)) {
    if (window.TAG.startsWith('small') && ['white', 'english'].includes(name)) continue;
    for (const [id, value] of Object.entries(values)) await oort.ask('settings.set', { id, value });
    await oort.ask('settings.save'); await P.settings(); await P.press('b'); await P.until(() => oort.layers.length === 1); await P.wait(300);
    // The menu's page applied what was saved only if it changed the view: make sure.
    oort.apply(await oort.ask('view')); await P.wait(200);
    const panel = solid('var(--p-low)', 'backgroundColor'), raised = solid('var(--p-raised)', 'backgroundColor');
    for (const [a, b, min, what] of [['var(--ink)', panel, 4.5, 'ink on panel'], ['var(--ink)', raised, 4.5, 'ink on raised'], ['var(--quiet)', raised, 4.5, 'quiet on raised'], ['var(--on-focus)', solid('color-mix(in srgb,var(--key),var(--glyph) 22%)', 'backgroundColor'), 4.5, 'key text on focus'], ['var(--ring-color)', raised, 3, 'ring on raised'], ['var(--mark)', raised, 3, 'icon on raised']]) { const r = ratio(solid(a), b); P.ok(r >= min, `${name}: ${what} ${r.toFixed(1)}:1`); }
    await visit(name);
    if (name === 'still') { const before = oort.cloud.frames; await P.wait(600); P.same(oort.cloud.frames - before <= 1, true, 'the cloud holds still'); P.same(getComputedStyle(document.querySelector('.ring')).transitionDuration.split(',')[0], '0ms'.replace('ms', 's'), 'the ring does not glide'); }
    for (const id of Object.keys(values)) await oort.ask('settings.set', { id, value: { colorThemeID: 'oort', reduceMotion: false, interfaceZoom: 1, appLanguage: 'auto' }[id] });
    await oort.ask('settings.save'); oort.apply(await oort.ask('view'));
  }
});
