// node --test desktop/tests/nav.test.mjs : what needs no window.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
const { nearest, repeater, brand, readPad, padName, reader } = await import('../ui/nav.js');
const { handOf, stepper, swiper } = await import('../ui/input.js');
const { menuOf } = await import('../ui/menu.js');
const { KINDS, SHAPES, padKind, kindNames, pressed, liveOf, sides, crosses } = await import('../ui/pads.js');
const { STRINGS, GAME_WORDS } = await import('../ui/gen/strings.js');
const { gameWord } = await import('../ui/words.js');
const box = (left, top, width = 100, height = 40) => ({ getBoundingClientRect: () => ({ left, top, width, height, right: left + width, bottom: top + height }) });

test('the nearest element is the one a hand expects', () => {
  const a = box(0, 0), right = box(120, 0), far = box(300, 0), below = box(0, 60), diagonal = box(140, 60), list = [a, right, far, below, diagonal];
  assert.equal(nearest(a, list, 'right'), right);
  assert.equal(nearest(right, list, 'right'), far);
  assert.equal(nearest(a, list, 'down'), below);
  assert.equal(nearest(right, list, 'down'), diagonal);
  assert.equal(nearest(a, list, 'up'), null);
  assert.equal(nearest(below, list, 'up'), a);
});
test('a held direction fires, waits, then repeats', () => {
  const out = [], turn = repeater(d => out.push(d), 340, 110);
  for (let now = 0; now <= 600; now += 10) turn('down', now);
  assert.equal(out.length, 4);
  turn(null, 610); turn('down', 620); turn('up', 630);
  assert.deepEqual(out.slice(4), ['down', 'up']);
});
test('controllers are told apart', () => {
  assert.equal(brand('Pro Controller (STANDARD GAMEPAD Vendor: 057e Product: 2009)'), 'nintendo');
  assert.equal(brand('DualSense Wireless Controller (Vendor: 054c)'), 'playstation');
  assert.equal(brand('Xbox Wireless Controller'), 'xbox');
  assert.equal(brand('8BitDo'), 'xbox');
});
test('standard and raw controllers read the same', () => {
  const buttons = n => Array.from({ length: n }, () => ({ pressed: false, value: 0 }));
  const std = { id: 'x', mapping: 'standard', buttons: buttons(17), axes: [0, 0, 0, 0] };
  std.buttons[13].pressed = true; std.buttons[7].value = .9;
  let r = readPad(std);
  assert.ok(r.b.down && r.b.r2 && !r.b.up);
  const raw = { id: '057e-2009-Pro Controller', mapping: '', buttons: buttons(14), axes: [0, 0, 0, 0, 0, 0, 0, 0, 0, .1429] };
  r = readPad(raw);
  assert.ok(r.b.down && !r.b.up && !r.b.left);
  raw.axes[9] = 1.28; assert.ok(!readPad(raw).b.down);
});
const idle = { s: false, e: false, w: false, n: false, l1: false, r1: false, l2: false, r2: false, minus: false, plus: false, l: false, r: false, h: false, up: false, down: false, left: false, right: false };
const playing = (name = 'Xbox Controller') => {
  const out = []; let now = 0;
  const read = reader({ act: x => out.push(x), hold: x => out.push('hold ' + x), found: p => out.push(p ? 'found ' + p.brand + (p.pressed ? ' pressed' : '') : 'gone'), scroll: () => {}, live: () => {} });
  return { out, step: (b = {}, ms = 16, ax = [0, 0, 0, 0]) => { now += ms; read(b === null ? null : { name, b: { ...idle, ...b }, ax }, now); return out.splice(0); } };
};
test('+, Home and − act when let go, and hold for something else', () => {
  for (const [key, role] of [['plus', 'menu'], ['h', 'home'], ['minus', 'view']]) {
    const p = playing(); p.step();
    assert.deepEqual(p.step({ [key]: true }), [], key + ' waits to be let go');
    assert.deepEqual(p.step({}), [role]);
    p.step({ [key]: true }); assert.deepEqual(p.step({ [key]: true }, 500), ['hold ' + role]); assert.deepEqual(p.step({}), [], 'a hold is not a press too');
  }
});
test('a button held as the window goes behind does nothing on return', () => {
  const p = playing(); p.step(); p.step({ plus: true }); p.step(null); assert.deepEqual(p.step({}).filter(x => x === 'menu'), []);
});
test('what a controller does at once, by its family', () => {
  const xbox = playing(); xbox.step(); assert.deepEqual(xbox.step({ s: true }), ['a']); assert.deepEqual(xbox.step({ n: true }), ['y']);
  const pro = playing('Pro Controller (Vendor: 057e)'); pro.step(); assert.deepEqual(pro.step({ e: true }), ['a']); assert.deepEqual(pro.step({ w: true }), ['y']);
});
test('a controller found by a press says so; a stick that leans a little does not', () => {
  assert.deepEqual(playing().step({ s: true }), ['found xbox pressed']);
  assert.deepEqual(playing().step({}, 16, [.2, 0, 0, 0]), ['found xbox']);
});
test('the touchpad of a DualSense is its view button as Create is', () => {
  const g = { id: 'DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)', mapping: 'standard', buttons: Array.from({ length: 18 }, () => ({ pressed: false, value: 0 })), axes: [0, 0, 0, 0] };
  assert.ok(!readPad(g).b.minus); g.buttons[17].pressed = true; assert.ok(readPad(g).b.minus);
});
test('the last thing used is the one in hand, and a small knock is not', () => {
  const out = [], hand = handOf(h => out.push(h));
  assert.equal(hand.now, 'keys');
  hand.pad(); hand.pad(); assert.deepEqual(out, ['pad']);
  hand.move({ pointerType: 'mouse', movementX: 2, movementY: 1, timeStamp: 10 }); assert.equal(hand.now, 'pad', 'a small knock on the mouse');
  hand.move({ pointerType: 'mouse', movementX: 2, movementY: 1, timeStamp: 900 }); hand.move({ pointerType: 'mouse', movementX: 3, movementY: 0, timeStamp: 1900 }); assert.equal(hand.now, 'pad', 'small knocks far apart do not add up');
  for (let i = 0; i < 5; i++) hand.move({ pointerType: 'mouse', movementX: 4, movementY: 0, timeStamp: 3000 + i * 16 });
  assert.equal(hand.now, 'mouse');
  hand.move({ pointerType: 'mouse', movementX: 0, movementY: 0, timeStamp: 4000 }); hand.keys(); assert.equal(hand.now, 'keys');
  hand.down({ pointerType: 'touch' }); assert.equal(hand.now, 'touch'); hand.down({ pointerType: 'mouse' }); assert.equal(hand.now, 'mouse');
});
test('a notch of a wheel is one game, a touchpad adds up', () => {
  const out = [], wheel = stepper(d => out.push(d));
  const turn = (deltaX, deltaY, timeStamp, deltaMode = 0) => wheel({ deltaX, deltaY, deltaMode, timeStamp });
  turn(0, 100, 0); turn(0, 100, 100); assert.deepEqual(out.splice(0), [1, 1]); turn(0, -120, 200); assert.deepEqual(out.splice(0), [-1]);
  turn(0, 3, 600, 1); assert.deepEqual(out.splice(0), [1], 'three lines');
  for (let i = 0; i < 20; i++) turn(10, 1, 1000 + i * 8); assert.equal(out.splice(0).length, 2, '200 points, 80 a game');
  turn(40, 0, 3000); turn(-45, 0, 3010); assert.deepEqual(out.splice(0), [], 'the other way starts again');
  turn(60, 0, 5000); turn(60, 0, 6000); assert.deepEqual(out.splice(0), [], 'and so does a pause');
});
test('a finger moves the shelf with it, and a tap stays a tap', () => {
  const out = [], s = swiper(d => out.push(d), () => 100);
  s.down(500, 1); s.move(496, 1); assert.equal(s.up(1), false); assert.deepEqual(out, []);
  s.down(500, 1); s.move(380, 1); s.move(290, 1); assert.deepEqual(out.splice(0), [1, 1]); s.move(405, 1); assert.deepEqual(out.splice(0), [-1]); assert.equal(s.up(1), true);
  s.down(500, 1); s.move(100, 2); assert.deepEqual(out, [], 'another finger'); s.up(1); s.move(0, 1); assert.deepEqual(out, [], 'and nothing once lifted');
});
test('the menu: five icons at most, Power in the middle, Quit last, nothing that does nothing', () => {
  const all = menuOf({ people: 2, abilities: ['fullscreen', 'hide', 'restart', 'quit'] });
  assert.deepEqual(all.map(x => x.id), ['profile', 'library', 'power', 'activity', 'settings']);
  assert.equal(all[2].id, 'power');
  for (const x of all) { assert.ok((x.entries || []).length <= 5, x.id); if (x.entries) assert.ok(x.entries.length > 0, x.id); }
  const power = all[2].entries.map(x => x.id); assert.deepEqual(power, ['fullscreen', 'hide', 'restart', 'quit']);
  assert.deepEqual(menuOf({ people: 1, abilities: ['restart', 'quit'] })[2].entries.map(x => x.id), ['restart', 'quit']);
  assert.ok(!menuOf({ people: 1, abilities: ['quit'] })[0].entries.some(x => x.id === 'switch'), 'one profile: nobody to switch to');
  assert.deepEqual(menuOf({ people: 0, abilities: ['quit'] }).map(x => x.id), ['library', 'power', 'activity', 'settings']);
  assert.ok(!menuOf({ people: 1, abilities: [] }).some(x => x.id === 'power'), 'no power a host does not have');
});
test('each kind of controller is told, named and drawn', () => {
  for (const [name, kind] of [['Xbox Wireless Controller', 'xbox'], ['8BitDo Ultimate', 'xbox'], ['DualSense Wireless Controller (Vendor: 054c)', 'playstation'], ['Pro Controller (STANDARD GAMEPAD Vendor: 057e Product: 2009)', 'switchPro'], ['Nintendo Switch Pro Controller', 'switchPro'], ['Joy-Con (L) (STANDARD GAMEPAD Vendor: 057e Product: 2006)', 'joyConLeft'], ['Joy-Con (R) (Vendor: 057e Product: 2007)', 'joyConRight'], ['Joy-Con L+R (STANDARD GAMEPAD Vendor: 057e Product: 200e)', 'joyConPair'], [undefined, 'xbox']]) assert.equal(padKind(name), kind, name);
  for (const kind of KINDS) {
    const s = SHAPES(kind);
    assert.ok(s.body.length > 300, `${kind}: ${s.body.length} dots`); assert.ok(s.rim.length >= 150, kind);
    for (const [x, y] of [...s.body, ...s.rim]) assert.ok(Math.abs(x) <= 1 && y > -.8 && y < .75, `${kind}: inside the drawing`);
    for (const button of ['a', 'b', 'x', 'y']) assert.ok(s.anchors[button], `${kind} has ${button}`);
    assert.ok(['xbox', 'playstation', 'nintendo'].includes(kindNames(kind)));
  }
  // The dots leave the buttons clear.
  const a = SHAPES('xbox').parts.find(p => p.button === 'a'); assert.ok(!SHAPES('xbox').body.some(([x, y]) => Math.hypot(x - a.x, y - a.y) < a.radius));
});
test('a pressed button lights the one drawn, whatever the family', () => {
  assert.deepEqual([...pressed({ name: 'Xbox', b: { ...idle, s: true, plus: true, l2: true } })].sort(), ['a', 'menu', 'zl']);
  assert.deepEqual([...pressed({ name: 'Pro Controller 057e', b: { ...idle, s: true, l: true } })].sort(), ['b', 'l3']);
  let now = 0, woke = 0; const live = liveOf(() => now); live.listen(() => woke++);
  live.feed({ name: 'Xbox', b: { ...idle, s: true }, ax: [.5, 0, 0, 0] }); assert.equal(live.light('a'), 1); assert.equal(live.left[0], .5); assert.ok(woke > 0 && live.awake());
  live.feed({ name: 'Xbox', b: idle, ax: [0, 0, 0, 0] }); now = 180; assert.ok(live.light('a') > .4 && live.light('a') < .6, 'it fades'); now = 1000; assert.equal(live.light('a'), 0); assert.ok(!live.awake());
  const before = woke; live.feed({ name: 'Xbox', b: idle, ax: [0, 0, 0, 0] }); assert.equal(woke, before, 'a pad at rest wakes nothing');
  live.feed(null); assert.equal(live.held.size, 0);
});
test('no two lines of the button map cross', () => {
  const buttons = ['up', 'a', 'b', 'x', 'y', 'l', 'r', 'zl', 'zr', 'l3', 'r3', 'view', 'menu', 'home'];
  for (const kind of KINDS) {
    const s = SHAPES(kind), [left, right] = sides(buttons, s, 46 / 230);
    assert.equal(left.length + right.length, buttons.filter(b => s.anchors[b]).length, kind);
    for (const [list, edge] of [[left, -1.15], [right, 1.15]]) {
      const at = i => [edge, (i - (list.length - 1) / 2) * 46 / 230 - .05];
      for (let i = 0; i < list.length; i++) for (let k = i + 1; k < list.length; k++) assert.ok(!crosses(s.anchors[list[i]].middle, at(i), s.anchors[list[k]].middle, at(k)), `${kind}: ${list[i]} and ${list[k]}`);
    }
  }
});
test('the state sent by the host has the same buttons', () => {
  const rust = readFileSync(new URL('../src-tauri/src/pad.rs', import.meta.url), 'utf8');
  const names = [...rust.matchAll(/Button::\w+, "(\w+)"/g)].map(m => m[1]).sort();
  const b = readPad({ id: 'x', mapping: 'standard', buttons: Array.from({ length: 17 }, () => ({})), axes: [0, 0, 0, 0] }).b;
  assert.deepEqual(names, Object.keys(b).sort());
});
test('every text has its French, with the same holes', () => {
  const holes = s => (String(typeof s === 'object' ? s.other : s).match(/%(?:\d+\$)?(?:lld|@|d)/g) || []).length;
  for (const [key, en] of Object.entries(STRINGS.en)) { assert.ok(key in STRINGS.fr, key); assert.equal(holes(STRINGS.fr[key]), holes(en), key); }
});
test('the page loads nothing from outside and holds no colour of its own', () => {
  const ui = new URL('../ui/', import.meta.url);
  for (const f of readdirSync(ui).filter(f => /\.(js|css|html)$/.test(f))) {
    const text = readFileSync(new URL(f, ui), 'utf8');
    assert.ok(!/(?:src|href|url\(|import\s+.*from)\s*=?\s*['"(]https?:/.test(text), f + ' loads from outside');
    assert.ok(!/innerHTML|insertAdjacentHTML|document\.write|eval\(/.test(text), f + ' writes markup from text');
  }
  const css = readFileSync(new URL('app.css', ui), 'utf8');
  const literal = [...css.matchAll(/#[0-9a-f]{3,8}\b/gi)].map(m => m[0].toLowerCase()).filter(c => !['#000', '#fff'].includes(c) && !/^#(cloud|art|hints|card)/.test(c) && !'#layers'.startsWith(c));
  assert.deepEqual(literal.filter(c => !['#ca', '#card'].includes(c)), []);
});
test('a controller is named as a player would', () => {
  assert.equal(padName('Xbox 360 Controller (XInput STANDARD GAMEPAD)'), 'Xbox 360 Controller');
  assert.equal(padName('Pro Controller (STANDARD GAMEPAD Vendor: 057e Product: 2009)'), 'Pro Controller');
  assert.equal(padName('Pad (left hand) (Vendor: 1234 Product: 5678)'), 'Pad (left hand)');
});
test('names games give their settings read in French when they are known', () => {
  const fr = text => gameWord(GAME_WORDS.fr, text);
  assert.equal(fr('Picture'), 'Image');
  for (const same of ['V-Sync', 'VSync', 'v-sync', 'Vertical Sync']) assert.equal(fr(same), 'Synchronisation verticale', same);
  assert.equal(fr('Coin magnet'), 'Coin magnet', 'an unknown name stays');
  assert.equal(fr('constructor'), 'constructor');
  assert.equal(gameWord(GAME_WORDS.en, 'Picture'), 'Picture');
});

test('French speaks to one player, as the rest of Oort', () => {
  const page = readdirSync(new URL('../ui/', import.meta.url)).filter(f => f.endsWith('.js')).map(f => readFileSync(new URL('../ui/' + f, import.meta.url), 'utf8')).join('\n');
  const used = [...page.matchAll(/\bt\((['"])((?:(?!\1)[^\\]|\\.)+)\1/g)].map(m => m[2].replace(/\\'/g, "'"));
  const own = Object.keys(JSON.parse(readFileSync(new URL('../strings.json', import.meta.url), 'utf8')));
  for (const key of [...used, ...own]) for (const text of [STRINGS.fr[key]].flatMap(v => typeof v === 'object' ? Object.values(v) : [v])) assert.ok(!/\b(vous|votre|vos)\b|(^|[\s(])(?!assez\b|chez\b)[A-Za-zéèê]+ez\b/i.test(text ?? ''), `${key}: ${text}`);
});
