// node --test desktop/tests/nav.test.mjs : what needs no window.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
const { nearest, repeater, brand, readPad } = await import('../ui/nav.js');
const { STRINGS } = await import('../ui/gen/strings.js');
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
