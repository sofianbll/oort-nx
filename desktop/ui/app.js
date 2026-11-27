/* Oort NX for Windows and Linux: the screens. What the app knows and decides is in oort-core; this file draws it. */
import { STRINGS, GAME_WORDS } from './gen/strings.js';
import { ICONS, PALETTES } from './gen/names.js';
import { cloud as makeCloud } from './cloud.js';
import { sounds as makeSounds } from './sound.js';
import { still, focusable, nearest, controller, padName } from './nav.js';
import { handOf, stepper as wheelOf, swiper } from './input.js';
import { menuOf } from './menu.js';
import { KINDS, KIND_NAMES, padKind, kindNames, liveOf } from './pads.js';
import { padMap } from './padview.js';
import { gameWord } from './words.js';

const T = window.__TAURI__, root = document.documentElement, $ = (s, r = document) => r.querySelector(s);
const invoke = (name, args) => T.core.invoke(name, args);
/* One question at a time, so an answer never overtakes a later change. Sounds do not wait in line. */
let line = Promise.resolve();
export const ask = (method, params = {}) => method === 'sound' ? invoke('core', { method, params }) : line = line.catch(() => {}).then(() => invoke('core', { method, params }));

/* ---------- Texts ---------- */
let V = {}, language = 'en';
const translate = (lang, key, ...args) => {
  let s = (STRINGS[lang] || STRINGS.en)[key] ?? STRINGS.en[key] ?? key;
  if (typeof s === 'object') s = s[new Intl.PluralRules(lang).select(args[0])] ?? s.other;
  return s.replace(/%(?:\d+\$)?(?:lld|@|d)/g, () => args.shift() ?? '').replace(/ {2,}/g, ' ');
};
export const t = (key, ...args) => translate(language, key, ...args);
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
const key = (label, act, { ic, cls = '', off, id, aria, pressed } = {}) => h('button', { cls: 'key ' + cls, 'aria-disabled': off ? true : null, 'aria-pressed': pressed, 'data-id': id, 'aria-label': aria, onclick: e => off ? deny(e.currentTarget, off) : act(e) }, ic && icon(ic), label && h('span', {}, label));
const row = (what, value, act, o = {}) => h('button', { cls: 'row ' + (o.cls || ''), 'data-id': o.id, 'data-help': o.help, 'data-idle': !act && !o.slides, 'data-pick': o.pick, role: o.role, 'aria-checked': o.checked, 'aria-disabled': o.off ? true : null, 'aria-label': o.aria, onclick: e => o.off ? deny(e.currentTarget, o.off === true ? '' : o.off) : act && act(e.currentTarget) }, o.ic && icon(o.ic), h('span', { cls: 'what' }, what, o.sub && h('small', {}, o.sub)), value && h('span', { cls: 'value' }, value));
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
  V = v; language = ['en', 'fr'].includes(v.language) ? v.language : 'en';
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
  // Drawn while out of sight, the tabs have no width to mark.
  requestAnimationFrame(() => layer.el.querySelectorAll('.tabs').forEach(pill));
  hints();
};
/* Draws a layer again without losing the place. */
const again = (layer, draw) => { const keep = layer.el.contains(document.activeElement) ? document.activeElement.dataset.id : layer.keep, at = [...layer.el.querySelectorAll('.list,.detail,.scroll,.side')].map(e => e.scrollTop); fill(layer.el, draw()); [...layer.el.querySelectorAll('.list,.detail,.scroll,.side')].forEach((e, i) => { e.scrollTop = at[i] || 0; }); layer.keep = keep; if (layer === top()) restore(layer); hints(); };

/* ---------- Hints: the buttons in hand, and only what works now ---------- */
let pad = null, plugged = [], prompts = {}, version = '', system = '', abilities = [], homeSeen = false;
const keyCaps = { a: '⏎', b: 'Esc', x: 'X', y: 'Y', lb: 'Q', rb: 'E', lt: 'Home', rt: 'End', ls: 'Ctrl F', rs: 'F3', view: 'V', menu: 'Ctrl O', home: 'Ctrl K', move: '← →' };
/* The last thing used: its names are on the hints, whatever else is plugged in. A finger has no buttons to name. */
const hand = handOf(now => { root.dataset.hand = now; hints(); top()?.handChanged?.(); });
root.dataset.hand = hand.now;
const inPad = () => hand.now === 'pad' && pad;
const padNames = (style, name = '') => style === 'playstation' && /dualshock|05c4|09cc/i.test(name) ? { ...prompts.playstation, view: 'Share' } : prompts[style] || {};
const badgeText = b => inPad() ? padNames(V.buttonNames === 'automatic' ? pad.brand : V.buttonNames, pad.name)[b] : keyCaps[b];
const badge = b => h('span', { cls: 'badge', 'aria-hidden': 'true' }, badgeText(b) || b.toUpperCase());
/* Windows keeps an Xbox controller's Home for itself: it is named once it was seen, and + held does the same. */
const hasHome = () => !inPad() || homeSeen || pad.brand !== 'xbox';
const menuHint = () => hasHome() ? ['home', t('Control center'), openMenu, inPad() && t('Hold: %@', t('Settings'))] : ['menu', t('Hold: %@', t('Control center')), openMenu];
/* What A does on what has the focus, in a word; nothing where A does nothing. */
const aHint = () => {
  const e = document.activeElement;
  if (!e || !top()?.el.contains(e) || e.getAttribute('aria-disabled') === 'true' || e.hasAttribute('data-idle') || e.matches('input,.about,.box')) return null;
  return e.slides ? ['move', t('Change')] : e.step || e.getAttribute('role') === 'switch' ? ['a', t('Change')] : e.matches('.key,[data-pick]') ? ['a', t('Select')] : ['a', t('Open')];
};
const hints = () => {
  const bar = $('#hints'), layer = top();
  document.querySelectorAll('[data-badge]').forEach(e => { e.textContent = badgeText(e.dataset.badge) || ''; });
  if (!layer) return bar.replaceChildren();
  // Turned off, the hints still leave a way back and the menu to a mouse, a finger or a keyboard.
  const keep = list => V.hints ? list : inPad() ? [] : list.filter(x => x && x[2] && (x[0] === 'b' || x[0] === 'home'));
  const [left, right] = (layer.hints ? layer.hints() : [[], []]).map(list => keep(list).filter(Boolean));
  bar.replaceChildren(...[left, right].map(list => h('div', {}, list.map(([b, label, run, sub]) => h(run ? 'button' : 'span', { cls: 'hint', tabindex: run ? '-1' : null, onclick: run }, badge(b), h('span', {}, label, sub && h('small', {}, sub)))))));
};

/* A hint pressed with the mouse acts for where the player is: it never takes the focus, which says where Back goes. */
$('#hints').addEventListener('mousedown', e => e.preventDefault());

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
  if (name === 'home' && isPage(layer)) return openMenu();
};
/* A page of the app: not a question, a search, the first steps or a game being started. */
const isPage = (layer = top()) => !!layer && !layer.over && !layer.launch && !layer.guide;
const zoom = async d => { const row = (await ask('settings')).categories.flatMap(c => [...c.rows, ...c.subjects.flatMap(x => x.rows)]).find(r => r.id === 'interfaceZoom'); await ask('settings.set', { id: row.id, value: d ? Math.min(row.max, Math.max(row.min, row.value + d * row.step)) : row.default }); apply((await ask('settings.save')).view); };
/* With Ctrl, what the Mac app does with ⌘. */
const shortcuts = { f: () => act('ls'), k: () => act('home'), o: () => act('menu'), d: () => act('x'), ',': () => openSettings(), n: () => openAdd(), Enter: () => top().play?.(), '+': () => zoom(1), '=': () => zoom(1), '-': () => zoom(-1), 0: () => zoom(0) };
addEventListener('keydown', e => {
  if (e.altKey || e.metaKey) return;
  const typing = e.target.matches?.('input');
  if (!['Control', 'Shift'].includes(e.key)) hand.keys();
  const arrows = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };
  const letters = { x: 'x', y: 'y', q: 'lb', e: 'rb', v: 'view', m: 'menu', h: 'home' }, others = { Escape: 'b', F3: 'rs', Home: 'lt', End: 'rt' };
  if (e.ctrlKey) {
    const run = shortcuts[e.key.length === 1 ? e.key.toLowerCase() : e.key];
    if (run && !e.repeat) { e.preventDefault(); if (isPage() || 'fk'.includes(e.key.toLowerCase())) run(); }
    return;
  }
  if (arrows[e.key]) { if (typing && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) return; e.preventDefault(); return act(arrows[e.key]); }
  if (e.key === 'F11') { e.preventDefault(); return abilities.includes('fullscreen') && setFullscreen(!full); }
  if (others[e.key] && !(typing && others[e.key] !== 'b' && e.key !== 'F3')) { e.preventDefault(); return act(others[e.key]); }
  if (!typing && !e.repeat && letters[e.key.toLowerCase()]) { e.preventDefault(); act(letters[e.key.toLowerCase()]); }
});
/* From a finger lifted to its click, in milliseconds. */
const PRESS = 120;
/* The game chosen when a press began: a click chooses, a click on the chosen game opens it. */
let chosen = null;
addEventListener('pointerdown', e => { chosen = selected; const b = e.target.closest('button'); if (b) S.play('select', b); }, true);
addEventListener('pointermove', e => { if (!e.buttons) hand.move(e); }, { passive: true });
/* What is drawn for a mouse or a finger is drawn once the press is over: what is pressed stays where it is. */
for (const kind of ['pointerup', 'pointercancel']) addEventListener(kind, e => hand.lifted(e, f => setTimeout(f, e.pointerType === 'touch' ? PRESS : 0)), true);
addEventListener('click', e => { if (!e.detail && e.isTrusted) S.play('select', document.activeElement); }, true);
/* Rows follow the pointer. The shelf, the grid and the list of pages do not: they only show it, so nothing slides under it
   and the line marked is the page shown. */
addEventListener('mouseover', e => { if (!e.movementX && !e.movementY || hand.now === 'pad') return; const b = e.target.closest('.row,.found .tile,.orb,.pills .key'); if (b && b !== document.activeElement && top()?.el.contains(b) && !b.closest('.holding')) b.focus({ preventScroll: true }); });
addEventListener('focusin', e => { const layer = top(); if (layer?.el.contains(e.target)) { layer.onfocus && layer.onfocus(e.target); const p = $('.help', layer.el); if (p) p.textContent = e.target.dataset.help || ''; hints(); } });
/* A right click, a long press, the keyboard's menu key: the options of what is under it. */
addEventListener('mousedown', e => {
  // Focusing a tile scrolls the shelf before the context-menu event can name the pressed tile.
  if (e.button === 2 && e.target.closest('.shelf .tile,.grid .tile')) e.preventDefault();
});
addEventListener('contextmenu', e => { if (e.target.closest('input')) return; e.preventDefault(); if (isPage()) top().context?.(e.target); });
/* The shelf: a wheel or a finger goes from game to game. */
const turnShelf = d => isPage() && top().slide?.(d), wheel = wheelOf(turnShelf), swipe = swiper(turnShelf, () => top()?.pitch?.() || Infinity);
let swiped = false;
addEventListener('wheel', e => { if (e.ctrlKey || !isPage() || !top().slide?.(0)) return; hand.down({ pointerType: 'mouse' }); wheel(e); }, { passive: true });
addEventListener('pointerdown', e => { swiped = false; if (e.pointerType === 'touch' && e.isPrimary && isPage() && top().slide?.(0)) swipe.down(e.clientX, e.pointerId); }, true);
addEventListener('pointermove', e => { if (e.pointerType === 'touch') swipe.move(e.clientX, e.pointerId); }, { passive: true });
for (const kind of ['pointerup', 'pointercancel']) addEventListener(kind, e => { if (e.pointerType === 'touch' && swipe.up(e.pointerId)) swiped = true; }, true);
addEventListener('click', e => { if (swiped && e.detail) { swiped = false; e.stopImmediatePropagation(); e.preventDefault(); } }, true);
const live = liveOf();
const padding = controller({
  act: name => { hand.pad(); if (name === 'home') homeSeen = true; if (name === 'a') S.play('select', document.activeElement); act(name); },
  // Held: View searches, + opens the menu where Home is out of reach, Home goes to Settings.
  hold: name => { hand.pad(); if (name === 'view') act('ls'); else if (name === 'menu') act('home'); else { homeSeen = true; if (isPage() && !top().settings) openSettings(); } },
  live: s => live.feed(s),
  found: p => { pad = p; if (p?.pressed) hand.pad(); else if (!p && hand.now === 'pad') hand.keys(); S.warm(); if (p) ask('pad', { kind: p.brand }).catch(() => {}); hints(); padChanged(); top()?.padChanged?.(); },
  scroll: dy => { const e = top()?.el.querySelector('.list,.detail,.scroll,.found'); if (e) e.scrollTop += dy; },
});
let full = false;
const setFullscreen = on => { full = on; invoke('set_fullscreen', { on }).catch(() => {}); for (const l of layers) l.fullChanged?.(); };
const leaving = () => layers.some(l => l.pending?.()) ? t('Changes you did not save are lost.') : t('Your library and your settings are kept.');
/* Quit and Restart are asked first, "Cancel" chosen. */
const askQuit = () => dialog(t('Quit Oort NX?'), leaving(), [[t('Cancel'), () => {}], [t('Quit'), () => invoke('quit')]]);
const askRestart = () => dialog(t('Restart Oort NX?'), leaving(), [[t('Cancel'), () => {}], [t('Restart app'), () => invoke('restart').catch(e => deny(null, because(e)))]]);
const openLogs = () => invoke('open_logs').catch(e => deny(document.activeElement, because(e)));

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
  return h('div', { cls: 'top' }, padLabel(), h('div', { cls: 'mid' }, h('span', { cls: 'badge', 'data-badge': 'lb', 'aria-hidden': 'true' }), bar, h('span', { cls: 'badge', 'data-badge': 'rb', 'aria-hidden': 'true' })), V.clock && h('time', { cls: 'clock num' }, clockText()));
};
const pill = bar => { const on = $('[aria-selected=true]', bar), p = $('.pill', bar); if (on && p) { p.style.width = on.offsetWidth + 'px'; p.style.transform = `translateX(${on.offsetLeft}px)`; } };
const clockText = () => new Intl.DateTimeFormat(language, { hour: '2-digit', minute: '2-digit' }).format(new Date());
setInterval(() => document.querySelectorAll('.clock').forEach(c => { c.textContent = clockText(); }), 5000);
addEventListener('resize', () => document.querySelectorAll('.tabs').forEach(pill));
document.fonts.ready.then(() => document.querySelectorAll('.tabs').forEach(pill));

const setTab = async x => { tab = x; await reload(); homeLayer.redraw(); };
const shiftTab = d => { const i = Math.max(0, Math.min(TABS.length - 1, TABS.indexOf(tab) + d)); if (TABS[i] !== tab) { S.play('confirm'); const bar = $('.tabs', homeLayer.el); tab = TABS[i]; [...bar.querySelectorAll('[role=tab]')].forEach((b, k) => b.setAttribute('aria-selected', k === i)); pill(bar); setTimeout(() => setTab(tab), root.hasAttribute('data-still') ? 0 : 160); } else S.play('deny'); };

/* Steam's row in Add game, as the core decides it when the sheet opens (integrations, at add). */
let addable = [], gameSources = [];
const added = async r => {
  // Refused (changed since the sheet opened): the sheet shows the core's row as it is now.
  if (!r) { addable = (await ask('integrations', { at: 'add' }).catch(() => ({ entries: [] }))).entries; return top().refresh?.(); }
  await reload(true); selected = L.games.find(g => g.kind === 'steam')?.id ?? selected; S.play('success'); while (layers.length > 1) pop(); homeLayer.redraw(); };
const addRows = () => [
  ...addable.map(e => entryRow(e, added, { at: 'add' })),
  ...gameSources.map(e => entryRow(e, null, { after: () => { while (layers.length > 1) pop(); selected = L.games[0]?.id ?? null; homeLayer.redraw(); } })),
].filter(Boolean);

const cards = [{ id: 'add', ic: 'add', name: () => t('Add game'), run: () => openAdd() }];
const addCard = () => row(t('Add game'), icon('chevron'), () => openAdd(), { id: 'add', ic: 'add' });

/* The shelf: one row of tiles, one ring, one camera (SpotlightRowGeometry). */
const HOST = 174, PITCH = 178, START = 72, GROW = 1.3, ANCHOR = 2;
const shelf = () => {
  const items = [...cards, ...L.games], nodes = new Map(), el = h('div', { cls: 'shelf', role: 'listbox', 'aria-label': t('Library') }), ring = h('span', { cls: 'ring' }), name = h('span', { cls: 'name' });
  let at = Math.max(0, items.findIndex(x => x.id === selected)); if (selected == null || !items[at] || items[at].id !== selected) at = Math.min(cards.length, items.length - 1);
  el.append(ring, name);
  const u = n => `calc(${n.toFixed(1)}*var(--u))`;
  const place = i => START + i * PITCH + (i > at ? HOST * (GROW - 1) : 0) + 1 - Math.max(0, at - ANCHOR) * PITCH;
  const tile = i => { const x = items[i], b = h('button', { cls: 'tile', role: 'option', 'data-id': x.id, 'data-i': i, 'aria-label': x.run ? x.name() : x.name, onclick: e => { if (e.detail && x.id !== chosen) return set(+b.dataset.i, true); x.run ? x.run() : primary(x)[1](); } }, x.run ? h('span', { cls: 'face' }, icon(x.ic)) : face(x, 'icon')); return b; };
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
  return { el, refreshed, get item() { return items[at]; }, focus: () => nodes.get(at)?.focus({ preventScroll: true }), has: e => e.closest('.shelf') === el, step: d => { const i = at + d; if (i < 0 || i >= items.length) S.play('deny', nodes.get(at)); else set(i, true); }, end: d => set(d < 0 ? 0 : items.length - 1, true), set: i => set(i, false), index: e => +e.dataset.i, find: id => items.findIndex(x => x.id === id) };
};

const homeLayer = (() => {
  const el = h('section'), layer = { el };
  let row = null, grid = null, box = null, ringGrid = null;
  const current = () => home === 'spotlight' ? row?.item : game(selected);
  const spotlight = () => { row = shelf(); grid = null; box = h('div', { cls: 'info' }); return [topBar(), row.el, box]; };
  const collection = () => {
    row = null; ringGrid = h('span', { cls: 'ring' }); if (!game(selected)) selected = L.games[0]?.id ?? null;
    box = h('div', { cls: 'gridinfo' });
    grid = h('div', { cls: 'grid', role: 'listbox', 'aria-label': t('Collection') }, ringGrid, L.games.map(g => h('button', { cls: 'tile', role: 'option', 'data-id': g.id, 'aria-label': g.name, onclick: e => { if (e.detail && g.id !== chosen) return e.currentTarget.focus({ preventScroll: true }); primary(g)[1](); } }, face(g, 'cover'))));
    return [topBar(), h('div', { cls: 'gridpage' }, box, h('div', { cls: 'scroll' }, grid))];
  };
  const empty = () => [topBar(), h('div', { cls: 'empty' }, L.total ? [h('h1', {}, t('No games in %@', t(tab)))] : [h('h1', {}, t('Add your first game')), h('p', { cls: 'say' }, t('Oort NX shows the games you already have. Nothing is moved or changed.')), h('div', { cls: 'rows' }, addCard())])];
  const draw = () => !L.games.length && (home === 'collection' || !L.total) ? (row = grid = null, empty()) : home === 'spotlight' ? spotlight() : collection();
  layer.refreshed = id => { row?.refreshed(); const x = current(); if (layer === top() && x && !x.run && (!id || x.id === id)) { const keep = document.activeElement?.dataset?.id, inside = box?.contains(document.activeElement); layer.info(true); if (inside) box.querySelector(`[data-id="${keep}"]`)?.focus({ preventScroll: true }); settle(); } };
  layer.info = quiet => {
    if (!box) return;
    box.classList.toggle('quiet', !!quiet);
    const x = current();
    clearTimeout(layer.look); if (L.online && x?.look) layer.look = setTimeout(() => invoke('online_look', { ids: [x.id], front: true }).catch(() => {}), 700);
    if (!x) return box.replaceChildren();
    if (x.run) return fill(box, h('h1', { cls: 'hero' }, x.name()), h('p', { cls: 'say' }, t('Games from Steam, any program, or a folder of recompiled games.')));
    if (home === 'collection') return fill(box, h('h1', { cls: 'hero' }, x.name), stats(x));
    const [label, run] = primary(x);
    fill(box, heading(x), h('div', { cls: 'keys' }, key(label, run, { ic: x.state === 'ready' ? 'play' : null, id: 'primary' }), key(t('Options'), () => openOptions(x.id), { id: 'options' }), key('', async () => {
      await favorite(x);
      if (current()?.id !== x.id) return;
      const active = document.activeElement, keep = box.contains(active) && active.dataset.id;
      layer.info();
      if (keep && layer === top()) $(`[data-id="${keep}"]`, box)?.focus();
    }, { ic: x.favorite ? 'favorite' : 'favoriteBorder', cls: 'round', id: 'heart', aria: x.favorite ? t('Remove from favorites') : t('Add to favorites') })), x.state !== 'ready' && h('p', { cls: 'say' }, stateText(x)), stats(x), genres(x));
  };
  layer.redraw = () => { el.replaceChildren(...draw()); layer.info(); if (layer === top()) { layer.focus(); settle(); } };
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
    x: () => { const x = current(); if (x && !x.run) openDetail(x.id); }, y: () => openSearch(), ls: () => openSearch(), menu: () => { const x = current(); x && !x.run ? openOptions(x.id) : S.play('deny', document.activeElement); }, view: () => V.viewSwitches && other(), rs: () => openSort(),
    lb: () => shiftTab(-1), rb: () => shiftTab(1), lt: () => row ? row.end(-1) : edge(-1), rt: () => row ? row.end(1) : edge(1),
  };
  const edge = d => { const list = grid ? focusable(grid) : []; const e = list[d < 0 ? 0 : list.length - 1]; if (e) go(e); };
  // Where this layer's shelf takes a wheel or a finger.
  layer.slide = d => { if (!row) return false; if (d) row.step(d); return true; };
  layer.pitch = () => Math.max(40, $('.shelf .ring', el)?.offsetWidth || 0);
  layer.play = () => { const x = current(); if (x) x.run ? x.run() : primary(x)[1](); };
  layer.context = e => { const id = e.closest('.tile')?.dataset.id ?? (e.closest('.key') || e === document.body ? current()?.id : null), g = id && game(id); if (!g) return; if (row) { const i = row.find(id); if (i >= 0) row.set(i); } else if (grid) grid.querySelector(`[data-id="${CSS.escape(id)}"]`)?.focus({ preventScroll: true }); openOptions(id); };
  layer.hints = () => {
    const x = current(), g = x && !x.run ? x : null, onTile = !document.activeElement?.classList.contains('key');
    return [[V.viewSwitches && L.total && ['view', home === 'spotlight' ? t('Collection') : t('Spotlight'), other, inPad() && t('Hold: %@', t('Search'))], L.total && ['y', t('Search'), openSearch], menuHint()],
      [g && onTile && ['x', t('Details'), () => openDetail(g.id)], g && ['menu', t('Options'), () => openOptions(g.id)], x && ['a', g ? onTile ? primary(g)[0] : t('Select') : t('Open')], L.total && ['rs', t('Sort'), openSort, t({ recent: 'Sort: Recent', name: 'Sort: Name', added: 'Sort: Recently added', playtime: 'Sort: Playtime' }[V.sort])]]];
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
      [h('h2', {}, t('Details')), h('dl', { cls: 'facts' }, [[t('Publisher'), d.publisher], [t('Developer'), d.developer], [t('Release date'), d.year], [t('Version'), d.version], [t('Installed in'), d.folder], [t('Saves and mods'), t('In the game')]].filter(x => x[1]).map(([a, b]) => h('div', {}, h('dt', {}, a), h('dd', {}, b)))), h('div', { cls: 'rows' }, d.page && row(t('Open the page this comes from'), icon('link'), () => link(d.page), { id: 'page', sub: d.page.replace(/^https:\/\//, '').split('/')[0] }), row(t('Pictures and information'), icon('chevron'), () => openOptions(id, 'look'), { id: 'look', ic: 'image', sub: wording(d.information.pictures) }))],
      d.inputs?.length && [h('h2', { 'data-part': 'inputs' }, t('Files')), h('div', { cls: 'rows' }, d.inputs.map(i => row(i.label || i.id, [i.path ? h('span', {}, i.path.split(/[\\/]/).pop()) : i.optional ? t('Optional') : t('Missing'), dot(i.path ? 'ok' : i.optional ? 'mark' : '')], () => pickFile({ title: i.label || t('Files'), extensions: i.extensions, folders: i.folder, files: i.file, done: path => change(ask('game.input', { id, input: i.id, path })) }), { id: 'input-' + i.id, ic: i.role === 'key' ? 'key' : 'folder', sub: i.path && i.unchecked ? t('Oort NX does not check this copy; the project does.') : i.shared ? t('Kept where it is. Only its path is remembered.') : null })))],
      d.prepare && [h('h2', { 'data-part': 'prepare' }, t('Get ready')), h('div', { cls: 'rows' }, d.prepare.options.map(o => row(o.label, h('span', { cls: 'sw' }), () => change(ask('game.option', { id, option: o.id, on: !o.on })), { id: 'option-' + o.id, role: 'switch', checked: o.on, sub: [o.note, o.license && t('Turning this on accepts: %@', o.license.name), o.required && t('Required')].filter(Boolean).join(' ') })), d.prepare.options.filter(o => o.license?.url).map(o => row(t('Read: %@', o.license.name), icon('link'), () => link(o.license.url), { id: 'license-' + o.id })), row(d.prepare.needed ? t('Get ready') : t('Get ready again'), d.prepare.needed ? t('Needed') : t('Done'), () => prepare(id), { id: 'prepare', ic: 'build', sub: d.prepare.label, off: busy || d.state === 'inputs' ? stateText(d) || true : null }))],
      d.repo && [h('h2', {}, t('Project')), h('div', { cls: 'rows' }, row(d.repo, icon('link'), () => link('https://github.com/' + d.repo), { id: 'repo' }))]);
    return [h('div', { cls: 'detail' }, body)];
  };
  layer.el.append(...draw());
  layer.redraw = () => refresh(); layer.refresh = refresh; layer.id = id;
  layer.hints = () => [[['b', t('Back'), () => act('b')], ['y', t('Search'), openSearch], menuHint()], [['menu', t('Options'), () => openOptions(id)], aHint()]];
  layer.actions = { menu: () => openOptions(id), y: () => openSearch(), ls: () => openSearch() };
  layer.context = () => openOptions(id); layer.play = () => $('[data-id=primary]', layer.el)?.click();
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
      ...kinds.map(([kind, label]) => row(label, [d.pictures?.includes(kind) ? t('Yours') : d[kind] || kind === 'icon' && d.mark ? t('Automatic') : t('No picture'), icon('chevron')], () => d.pictures?.includes(kind) ? dialog(label, t('Your own picture is copied into Oort NX’s folder. The file you chose is not changed.'), [[t('Cancel'), () => {}], [t('Put it away'), () => ask('game.picture', { id, kind }).then(changed)], [t('Choose another'), () => choosePicture(kind)]]) : choosePicture(kind), { id: 'pic-' + kind, ic: 'image', help: t('A PNG, JPEG or WebP of yours. It stays on this computer.') })),
      d.program && row(t('Name'), d.name, () => type(t('Name'), d.name, async name => { await ask('programs.rename', { key: d.program.key, name }); await reload(); await refresh(); }), { id: 'rename', ic: 'edit' }),
      entryRow(d.information.online, null, { chevron: false, game: () => [id, d.name, changed],
        after: async () => { await refresh(); if (d.information.online.open === 'match') openMatch(id, d.name, changed); } }),
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
/* The question asked before information online is on, as the core says it (hello): what it does and sends, No and Yes.
   The first steps ask it too. */
let onlineQuestion = null;
const askOnline = after => dialog(wording(onlineQuestion.title), wording(onlineQuestion.text), [[wording(onlineQuestion.no), () => {}], [wording(onlineQuestion.yes), async () => { await ask('online.set', { on: true }); S.play('success'); await reload(); await after?.(); }]]);
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

/* ---------- Rows about integrations: each as the core decides it (integrations), sent back as it was shown ---------- */
/* The pages a row may open, each once. One the core names and this app does not have is refused. */
const PAGES = { programs: () => openProgram(), folder: o => pickFolder(o.after), match: (o, el) => o.game ? openMatch(...o.game()) : deny(el, ''), onlineQuestion: o => askOnline(o.after), integrations: () => openSettings('integrations'), steamLibrary: o => o.steamLibrary?.() };
/* The core's words, [key, count?, args…]; "%@" alone is shown as it is (a path, a number). */
const wording = w => w && (w[0] === '%@' ? String(w[1]) : t(...w));
/* o.at: the place (Settings by default); o.chevron: false where a page opens without one; o.press: A, when the place keeps
   the choice itself (the first steps); o.game: the match page's arguments; o.after: what the caller does on return. */
const entryRow = (e, done, o = {}) => {
  const say = o.words || wording;
  return row(say(e.title), [say(e.value), e.checked != null && h('span', { cls: 'sw' }), e.open && o.chevron !== false && icon('chevron')].filter(Boolean),
    el => (o.press || askEntry)(e, el, done, o.at, o), { id: e.id, ic: e.icon, role: e.checked != null ? 'switch' : null, checked: e.checked, sub: say(e.sub), help: e.help?.map(say).join('. ') });
};
const askEntry = (e, el, done, at, o = {}) => {
  if (e.open) return PAGES[e.open] ? PAGES[e.open](o, el) : deny(el, '');
  if (!e.token) return;
  // The core does it if the row is still the one shown and was not done since; else the row is drawn again.
  const run = async () => { if (e.checked != null) S.play('confirm', document.activeElement); try { done(await ask('integrations.act', { at, id: e.id, token: e.token })); } catch (x) { deny(el, ['stale', 'entry-missing'].includes(x) ? '' : because(x)); done(null); } };
  const say = o.words || wording;
  return e.confirm ? confirm(say(e.confirm.title), say(e.confirm.text), say(e.confirm.label), run, o.cancel) : run();
};

/* ---------- Rows that hold a value ---------- */
const chooser = (label, options, value, set, o = {}) => {
  const i = options.findIndex(x => x[0] === value), at = i < 0 ? 0 : i;
  const step = d => { const n = i < 0 ? 0 : (at + d + options.length) % options.length; S.play('confirm', document.activeElement); set(options[n][0]); };
  const e = row(label, [o.mark && dot('mark'), glyph(''), h('span', { cls: 'chip' }, i < 0 ? o.text || '—' : options[i][1]), glyph('')], () => step(1), { ...o, aria: `${label}: ${i < 0 ? o.text || '' : options[i][1]}` });
  e.step = step; return e;
};
const stepper = (label, value, { min, max, step }, set, o = {}) => {
  const move = d => { const n = Math.min(max, Math.max(min, Math.round((value + d * step) * 1e6) / 1e6)); if (n !== value) set(n); else S.play('deny', document.activeElement); };
  const e = row(label, [o.mark && dot('mark'), h('span', { cls: 'track', style: `--at:${(value - min) / (max - min || 1)}` }), h('span', { cls: 'chip num' }, o.text ?? String(value))], null, { ...o, slides: true, aria: `${label}: ${o.text ?? value}` });
  e.addEventListener('click', ev => { const r = $('.track', e).getBoundingClientRect(); if (ev.detail && ev.clientX >= r.left - 12 && ev.clientX <= r.right + 12) set(Math.min(max, Math.max(min, Math.round((min + (ev.clientX - r.left) / r.width * (max - min)) / step) * step))); });
  e.step = move; e.slides = true; return e;
};

/* ---------- The two-level page: a list at the side, its rows, one line of help ---------- */
const shellOf = (name, items, title, body, foot, lang) => {
  let group;
  return [h('div', { cls: 'shell' }, h('nav', { cls: 'side panel', 'aria-label': name }, name && h('p', {}, name), items.flatMap(x => { const head = x.group !== group && x.group ? h('h3', {}, x.group) : null; group = x.group; return [head, h('button', { 'data-id': x.id, 'aria-current': x.on ? 'page' : null, onclick: e => { if (x.on) { const r = layerRow(); return r && go(r); } e.currentTarget.focus({ preventScroll: true }); x.pick(); } }, x.ic && icon(x.ic), x.title)]; })), h('div', { cls: 'col', lang }, h('h1', {}, title), h('div', { cls: 'list' }, body), h('p', { cls: 'help', 'aria-live': 'polite' }), foot))];
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
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['lb', t('Previous'), () => layer.turn(-1)], ['rb', t('Next'), () => layer.turn(1)], aHint()]];
};

/* ---------- Profiles ---------- */
const selectProfile = (p, done) => { const take = async pin => { const list = await ask('profiles.select', { profile: p.id, pin }); await reload(); await done(list); }; if (p.locked) type(t('Use four digits.'), '', take, true); else take().catch(e => deny(document.activeElement, because(e))); };
const openProfiles = async () => {
  let people = await ask('profiles');
  const layer = { el: h('section', { cls: 'veil dialog', role: 'dialog', 'aria-label': t('Switch profile') }), over: true };
  const draw = () => h('div', {}, h('h1', {}, t('Switch profile')), h('div', { cls: 'rows' }, people.list.map(p => row(p.name, [p.locked && icon('lock'), p.id === people.active && icon('done')], () => p.id === people.active ? act('b') : selectProfile(p, async list => { people = list; apply(await ask('view')); while (layers.length > 1) pop(); homeLayer.redraw(); }), { id: p.id, ic: 'person', pick: true }))));
  layer.el.append(draw()); layer.keep = people.active; layer.focus = l => restore({ ...l, focus: first, keep: people.active });
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [aHint()]];
  S.play('open'); push(layer);
};

/* ---------- The menu: one row of icons along the bottom, its cards above them (the Mac app's MenuOverlayView) ---------- */
const openMenu = async () => {
  if (top().menu) return pop();
  // working: information is still looked for online, as the core says it.
  const under = top(), people = await ask('profiles').catch(() => ({ list: [] })), me = people.list.find(p => p.id === people.active);
  const working = (await ask('integrations', { at: 'activity' }).catch(() => ({}))).working;
  if (top() !== under || !isPage(under)) return;
  const items = menuOf({ people: people.list.length, abilities });
  const run = {
    controllers: () => openSettings('controllers'), switch: () => openProfiles(), edit: () => openSettings('account'), theme: () => openSettings('appearance'), add: () => openAdd(), sources: () => openSettings('home'),
    refresh: async () => { await reload(true); refaces(); homeLayer.redraw(); S.play('success'); card(h('strong', {}, t('Library refreshed')), t('%lld games in your library', L.total)); },
    fullscreen: () => setFullscreen(!full), hide: () => invoke('hide').catch(() => {}), restart: askRestart, quit: askQuit, activity: () => openActivity(), settings: () => openSettings(),
  };
  const layer = { el: h('section', { cls: 'veil menu', role: 'dialog', 'aria-label': t('Control center') }), over: true, menu: true };
  let open = null;
  const choose = id => { S.play('confirm'); layer.close(); run[id](); };
  const orb = (x, i) => h('button', { cls: 'orb', 'data-id': x.id, 'aria-label': t(x.title), 'aria-haspopup': x.entries ? 'menu' : null, 'aria-expanded': x.entries ? false : null, onclick: () => x.entries ? (open === i ? shut() : show(i)) : choose(x.id) },
    h('span', { cls: 'name' }, x.id === 'profile' && me ? [me.name, h('small', {}, t('Profile'))] : t(x.title)), h('span', { cls: 'circle' }, icon(x.icon), x.id === 'activity' && (preparing || working) && h('i', { cls: 'dot ok' })));
  const bar = h('div', { cls: 'orbs' }, items.map(orb)), pills = h('div', { cls: 'pills', role: 'menu' });
  const orbs = () => [...bar.children];
  const label = x => x.id === 'fullscreen' && full ? t('Leave full screen') : t(x.title);
  const show = i => {
    open = i; S.play('open');
    fill(pills, items[i].entries.map(x => key(label(x), () => choose(x.id), { ic: x.icon, id: x.id })));
    pills.style.setProperty('--from', i - (items.length - 1) / 2);
    orbs().forEach((o, n) => { o.classList.toggle('open', n === i); if (items[n].entries) o.setAttribute('aria-expanded', n === i); });
    bar.classList.add('holding'); layer.el.classList.add('deep'); pills.firstElementChild.focus({ preventScroll: true }); hints();
  };
  const shut = quiet => { const i = open; if (i == null) return; open = null; fill(pills); bar.classList.remove('holding'); layer.el.classList.remove('deep'); orbs().forEach((o, n) => { o.classList.remove('open'); if (items[n].entries) o.setAttribute('aria-expanded', false); }); if (!quiet) { S.play('back'); orbs()[i].focus({ preventScroll: true }); } };
  const step = d => { const list = orbs(), i = open ?? list.indexOf(document.activeElement); shut(true); const n = list[i + d]; if (n) go(n); else { list[i]?.focus(); S.play('deny', list[i]); } };
  layer.close = () => { if (top() === layer) pop(); };
  layer.focus = () => orbs()[Math.max(0, items.findIndex(x => x.id === 'power'))].focus({ preventScroll: true });
  layer.move = (dir, a) => {
    if (open != null) { const list = [...pills.children], n = list[list.indexOf(a) + (dir === 'up' ? -1 : dir === 'down' ? 1 : NaN)]; if (n) go(n); else if (dir === 'down') shut(); else S.play('deny', a); return true; }
    if (dir === 'left' || dir === 'right') step(dir === 'left' ? -1 : 1);
    else if (dir === 'up' && items[orbs().indexOf(a)]?.entries) show(orbs().indexOf(a)); else S.play('deny', a);
    return true;
  };
  layer.actions = { b: () => { if (open != null) return shut(); S.play('back'); layer.close(); }, home: () => { S.play('back'); layer.close(); }, lb: () => step(-1), rb: () => step(1) };
  layer.hints = () => [[['b', open != null ? t('Back') : t('Close'), () => act('b')]], [['lb', t('Previous'), () => step(-1)], ['rb', t('Next'), () => step(1)], ['a', t('Select')]]];
  layer.el.addEventListener('click', e => { if (e.target === layer.el) act('b'); });
  layer.el.append(pills, bar);
  S.play('open'); push(layer);
};
/* What Oort does now, and the last games played. */
const openActivity = async () => {
  let now = [], last = [];
  const read = async () => {
    // The core's rows: information still looked for online, what Steam still downloads.
    const [integrations, folders, recent] = [(await ask('integrations', { at: 'activity' }).catch(() => ({ entries: [] }))).entries, await ask('folders'), await ask('library', { tab: 'Recently played', sort: 'recent' })];
    now = [
      preparing && row(game(preparing.id)?.name || t('Getting ready…'), `${Math.round(preparing.value * 100)} %`, () => openDetail(preparing?.id ?? now.id), { id: 'preparing', ic: 'build', sub: preparing.text || t('Getting ready…') }),
      ...integrations.map(e => entryRow(e, null, { chevron: false })),
      ...folders.folders.filter(f => !f.found).map(f => row(f.path, [t('Not found'), dot('bad')], () => openSettings('home'), { id: 'f' + f.key, ic: 'folder' })),
    ].filter(Boolean);
    last = recent.games.slice(0, 5);
  };
  await read();
  const layer = sheet(t('Activity center'), () => [h('div', {}, h('h2', {}, t('In progress')), now.length ? h('div', { cls: 'rows' }, now) : h('p', { cls: 'say' }, t('No activity'))), last.length > 0 && h('div', {}, h('h2', {}, t('Recently played')), h('div', { cls: 'rows' }, last.map(g => row(g.name, duration(g.seconds), () => openDetail(g.id), { id: g.id, ic: 'play', sub: day(g.last) }))))], { activity: true });
  const draw = layer.refresh; layer.refresh = async () => { await read(); if (layers.includes(layer)) draw(); }; layer.back = layer.redraw = layer.refresh;
};

/* ---------- Controls: the pad in hand, and what each button, key and gesture does ---------- */
const controls = kind => {
  const names = padNames(kindNames(kind), kind === 'playstation' ? pad?.name : ''), hold = x => t('Hold: %@', x);
  return [['up', '✚', t('Move')], ['a', 'a', t('Select')], ['b', 'b', t('Back')], ['x', 'x', t('Details')], ['y', 'y', t('Search')], ['l', 'lb', t('Previous')], ['r', 'rb', t('Next')], ['zl', 'lt', t('First')], ['zr', 'rt', t('Last')], ['l3', 'ls', t('Search')], ['r3', 'rs', t('Sort')], ['view', 'view', t('Change view'), hold(t('Search'))], ['menu', 'menu', t('Options'), hold(t('Control center'))], ['home', 'home', t('Control center'), hold(t('Settings'))]]
    .map(([button, name, title, held]) => ({ button, name: names[name] ?? name, title, hold: held }));
};
const controlsMap = kind => padMap({ kind, entries: controls(kind), live, label: t('What each button does'), quiet: root.hasAttribute('data-still') });
const openControls = () => {
  let kind = padKind(pad?.name);
  const facts = list => h('dl', { cls: 'facts' }, list.map(([a, b]) => h('div', {}, h('dt', {}, b), h('dd', {}, a))));
  sheet(t('Controls'), layer => [
    h('div', { cls: 'rows' }, chooser(t('Controller'), KINDS.map(k => [k, KIND_NAMES[k]]), kind, k => { kind = k; layer.refresh(); }, { id: 'kind', ic: 'gamepad' })),
    controlsMap(kind),
    h('div', { cls: 'boxes' }, h('div', { tabindex: '0', cls: 'box panel', 'data-id': 'keys' }, h('h2', {}, t('Keyboard')), facts([[t('Move'), t('Arrow keys')], [t('Select'), '⏎'], [t('Back'), 'Esc'], [t('Details'), 'X, Ctrl D'], [t('Options'), 'Ctrl O, M'], [t('Search'), 'Y, Ctrl F'], [t('Control center'), 'Ctrl K, H'], [t('Settings'), 'Ctrl ,'], [t('Add game'), 'Ctrl N'], [t('Play'), 'Ctrl ⏎'], [t('Change view'), 'V'], [t('Sort'), 'F3'], [t('Interface size'), 'Ctrl +, Ctrl −, Ctrl 0'], abilities.includes('fullscreen') && [t('Fullscreen'), 'F11']].filter(Boolean))),
    h('div', { tabindex: '0', cls: 'box panel', 'data-id': 'mouse' }, h('h2', {}, t('Mouse and touch')), facts([[t('Choose a game'), t('Click, or touch it')], [t('Play'), t('Double-click, or touch it again')], [t('Options'), t('Right click, or keep a finger on it')], [t('Next or previous game'), t('Wheel, or swipe')]]))),
  ]);
};

/* ---------- Settings ---------- */
const section = id => t(['Settings navigation', id].join(': '));
const openSettings = async (start = 'general') => {
  if (typeof start !== 'string') start = 'general';
  const open = layers.find(l => l.settings); if (open) return open === top() ? open.go(start) : S.play('deny');
  const icons = { general: 'settings', appearance: 'palette', sound: 'volume', controllers: 'gamepad', account: 'person', home: 'collections', library: 'image', integrations: 'puzzle', about: 'info' };
  let integrations = await ask('integrations'), online = await ask('online'), page = await ask('settings'), folders = await ask('folders'), people = await ask('profiles'), cat = start, sub = null, integrationID = null;
  const layer = { el: h('section'), page: true, settings: true, pending: () => page.pending };
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
  // Only this catalogue ships all seven languages; the rest of desktop keeps its English/French locale.
  const ct = (key, ...args) => translate(V.language, key, ...args);
  const cw = w => w && (w[0] === '%@' ? String(w[1]) : ct(...w));
  const extra = {
    home: () => [h('div', {}, h('h2', {}, t('Game folders')), h('div', { cls: 'rows' }, folders.folders.map(f => row(f.path, [f.found ? t('%lld games', f.games) : t('Not found'), dot(f.found ? 'ok' : 'bad')], () => confirm(t('Remove this folder?'), t('%@ leaves the library. Nothing is deleted from the disk.', f.path), t('Remove'), async () => { folders = await ask('folders.remove', { path: f.key }); await reload(); again(layer, draw); }), { id: 'f' + f.key, ic: 'folder', help: t('Select to remove it from the library.') })), row(t('Add a folder'), icon('add'), () => pickFolder(async () => { folders = await ask('folders'); again(layer, draw); }), { id: 'addfolder' }), row(t('Look again'), t('%lld games', L.total), async () => { await reload(true); folders = await ask('folders'); again(layer, draw); }, { id: 'rescan', ic: 'sync', help: t('Reads the game folders again.') })))],
    account: () => [h('div', { cls: 'rows' }, people.list.map(p => row(p.name, [p.locked && icon('lock'), p.id === people.active && icon('done')], () => p.id === people.active ? type(t('Name'), p.name, async name => { people = await ask('profiles.rename', { profile: p.id, name }); again(layer, draw); }) : choose(p), { id: 'p' + p.id, ic: 'person', help: p.id === people.active ? t('Select to rename it.') : t('Select to play as this profile.') })), row(t('New profile'), icon('add'), () => type(t('Name'), '', async name => { people = await ask('profiles.add', { name }); again(layer, draw); }), { id: 'newp' }))],
    general: () => [h('div', { cls: 'rows' }, abilities.includes('fullscreen') && row(t('Fullscreen'), h('span', { cls: 'sw' }), () => { S.play('confirm', document.activeElement); setFullscreen(!full); }, { id: 'full', ic: 'monitor', role: 'switch', checked: full, help: t('Right now. F11 does the same.') }), row(t('Guided setup'), icon('chevron'), () => openGuide(), { id: 'guide', ic: 'checklist', help: t('Reopen the guided setup without resetting your library.') }), abilities.includes('quit') && row(t('Quit Oort NX'), '', askQuit, { id: 'quit', ic: 'power' }))],
    controllers: () => [h('div', {}, controlsMap(padKind(pad?.name)), h('div', { cls: 'rows' }, row(t('Controls'), icon('chevron'), () => openControls(), { id: 'controls', ic: 'gamepad', help: t('What each button, key and gesture does.') })))],
    // One action per row, A: the detail. A switch on the row is X, or a click on it: what the detail's Link step asks.
    integrations: () => integrations.sections.map(group => h('section', { 'data-section': group.id, lang: V.language },
      h('h2', {}, cw(group.title)),
      group.entries.length ? h('div', { cls: 'rows' }, group.entries.map(e => withSwitchKey(e, row(cw(e.title),
        [h('span', { cls: 'integration-status' }, cw(e.status)),
          e.switch && h('span', { cls: 'sw' + (e.switch.checked ? ' on' : ''), 'aria-hidden': 'true', onclick: ev => { ev.stopPropagation(); flip(e); } }),
          icon('chevron')].filter(Boolean),
        () => openIntegration(e.id), { id: e.id, ic: e.icon, sub: cw(e.note || e.capabilities), cls: 'integration-summary' })))) : null,
      group.upcoming && h('p', { cls: 'say', 'data-upcoming': '' }, cw(group.upcoming)))),
    about: () => [h('div', {}, h('div', { cls: 'rows' }, row(t('Version'), [version, icon('link')], () => link('https://github.com/sofianbll/oort-nx/releases'), { id: 'version', help: t('Opens the page of versions in your browser. Oort NX does not look by itself.') }), row(t('Logs'), icon('folder'), openLogs, { id: 'logs', help: t('What games said the last time they ran.') }), row(t('Open project docs'), icon('link'), () => link('https://github.com/sofianbll/oort-nx'), { id: 'docs' }))), h('div', {}, h('h2', {}, t('Credits')), h('div', { cls: 'rows' }, [['RecompLauncher SDK', t('The recomplauncher.json format, by Ripalda (MIT)'), 'https://github.com/elripalda/RecompLauncher-SDK'], ['Padwake', t('Following a game’s processes on Windows, by ddoinn (MIT)'), 'https://github.com/ddoinn/padwake'], ['Arcane, Selene', t('The app and the interface Oort NX comes from, by Bium23 and Matthew Silva (MIT)'), 'https://github.com/sofianbll/oort-nx']].map(([a, b, url]) => row(a, icon('link'), () => link(url), { id: a, sub: b })))), h('p', { cls: 'say' }, online.on ? t('No account, no telemetry. Only the names of your games go out, to find their information online: Integrations turns it off.') : t('Everything stays on this computer: no account, no telemetry, no data sent.'))],
  };
  // What a row asked is done: the core's rows again, then the library (Steam's games come or go) and what About says.
  const acted = async r => {
    const id = integrationID;
    integrations = r || await ask('integrations');
    if (r) { online = await ask('online'); await reload(!!r.rescan); }
    again(layer, draw);
    if (integrationID && integrationID === id && top() === layer && document.activeElement.closest('.side')) {
      const row = layerRow();
      if (row) go(row);
    }
  };
  // The switch is drawn, not focused: a screen reader hears X as the row's shortcut.
  const withSwitchKey = (e, el) => { if (e.switch) el.setAttribute('aria-keyshortcuts', 'X'); return el; };
  const integration = () => integrationID && integrations.sections.flatMap(group => group.entries).find(e => e.id === integrationID);
  // The catalogue row that has the focus, when it has a switch: X turns it on or off without opening the detail.
  const switchRow = () => {
    if (cat !== 'integrations' || integration()) return null;
    const id = document.activeElement?.closest('.integration-summary')?.dataset.id;
    return id ? integrations.sections.flatMap(group => group.entries).find(e => e.id === id && e.switch) : null;
  };
  const flip = e => askEntry(e.switch, $(`[data-id="${CSS.escape(e.id)}"]`, layer.el) || document.activeElement, acted, undefined, { words: cw });
  const steamLibrary = async () => {
    if (page.pending) return deny(document.activeElement, ct('Save or discard your changes before opening the library.'));
    const active = integrationID;
    const games = await ask('library', { tab: TABS[0], sort: V.sort }).catch(e => { if (top() === layer) deny(document.activeElement, because(e)); });
    if (!games || top() !== layer || integrationID !== active) return;
    const first = games.games.find(g => g.kind === 'steam');
    if (!first) return deny(document.activeElement, t('Not found'));
    tab = TABS[0]; L = games; selected = first.id;
    while (layers.length > 1) pop();
    homeLayer.redraw();
  };
  const openIntegration = id => {
    integrationID = id; S.play('open'); again(layer, draw);
    const first = $('[data-primary]', layer.el) || layerRow() || $('[data-id=integration-back]', layer.el);
    if (first) go(first);
  };
  const backIntegration = () => {
    const id = integrationID; integrationID = null; S.play('back'); again(layer, draw);
    const summary = $(`[data-id="${CSS.escape(id)}"]`, layer.el);
    if (summary) go(summary);
  };
  const integrationDetail = e => [
    h('p', { cls: 'say', lang: V.language }, h('strong', {}, cw(e.status))),
    h('p', { cls: 'say', lang: V.language }, cw(e.about)),
    // One box per step (IntegrationCatalog.steps): title, sentences, then its buttons under them, aligned.
    ...e.steps.map(step => h('section', { cls: 'panel integration-step', 'data-phase': step.id, lang: V.language }, h('h2', {}, cw(step.title)),
      h('div', { cls: 'rows' }, step.items.map(item => {
        if (item.say) return h('p', { cls: 'say' }, cw(item.say));
        if (!item.row) return h('p', { cls: 'say' }, ct(item.label[0], cw(item.text)));
        if (!item.primary) return entryRow(item.row, acted, { words: cw, cancel: ct('Cancel') });
        const action = key(cw(item.row.title), event => askEntry(item.row, event.currentTarget, acted, undefined, { steamLibrary }), { id: item.row.id });
        action.setAttribute('data-primary', '');
        return h('div', { cls: 'integration-primary' }, action);
      })))),
  ];
  const choose = p => selectProfile(p, async list => { people = list; await take(ask('settings'), false); again(layer, draw); });
  layer.go = to => { cat = to; sub = null; integrationID = null; layer.keep = 'c-' + to; again(layer, draw); layer.focus(layer); };
  layer.fullChanged = () => cat === 'general' && again(layer, draw);
  const draw = () => {
    const c = page.categories.find(x => x.id === cat), s = sub && c.subjects.find(x => x.id === sub);
    const detail = integration(), title = detail ? cw(detail.title) : cat === 'integrations' ? ct('Integrations') : s ? t(s.title) : section(cat);
    const own = (s || c).rows, body = detail ? integrationDetail(detail) : [own.length && h('div', { cls: 'rows' }, own.map(draft)), !s && c.subjects.length && h('div', { cls: 'rows' }, c.subjects.map(x => row(t(x.title), icon('chevron'), () => { S.play('open'); sub = x.id; layer.keep = null; again(layer, draw); layerRow()?.focus(); }, { id: 'sub-' + x.id }))), ...(!s && extra[cat] ? extra[cat]() : [])];
    const foot = detail ? h('div', { cls: 'keys', lang: V.language }, key(ct('Back'), backIntegration, { id: 'integration-back' })) : page.pending && h('div', { cls: 'draft panel' }, h('p', {}, t('%lld changes to save', page.changes.length)), key(t('Leave without saving'), async () => { S.play('back'); await take(ask('settings.discard'), false); pop(); }, { id: 'discard' }), key(t('Save'), () => { S.play('success'); take(ask('settings.save')); }, { id: 'save' }));
    return shellOf(null, page.categories.map(x => ({ id: 'c-' + x.id, title: section(x.id), ic: icons[x.id], group: x.group && t(x.group), on: x.id === cat, pick: () => { cat = x.id; sub = null; integrationID = null; again(layer, draw); } })), title, body, foot, cat === 'integrations' ? V.language : null);
  };
  shellActions(layer, () => {
    if (!page.pending) { S.play('back'); return pop(); }
    dialog(t('Save your changes?'), page.changes.length === 1 ? t('One setting changed.') : t('%lld settings changed.', page.changes.length), [[t('Keep editing'), () => {}], [t('Leave without saving'), async () => { await take(ask('settings.discard'), false); pop(); }], [t('Save'), async () => { await take(ask('settings.save'), false); S.play('success'); pop(); }]]);
  });
  const b = layer.actions.b;
  layer.actions.b = () => { if (integration()) return backIntegration(); if (sub && !document.activeElement.closest('.side')) { const was = 'sub-' + sub; sub = null; S.play('back'); layer.keep = was; again(layer, draw); $(`[data-id="${was}"]`, layer.el)?.focus(); } else b(); };
  const turn = layer.turn;
  layer.turn = d => { if (!integration()) turn(d); };
  const move = layer.move;
  layer.move = (dir, active) => {
    if (!integration()) return move(dir, active);
    if (dir === 'left' || dir === 'right') {
      const next = dir === 'left' ? $('[data-id=integration-back]', layer.el) : $('[data-primary]', layer.el) || layerRow();
      if (next && next !== active) go(next);
      return true;
    }
    const list = focusable($('.col', layer.el)), next = list[list.indexOf(active) + (dir === 'up' ? -1 : 1)];
    if (next) go(next);
    return true;
  };
  const resetGroup = () => { const c = page.categories.find(x => x.id === cat), rows = (sub && c.subjects.find(x => x.id === sub) || c).rows, sections = [...new Set(rows.filter(r => r.changed).map(r => r.section))]; if (!sections.length) return S.play('deny'); (async () => { for (const section of sections) await take(ask('settings.reset', { section }), false); S.play('confirm'); again(layer, draw); })(); };
  layer.actions.x = () => { const e = switchRow(); return e ? flip(e) : resetGroup(); };
  const baseHints = layer.hints;
  layer.hints = () => { const [l, r] = baseHints(); if (integration()) return [l, [aHint()]]; const e = switchRow(); if (e) return [l, [['x', cw(e.toggle), () => flip(e)], ...r]]; const c = page.categories.find(x => x.id === cat), rows = (sub && c.subjects.find(x => x.id === sub) || c).rows; return [l, [rows.some(r => r.changed) && ['x', t('Reset group'), layer.actions.x], ...r]]; };
  layer.redraw = () => again(layer, draw);
  layer.back = () => { (async () => { [folders, integrations, online] = [await ask('folders'), await ask('integrations'), await ask('online')]; await take(ask('settings')); })(); };
  layer.gone = async () => { await reload(); TABS.includes(tab) || (tab = TABS[0]); homeLayer.redraw(); };
  layer.el.append(...draw());
  S.play('open'); push(layer);
};

/* ---------- Sort ---------- */
const openSort = () => {
  const sorts = [['recent', t('Sort: Recent')], ['name', t('Sort: Name')], ['added', t('Sort: Recently added')], ['playtime', t('Sort: Playtime')]];
  const layer = { el: h('section', { cls: 'veil dialog', role: 'dialog', 'aria-label': t('Sort games') }), over: true };
  const draw = () => h('div', {}, h('h1', {}, t('Sort games')), h('div', { cls: 'rows' }, sorts.map(([id, name]) => row(name, V.sort === id && icon('done'), async () => { S.play('confirm', document.activeElement); await remember({ sort: id }); V.sort = id; await reload(); again(layer, draw); }, { id, pick: true, cls: V.sort === id ? 'chosen' : '' }))));
  layer.el.append(draw()); layer.keep = V.sort; layer.focus = l => restore({ ...l, focus: first, keep: V.sort });
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['a', t('Select')]]]; layer.gone = () => homeLayer.redraw();
  layer.actions = { rs: () => act('b') };
  S.play('open'); push(layer);
};

/* ---------- Search, and the keys to type with a controller ---------- */
/* Letters, capitals (one, or kept), marks; for a code, digits only. It shows when a controller or a finger may need it. */
const LETTERS = [...'abcdefghijklmnopqrstuvwxyz0123456789-'], MARKS = [...'àâäãåæçéèêëîïíñôöóõœùûüúÿß.,\'":!?&()/'];
const wantsKeys = () => !!pad || hand.now === 'touch';
const keyboard = ({ put, erase, done, digits }) => {
  const el = h('div', { cls: 'keyboard' + (digits ? ' digits' : '') });
  let capital = 0, marks = false;
  const turn = keep => { draw(); $(`[data-id=${keep}]`, el)?.focus({ preventScroll: true }); };
  const letter = c => { const s = capital && c !== 'ß' ? c.toLocaleUpperCase(language) : c; return key(s, () => { put(s); if (capital === 1) { capital = 0; turn('k' + c.codePointAt(0)); } }, { id: 'k' + c.codePointAt(0) }); };
  const tail = () => [key('', erase, { ic: 'backspace', aria: t('Erase'), id: 'erase' }), key('', done, { ic: 'done', aria: t('Done'), id: 'ok' })];
  const draw = () => digits ? fill(el, [...'123456789'].map(c => key(c, () => put(c))), tail()[0], key('0', () => put('0')), tail()[1])
    : fill(el, (marks ? MARKS : LETTERS).map(letter), tail(),
      h('div', { cls: 'wide' }, key(t('Shift'), () => { capital = (capital + 1) % 3; turn('shift'); }, { id: 'shift', cls: ['', 'lit', 'lit kept'][capital], pressed: capital > 0 }), key(t('Space'), () => put(' '), { id: 'space', cls: 'space' }), key(marks ? 'abc' : 'é & ?', () => { marks = !marks; turn('marks'); }, { id: 'marks', aria: marks ? t('Letters') : t('Accents and signs') })));
  draw(); return el;
};
const openSearch = () => {
  if (top().search) return;
  const input = h('input', { type: 'text', placeholder: t('Find a game'), 'aria-label': t('Find a game'), autocomplete: 'off', spellcheck: 'false', 'data-id': 'q' }), found = h('div', { cls: 'found', 'aria-live': 'polite' }), keys = h('div');
  const layer = { el: h('section', { cls: 'veil', role: 'search' }, h('div', { cls: 'find' }, h('label', { cls: 'field' }, icon('search'), input), keys, found)), over: true, search: true };
  const open = g => { S.play('confirm'); pop(); tab = TABS[0]; selected = g.id; reload().then(() => { while (layers.length > 1) pop(); homeLayer.redraw(); }); };
  let turn = 0;
  const look = async () => { const me = ++turn, q = input.value.trim(), r = q ? (await ask('library', { search: q, sort: 'name' })).games.slice(0, 12) : []; if (me !== turn) return; hints(); found.replaceChildren(...(r.length ? r.map(g => h('button', { cls: 'tile', 'data-id': g.id, onclick: () => open(g) }, face(g, 'icon'), g.name)) : q ? [h('p', { cls: 'say' }, t('No games match.'))] : [])); };
  input.addEventListener('input', look);
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); found.querySelector('button')?.click(); } });
  const erase = () => { input.value = input.value.slice(0, -1); look(); }, clear = () => { input.value = ''; look(); };
  let drawn = null;
  layer.padChanged = layer.handChanged = () => { if (drawn === wantsKeys()) return; drawn = wantsKeys(); keys.replaceChildren(...(drawn ? [keyboard({ put: c => { input.value += c; look(); }, erase, done: () => { const e = found.querySelector('button'); e ? go(e) : S.play('deny'); } })] : [])); hints(); };
  layer.padChanged(); layer.focus = () => (wantsKeys() && hand.now !== 'keys' && hand.now !== 'mouse' ? focusable(keys)[0] : input).focus();
  layer.hints = () => [[['b', t('Close'), () => act('b')]], [...(inPad() && input.value ? [['x', t('Erase'), erase], ['y', t('Clear all'), clear]] : []), document.activeElement?.closest('.found') ? ['a', t('Open')] : aHint()]];
  layer.actions = { x: erase, y: clear };
  S.play('open'); push(layer);
};
/* One line of text, by keyboard or controller. */
const type = (title, value, done, digits) => {
  const input = h('input', { type: 'text', value, 'aria-label': title, inputmode: digits ? 'numeric' : null, maxlength: digits ? 4 : 40, 'data-id': 'q', autocomplete: 'off', spellcheck: 'false' });
  const ok = async () => { try { await done(input.value.trim()); S.play('success'); pop(); } catch (e) { deny(input, because(e)); $('p', layer.el).textContent = because(e); } };
  const layer = { el: h('section', { cls: 'veil dialog typing', role: 'dialog', 'aria-label': title }), over: true }, keys = h('div');
  const put = c => { if (input.value.length < input.maxLength && (!digits || /\d/.test(c))) input.value += c; hints(); }, erase = () => { input.value = input.value.slice(0, -1); hints(); }, clear = () => { input.value = ''; hints(); };
  layer.el.append(h('div', {}, h('h1', {}, title), h('label', { cls: 'field' }, input), h('p', { 'aria-live': 'polite' }), keys, h('div', { cls: 'keys' }, key(t('Cancel'), () => pop()), key(t('Save'), ok))));
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); ok(); } });
  let drawn = null;
  layer.padChanged = layer.handChanged = () => { if (drawn === wantsKeys()) return; drawn = wantsKeys(); keys.replaceChildren(...(drawn ? [keyboard({ put, erase, done: ok, digits })] : [])); hints(); };
  layer.padChanged();
  layer.focus = () => { (wantsKeys() && hand.now !== 'keys' && hand.now !== 'mouse' ? focusable(keys)[0] : input).focus(); };
  layer.actions = { x: erase, y: clear };
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [...(inPad() && input.value ? [['x', t('Erase'), erase], ['y', t('Clear all'), clear]] : []), aHint()]];
  push(layer);
};

/* ---------- Dialog: precise, at most three keys, the safe one first ---------- */
const dialog = (title, text, keys) => {
  const layer = { el: h('section', { cls: 'veil dialog', role: 'alertdialog', 'aria-label': title }), over: true };
  layer.el.append(h('div', {}, h('h1', {}, title), text && h('p', {}, text), h('div', { cls: 'keys' }, keys.map(([label, run, cls]) => key(label, async () => { pop(); await run(); }, { cls: cls || '' })))));
  layer.hints = () => [[['b', t('Back'), () => act('b')]], [['a', t('Select')]]];
  S.play('notification'); push(layer);
};
const confirm = (title, text, label, run, cancel = t('Cancel')) => dialog(title, text, [[cancel, () => {}], [label, run, 'danger']]);

/* ---------- Choosing folders and files, without leaving the app ---------- */
const pickFile = ({ title, extensions = [], folders = false, files = true, done }) => {
  let at = { path: '', entries: [], parent: null };
  const layer = { el: h('section'), page: true };
  const openPath = async (path, from) => { try { at = await ask('files', { path, extensions, folders: folders && !files }); layer.keep = from || null; again(layer, draw); if (!from) first(layer); } catch (e) { deny(document.activeElement, because(e)); } };
  const use = path => { S.play('confirm'); pop(); done(path); };
  const up = () => at.parent == null ? (S.play('back'), pop()) : (S.play('back'), openPath(at.parent, at.path));
  const draw = () => h('div', { cls: 'sheet' }, h('h1', {}, title), h('p', { cls: 'sub' }, at.shown || at.path || ''), h('div', { cls: 'list' }, h('div', { cls: 'rows' }, folders && at.path && row(t('Choose this folder'), at.games ? t('%lld games', at.games) : '', () => use(at.path), { id: 'this', ic: 'done' }), at.parent != null && row(t('Up one folder'), '', up, { id: 'up', ic: 'folder' }), at.entries.length ? at.entries.map(e => row(e.name, e.folder && icon('chevron'), () => e.folder ? (S.play('open'), openPath(e.path)) : use(e.path), { id: e.path, ic: e.folder ? 'folder' : 'save' })) : h('p', { cls: 'say' }, t('No matching files or folders.')))), h('p', { cls: 'help', 'aria-live': 'polite' }));
  layer.el.append(draw());
  layer.hints = () => [[['b', at.parent != null ? t('Up one folder') : t('Back'), up], ['menu', t('Close'), layer.actions.menu]], [folders && at.path && ['x', t('Choose this folder'), () => use(at.path)], ['a', t('Open')]]];
  layer.actions = { b: up, menu: () => { S.play('back'); pop(); }, x: () => folders && at.path && use(at.path) };
  push(layer); openPath('');
};
const pickFolder = after => pickFile({ title: t('Choose a folder of game files'), folders: true, files: false, done: path => addFolder(path, after) });
const addFolder = async (path, after) => { try { const f = await ask('folders.add', { path }); await reload(); if (after) await after(); else { selected = L.games[0]?.id ?? null; homeLayer.redraw(); } const n = f.folders.at(-1)?.games ?? 0; if (!n) dialog(t('No games were found in this folder.'), t('Games come as folders with a recomplauncher.json inside. The folder stays in the library and is read again at each start.'), [[t('Close'), () => {}]]); } catch (e) { deny(null, because(e)); } };
/* A folder or a program dropped on the window: as if it had been chosen there. One at a time. */
const dropped = async paths => {
  const path = paths?.[0]?.replaceAll('\\', '/');
  if (!path) return;
  if (!isPage()) return deny(null, t('Close this first, then drop it again.'));
  const folder = await ask('files', { path, folders: true }).catch(() => null);
  folder ? addFolder(path, () => { while (layers.length > 1) pop(); selected = L.games[0]?.id ?? null; homeLayer.redraw(); }) : openProgram(path);
};

/* ---------- Adding ---------- */
const sheet = (title, draw, more = {}) => { const layer = { el: h('section'), page: true, ...more }; const body = () => h('div', { cls: 'sheet' }, h('h1', {}, title), h('div', { cls: 'list' }, draw(layer)), h('p', { cls: 'help', 'aria-live': 'polite' })); layer.refresh = () => again(layer, body); layer.redraw = layer.refresh; layer.move = layer.move || ((dir, a) => a.step && (dir === 'left' || dir === 'right') ? (a.step(dir === 'left' ? -1 : 1), true) : false); layer.el.append(body()); layer.hints = layer.hints || (() => [[['b', t('Back'), () => act('b')]], [aHint()]]); S.play('open'); return push(layer); };
const openAdd = async () => { addable = (await ask('integrations', { at: 'add' }).catch(() => ({ entries: [] }))).entries; return sheet(t('Add game'), () => h('div', { cls: 'rows' }, addRows())); };
const openProgram = async first => {
  if (typeof first !== 'string') first = '';
  const p = { program: first, target: '', args: '', name: '', about: first ? await ask('programs.about', { path: first }).catch(() => null) : null }, base = x => x.split(/[\\/]/).pop(), native = x => system === 'windows' ? x.replaceAll('/', '\\') : x;
  const add = async () => { try { const r = await ask('programs.add', { program: p.program, target: p.target || null, args: p.args, name: p.name }); S.play('success'); await reload(); selected = r.added; tab = TABS[0]; while (layers.length > 1) { if (top().guide) break; pop(); } if (top().guide) top().refresh(); else homeLayer.redraw(); } catch (e) { deny(document.activeElement, because(e)); } };
  // A game for this system, in what a folder holds.
  const programs = system === 'windows' ? ['exe', 'bat', 'cmd'] : [];
  sheet(t('Add a program'), layer => h('div', { cls: 'rows' },
    row(t('Program'), p.program ? base(p.program) : t('Choose'), () => pickFile({ title: t('Program'), extensions: programs, done: async x => { p.program = x; p.about = await ask('programs.about', { path: x }).catch(() => null); layer.refresh(); } }), { id: 'program', ic: 'terminal', sub: p.program && [native(p.program), p.about?.publisher, p.about?.version && t('Version %@', p.about.version)].filter(Boolean).join(', ') }),
    row(t('Game file'), p.target ? base(p.target) : t('Optional'), () => pickFile({ title: t('Game file'), done: x => { p.target = x; layer.refresh(); } }), { id: 'target', ic: 'save', sub: p.target && native(p.target), help: t('For an emulator: the game it opens. Passed to the program as its last argument.') }),
    row(t('Arguments'), p.args || t('Optional'), () => type(t('Arguments'), p.args, x => { p.args = x; layer.refresh(); }), { id: 'args', ic: 'tune', help: t('Put quotes around an argument with spaces.') }),
    row(t('Name'), p.name || (!p.target && p.about?.name) || base(p.target || p.program).replace(/\.[^.]+$/, '') || t('Automatic'), () => type(t('Name'), p.name || p.about?.name || '', x => { p.name = x; layer.refresh(); }), { id: 'name', ic: 'edit' }),
    row(t('Add to the library'), icon('add'), add, { id: 'add', off: !p.program && t('Choose the program first.') })));
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
  if (end.crashed || end.error) dialog(t('%@ stopped', end.name || g?.name || ''), end.message || (end.error ? because(end.error) : t('It closed with an error. Its last messages are kept with Oort NX’s logs.')), [[t('Close'), () => {}], [t('Details'), () => openDetail(end.id)], [t('Log'), openLogs]]);
  else if (V.sessionCard) card(h('strong', {}, end.name || ''), t('Session ended'), t('This session: %@', duration(end.seconds)), t('In total: %@', duration(end.total)));
};
let carded = 0;
const card = (...lines) => { const c = $('#card'); clearTimeout(carded); c.replaceChildren(...lines.map(l => typeof l === 'string' ? h('span', {}, l) : l)); c.classList.add('on'); carded = setTimeout(() => c.classList.remove('on'), 8000); };
const prepare = async id => { try { await invoke('prepare', { id }); preparing = { id, value: 0, text: '' }; S.play('play'); top().refresh?.(); } catch (e) { deny(document.activeElement, because(e)); dialog(t('This game could not get ready'), because(e), [[t('Close'), () => {}]]); } };
const prepared = async p => {
  const layer = layers.find(l => l.id === p.id);
  if (p.progress) { preparing = { id: p.id, ...p.progress }; const bar = layer && $('.bar', layer.el); if (bar) { bar.style.setProperty('--at', p.progress.value); $('.wait .say', layer.el).textContent = p.progress.text; } layers.find(l => l.activity)?.refresh(); return; }
  preparing = null; await reload(); layer?.refresh?.(); if (!layer) homeLayer.redraw(); layers.find(l => l.activity)?.refresh();
  if (p.end.done) { S.play('success'); card(h('strong', {}, game(p.id)?.name || ''), t('Ready to play')); } else dialog(t('This game could not get ready'), p.end.message || t('Its setup step stopped with code %@.', p.end.code ?? '—'), [[t('Close'), () => {}]]);
};

/* ---------- The first steps: short, never in the way, and there again in Settings ---------- */
const openGuide = async (at = 'welcome') => {
  // before: Steam's row of the games page as the core says it before it is read, while it is looked for and without an answer.
  const { pages, steam: before } = await ask('guide'), question = onlineQuestion;
  // steam: Steam's row of the games page, as the core decides it; take: what its switch shows, kept until the player goes on.
  let page = at, steam = null, take = null;
  const lookSteam = async () => { steam = null; take = null; steam = (await ask('integrations', { at: 'guide' }).catch(() => null))?.entries[0] ?? before.unanswered; take = steam.checked ?? null; };
  const layer = { el: h('section', { cls: 'veil guide' }), guide: true };
  const set = async (id, value) => { await ask('settings.set', { id, value }); const p = await ask('settings.save'); apply(p.view); layer.refresh(); };
  const turn = async d => {
    const to = pages[pages.indexOf(page) + d];
    if (!to) return end();
    if (page === 'games' && d > 0 && take != null && (await ask('integrations.keep', { on: take })).rescan) await reload(true);
    page = to; S.play(d > 0 ? 'confirm' : 'back'); layer.keep = 'continue';
    await ask('guide', { page }).catch(() => {});
    if (page === 'games') { steam = null; enter(); await lookSteam(); }
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
      entryRow(steam ? { ...steam, checked: take ?? undefined } : before.looking, null, { press: () => { if (take == null) return; take = !take; S.play('confirm', document.activeElement); layer.refresh(); } }),
      ...gameSources.map(e => entryRow(e, null, { after: () => layer.refresh() })),
    ], status: L.total ? t('%lld games in your library', L.total) : null }),
    online: () => ({ title: wording(question.title), say: wording(question.text), rows: [], keys: [key(wording(question.no), () => online(false), { id: 'continue' }), key(wording(question.yes), () => online(true), { id: 'yes' })], status: t('You can change this in Settings, Integrations.') }),
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
  layer.hints = () => [[page !== 'welcome' && ['b', t('Back'), () => turn(-1)]], [aHint()]];
  layer.settings = await ask('settings');
  if (page === 'games') await lookSteam();
  layer.el.append(...shown([draw()]));
  S.play('open'); push(layer);
};

/* ---------- Start ---------- */
export const oort = { act, ask, hand, live, dropped, apply, layers, sounds: S, cloud: C, get view() { return V; }, get library() { return L; }, guide: openGuide, pad: s => padding.feed(s), fullscreen: setFullscreen };
const start = async () => {
  const hello = await ask('hello', { languages: [...navigator.languages] });
  prompts = await ask('prompts'); plugged = await invoke('pads'); abilities = await invoke('abilities').catch(() => ['quit']); version = hello.version; system = hello.system; onlineQuestion = hello.onlineQuestion; gameSources = hello.gameSources; TABS = hello.tabs; full = hello.view.fullscreen; home = hello.lastHome === 'collection' ? 'collection' : 'spotlight';
  apply(hello.view); tab = TABS.includes(hello.view.startingTab) ? hello.view.startingTab : TABS[0];
  if (hello.view.restore && hello.lastGame) selected = hello.lastGame;
  await reload();
  homeLayer.el.classList.add('layer'); layers.push(homeLayer); host.append(homeLayer.el); homeLayer.redraw();
  T.event.listen('tauri://drag-drop', e => dropped(e.payload?.paths)); T.event.listen('session', e => ended(e.payload)); T.event.listen('prepare', e => prepared(e.payload)); T.event.listen('online', e => found(e.payload)); T.event.listen('steam', e => { if (playing?.id === e.payload.id) { playing.phase = e.payload.phase; layers.find(l => l.launch)?.phase(); } }); T.event.listen('pad', e => padding.feed(e.payload)); T.event.listen('pads', e => { plugged = e.payload; padChanged(); top()?.padChanged?.(); });
  // Games unzipped while Oort was behind show on return.
  addEventListener('focus', async () => { if (playing || layers.length > 1) return; const before = JSON.stringify(L.games.map(g => [g.id, g.state])); await reload(true); if (JSON.stringify(L.games.map(g => [g.id, g.state])) !== before) homeLayer.redraw(); });
  S.warm(); S.play('boot');
  if (hello.guide.open) await openGuide(hello.guide.page);
  else if (hello.guide.news) { await ask('guide', { seen: true }); dialog(t('What’s new in Oort NX'), t('The + button (Menu, Options) now opens the options of the chosen game, and Home or + held opens the control center: your library, Settings, full screen, Quit. With a mouse: the wheel, and a right click for the options.'), [[t('Open library'), () => {}], [t('Controls'), () => openControls()]]); }
  root.dataset.ready = '1'; root.dataset.version = version;
  window.oort = oort;
};
start().catch(e => { host.replaceChildren(h('div', { cls: 'empty' }, h('h1', {}, 'Oort NX'), h('p', { cls: 'say' }, String(e)))); root.dataset.ready = 'error'; });
