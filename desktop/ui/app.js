/* Oort NX for Windows and Linux: the screens. What the app knows and decides is in oort-core; this file draws it. */
import { STRINGS, GAME_WORDS } from './gen/strings.js';
import { ICONS, PALETTES } from './gen/names.js';
import { cloud as makeCloud } from './cloud.js';
import { sounds as makeSounds } from './sound.js';
import { still, focusable, nearest, controller, padName } from './nav.js';
import { gameWord } from './words.js';

const T = window.__TAURI__, root = document.documentElement, $ = (s, r = document) => r.querySelector(s);
const invoke = (name, args) => T.core.invoke(name, args);
/* One question at a time, so an answer never overtakes a later change. Sounds do not wait in line. */
let line = Promise.resolve();
export const ask = (method, params = {}) => method === 'sound' ? invoke('core', { method, params }) : line = line.catch(() => {}).then(() => invoke('core', { method, params }));

/* ---------- Texts ---------- */
let V = {}, language = 'en';
export const t = (key, ...args) => {
  let s = (STRINGS[language] || STRINGS.en)[key] ?? STRINGS.en[key] ?? key;
  if (typeof s === 'object') s = s[new Intl.PluralRules(language).select(args[0])] ?? s.other;
  return s.replace(/%(?:\d+\$)?(?:lld|@|d)/g, () => args.shift() ?? '').replace(/ {2,}/g, ' ');
};
/* A name a game's manifest gives one of its settings: in the player's language when it is a known one, else as it is. */
const word = text => gameWord(GAME_WORDS[language], text);
const duration = s => {
  if (s < 60) return s > 0 ? t('Under a minute') : '—';
  const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
  return h ? t('%lld h %lld min', h, m) : t('%lld min', m);
};
const day = s => s == null ? t('Never') : new Intl.DateTimeFormat(language, { dateStyle: 'medium' }).format(new Date(s * 1000));
const reasons = {
  'inputs-missing': () => t('Choose the files this game needs first.'), 'prepare-first': () => t('Get this game ready first.'),
  'program-missing': () => t('The program was not found.'), 'unsupported-placing': () => t('This project needs its files copied into its folder. Open the project to do it.'),
  'unsupported-download': () => t('This project needs a file it downloads. Open the project to do it.'), 'option-required': () => t('Turn on the required choice first.'),
  'disk-full': () => t('Free at least 1 GB on this game’s drive.'), 'config-unreadable': () => t('This game’s settings file could not be read. It was left as it is.'),
  'config-place': () => t('This game’s settings file is outside its own folders. Nothing was written.'), 'manifest-json': () => t('This game’s recomplauncher.json could not be read.'),
  'manifest-format': () => t('This game’s recomplauncher.json is for a newer launcher.'), 'manifest-unreadable': () => t('This game’s recomplauncher.json could not be read.'),
  'folder-missing': () => t('Folder unavailable'), 'folder-closed': () => t('Could not read this folder'), 'already-playing': () => t('A game is already running.'),
  'input-kind': () => t('This game does not take this kind of file.'), 'input-check': () => t('This is not the copy this game asks for.'), 'input-twice': () => t('This file is already chosen for this game.'),
  picture: () => t('This file is not a picture Oort NX can show. Choose a PNG, JPEG or WebP.'),
  'steam-missing': () => t('Steam is not installed on this computer.'), 'steam-refused': () => t('Steam did not receive the request. Try again.'), 'steam-not-started': () => t('The game did not start. Check Steam, then try again.'), 'steam-gone': () => t('Steam no longer has this game installed.'),
  online: () => t('No answer from the network. Try again later.'), 'online-slow': () => t('The service is asked too much. Try again in a few minutes.'), 'online-off': () => t('Turn on game information online first.'), 'online-none': () => t('Type a name to look for.'),
  'program-known': () => t('This game is already in your library.'), 'core-lost': () => t('Oort NX lost its place and started again. Try once more.'), pin: () => t('Wrong code.'), 'pin-shape': () => t('Use four digits.'),
};
const because = e => (reasons[String(e)] || (() => t('Something went wrong: %@', String(e))))();

/* ---------- Small pieces ---------- */
const shown = kids => kids.flat(3).filter(x => x != null && x !== false && x !== 0);
const fill = (e, ...kids) => e.replaceChildren(...shown(kids));
const h = (tag, props = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false && !k.startsWith('aria-')) continue;
    if (k.startsWith('aria-')) e.setAttribute(k, String(v)); else if (k.startsWith('on')) e.addEventListener(k.slice(2), v); else if (k === 'style') e.style.cssText = v; else e.setAttribute(k === 'cls' ? 'class' : k, v === true ? '' : v);
  }
  e.append(...shown(kids));
  return e;
};
const icon = name => h('i', { cls: 'icon', 'aria-hidden': 'true' }, String.fromCodePoint(parseInt(ICONS[name] || 'E88E', 16)));
const glyph = char => h('i', { cls: 'icon', 'aria-hidden': 'true' }, char);
const key = (label, act, { ic, cls = '', off, id, aria } = {}) => h('button', { cls: 'key ' + cls, 'aria-disabled': off ? true : null, 'data-id': id, 'aria-label': aria, onclick: e => off ? deny(e.currentTarget, off) : act(e) }, ic && icon(ic), label && h('span', {}, label));
const row = (what, value, act, o = {}) => h('button', { cls: 'row ' + (o.cls || ''), 'data-id': o.id, 'data-help': o.help, role: o.role, 'aria-checked': o.checked, 'aria-disabled': o.off ? true : null, 'aria-label': o.aria, onclick: e => o.off ? deny(e.currentTarget, o.off === true ? '' : o.off) : act && act(e.currentTarget) }, o.ic && icon(o.ic), h('span', { cls: 'what' }, what, o.sub && h('small', {}, o.sub)), value && h('span', { cls: 'value' }, value));
const dot = cls => h('i', { cls: 'dot ' + cls, 'aria-hidden': 'true' });
const artURL = (g, kind) => T.core.convertFileSrc(`${g.id}/${kind}`, 'oort-art').replace(/%2F/gi, '/') + '?' + (g.art || 0);
const deny = (el, why) => { S.play('deny', el); if (why) notice(why); };
let noticed = 0;
const notice = text => { clearTimeout(noticed); helpText(text); noticed = setTimeout(() => helpText(null), 6000); };
const helpText = text => { const p = $('.help', top()?.el); if (p) p.textContent = text ?? document.activeElement?.dataset?.help ?? ''; else if (text) card(text); };

/* ---------- Sound and cloud ---------- */
const S = makeSounds(ask), C = makeCloud($('#cloud'));
const css = n => getComputedStyle(root).getPropertyValue(n).trim();

const apply = v => {
  const before = V;
  V = v; language = STRINGS[v.language] ? v.language : 'en';
  root.lang = language; root.dataset.palette = v.palette; root.dataset.mode = (PALETTES.find(p => p[0] === v.palette) || [])[2] || 'dark';
  root.style.setProperty('--zoom', v.zoom);
  root.toggleAttribute('data-still', v.reduceMotion || still.matches);
  S.set(v);
  C.set({ moves: v.animated && !root.hasAttribute('data-still'), colors: [css('--glyph'), css('--sun'), '#fff'] });
  requestAnimationFrame(() => document.querySelectorAll('.tabs').forEach(pill));
  if (before.language && before.language !== v.language) for (const l of layers) l.redraw && l.redraw();
  hints();
};
still.addEventListener('change', () => apply(V));

/* ---------- Layers ---------- */
const layers = [], host = $('#layers');
const top = () => layers[layers.length - 1];
const push = layer => {
  const under = top();
  if (under) { under.keep = document.activeElement?.dataset?.id ?? null; under.kept = document.activeElement; under.el.inert = true; if (!layer.over) under.el.hidden = true; }
  layer.el.classList.add('layer'); layers.push(layer); host.append(layer.el); settle(); (layer.focus || first)(layer); return layer;
};
const pop = () => {
  if (layers.length < 2) return;
  const gone = layers.pop(); gone.el.remove(); gone.gone && gone.gone();
  const now = top(); now.el.inert = false; now.el.hidden = false; now.back ? now.back() : restore(now); settle();
};
const first = layer => (focusable(layer.el)[0])?.focus({ preventScroll: true });
const restore = layer => { const same = layer.keep && layer.el.querySelector(`[data-id="${CSS.escape(layer.keep)}"]`); const e = same || (layer.kept?.isConnected ? layer.kept : null); e ? e.focus({ preventScroll: true }) : (layer.focus || first)(layer); };
const settle = () => {
  const layer = top(), page = layers.some(l => l.page);
  root.classList.toggle('page', page);
  const art = [...layers].reverse().find(l => !l.over)?.art?.() || null;
  root.classList.toggle('art', !!art && !V.keepCloud); root.classList.toggle('busy', home === 'collection' && layers.length > 0);
  if (art && !V.keepCloud) $('#art').style.backgroundImage = `url("${art}")`;
  C.set({ awake: !page && !(art && !V.keepCloud) && !layers.some(l => l.launch) });
  $('#hints').classList.toggle('veil', !!layer.over);
  hints();
};
/* Draws a layer again without losing the place. */
const again = (layer, draw) => { const keep = layer.el.contains(document.activeElement) ? document.activeElement.dataset.id : layer.keep, at = [...layer.el.querySelectorAll('.list,.detail,.scroll,.side')].map(e => e.scrollTop); fill(layer.el, draw()); [...layer.el.querySelectorAll('.list,.detail,.scroll,.side')].forEach((e, i) => { e.scrollTop = at[i] || 0; }); layer.keep = keep; if (layer === top()) restore(layer); hints(); };

/* ---------- Hints: the buttons in hand, and only what works now ---------- */
let pad = null, plugged = [], prompts = {}, keysInHand = true, version = '', system = '';
const keyCaps = { a: '⏎', b: 'Esc', x: 'X', y: 'Y', lb: 'Q', rb: 'E', lt: 'Home', rt: 'End', ls: 'Ctrl F', rs: 'F3', view: 'V', menu: 'M', home: 'H' };
const badgeText = b => V.buttonNames === 'automatic' ? (pad ? prompts[pad.brand]?.[b] : keyCaps[b]) : prompts[V.buttonNames]?.[b];
const badge = b => h('span', { cls: 'badge', 'aria-hidden': 'true' }, badgeText(b) || b.toUpperCase());
const hints = () => {
  const bar = $('#hints'), layer = top();
  if (!layer || !V.hints) return bar.replaceChildren();
  const [left, right] = layer.hints ? layer.hints() : [[], []];
  bar.replaceChildren(...[left, right].map(list => h('div', {}, list.filter(Boolean).map(([b, label, run, sub]) => h(run ? 'button' : 'span', { cls: 'hint', tabindex: run ? '-1' : null, onclick: run }, badge(b), h('span', {}, label, sub && h('small', {}, sub)))))));
  document.querySelectorAll('[data-badge]').forEach(e => { e.textContent = badgeText(e.dataset.badge) || ''; });
};

/* The controller in hand, else the ones plugged in: WebView2 sees a controller only once a button was pressed. */
const padText = () => {
  const one = plugged.length === 1 || !pad ? plugged[0] : padName(pad.name) || plugged[0];
  return one ? one + (plugged.length > 1 ? ` +${plugged.length - 1}` : '') : t('No controllers connected');
};
const padLabel = () => h('span', { cls: 'padname', role: 'status', 'aria-label': padText() }, icon('gamepad'), h('span', {}, padText()));
const padChanged = () => document.querySelectorAll('.padname').forEach(e => { e.replaceWith(padLabel()); });

/* ---------- Moving and pressing ---------- */
const go = e => { e.focus({ preventScroll: true }); e.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: root.hasAttribute('data-still') ? 'instant' : 'smooth' }); S.move(e); };
const move = dir => {
  const layer = top(), a = document.activeElement;
  if (!layer || layer.launch && !focusable(layer.el).length) return;
  if (!a || !layer.el.contains(a)) return restore(layer);
  if (layer.move && layer.move(dir, a)) return;
  if (a.matches('input') && (dir === 'left' || dir === 'right')) return;
  const e = nearest(a, focusable(layer.el), dir);
  if (e) go(e); else S.play('deny', a);
};
const act = name => {
  const layer = top();
  if (['up', 'down', 'left', 'right'].includes(name)) return move(name);
  if (name === 'a') {
    const e = document.activeElement;
    if (!e || !layer.el.contains(e)) return restore(layer);
    e.classList.add('down'); setTimeout(() => e.classList.remove('down'), 110);
    return layer.actions?.a ? layer.actions.a(e) : e.click();
  }
  if (name === 'b') return layer.actions?.b ? layer.actions.b() : layers.length > 1 ? (S.play('back'), pop()) : null;
  if (layer.actions?.[name]) return layer.actions[name]();
};
addEventListener('keydown', e => {
  if (e.altKey || e.metaKey) return;
  const typing = e.target.matches?.('input');
  if (!keysInHand) { keysInHand = true; hints(); }
  const arrows = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };
  const letters = { x: 'x', y: 'y', q: 'lb', e: 'rb', v: 'view', m: 'menu' }, others = { Escape: 'b', F3: 'rs', Home: 'lt', End: 'rt' };
  if (e.ctrlKey) { if (e.key.toLowerCase() === 'f') { e.preventDefault(); act('ls'); } return; }
  if (arrows[e.key]) { if (typing && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return; e.preventDefault(); return act(arrows[e.key]); }
  if (e.key === 'F11') { e.preventDefault(); return setFullscreen(!full); }
  if (others[e.key] && !(typing && others[e.key] !== 'b' && e.key !== 'F3')) { e.preventDefault(); return act(others[e.key]); }
  if (!typing && !e.repeat && letters[e.key.toLowerCase()]) { e.preventDefault(); act(letters[e.key.toLowerCase()]); }
});
addEventListener('pointerdown', e => { const b = e.target.closest('button'); if (b) S.play('select', b); }, true);
addEventListener('click', e => { if (!e.detail && e.isTrusted) S.play('select', document.activeElement); }, true);
addEventListener('mouseover', e => { if (!e.movementX && !e.movementY) return; const b = e.target.closest('.tile,.row,.side button'); if (b && b !== document.activeElement && top()?.el.contains(b)) { b.focus({ preventScroll: true }); } });
addEventListener('focusin', e => { const layer = top(); if (layer?.el.contains(e.target)) { layer.onfocus && layer.onfocus(e.target); const p = $('.help', layer.el); if (p) p.textContent = e.target.dataset.help || ''; hints(); } });
addEventListener('contextmenu', e => e.preventDefault());
const padding = controller({
  act: name => { keysInHand = false; if (['a'].includes(name)) S.play('select', document.activeElement); act(name); },
  hold: name => name === 'view' && act('ls'),
  found: p => { pad = p; S.warm(); if (p) ask('pad', { kind: p.brand }).catch(() => {}); hints(); padChanged(); top()?.padChanged?.(); },
  scroll: dy => { const e = top()?.el.querySelector('.list,.detail,.scroll,.found'); if (e) e.scrollTop += dy; },
});
let full = false;
const setFullscreen = on => { full = on; invoke('set_fullscreen', { on }).catch(() => {}); };

/* ---------- The library ---------- */
let L = { games: [], total: 0, folders: 0 }, tab = 'All games', selected = null, home = 'spotlight', TABS = ['All games'];
const reload = async (rescan = false) => {
  L = await ask(rescan ? 'library.rescan' : 'library', { tab, sort: V.sort });
  if (L.online) { const ids = L.games.filter(g => g.look).map(g => g.id); if (ids.length) invoke('online_look', { ids, front: false }).catch(() => {}); }
  // A large library's icons are read in parts, while the rest is there to play.
  clearTimeout(reload.more);
  if (L.more) reload.more = setTimeout(async () => { if (playing) return; await reload(true); refaces(); }, 400);
};
/* New pictures go in where they are: the place, the focus and the rest of the page do not move. */
const refaces = id => {
  for (const tile of homeLayer.el.querySelectorAll('.tile[data-id]')) { const g = game(tile.dataset.id); if (g && (!id || g.id === id)) $('.face', tile)?.replaceWith(face(g, tile.closest('.grid') ? 'cover' : 'icon')); }
  homeLayer.refreshed(id);
};
const game = id => L.games.find(g => g.id === id);
const primary = g => g.state === 'ready' ? [t('Play'), () => play(g.id)] : g.state === 'prepare' ? [t('Get ready'), () => openDetail(g.id, 'prepare')] : g.state === 'inputs' ? [t('Choose files'), () => openDetail(g.id, 'inputs')] : [t('Details'), () => openDetail(g.id)];
const picture = (g, kind) => h('img', { src: artURL(g, kind), alt: '', draggable: 'false' });
/* A program's icon is small and square: it sits on Oort's halftone, at its own size, never stretched to fill. */
const plate = (g, kind, named) => h('span', { cls: 'plate' + (named ? ' named' : '') }, picture(g, kind), named && h('b', {}, g.name));
const faced = (g, kind) => g[kind] ? picture(g, kind) : kind === 'cover' ? g.mark || g.icon ? plate(g, g.mark ? 'mark' : 'icon', true) : h('b', {}, g.name) : g.mark ? plate(g, 'mark') : g.cover ? picture(g, 'cover') : h('b', {}, g.name);
const face = (g, kind) => h('span', { cls: 'face' }, faced(g, kind), g.state !== 'ready' && h('span', { cls: 'todo' }, icon(g.state === 'prepare' ? 'build' : g.state === 'inputs' ? 'folder' : 'info')));
const heading = g => g.logo ? h('h1', {}, h('img', { cls: 'logo', src: artURL(g, 'logo'), alt: g.name })) : h('h1', { cls: 'hero' }, g.name);
const kindText = g => ({ program: t('Program'), steam: t('Steam') })[g.kind] || t('Recompilation');
const stats = g => h('dl', { cls: 'stats' }, [[t('Playtime'), duration(g.seconds)], [t('Last played'), day(g.last)], [t('Kind'), kindText(g)], g.year && [t('Release date'), g.year]].filter(Boolean).map(([a, b]) => h('div', {}, h('dt', {}, a), h('dd', { cls: 'num' }, b))));
const genres = g => g.genres?.length > 0 && h('div', { cls: 'chips' }, g.genres.map(x => h('span', { cls: 'chip' }, x)));
const stateText = g => ({ inputs: t('Choose the files this game needs first.'), prepare: t('Get this game ready first.'), unsupported: t('Some of this project’s setup is done in the project itself.'), broken: because(g.reason || 'manifest-json') })[g.state];
const favorite = async g => { const n = await ask('game.favorite', { id: g.id, on: !g.favorite }); S.play('confirm', document.activeElement); Object.assign(g, n); };
const remember = p => ask('settings.remember', p).catch(() => {});

const topBar = () => {
  const bar = h('div', { cls: 'tabs panel', role: 'tablist', 'aria-label': t('Library') }, h('span', { cls: 'pill' }), TABS.map(x => h('button', { role: 'tab', tabindex: '-1', 'aria-selected': x === tab, onclick: () => setTab(x) }, t(x))));
  requestAnimationFrame(() => pill(bar));
  return h('div', { cls: 'top' }, padLabel(), h('span', { cls: 'badge', 'data-badge': 'lb', 'aria-hidden': 'true' }), bar, h('span', { cls: 'badge', 'data-badge': 'rb', 'aria-hidden': 'true' }), V.clock && h('time', { cls: 'clock num' }, clockText()));
};
const pill = bar => { const on = $('[aria-selected=true]', bar), p = $('.pill', bar); if (on && p) { p.style.width = on.offsetWidth + 'px'; p.style.transform = `translateX(${on.offsetLeft}px)`; } };
const clockText = () => new Intl.DateTimeFormat(language, { hour: '2-digit', minute: '2-digit' }).format(new Date());
setInterval(() => document.querySelectorAll('.clock').forEach(c => { c.textContent = clockText(); }), 5000);
addEventListener('resize', () => document.querySelectorAll('.tabs').forEach(pill));
document.fonts.ready.then(() => document.querySelectorAll('.tabs').forEach(pill));

const setTab = async x => { tab = x; await reload(); homeLayer.redraw(); };
const shiftTab = d => { const i = Math.max(0, Math.min(TABS.length - 1, TABS.indexOf(tab) + d)); if (TABS[i] !== tab) { S.play('confirm'); const bar = $('.tabs', homeLayer.el); tab = TABS[i]; [...bar.querySelectorAll('[role=tab]')].forEach((b, k) => b.setAttribute('aria-selected', k === i)); pill(bar); setTimeout(() => setTab(tab), root.hasAttribute('data-still') ? 0 : 160); } else S.play('deny'); };

/* What Steam has on this computer: looked at when a screen offers it. */
let steamSeen = null;
const findSteam = async () => { steamSeen = await ask('steam').catch(() => ({ found: false })); return steamSeen; };
const addSteam = async () => { steamSeen = await ask('steam.set', { on: true }); await reload(true); selected = L.games.find(g => g.kind === 'steam')?.id ?? selected; S.play('success'); };
const guideRow = () => row(t('Guided setup'), icon('chevron'), () => openGuide(), { id: 'guide', ic: 'checklist', sub: t('Language, controller, games: a few short steps.') });
const addRows = after => [
  steamSeen?.found && !steamSeen.on && row(t('Steam'), t('%lld games', steamSeen.games), async () => { await addSteam(); while (layers.length > 1) pop(); after ? after() : homeLayer.redraw(); }, { id: 'steam', ic: 'gamepad', sub: t('Adds the games Steam installed on this computer. Steam’s own files do not change.') }),
  row(t('A program'), icon('chevron'), () => openProgram(), { id: 'program', ic: 'terminal', sub: system === 'windows' ? t('Any game or emulator you start with an .exe file. Its name and icon come with it.') : t('Any game or emulator, or its menu entry. Its name and icon come with it.') }),
  row(t('A folder of games'), icon('chevron'), () => pickFolder(() => { while (layers.length > 1) pop(); selected = L.games[0]?.id ?? null; homeLayer.redraw(); }), { id: 'folder', ic: 'folder', sub: t('For recompiled games: each one has its recomplauncher.json.') }),
  row(t('Projects'), icon('chevron'), () => openCatalog(), { id: 'catalog', ic: 'store', sub: t('Projects that rebuild older games for this computer. Oort NX opens their page and installs nothing.') }),
].filter(Boolean);

const cards = [{ id: 'catalog', ic: 'store', name: () => t('Projects'), run: () => openCatalog() }, { id: 'add', ic: 'add', name: () => t('Add game'), run: () => openAdd() }];

/* The shelf: one row of tiles, one ring, one camera (SpotlightRowGeometry). */
const HOST = 174, PITCH = 178, START = 72, GROW = 1.3, ANCHOR = 2;
const shelf = () => {
  const items = [...cards, ...L.games], nodes = new Map(), el = h('div', { cls: 'shelf', role: 'listbox', 'aria-label': t('Library') }), ring = h('span', { cls: 'ring' }), name = h('span', { cls: 'name' });
  let at = Math.max(0, items.findIndex(x => x.id === selected)); if (selected == null || !items[at] || items[at].id !== selected) at = Math.min(cards.length, items.length - 1);
  el.append(ring, name);
  const u = n => `calc(${n.toFixed(1)}*var(--u))`;
  const place = i => START + i * PITCH + (i > at ? HOST * (GROW - 1) : 0) + 1 - Math.max(0, at - ANCHOR) * PITCH;
  const tile = i => { const x = items[i], b = h('button', { cls: 'tile', role: 'option', 'data-id': x.id, 'data-i': i, 'aria-label': x.run ? x.name() : x.name, onclick: () => { if (+b.dataset.i !== at) return set(i, true); x.run ? x.run() : primary(x)[1](); } }, x.run ? h('span', { cls: 'face' }, icon(x.ic)) : face(x, 'icon')); return b; };
  const paint = () => {
    // Only the tiles near the screen exist, however long the library.
    const from = Math.max(0, at - 14), to = Math.min(items.length, at + 24);
    for (const [i, n] of nodes) if (i < from || i >= to) { n.remove(); nodes.delete(i); }
    for (let i = from; i < to; i++) {
      let n = nodes.get(i); if (!n) { n = tile(i); nodes.set(i, n); el.append(n); }
      n.style.transform = `translate(${u(place(i))},0) scale(${i === at ? GROW : 1})`; n.tabIndex = i === at ? 0 : -1; n.setAttribute('aria-selected', i === at); n.style.zIndex = i === at ? 2 : 1;
    }
    ring.style.transform = `translate(${u(place(at))},0) scale(${GROW})`; name.style.transform = `translate(${u(place(at) + HOST * GROW + 16)},0)`;
    const x = items[at]; name.textContent = x.run ? x.name() : x.name;
  };
  const set = (i, sound) => { at = i; selected = items[at].id; paint(); const n = nodes.get(at); n.focus({ preventScroll: true }); if (sound) S.move(n); changed(); };
  const refreshed = () => { for (const [k, x] of items.entries()) if (!x.run) items[k] = game(x.id) || x; };
  const changed = () => { homeLayer.info(); settle(); if (items[at] && !items[at].run) { clearTimeout(shelf.t); shelf.t = setTimeout(() => remember({ game: selected }), 1500); } };
  selected = items[at]?.id ?? null; paint();
  return { el, refreshed, get item() { return items[at]; }, focus: () => nodes.get(at)?.focus({ preventScroll: true }), has: e => e.closest('.shelf') === el, step: d => { const i = at + d; if (i < 0 || i >= items.length) S.play('deny', nodes.get(at)); else set(i, true); }, end: d => set(d < 0 ? 0 : items.length - 1, true), set: i => set(i, false), index: e => +e.dataset.i };
};

const homeLayer = (() => {
  const el = h('section'), layer = { el };
  let row = null, grid = null, box = null, ringGrid = null;
  const current = () => home === 'spotlight' ? row?.item : game(selected);
  const spotlight = () => { row = shelf(); grid = null; box = h('div', { cls: 'info' }); return [topBar(), row.el, box]; };
  const collection = () => {
    row = null; ringGrid = h('span', { cls: 'ring' }); if (!game(selected)) selected = L.games[0]?.id ?? null;
    box = h('div', { cls: 'gridinfo' });
    grid = h('div', { cls: 'grid', role: 'listbox', 'aria-label': t('Collection') }, ringGrid, L.games.map(g => h('button', { cls: 'tile', role: 'option', 'data-id': g.id, 'aria-label': g.name, onclick: () => primary(g)[1]() }, face(g, 'cover'))));
    return [topBar(), h('div', { cls: 'gridpage' }, box, h('div', { cls: 'scroll' }, grid))];
  };
  const empty = () => [topBar(), h('div', { cls: 'empty' }, L.total ? [h('h1', {}, t('No games in %@', t(tab)))] : [h('h1', {}, t('Add your first game')), h('p', { cls: 'say' }, t('Oort NX shows the games you already have. Nothing is moved or changed.')), h('div', { cls: 'rows' }, addRows(() => layer.redraw()), guideRow())])];
  const draw = () => !L.games.length && (home === 'collection' || !L.total) ? (row = grid = null, empty()) : home === 'spotlight' ? spotlight() : collection();
  layer.refreshed = id => { row?.refreshed(); const x = current(); if (layer === top() && x && !x.run && (!id || x.id === id)) { const keep = document.activeElement?.dataset?.id, inside = box?.contains(document.activeElement); layer.info(true); if (inside) box.querySelector(`[data-id="${keep}"]`)?.focus({ preventScroll: true }); settle(); } };
  layer.info = quiet => {
    if (!box) return;
    box.classList.toggle('quiet', !!quiet);
    const x = current();
    clearTimeout(layer.look); if (L.online && x?.look) layer.look = setTimeout(() => invoke('online_look', { ids: [x.id], front: true }).catch(() => {}), 700);
    if (!x) return box.replaceChildren();
    if (x.run) return fill(box, h('h1', { cls: 'hero' }, x.name()), h('p', { cls: 'say' }, x.id === 'add' ? t('Games from Steam, any program, or a folder of recompiled games.') : t('Projects that rebuild older games for this computer. Oort NX opens their page and installs nothing.')));
    if (home === 'collection') return fill(box, h('h1', { cls: 'hero' }, x.name), stats(x));
    const [label, run] = primary(x);
    fill(box, heading(x), h('div', { cls: 'keys' }, key(label, run, { ic: x.state === 'ready' ? 'play' : null, id: 'primary' }), key(t('Options'), () => openOptions(x.id), { id: 'options' }), key('', async () => { await favorite(x); layer.info(); $('[data-id=heart]', box)?.focus(); }, { ic: x.favorite ? 'favorite' : 'favoriteBorder', cls: 'round', id: 'heart', aria: x.favorite ? t('Remove from favorites') : t('Add to favorites') })), x.state !== 'ready' && h('p', { cls: 'say' }, stateText(x)), stats(x), genres(x));
  };
  layer.redraw = () => { if (!L.games.length && !steamSeen) findSteam().then(() => { if (!L.games.length) layer.redraw(); }); el.replaceChildren(...draw()); layer.info(); if (layer === top()) { layer.focus(); settle(); } };
  layer.focus = () => { if (row) row.focus(); else if (grid) { const b = grid.querySelector(`[data-id="${selected}"]`); b && (b.focus({ preventScroll: true }), b.scrollIntoView({ block: 'nearest' })); } else first(layer); };
  layer.back = () => { if (!row && !grid) return restore(layer); if (layer.keep && ['primary', 'options', 'heart'].includes(layer.keep)) restore(layer); else layer.focus(); };
  layer.art = () => { const x = current(); return x && !x.run && x.hero ? artURL(x, 'hero') : null; };
  layer.onfocus = e => {
    if (row && row.has(e)) { const i = row.index(e); if (row.item?.id !== e.dataset.id) row.set(i); }
    if (grid && e.closest('.grid')) { ringGrid.style.cssText = `width:${e.offsetWidth * 1.04}px;height:${e.offsetHeight * 1.04}px;transform:translate(${e.offsetLeft - e.offsetWidth * .02}px,${e.offsetTop - e.offsetHeight * .02}px)`; if (selected !== e.dataset.id) { selected = e.dataset.id; layer.info(); settle(); remember({ game: selected }); } }
  };
  layer.move = (dir, a) => {
    if (!row || !row.has(a)) { if (row && dir === 'up') { row.focus(); S.move(a); return true; } return false; }
    if (dir === 'left' || dir === 'right') { row.step(dir === 'left' ? -1 : 1); return true; }
    if (dir === 'down') { const k = $('.key', box); if (k) go(k); else S.play('deny', a); return true; }
    return true;
  };
  const other = () => { home = home === 'spotlight' ? 'collection' : 'spotlight'; S.play('open'); remember({ home }); if (!game(selected) && home === 'collection') selected = L.games[0]?.id ?? null; layer.redraw(); };
  layer.actions = {
    b: () => { if (row && !row.has(document.activeElement)) { S.play('back'); row.focus(); } },
    x: () => { const x = current(); if (x && !x.run) openDetail(x.id); }, y: () => openSearch(), ls: () => openSearch(), menu: () => openSettings(), home: () => openSettings(), view: () => V.viewSwitches && other(), rs: () => openSort(),
    lb: () => shiftTab(-1), rb: () => shiftTab(1), lt: () => row ? row.end(-1) : edge(-1), rt: () => row ? row.end(1) : edge(1),
  };
  const edge = d => { const list = grid ? focusable(grid) : []; const e = list[d < 0 ? 0 : list.length - 1]; if (e) go(e); };
  layer.hints = () => {
    const x = current(), g = x && !x.run ? x : null, onTile = !document.activeElement?.classList.contains('key');
    return [[V.viewSwitches && L.total && ['view', home === 'spotlight' ? t('Collection') : t('Spotlight'), other, pad && t('Hold: %@', t('Search'))], L.total && ['y', t('Search'), openSearch], ['menu', t('Settings'), openSettings]],
      [g && onTile && ['x', t('Details'), () => openDetail(g.id)], x && ['a', g ? onTile ? primary(g)[0] : t('Select') : t('Open')], L.total && ['rs', t('Sort'), openSort, t({ recent: 'Sort: Recent', name: 'Sort: Name', added: 'Sort: Recently added', playtime: 'Sort: Playtime' }[V.sort])]]];
  };
  return layer;
})();

/* ---------- A game's page ---------- */
const openDetail = async (id, section) => {
  let d = await ask('game', { id });
  const layer = { el: h('section'), art: () => d.hero ? artURL(d, 'hero') : null };
  const refresh = async next => { d = next || await ask('game', { id }); again(layer, draw); };
  const change = p => p.then(refresh).catch(e => deny(document.activeElement, because(e)));
  const draw = () => {
    const [label, run] = primary(d), busy = preparing?.id === id;
    const body = h('div', { cls: 'in' }, heading(d), d.project && d.project !== d.name && h('p', { cls: 'say' }, d.project),
      h('div', { cls: 'keys' }, d.state === 'ready' ? key(label, run, { ic: 'play', id: 'primary' }) : d.state === 'prepare' ? key(busy ? t('Getting ready…') : t('Get ready'), () => prepare(id), { ic: 'build', id: 'primary', off: busy && t('A game is already running.') }) : d.state === 'inputs' ? key(t('Choose files'), () => { const r = $('[data-id^="input-"]', layer.el); if (r) go(r); }, { ic: 'folder', id: 'primary' }) : key(t('Play'), () => {}, { ic: 'play', id: 'primary', off: stateText(d) }),
        key(t('Options'), () => openOptions(id), { id: 'options' }), key('', async () => { await favorite(d); refresh(); }, { ic: d.favorite ? 'favorite' : 'favoriteBorder', cls: 'round', id: 'heart', aria: d.favorite ? t('Remove from favorites') : t('Add to favorites') }),
        key('', () => invoke('open_folder', { id, name: null }).catch(e => deny(null, because(e))), { ic: 'folder', cls: 'round', id: 'folder', aria: t('Open folder') })),
      busy && h('div', { cls: 'wait' }, h('div', { cls: 'bar', role: 'progressbar', 'aria-label': t('Getting ready…'), style: `--at:${preparing.value}` }, h('i')), h('p', { cls: 'say' }, preparing.text || d.prepare?.label || ''), key(t('Cancel'), () => invoke('close_game'), { id: 'stop' })),
      stats(d), genres(d), d.state !== 'ready' && !busy && h('p', { cls: 'say' }, stateText(d)), d.unsupported?.length && h('p', { cls: 'say' }, because('unsupported-' + d.unsupported[0])),
      d.about && [h('h2', {}, t('About this game')), h('div', { cls: 'about', tabindex: '0', 'data-id': 'about' }, d.about.split(/\n+/).map(x => h('p', {}, x)), d.source && h('small', {}, t('Source: %@', d.source)))],
      [h('h2', {}, t('Details')), h('dl', { cls: 'facts' }, [[t('Publisher'), d.publisher], [t('Developer'), d.developer], [t('Release date'), d.year], [t('Version'), d.version], [t('Installed in'), d.folder]].filter(x => x[1]).map(([a, b]) => h('div', {}, h('dt', {}, a), h('dd', {}, b)))), h('div', { cls: 'rows' }, d.page && row(t('Open the page this comes from'), icon('link'), () => link(d.page), { id: 'page', sub: d.page.replace(/^https:\/\//, '').split('/')[0] }), row(t('Pictures and information'), icon('chevron'), () => openOptions(id, 'look'), { id: 'look', ic: 'image', sub: d.online ? d.about || d.year ? t('Another cover, or another game if this is not the right one.') : d.searched ? t('Nothing was found online. Look for it by another name, or choose your own pictures.') : t('Choose your own pictures, or look for this game online.') : t('Choose your own pictures, or turn on game information online.') }))],
      d.inputs?.length && [h('h2', { 'data-part': 'inputs' }, t('Files')), h('div', { cls: 'rows' }, d.inputs.map(i => row(i.label || i.id, [i.path ? h('span', {}, i.path.split(/[\\/]/).pop()) : i.optional ? t('Optional') : t('Missing'), dot(i.path ? 'ok' : i.optional ? 'mark' : '')], () => pickFile({ title: i.label || t('Files'), extensions: i.extensions, folders: i.folder, files: i.file, done: path => change(ask('game.input', { id, input: i.id, path })) }), { id: 'input-' + i.id, ic: i.role === 'key' ? 'key' : 'folder', sub: i.path && i.unchecked ? t('Oort NX does not check this copy; the project does.') : i.shared ? t('Kept where it is. Only its path is remembered.') : null })))],
      d.prepare && [h('h2', { 'data-part': 'prepare' }, t('Get ready')), h('div', { cls: 'rows' }, d.prepare.options.map(o => row(o.label, h('span', { cls: 'sw' }), () => change(ask('game.option', { id, option: o.id, on: !o.on })), { id: 'option-' + o.id, role: 'switch', checked: o.on, sub: [o.note, o.license && t('Turning this on accepts: %@', o.license.name), o.required && t('Required')].filter(Boolean).join(' ') })), d.prepare.options.filter(o => o.license?.url).map(o => row(t('Read: %@', o.license.name), icon('link'), () => link(o.license.url), { id: 'license-' + o.id })), row(d.prepare.needed ? t('Get ready') : t('Get ready again'), d.prepare.needed ? t('Needed') : t('Done'), () => prepare(id), { id: 'prepare', ic: 'build', sub: d.prepare.label, off: busy || d.state === 'inputs' ? stateText(d) || true : null }))],
      d.repo && [h('h2', {}, t('Project')), h('div', { cls: 'rows' }, row(d.repo, icon('link'), () => link('https://github.com/' + d.repo), { id: 'repo' }))]);
    return [h('div', { cls: 'detail' }, body)];
  };
  layer.el.append(...draw());
  layer.redraw = () => refresh(); layer.refresh = refresh; layer.id = id;
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['y', t('Options'), () => openOptions(id)], ['a', t('Select')]]];
  layer.actions = { y: () => openOptions(id) };
  layer.gone = async () => { await reload(); homeLayer.redraw(); };
  layer.back = () => refresh();
  S.play('open'); push(layer);
  if (section) { const e = layer.el.querySelector(`[data-part=${section}]+.rows .row`); if (e) go(e); }
};
const link = url => invoke('open_link', { url }).catch(e => deny(document.activeElement, because(e)));

/* ---------- Options of one game: two levels, as Settings ---------- */
const openOptions = async (id, start) => {
  let d = await ask('game', { id }), at = start === 'look' ? 1 : 0;
  const groups = () => {
    const out = [{ title: t('General'), ic: 'settings', rows: [
      row(t('Play'), icon('play'), () => { pop(); primary(d)[1](); }, { id: 'play', off: d.state !== 'ready' && stateText(d) }),
      row(t('Favorite'), h('span', { cls: 'sw' }), async () => { await favorite(d); refresh(); }, { id: 'fav', role: 'switch', checked: !!d.favorite }),
      row(t('Files and setup'), icon('chevron'), () => openDetail(id, 'inputs'), { id: 'files' }),
      row(t('Open folder'), icon('folder'), () => invoke('open_folder', { id, name: null }), { id: 'open', sub: d.folder }),
      ...(d.actions || []).map(a => row(word(a.label), icon('folder'), () => invoke('open_folder', { id, name: a.open }).catch(e => deny(null, because(e))), { id: 'do-' + a.id, help: a.help })),
      d.program && row(t('Remove from the library'), '', () => confirm(t('Remove %@?', d.name), t('The program and the game’s file stay where they are.'), t('Remove'), async () => { await ask('programs.remove', { key: d.program.key }); await reload(); while (layers.length > 1) pop(); homeLayer.redraw(); }), { id: 'remove', cls: 'danger' }),
    ].filter(Boolean) }];
    const kinds = [['cover', t('Cover')], ['icon', t('Icon')], ['hero', t('Background')], ['logo', t('Logo')]];
    const changed = n => { d = n; refresh(n); reload().then(() => refaces(id)); };
    const choosePicture = kind => pickFile({ title: t('Choose an image'), extensions: ['png', 'jpg', 'jpeg', 'webp'], done: path => ask('game.picture', { id, kind, path }).then(changed).catch(e => deny(document.activeElement, because(e))) });
    out.push({ title: t('Pictures and information'), ic: 'image', rows: [
      ...kinds.map(([kind, label]) => row(label, [d.pictures?.includes(kind) ? t('Yours') : d[kind] ? t('Automatic') : t('None'), icon('chevron')], () => d.pictures?.includes(kind) ? dialog(label, t('Your own picture is copied into Oort NX’s folder. The file you chose is not changed.'), [[t('Cancel'), () => {}], [t('Put it away'), () => ask('game.picture', { id, kind }).then(changed)], [t('Choose another'), () => choosePicture(kind)]]) : choosePicture(kind), { id: 'pic-' + kind, ic: 'image', help: t('A PNG, JPEG or WebP of yours. It stays on this computer.') })),
      d.program && row(t('Name'), d.name, () => type(t('Name'), d.name, async name => { await ask('programs.rename', { key: d.program.key, name }); await reload(); await refresh(); }), { id: 'rename', ic: 'edit' }),
      row(t('Information online'), d.online ? d.about || d.year ? d.title || t('Found') : d.chosen ? t('None') : d.searched ? t('Not found') : t('Waiting') : t('Off'), () => d.online ? openMatch(id, d.name, changed) : askOnline(async () => { await refresh(); if (d.online) openMatch(id, d.name, changed); }), { id: 'online', ic: 'search', help: d.online ? t('Choose the right game, or none.') : t('Off. Select to read what it does and what it sends.') }),
    ].filter(Boolean) });
    const groupOf = s => s.advanced ? t('Advanced') : s.group ? word(s.group) : t('Game settings'), list = d.settings || [], names = [...new Set(list.map(groupOf))];
    for (const name of names) out.push({ title: name, ic: 'tune', rows: list.filter(s => groupOf(s) === name).map(s => s.kind === 'elsewhere' ? row(word(s.label), t('In the game’s own menu'), null, { id: 's-' + s.id, off: true, help: s.help })
      : s.kind === 'slider' ? stepper(word(s.label), s.value, s, v => set(s, v), { id: 's-' + s.id, help: s.help, text: s.text, off: !s.enabled })
      : chooser(word(s.label), s.choices.map((c, i) => [i, word(c)]), s.value, v => set(s, v), { id: 's-' + s.id, help: s.help, text: s.text, off: !s.enabled })) });
    return out;
  };
  const set = (s, value) => ask('game.setting', { id, setting: s.id, value }).then(n => { d = n; refresh(n); }).catch(e => deny(document.activeElement, because(e)));
  const refresh = async n => { d = n || await ask('game', { id }); again(layer, draw); };
  const draw = () => { const g = groups(); at = Math.min(at, g.length - 1); return shellOf(d.name, g.map((x, i) => ({ id: 'g' + i, title: x.title, ic: x.ic, on: i === at, pick: () => { at = i; again(layer, draw); } })), g[at].title, [h('div', { cls: 'rows' }, g[at].rows)]); };
  const layer = { el: h('section'), page: true, back: () => refresh(), redraw: () => refresh() };
  shellActions(layer); layer.el.append(...draw());
  S.play('open'); push(layer);
};

/* ---------- Information online: asked first, and corrected by hand ---------- */
const onlineText = () => t('Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer.');
const askOnline = after => dialog(t('Look for game information online?'), onlineText(), [[t('No'), () => {}], [t('Yes, look online'), async () => { await ask('online.set', { on: true }); S.play('success'); await reload(); await after?.(); }]]);
const openMatch = (id, name, done) => {
  let text = name, list = null, said = t('Looking…'), turn = 0;
  const look = async () => {
    const me = ++turn; list = null; said = t('Looking…'); layer.refresh();
    try { const r = (await invoke('online_search', { id, text })).choices; if (me !== turn) return; list = r; said = r.length ? null : t('No game found with this name.'); } catch (e) { if (me !== turn) return; said = because(e); }
    if (layers.includes(layer)) layer.refresh();
  };
  const take = async run => { said = t('Looking…'); list = null; layer.refresh(); try { await run(); S.play('success'); const n = await ask('game', { id }); pop(); done(n); } catch (e) { said = because(e); layer.refresh(); } };
  const layer = sheet(t('Choose the right game'), () => [h('p', { cls: 'say', 'aria-live': 'polite' }, said || t('Choose the game this is. Its cover and description replace the ones shown.')), h('div', { cls: 'rows' }, row(t('Name to look for'), text, () => type(t('Name to look for'), text, x => { if (x) { text = x; look(); } }), { id: 'text', ic: 'search' }), (list || []).map((c, i) => row(c.title, c.appID ? t('Steam store') : 'Wikipedia', () => take(() => invoke('online_pick', { id, choice: c })), { id: 'c' + i, ic: 'image' })), row(t('None of these'), '', () => take(() => ask('online.none', { id })), { id: 'none', ic: 'close', help: t('Nothing found online is shown for this game, and it is not looked for again.') }))]);
  look();
};
let redone = 0;
/* A game found while the player is elsewhere: its pictures change in place. */
const found = ({ id }) => { clearTimeout(redone); redone = setTimeout(async () => { if (playing) return; await reload(); refaces(); const l = layers.find(x => x.id === id && x.refresh); l?.refresh(); }, 900); };

/* ---------- Rows that hold a value ---------- */
const chooser = (label, options, value, set, o = {}) => {
  const i = options.findIndex(x => x[0] === value), at = i < 0 ? 0 : i;
  const step = d => { const n = i < 0 ? 0 : (at + d + options.length) % options.length; S.play('confirm', document.activeElement); set(options[n][0]); };
  const e = row(label, [o.mark && dot('mark'), glyph(''), h('span', { cls: 'chip' }, i < 0 ? o.text || '—' : options[i][1]), glyph('')], () => step(1), { ...o, aria: `${label}: ${i < 0 ? o.text || '' : options[i][1]}` });
  e.step = step; return e;
};
const stepper = (label, value, { min, max, step }, set, o = {}) => {
  const move = d => { const n = Math.min(max, Math.max(min, Math.round((value + d * step) * 1e6) / 1e6)); if (n !== value) set(n); else S.play('deny', document.activeElement); };
  const e = row(label, [o.mark && dot('mark'), h('span', { cls: 'track', style: `--at:${(value - min) / (max - min || 1)}` }), h('span', { cls: 'chip num' }, o.text ?? String(value))], null, { ...o, aria: `${label}: ${o.text ?? value}` });
  e.addEventListener('click', ev => { const r = $('.track', e).getBoundingClientRect(); if (ev.detail && ev.clientX >= r.left - 12 && ev.clientX <= r.right + 12) set(Math.min(max, Math.max(min, Math.round((min + (ev.clientX - r.left) / r.width * (max - min)) / step) * step))); });
  e.step = move; return e;
};

/* ---------- The two-level page: a list at the side, its rows, one line of help ---------- */
const shellOf = (name, items, title, body, foot) => {
  let group;
  return [h('div', { cls: 'shell' }, h('nav', { cls: 'side panel', 'aria-label': name }, name && h('p', {}, name), items.flatMap(x => { const head = x.group !== group && x.group ? h('h3', {}, x.group) : null; group = x.group; return [head, h('button', { 'data-id': x.id, 'aria-current': x.on ? 'page' : null, onclick: () => { if (!x.on) x.pick(); else { const r = layerRow(); r && go(r); } } }, x.ic && icon(x.ic), x.title)]; })), h('div', { cls: 'col' }, h('h1', {}, title), h('div', { cls: 'list' }, body), h('p', { cls: 'help', 'aria-live': 'polite' }), foot))];
};
const layerRow = () => focusable($('.list', top().el))[0];
const shellActions = (layer, up) => {
  layer.focus = l => $('.side [aria-current]', l.el)?.focus({ preventScroll: true });
  layer.move = (dir, a) => {
    if (a.closest('.side')) {
      if (dir === 'right') { const r = layerRow(); if (r) go(r); return true; }
      if (dir === 'up' || dir === 'down') { const list = focusable($('.side', layer.el)), n = list[list.indexOf(a) + (dir === 'up' ? -1 : 1)]; if (n) { go(n); n.click(); } else S.play('deny', a); return true; }
      return true;
    }
    if (dir === 'left' || dir === 'right') { if (a.step && a.getAttribute('aria-disabled') !== 'true') { a.step(dir === 'left' ? -1 : 1); return true; } if (a.closest('.draft')) return false; if (dir === 'left') { layer.focus(layer); S.move(a); return true; } return true; }
    const list = focusable($('.col', layer.el)), n = list[list.indexOf(a) + (dir === 'up' ? -1 : 1)]; if (n) go(n); else S.play('deny', a); return true;
  };
  layer.actions = { b: () => { if (!document.activeElement.closest('.side')) { S.play('back'); layer.focus(layer); } else if (up) up(); else { S.play('back'); pop(); } }, lb: () => layer.turn?.(-1), rb: () => layer.turn?.(1) };
  layer.turn = d => { const list = focusable($('.side', layer.el)), i = list.findIndex(x => x.hasAttribute('aria-current')), n = list[i + d]; if (n) { S.play('confirm', n); n.focus({ preventScroll: true }); n.click(); } };
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['lb', t('Previous'), () => layer.turn(-1)], ['rb', t('Next'), () => layer.turn(1)], document.activeElement?.step ? ['a', t('Change')] : ['a', t('Open')]]];
};

/* ---------- Settings ---------- */
const section = id => t(['Settings navigation', id].join(': '));
const openSettings = async (start = 'general') => {
  const icons = { general: 'settings', appearance: 'palette', sound: 'volume', controllers: 'gamepad', account: 'person', home: 'collections', library: 'image', integrations: 'puzzle', about: 'info' };
  let steam = await findSteam(), online = await ask('online'), page = await ask('settings'), folders = await ask('folders'), people = await ask('profiles'), cat = start, sub = null;
  const layer = { el: h('section'), page: true };
  const take = async (p, redraw = true) => { page = await p; apply(page.view); if (redraw) again(layer, draw); };
  const set = (id, value) => take(ask('settings.set', { id, value })).catch(e => deny(document.activeElement, because(e)));
  const label = (r, v) => r.id === 'colorThemeID' ? (PALETTES.find(p => p[0] === v) || [, v])[1] : t((r.options.find(o => o.value === v) || { label: String(v) }).label);
  const draft = r => {
    const o = { id: r.id, help: [r.about && t(r.about), r.pending && t('Was: %@', r.kind === 'toggle' ? t(r.saved ? 'On' : 'Off') : r.kind === 'choice' ? label(r, r.saved) : show(r, r.saved))].filter(Boolean).join(' '), mark: r.pending };
    if (r.kind === 'toggle') return row(t(r.title), [r.pending && dot('mark'), h('span', { cls: 'sw' })], () => { S.play('confirm', document.activeElement); set(r.id, !r.value); }, { ...o, role: 'switch', checked: r.value });
    if (r.kind === 'slider') return stepper(t(r.title), r.value, r, v => set(r.id, v), { ...o, text: show(r, r.value) });
    const options = r.id === 'colorThemeID' ? PALETTES.map(p => [p[0], p[1]]) : r.options.map(x => [x.value, t(x.label)]);
    return chooser(t(r.title), options, r.value, v => set(r.id, v), o);
  };
  const show = (r, v) => r.id === 'noteOctave' ? (v > 0 ? '+' : '') + v : Math.round(v * 100) + ' %';
  const extra = {
    home: () => [h('div', {}, h('h2', {}, t('Game folders')), h('div', { cls: 'rows' }, folders.folders.map(f => row(f.path, [f.found ? t('%lld games', f.games) : t('Not found'), dot(f.found ? 'ok' : 'bad')], () => confirm(t('Remove this folder?'), t('%@ leaves the library. Nothing is deleted from the disk.', f.path), t('Remove'), async () => { folders = await ask('folders.remove', { path: f.key }); await reload(); again(layer, draw); }), { id: 'f' + f.key, ic: 'folder', help: t('Select to remove it from the library.') })), row(t('Add a folder'), icon('add'), () => pickFolder(async () => { folders = await ask('folders'); again(layer, draw); }), { id: 'addfolder' }), row(t('Look again'), t('%lld games', L.total), async () => { await reload(true); folders = await ask('folders'); again(layer, draw); }, { id: 'rescan', ic: 'sync', help: t('Reads the game folders again.') })))],
    account: () => [h('div', { cls: 'rows' }, people.list.map(p => row(p.name, [p.locked && icon('lock'), p.id === people.active && icon('done')], () => p.id === people.active ? type(t('Name'), p.name, async name => { people = await ask('profiles.rename', { profile: p.id, name }); again(layer, draw); }) : choose(p), { id: 'p' + p.id, ic: 'person', help: p.id === people.active ? t('Select to rename it.') : t('Select to play as this profile.') })), row(t('New profile'), icon('add'), () => type(t('Name'), '', async name => { people = await ask('profiles.add', { name }); again(layer, draw); }), { id: 'newp' }))],
    general: () => [h('div', { cls: 'rows' }, row(t('Guided setup'), icon('chevron'), () => openGuide(), { id: 'guide', ic: 'checklist', help: t('Reopen the guided setup without resetting your library.') }))],
    integrations: () => [
      h('div', { cls: 'rows' },
        row(t('Steam'), [steam.found ? t('%lld games', steam.games) : t('Not found'), h('span', { cls: 'sw' })], async () => { S.play('confirm', document.activeElement); steam = steamSeen = await ask('steam.set', { on: !steam.on }); await reload(true); again(layer, draw); }, { id: 'steam', ic: 'gamepad', role: 'switch', checked: steam.on, sub: t('Reads Steam’s lists of installed games and the pictures it keeps on this computer. Changes nothing and sends nothing; Steam itself starts the games.'), help: steam.found ? [steam.libraries.join(', '), steam.downloading && t('%lld still downloading, left out', steam.downloading), steam.others && t('%lld tools and extras, left out', steam.others)].filter(Boolean).join('. ') : t('Steam was not found on this computer. It is looked for again each time.') }),
        row(t('Game information online'), [online.on ? t('%lld games known', online.known) : t('Off'), h('span', { cls: 'sw' })], async () => { S.play('confirm', document.activeElement); online = await ask('online.set', { on: !online.on }); await reload(); again(layer, draw); }, { id: 'online', ic: 'search', role: 'switch', checked: online.on, sub: onlineText() }),
        online.known > 0 && row(t('Delete what was found online'), t('%lld games', online.known), () => confirm(t('Delete what was found online?'), t('Covers and descriptions found online leave this computer. Your own pictures stay.'), t('Delete'), async () => { online = await ask('online.clear'); await reload(); again(layer, draw); }), { id: 'clear', ic: 'delete' })),
      h('div', { cls: 'rows' }, row(t('Recompilations'), [t('%lld games', L.games.filter(g => g.kind === 'recompilation').length), icon('chevron')], () => openCatalog(), { id: 'recomp', ic: 'store', sub: t('Reads the recomplauncher.json of each game in your folders. Writes only the settings files games declare. Sends nothing.') }), row(t('Programs'), [String(folders.programs.length), icon('chevron')], () => openProgram(), { id: 'prog', ic: 'terminal', sub: t('Any program with its arguments, an emulator with a game for example. Sends nothing.') }))],
    about: () => [h('div', {}, h('div', { cls: 'rows' }, row(t('Version'), version, null, { id: 'version' }), row(t('Open project docs'), icon('link'), () => link('https://github.com/sofianbll/oort-nx'), { id: 'docs' }))), h('div', {}, h('h2', {}, t('Credits')), h('div', { cls: 'rows' }, [['RecompLauncher SDK', t('The recomplauncher.json format, by Ripalda (MIT)'), 'https://github.com/elripalda/RecompLauncher-SDK'], ['Padwake', t('Following a game’s processes on Windows, by ddoinn (MIT)'), 'https://github.com/ddoinn/padwake'], ['Arcane, Selene', t('The app and the interface Oort NX comes from, by Bium23 and Matthew Silva (MIT)'), 'https://github.com/sofianbll/oort-nx']].map(([a, b, url]) => row(a, icon('link'), () => link(url), { id: a, sub: b })))), h('p', { cls: 'say' }, online.on ? t('No account, no telemetry. Only the names of your games go out, to find their information online: Integrations turns it off.') : t('Everything stays on this computer: no account, no telemetry, no data sent.'))],
  };
  const choose = async p => { const go_ = async pin => { people = await ask('profiles.select', { profile: p.id, pin }); await take(ask('settings'), false); await reload(); again(layer, draw); }; if (p.locked) type(t('Use four digits.'), '', go_, true); else go_().catch(e => deny(document.activeElement, because(e))); };
  const draw = () => {
    const c = page.categories.find(x => x.id === cat), s = sub && c.subjects.find(x => x.id === sub);
    const title = s ? t(s.title) : section(cat);
    const own = (s || c).rows, body = [own.length && h('div', { cls: 'rows' }, own.map(draft)), !s && c.subjects.length && h('div', { cls: 'rows' }, c.subjects.map(x => row(t(x.title), icon('chevron'), () => { S.play('open'); sub = x.id; layer.keep = null; again(layer, draw); layerRow()?.focus(); }, { id: 'sub-' + x.id }))), ...(!s && extra[cat] ? extra[cat]() : [])];
    const foot = page.pending && h('div', { cls: 'draft panel' }, h('p', {}, t('%lld changes to save', page.changes.length)), key(t('Discard'), () => { S.play('back'); take(ask('settings.discard')); }, { id: 'discard' }), key(t('Save'), () => { S.play('success'); take(ask('settings.save')); }, { id: 'save' }));
    return shellOf(null, page.categories.map(x => ({ id: 'c-' + x.id, title: section(x.id), ic: icons[x.id], group: x.group && t(x.group), on: x.id === cat, pick: () => { cat = x.id; sub = null; again(layer, draw); } })), title, body, foot);
  };
  shellActions(layer, () => {
    if (!page.pending) { S.play('back'); return pop(); }
    dialog(t('Save your changes?'), page.changes.length === 1 ? t('One setting changed.') : t('%lld settings changed.', page.changes.length), [[t('Keep editing'), () => {}], [t('Discard'), async () => { await take(ask('settings.discard'), false); pop(); }], [t('Save'), async () => { await take(ask('settings.save'), false); S.play('success'); pop(); }]]);
  });
  const b = layer.actions.b;
  layer.actions.b = () => { if (sub && !document.activeElement.closest('.side')) { const was = 'sub-' + sub; sub = null; S.play('back'); layer.keep = was; again(layer, draw); $(`[data-id="${was}"]`, layer.el)?.focus(); } else b(); };
  layer.actions.x = () => { const c = page.categories.find(x => x.id === cat), rows = (sub && c.subjects.find(x => x.id === sub) || c).rows, sections = [...new Set(rows.filter(r => r.changed).map(r => r.section))]; if (!sections.length) return S.play('deny'); (async () => { for (const section of sections) await take(ask('settings.reset', { section }), false); S.play('confirm'); again(layer, draw); })(); };
  const baseHints = layer.hints;
  layer.hints = () => { const [l, r] = baseHints(); const c = page.categories.find(x => x.id === cat), rows = (sub && c.subjects.find(x => x.id === sub) || c).rows; return [l, [rows.some(r => r.changed) && ['x', t('Reset group'), layer.actions.x], ...r]]; };
  layer.redraw = () => again(layer, draw);
  layer.back = () => { (async () => { [folders, steam, online] = [await ask('folders'), await findSteam(), await ask('online')]; await take(ask('settings')); })(); };
  layer.gone = async () => { await reload(); TABS.includes(tab) || (tab = TABS[0]); homeLayer.redraw(); };
  layer.el.append(...draw());
  S.play('open'); push(layer);
};

/* ---------- Sort ---------- */
const openSort = () => {
  const sorts = [['recent', t('Sort: Recent')], ['name', t('Sort: Name')], ['added', t('Sort: Recently added')], ['playtime', t('Sort: Playtime')]];
  const layer = { el: h('section', { cls: 'veil dialog', role: 'dialog', 'aria-label': t('Sort games') }), over: true };
  const draw = () => h('div', {}, h('h1', {}, t('Sort games')), h('div', { cls: 'rows' }, sorts.map(([id, name]) => row(name, V.sort === id && icon('done'), async () => { S.play('confirm', document.activeElement); await remember({ sort: id }); V.sort = id; await reload(); again(layer, draw); }, { id, cls: V.sort === id ? 'chosen' : '' }))));
  layer.el.append(draw()); layer.keep = V.sort; layer.focus = l => restore({ ...l, focus: first, keep: V.sort });
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['a', t('Select')]]]; layer.gone = () => homeLayer.redraw();
  layer.actions = { rs: () => act('b') };
  S.play('open'); push(layer);
};

/* ---------- Search, and the keys to type with a controller ---------- */
const keyboard = (type, erase, done) => h('div', { cls: 'keyboard' }, [...'abcdefghijklmnopqrstuvwxyz0123456789-'].map(c => key(c, () => type(c))), key('', erase, { ic: 'backspace', aria: t('Erase') }), key('', done, { ic: 'done', aria: t('Done') }), key(t('Space'), () => type(' '), { cls: 'wide' }));
const openSearch = () => {
  if (top().search) return;
  const input = h('input', { type: 'text', placeholder: t('Find a game'), 'aria-label': t('Find a game'), autocomplete: 'off', spellcheck: 'false', 'data-id': 'q' }), found = h('div', { cls: 'found', 'aria-live': 'polite' }), keys = h('div');
  const layer = { el: h('section', { cls: 'veil', role: 'search' }, h('div', { cls: 'find' }, h('label', { cls: 'field' }, icon('search'), input), keys, found)), over: true, search: true };
  const open = g => { S.play('confirm'); pop(); tab = TABS[0]; selected = g.id; reload().then(() => { while (layers.length > 1) pop(); homeLayer.redraw(); }); };
  let turn = 0;
  const look = async () => { const me = ++turn, q = input.value.trim(), r = q ? (await ask('library', { search: q, sort: 'name' })).games.slice(0, 12) : []; if (me !== turn) return; found.replaceChildren(...(r.length ? r.map(g => h('button', { cls: 'tile', 'data-id': g.id, onclick: () => open(g) }, face(g, 'icon'), g.name)) : q ? [h('p', { cls: 'say' }, t('No games match.'))] : [])); };
  input.addEventListener('input', look);
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); found.querySelector('button')?.click(); } });
  layer.padChanged = () => { keys.replaceChildren(...(pad ? [keyboard(c => { input.value += c; look(); }, () => { input.value = input.value.slice(0, -1); look(); }, () => { const e = found.querySelector('button'); e ? go(e) : S.play('deny'); })] : [])); };
  layer.padChanged(); layer.focus = () => (pad && !keysInHand ? focusable(keys)[0] : input).focus();
  layer.hints = () => [[['b', t('Close'), () => act('b')]], [pad && ['x', t('Erase'), () => layer.actions.x()], ['a', t('Select')]]];
  layer.actions = { x: () => { input.value = input.value.slice(0, -1); look(); }, y: () => { input.value = ''; look(); } };
  S.play('open'); push(layer);
};
/* One line of text, by keyboard or controller. */
const type = (title, value, done, digits) => {
  const input = h('input', { type: 'text', value, 'aria-label': title, inputmode: digits ? 'numeric' : null, maxlength: digits ? 4 : 40, 'data-id': 'q', autocomplete: 'off', spellcheck: 'false' });
  const ok = async () => { try { await done(input.value.trim()); S.play('success'); pop(); } catch (e) { deny(input, because(e)); $('p', layer.el).textContent = because(e); } };
  const layer = { el: h('section', { cls: 'veil dialog', role: 'dialog', 'aria-label': title }), over: true };
  layer.el.append(h('div', {}, h('h1', {}, title), h('label', { cls: 'field' }, input), h('p', { 'aria-live': 'polite' }), pad && keyboard(c => { if (input.value.length < input.maxLength) input.value += c; }, () => { input.value = input.value.slice(0, -1); }, ok), h('div', { cls: 'keys' }, key(t('Cancel'), () => pop()), key(t('Save'), ok))));
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); ok(); } });
  layer.focus = () => { (pad && !keysInHand ? focusable($('.keyboard', layer.el))[0] : input).focus(); };
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['a', t('Select')]]];
  push(layer);
};

/* ---------- Dialog: precise, at most three keys, the safe one first ---------- */
const dialog = (title, text, keys) => {
  const layer = { el: h('section', { cls: 'veil dialog', role: 'alertdialog', 'aria-label': title }), over: true };
  layer.el.append(h('div', {}, h('h1', {}, title), text && h('p', {}, text), h('div', { cls: 'keys' }, keys.map(([label, run, cls]) => key(label, async () => { pop(); await run(); }, { cls: cls || '' })))));
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['a', t('Select')]]];
  S.play('notification'); push(layer);
};
const confirm = (title, text, label, run) => dialog(title, text, [[t('Cancel'), () => {}], [label, run, 'danger']]);

/* ---------- Choosing folders and files, without leaving the app ---------- */
const pickFile = ({ title, extensions = [], folders = false, files = true, done }) => {
  let at = { path: '', entries: [], parent: null };
  const layer = { el: h('section'), page: true };
  const openPath = async (path, from) => { try { at = await ask('files', { path, extensions, folders: folders && !files }); layer.keep = from || null; again(layer, draw); if (!from) first(layer); } catch (e) { deny(document.activeElement, because(e)); } };
  const use = path => { S.play('confirm'); pop(); done(path); };
  const up = () => at.parent == null ? (S.play('back'), pop()) : (S.play('back'), openPath(at.parent, at.path));
  const draw = () => h('div', { cls: 'sheet' }, h('h1', {}, title), h('p', { cls: 'sub' }, at.shown || at.path || ''), h('div', { cls: 'list' }, h('div', { cls: 'rows' }, folders && at.path && row(t('Choose this folder'), at.games ? t('%lld games', at.games) : '', () => use(at.path), { id: 'this', ic: 'done' }), at.parent != null && row(t('Up one folder'), '', up, { id: 'up', ic: 'folder' }), at.entries.length ? at.entries.map(e => row(e.name, e.folder && icon('chevron'), () => e.folder ? (S.play('open'), openPath(e.path)) : use(e.path), { id: e.path, ic: e.folder ? 'folder' : 'save' })) : h('p', { cls: 'say' }, t('No matching files or folders.')))), h('p', { cls: 'help', 'aria-live': 'polite' }));
  layer.el.append(draw());
  layer.hints = () => [[['b', at.parent != null ? t('Up one folder') : t('Back'), up], ['y', t('Close'), () => { S.play('back'); pop(); }]], [folders && at.path && ['x', t('Choose this folder'), () => use(at.path)], ['a', t('Open')]]];
  layer.actions = { b: up, y: () => { S.play('back'); pop(); }, x: () => folders && at.path && use(at.path) };
  push(layer); openPath('');
};
const pickFolder = after => pickFile({ title: t('Choose a folder of game files'), folders: true, files: false, done: async path => { try { const f = await ask('folders.add', { path }); await reload(); if (after) await after(); else { selected = L.games[0]?.id ?? null; homeLayer.redraw(); } const n = f.folders.at(-1)?.games ?? 0; if (!n) dialog(t('No games were found in this folder.'), t('Games come as folders with a recomplauncher.json inside. The folder stays in the library and is read again at each start.'), [[t('Close'), () => {}]]); } catch (e) { deny(null, because(e)); } } });

/* ---------- Adding ---------- */
const sheet = (title, draw, more = {}) => { const layer = { el: h('section'), page: true, ...more }; const body = () => h('div', { cls: 'sheet' }, h('h1', {}, title), h('div', { cls: 'list' }, draw(layer)), h('p', { cls: 'help', 'aria-live': 'polite' })); layer.refresh = () => again(layer, body); layer.redraw = layer.refresh; layer.el.append(body()); layer.hints = layer.hints || (() => [[['b', t('Back'), () => act('b')]], [['a', t('Open')]]]); S.play('open'); return push(layer); };
const openAdd = async () => { await findSteam(); return sheet(t('Add game'), () => h('div', { cls: 'rows' }, addRows())); };
const openProgram = () => {
  const p = { program: '', target: '', args: '', name: '', about: null }, base = x => x.split(/[\\/]/).pop();
  const add = async () => { try { const r = await ask('programs.add', { program: p.program, target: p.target || null, args: p.args, name: p.name }); S.play('success'); await reload(); selected = r.added; tab = TABS[0]; while (layers.length > 1) { if (top().guide) break; pop(); } if (top().guide) top().refresh(); else homeLayer.redraw(); } catch (e) { deny(document.activeElement, because(e)); } };
  // A game for this system, in what a folder holds.
  const programs = system === 'windows' ? ['exe', 'bat', 'cmd'] : [];
  sheet(t('Add a program'), layer => h('div', { cls: 'rows' },
    row(t('Program'), p.program ? base(p.program) : t('Choose'), () => pickFile({ title: t('Program'), extensions: programs, done: async x => { p.program = x; p.about = await ask('programs.about', { path: x }).catch(() => null); layer.refresh(); } }), { id: 'program', ic: 'terminal', sub: p.program && [p.program, p.about?.publisher, p.about?.version && t('Version %@', p.about.version)].filter(Boolean).join(', ') }),
    row(t('Game file'), p.target ? base(p.target) : t('Optional'), () => pickFile({ title: t('Game file'), done: x => { p.target = x; layer.refresh(); } }), { id: 'target', ic: 'save', sub: p.target, help: t('For an emulator: the game it opens. Passed to the program as its last argument.') }),
    row(t('Arguments'), p.args || t('Optional'), () => type(t('Arguments'), p.args, x => { p.args = x; layer.refresh(); }), { id: 'args', ic: 'tune', help: t('Put quotes around an argument with spaces.') }),
    row(t('Name'), p.name || (!p.target && p.about?.name) || base(p.target || p.program).replace(/\.[^.]+$/, '') || t('Automatic'), () => type(t('Name'), p.name || p.about?.name || '', x => { p.name = x; layer.refresh(); }), { id: 'name', ic: 'edit' }),
    row(t('Add to the library'), icon('add'), add, { id: 'add', off: !p.program && t('Choose the program first.') })));
};
const openCatalog = async () => {
  const list = await ask('catalog'), states = { playable: [t('Playable, says the project'), 'ok'], experimental: [t('Experimental'), ''], early: [t('Early'), ''], research: [t('Research'), ''], withdrawn: [t('Original project gone'), 'bad'] };
  sheet(t('Projects'), () => [h('p', { cls: 'say' }, t('Projects that rebuild older games for this computer. Oort NX opens their page and installs nothing. Each one asks for your own copy of the game.')), h('div', { cls: 'rows' }, list.map(p => row(p.project, [states[p.state]?.[0], dot(states[p.state]?.[1] ?? ''), icon('link')], () => link('https://github.com/' + p.repo), { id: p.repo, sub: [p.game, p.gameVersion && t('Game version %@', p.gameVersion), t('Licence: %@', p.license || t('not declared')), p.systems.map(s => ({ windows: 'Windows', linux: 'Linux' })[s]).join(', '), p.manifest && 'recomplauncher.json'].filter(Boolean).join(', '), help: 'https://github.com/' + p.repo })))]);
};

/* ---------- Playing ---------- */
let playing = null, preparing = null;
const play = async id => {
  const g = game(id) || await ask('game', { id });
  if (playing) return openPlaying();
  S.play('play');
  $('#card').classList.remove('on'); playing = g; g.phase = g.kind === 'steam' ? 'waiting' : null; openPlaying();
  try { await invoke('launch', { id, fullscreen: full }); } catch (e) { playing = null; const l = top(); if (l?.launch) pop(); dialog(t('%@ did not start', g.name), because(e), [[t('Close'), () => {}], [t('Details'), () => openDetail(id)]]); }
};
/* Black, the game's name, its art: what the Mac app shows while a game starts. Coming back to Oort finds it here. */
const openPlaying = () => {
  const g = playing, layer = { el: h('section', { cls: 'launch', role: 'status', 'aria-label': t('Starting %@', g.name) }), launch: true };
  const steam = { waiting: () => t('Waiting for Steam to start the game…'), updating: () => t('Steam is updating this game. It starts after.') };
  const draw = late => layer.el.replaceChildren(...[g.hero && h('div', { cls: 'bg', style: `background-image:url("${artURL(g, 'hero')}")` }), h('div', { cls: 'mid' }, g.logo ? h('img', { cls: 'logo', src: artURL(g, 'logo'), alt: g.name }) : [g.mark && !g.hero && h('img', { cls: 'mark', src: artURL(g, 'mark'), alt: '' }), h('h1', {}, g.name)], steam[g.phase] && h('p', { role: 'status' }, steam[g.phase]()), late && h('div', { cls: 'keys' }, steam[g.phase] ? key(t('Cancel'), () => invoke('close_game').catch(() => {}), { id: 'close' }) : key(t('Close Game'), () => confirm(t('Close %@?', g.name), t('Anything not saved in the game is lost.'), t('Close Game'), () => invoke('close_game').catch(() => {})), { id: 'close' })))].filter(Boolean));
  draw(false); layer.actions = { b: () => {} }; layer.hints = () => layer.late ? [[], [['a', t('Select')]]] : [[], []];
  layer.timer = setTimeout(() => { layer.late = true; draw(true); if (top() === layer) first(layer); hints(); }, 4000); layer.gone = () => clearTimeout(layer.timer);
  layer.phase = () => { draw(layer.late); if (layer.late && top() === layer) first(layer); };
  push(layer);
};
const ended = async end => {
  const g = playing; playing = null;
  while (layers.some(l => l.launch)) { if (top().launch) { pop(); break; } pop(); }
  await reload(); homeLayer.redraw(); top().refresh?.();
  if (end.cancelled) return S.play('back');
  S.play('resume');
  if (end.error === 'steam-not-started') return dialog(t('%@ did not start', end.name || g?.name || ''), because(end.error), [[t('Close'), () => {}], [t('Details'), () => openDetail(end.id)]]);
  if (end.crashed || end.error) dialog(t('%@ stopped', end.name || g?.name || ''), end.message || (end.error ? because(end.error) : t('It closed with an error. Its last messages are kept with Oort NX’s logs.')), [[t('Close'), () => {}], [t('Details'), () => openDetail(end.id)]]);
  else if (V.sessionCard) card(h('strong', {}, end.name || ''), t('Session ended'), t('This session: %@', duration(end.seconds)), t('In total: %@', duration(end.total)));
};
let carded = 0;
const card = (...lines) => { const c = $('#card'); clearTimeout(carded); c.replaceChildren(...lines.map(l => typeof l === 'string' ? h('span', {}, l) : l)); c.classList.add('on'); carded = setTimeout(() => c.classList.remove('on'), 8000); };
const prepare = async id => { try { await invoke('prepare', { id }); preparing = { id, value: 0, text: '' }; S.play('play'); top().refresh?.(); } catch (e) { deny(document.activeElement, because(e)); dialog(t('This game could not get ready'), because(e), [[t('Close'), () => {}]]); } };
const prepared = async p => {
  const layer = layers.find(l => l.id === p.id);
  if (p.progress) { preparing = { id: p.id, ...p.progress }; const bar = layer && $('.bar', layer.el); if (bar) { bar.style.setProperty('--at', p.progress.value); $('.wait .say', layer.el).textContent = p.progress.text; } return; }
  preparing = null; await reload(); layer?.refresh?.(); if (!layer) homeLayer.redraw();
  if (p.end.done) { S.play('success'); card(h('strong', {}, game(p.id)?.name || ''), t('Ready to play')); } else dialog(t('This game could not get ready'), p.end.message || t('Its setup step stopped with code %@.', p.end.code ?? '—'), [[t('Close'), () => {}]]);
};

/* ---------- The first steps: short, never in the way, and there again in Settings ---------- */
const openGuide = async (at = 'welcome') => {
  const pages = (await ask('guide')).pages;
  let page = at, steam = null, take = true;
  const layer = { el: h('section', { cls: 'veil guide' }), guide: true };
  const set = async (id, value) => { await ask('settings.set', { id, value }); const p = await ask('settings.save'); apply(p.view); layer.refresh(); };
  const turn = async d => {
    const to = pages[pages.indexOf(page) + d];
    if (!to) return end();
    if (page === 'games' && d > 0 && steam?.found && take !== steam.on) { steam = steamSeen = await ask('steam.set', { on: take }); await reload(true); }
    page = to; S.play(d > 0 ? 'confirm' : 'back'); layer.keep = 'continue';
    await ask('guide', { page }).catch(() => {});
    if (page === 'games') { steam = null; enter(); steam = await findSteam(); take = steam.chosen ? steam.on : steam.found; }
    enter();
  };
  const enter = () => { if (!layers.includes(layer)) return; fill(layer.el, draw()); if (layer === top()) { layer.focus(layer); settle(); } };
  const end = async () => { await ask('guide', { done: true }).catch(() => {}); await reload(); S.play('success'); pop(); homeLayer.redraw(); };
  const online = async on => { await ask('online.set', { on }); if (on) await reload(); await turn(1); };
  const options = id => layer.settings?.categories.flatMap(c => [...c.rows, ...c.subjects.flatMap(x => x.rows)]).find(r => r.id === id);
  const pick = (id, ic) => { const r = options(id); return r && chooser(t(r.title), r.options.map(o => [o.value, t(o.label)]), r.value, v => set(id, v), { id, ic }); };
  const faces = {
    welcome: () => ({ title: t('Welcome to Oort NX'), say: t('The games you already have, in one library. No account is needed.'), rows: [pick('appLanguage', 'language')] }),
    controller: () => ({ title: t('Your controller'), say: t('Plug one in or pair it, then press any button. Keyboard and mouse work everywhere too.'), rows: [row(pad ? padName(pad.name) || t('Controller') : plugged[0] || t('No Gamepad Connected'), pad ? [t('Controller recognised'), dot('ok')] : plugged.length ? t('Press any button') : t('Keyboard and mouse are ready'), () => {}, { id: 'pad', ic: 'gamepad' }), pick('buttonNames', 'tune')] }),
    games: () => ({ title: t('Where are your games?'), say: t('Add what you want now, or later with the + tile. Nothing is moved or changed.'), rows: [
      steam == null ? row(t('Steam'), t('Looking…'), () => {}, { id: 'steam', ic: 'gamepad' }) : steam.found ? row(t('Steam'), [t('%lld games', steam.games), h('span', { cls: 'sw' })], () => { take = !take; S.play('confirm', document.activeElement); layer.refresh(); }, { id: 'steam', ic: 'gamepad', role: 'switch', checked: take, sub: t('Reads Steam’s lists of installed games and the pictures it keeps on this computer. Changes nothing and sends nothing; Steam itself starts the games.') }) : row(t('Steam'), t('Not found'), () => {}, { id: 'steam', ic: 'gamepad', sub: t('Steam was not found on this computer. It is looked for again each time.') }),
      row(t('A program'), icon('chevron'), () => openProgram(), { id: 'program', ic: 'terminal', sub: system === 'windows' ? t('Any game or emulator you start with an .exe file. Its name and icon come with it.') : t('Any game or emulator, or its menu entry. Its name and icon come with it.') }),
      row(t('A folder of games'), icon('chevron'), () => pickFolder(() => layer.refresh()), { id: 'folder', ic: 'folder', sub: t('For recompiled games: each one has its recomplauncher.json.') }),
    ], status: L.total ? t('%lld games in your library', L.total) : null }),
    online: () => ({ title: t('Look for game information online?'), say: onlineText(), rows: [], keys: [key(t('No'), () => online(false), { id: 'continue' }), key(t('Yes, look online'), () => online(true), { id: 'yes' })], status: t('You can change this in Settings, Integrations.') }),
    done: () => ({ title: t('All set'), say: t('%lld games in your library', L.total), rows: [], status: t('The + tile adds games. Settings has these steps again, under General.'), next: t('Open library') }),
  };
  const draw = () => {
    const f = faces[page](), last = page === 'welcome';
    return [h('div', { cls: 'steps', role: 'dialog', 'aria-label': f.title }, h('p', { cls: 'num count' }, `${pages.indexOf(page) + 1} / ${pages.length}`), h('h1', {}, f.title), h('p', { cls: 'lead' }, f.say), f.rows.filter(Boolean).length > 0 && h('div', { cls: 'list' }, h('div', { cls: 'rows' }, f.rows)), f.status && h('p', { cls: 'status', role: 'status' }, f.status),
      h('div', { cls: 'keys' }, f.keys || key(f.next || t('Continue'), () => turn(1), { id: 'continue' }), last ? key(t('Skip setup'), end, { id: 'skip' }) : key(t('Back'), () => turn(-1), { id: 'back' })))];
  };
  layer.focus = l => $('[data-id=continue]', l.el)?.focus({ preventScroll: true });
  layer.refresh = async () => { layer.settings = await ask('settings'); if (layers.includes(layer)) again(layer, draw); };
  layer.redraw = layer.refresh; layer.back = () => layer.refresh(); layer.padChanged = () => layer.refresh();
  layer.move = (dir, a) => {
    if (dir === 'left' || dir === 'right') { if (!a.classList.contains('row')) return false; if (a.step) a.step(dir === 'left' ? -1 : 1); else S.play('deny', a); return true; }
    // The rows, then the key that goes on: the same way down and up.
    const list = [...layer.el.querySelectorAll('.row')], i = list.indexOf(a), n = i < 0 ? dir === 'up' && list.at(-1) : list[i + (dir === 'up' ? -1 : 1)] || dir === 'down' && $('[data-id=continue]', layer.el);
    if (n) go(n); else S.play('deny', a);
    return true;
  };
  layer.actions = { b: () => page === 'welcome' ? null : turn(-1) };
  layer.hints = () => [[page !== 'welcome' && ['b', t('Back'), () => turn(-1)]], [document.activeElement?.step ? ['a', t('Change')] : ['a', t('Select')]]];
  layer.settings = await ask('settings');
  if (page === 'games') { steam = await findSteam(); take = steam.chosen ? steam.on : steam.found; }
  layer.el.append(...shown([draw()]));
  S.play('open'); push(layer);
};

/* ---------- Start ---------- */
export const oort = { act, ask, apply, layers, sounds: S, cloud: C, get view() { return V; }, get library() { return L; }, guide: openGuide, pad: s => padding.feed(s), fullscreen: setFullscreen };
const start = async () => {
  const hello = await ask('hello', { languages: [...navigator.languages] });
  prompts = await ask('prompts'); plugged = await invoke('pads'); version = hello.version; system = hello.system; TABS = hello.tabs; full = hello.view.fullscreen; home = hello.lastHome === 'collection' ? 'collection' : 'spotlight';
  apply(hello.view); tab = TABS.includes(hello.view.startingTab) ? hello.view.startingTab : TABS[0];
  if (hello.view.restore && hello.lastGame) selected = hello.lastGame;
  await reload();
  homeLayer.el.classList.add('layer'); layers.push(homeLayer); host.append(homeLayer.el); homeLayer.redraw();
  T.event.listen('session', e => ended(e.payload)); T.event.listen('prepare', e => prepared(e.payload)); T.event.listen('online', e => found(e.payload)); T.event.listen('steam', e => { if (playing?.id === e.payload.id) { playing.phase = e.payload.phase; layers.find(l => l.launch)?.phase(); } }); T.event.listen('pad', e => padding.feed(e.payload)); T.event.listen('pads', e => { plugged = e.payload; padChanged(); top()?.padChanged?.(); });
  // Games unzipped while Oort was behind show on return.
  addEventListener('focus', async () => { if (playing || layers.length > 1) return; const before = JSON.stringify(L.games.map(g => [g.id, g.state])); await reload(true); if (JSON.stringify(L.games.map(g => [g.id, g.state])) !== before) homeLayer.redraw(); });
  S.warm(); S.play('boot');
  if (hello.guide.open) await openGuide(hello.guide.page);
  else if (hello.guide.news) { await ask('guide', { seen: true }); dialog(t('What’s new in Oort NX'), t('Your programs now show their own icon and name. Oort NX can also show the games Steam installed, and look for covers and descriptions online if you say yes.'), [[t('Open library'), () => {}], [t('Guided setup'), () => openGuide()]]); }
  root.dataset.ready = '1'; root.dataset.version = version;
  window.oort = oort;
};
start().catch(e => { host.replaceChildren(h('div', { cls: 'empty' }, h('h1', {}, 'Oort NX'), h('p', { cls: 'say' }, String(e)))); root.dataset.ready = 'error'; });
