/* The rows about integrations, through the real page and the real core: each row as the core decides it (integrations),
   drawn here, and sent back as the row that was shown (integrations.act) — in Settings › Integrations, the first steps,
   Add game and the activity center; and the question asked before information online is on. No game starts, nothing is heard.
   Wants an invented Steam with two games installed and one still downloading (steam=), and two games already found
   online (data=), in English. GUIDE=true keeps the first steps open. */
window.GUIDE = true;
const asked = [], heard = [];
let wrongRoute = null, hold = null, cut = false, fake = false;
(() => {
  const core = window.__TAURI__.core, real = core.invoke;
  // The transport is the real one; this only listens, once puts a page the core never sends in its reply, gives the
  // steps' row while Steam is looked for a word the page would not choose, and holds or cuts the steps' Steam row.
  core.invoke = async (name, args) => {
    if (name === 'online_look') return null;
    if (name === 'online_search') return { choices: [] };
    if (name === 'core') asked.push(args.method + (args.params?.at ? '@' + args.params.at : ''));
    if (name === 'core' && args.method === 'integrations' && args.params?.at === 'guide') { if (cut) throw 'core-lost'; await hold; }
    const r = await real(name, args);
    if (name === 'core' && args.method === 'guide' && r?.steam?.looking) r.steam.looking.value = ['Waiting'];
    // The question asked before information online is on, with a title the page would not choose (hello).
    if (name === 'core' && args.method === 'hello') {
      if (r?.onlineQuestion) r.onlineQuestion.title = ['Information online'];
      if (r?.gameSources) {
        r.gameSources.find(e => e.id === 'program').title = ['Programs'];
        r.gameSources.find(e => e.id === 'folder').title = ['Game folders'];
      }
    }
    if (name === 'core' && args.method === 'game' && r?.information?.online.open === 'onlineQuestion') {
      r.information.online.value = ['Waiting'];
      r.information.pictures = ['No picture'];
    }
    // The activity center as the core could say it: games looked for online, Oort at work.
    if (fake && name === 'core' && args.method === 'integrations' && args.params?.at === 'activity') {
      r.entries = [{ id: 'online', title: ['Information online'], sub: ['Looking…'], value: ['%lld games', 7], icon: 'search', open: 'integrations' }, ...r.entries.filter(e => e.id !== 'online')];
      r.working = true;
    }
    if (wrongRoute && name === 'core' && args.method === 'integrations' && !args.params?.at) {
      const programs = r.sections.flatMap(s => s.entries).find(e => e.id === 'prog');
      programs.steps.flatMap(s => s.items).find(i => i.row).row.open = wrongRoute;
    }
    return r;
  };
})();
probe(async P => {
  const { STRINGS } = await import('/gen/strings.js'), en = STRINGS.en, ask = oort.ask;
  const play = oort.sounds.play; oort.sounds.play = (event, el) => { heard.push(event); return play(event, el); };
  const in_ = scope => id => document.querySelector(`${scope} [data-id="${id}"]`);
  const row = in_('.shell .list'), step = in_('.steps'), sheetRow = in_('.sheet');
  const ids = () => [...document.querySelectorAll('.shell .list .row')].map(r => r.dataset.id);
  const text = (el, part) => el?.querySelector(part)?.textContent.replace(/[-]/g, '').trim() ?? null;  // without the icons' glyphs
  const ONLINE = 'Oort NX looks for each game’s cover, description, year and genres on the Steam store, Wikipedia and Wikidata. It sends the game’s name, or its Steam number, and your language. Like any site, they see your internet address. No account, no key, and nothing else leaves this computer.';
  const reads = 'Steam' + en['Reads Steam’s lists of installed games and the pictures it keeps on this computer. Changes nothing and sends nothing; Steam itself starts the games.'];
  const sources = (at, place) => {
    const title = id => at(id)?.querySelector('.what')?.firstChild?.textContent;
    P.same([title('program'), title('folder')], [en['Programs'], en['Game folders']], `${place}: the two sources are the core’s`);
  };

  // The first steps, games page: before Steam is read, the row is the core's too (guide), while it is looked for and
  // if the core does not answer; A does nothing there.
  const go = async want => { document.querySelector('.steps [data-id=continue]').click(); await P.until(() => P.text('.steps .count') === want, 8000, want); };
  let release; hold = new Promise(r => { release = r; });
  for (const want of ['2 / 5', '3 / 5']) await go(want);
  await P.until(() => step('steam'), 8000, 'the games page');
  sources(step, 'first steps');
  P.same([text(step('steam'), '.what'), text(step('steam'), '.value'), step('steam').getAttribute('role')], ['Steam', en['Waiting'], null], 'while Steam is looked for: the core’s words');
  // The page asks the core one thing at a time: nothing is asked of it until Steam's row comes.
  const waited = asked.length; heard.length = 0;
  step('steam').focus(); await P.press('a'); await P.wait(200);
  P.same([text(step('steam'), '.value'), step('steam').getAttribute('aria-checked'), asked.length - waited, heard], [en['Waiting'], null, 0, []], 'A does nothing while it is looked for: no change, no question, no sound');
  hold = null; release();
  await P.until(() => step('steam')?.getAttribute('role') === 'switch', 8000, 'then read');
  P.same((await ask('steam')).chosen, false, 'nothing was chosen');
  cut = true; await P.press('b'); await P.until(() => P.text('.steps .count') === '2 / 5', 8000, 'back');
  await go('3 / 5');
  await P.until(() => text(step('steam'), '.value') === en['Not found'], 8000, 'no answer');
  P.same([text(step('steam'), '.what'), step('steam').getAttribute('role')], ['Steam' + en['Steam was not found on this computer. It is looked for again each time.'], null], 'without an answer: Steam not found, with its sentence, as before the core said it');
  cut = false; await P.press('b'); await P.until(() => P.text('.steps .count') === '2 / 5', 8000, 'back again');
  await go('3 / 5');
  // The core's row, the switch kept by the steps until they go on.
  await P.until(() => step('steam')?.getAttribute('role') === 'switch', 8000, 'Steam read in the first steps');
  P.ok(asked.includes('integrations@guide'), 'the first steps’ Steam row is the core’s');
  P.same([text(step('steam'), '.what'), text(step('steam'), '.value'), step('steam').getAttribute('aria-checked')], [reads, '2 games', 'true'], 'never chosen: offered on');
  step('steam').focus(); await P.press('a');
  P.same([step('steam').getAttribute('aria-checked'), (await ask('steam')).chosen], ['false', false], 'switched off in the steps: nothing written yet');
  step('steam').focus(); await P.press('a');
  P.same(step('steam').getAttribute('aria-checked'), 'true', 'and on again');
  document.querySelector('.steps [data-id=continue]').click(); await P.until(() => P.text('.steps .count') === '4 / 5', 8000, 'online page');
  P.same([P.text('.steps h1'), P.text('.steps .lead'), P.text('.steps [data-id=continue]'), P.text('.steps [data-id=yes]')], [en['Information online'], en[ONLINE], en['No'], en['Yes, look online']], 'the online page asks the core’s question');
  await P.until(async () => (await ask('steam')).on, 5000, 'kept when they go on');
  P.same([asked.includes('integrations.keep'), (await ask('library')).total], [true, 2], 'Steam’s games come in');
  document.querySelector('.steps [data-id=continue]').click(); await P.until(() => P.text('.steps .count') === '5 / 5', 8000, 'done');
  document.querySelector('.steps [data-id=continue]').click(); await P.until(() => oort.layers.length === 1, 8000, 'the library');
  await ask('steam.set', { on: false }); await P.wait(300); dispatchEvent(new Event('focus')); await P.wait(600);

  // Add game: Steam's row is the core's while Steam is here and off; A turns it on and closes the sheets.
  await P.key('n', { ctrlKey: true }); await P.until(() => document.querySelector('.sheet'), 5000, 'Add game');
  sources(sheetRow, 'Add game');
  P.ok(asked.includes('integrations@add'), 'Add game’s Steam row is the core’s');
  P.same([text(sheetRow('steam'), '.value'), sheetRow('steam')?.getAttribute('role')], ['2 games', null], 'a row, not a switch');
  sheetRow('steam').focus(); await P.press('a');
  await P.until(() => oort.layers.length === 1 && oort.library.games.length === 2, 8000, 'added, the sheets close');
  P.same((await ask('steam')).on, true, 'on');
  await P.key('n', { ctrlKey: true }); await P.until(() => document.querySelector('.sheet'), 5000, 'Add game again');
  P.ok(!sheetRow('steam'), 'on: no longer offered'); while (oort.layers.length > 1) await P.press('b');

  // The activity center: what Steam still downloads, a row that opens Settings › Integrations. The control center's dot
  // and what is looked for online are the core's too.
  await P.key('k', { ctrlKey: true }); await P.until(() => document.querySelector('.menu [data-id=activity]'), 5000, 'the menu');
  P.same([(await ask('online')).on, !!document.querySelector('.menu [data-id=activity] .dot')], [false, false], 'nothing looked for online: no dot');
  await P.key('k', { ctrlKey: true }); await P.until(() => !document.querySelector('.menu'), 5000, 'the menu closes');
  fake = true;
  await P.key('k', { ctrlKey: true }); await P.until(() => document.querySelector('.menu [data-id=activity]'), 5000, 'the menu');
  P.ok(document.querySelector('.menu [data-id=activity] .dot'), 'the control center’s dot is the core’s');
  document.querySelector('.menu [data-id=activity]').click(); await P.until(() => oort.layers.at(-1).activity, 5000, 'Activity center');
  P.ok(asked.includes('integrations@activity'), 'the activity center’s Steam row is the core’s');
  P.same([text(sheetRow('steam'), '.what'), text(sheetRow('steam'), '.value')], ['Steam1 still downloading, left out', '1'], 'what still downloads');
  P.same([text(sheetRow('online'), '.what'), text(sheetRow('online'), '.value'), [...document.querySelectorAll('.sheet .row')].map(r => r.dataset.id).filter(id => ['online', 'steam'].includes(id))],
    [en['Information online'] + en['Looking…'], '7 games', ['online', 'steam']], 'what is looked for online, as the core says it, before Steam');
  fake = false;
  sheetRow('steam').click(); await P.until(() => document.querySelector('.shell'), 5000, 'Settings from the activity');
  P.same(document.querySelector('.side [aria-current=page]')?.dataset.id, 'c-integrations', 'at Integrations');
  while (oort.layers.length > 1) await P.press('b');
  await ask('steam.set', { on: false }); await P.wait(300);

  // Settings › Integrations.
  const open = async () => { await P.settings(); [...document.querySelectorAll('.side button')].find(b => b.dataset.id === 'c-integrations').click(); await P.until(() => row('steam'), 5000, 'Integrations'); await P.wait(200); };
  const close = async () => { while (oort.layers.length > 1) await P.press('b'); await P.wait(200); };
  await open();
  P.ok(asked.includes('integrations'), 'the rows are the core’s');
  P.same(ids(), ['steam', 'prog', 'online'], 'the catalogue rows, in their order');
  const detail = async id => {
    row(id).focus(); await P.press('a');
    await P.until(() => document.querySelector('.shell [data-id=integration-back]'), 5000, `detail ${id}`);
  };
  await detail('steam');
  P.same([text(row('steam'), '.what'), text(row('steam'), '.value'), row('steam').dataset.help?.includes('/Steam'), row('steam').dataset.help?.includes('1 still downloading')], [reads, '2 games', true, true], 'Steam: its words, its folders, what still downloads');

  // PC_STEAM: off and on are two rows; A asks for the other state, at once; the focus stays.
  P.same([row('steam').getAttribute('role'), row('steam').getAttribute('aria-checked')], ['switch', 'false'], 'Steam is a switch, off');
  row('steam').focus(); await P.press('a');
  await P.until(() => row('steam')?.getAttribute('aria-checked') === 'true', 5000, 'drawn on');
  P.same([(await ask('steam')).on, oort.library.games.length, P.id()], [true, 2, 'steam'], 'on: its games come in, the focus stays');
  await P.press('a');
  await P.until(() => row('steam')?.getAttribute('aria-checked') === 'false', 5000, 'drawn off');
  P.same([(await ask('steam')).on, oort.library.games.length, P.id()], [false, 0, 'steam'], 'off again: its games leave, the focus stays');

  // Two presses on one row shown once: done once, the second refused.
  heard.length = 0; row('steam').click(); row('steam').click();
  await P.until(() => row('steam')?.getAttribute('aria-checked') === 'true', 5000, 'drawn on once');
  await P.wait(400);
  P.same([(await ask('steam')).on, heard.includes('deny')], [true, true], 'one change for one look; the second press is refused');

  // PC_ONLINE: the switch both ways; Delete asks first, Cancel has the focus and deletes nothing.
  await P.press('b');
  await detail('online');
  P.same([text(row('online'), '.value'), text(row('clear'), '.value')], ['Off', '2 games'], 'online words and existing delete action');
  row('online').focus(); await P.press('a');
  await P.until(() => row('online')?.getAttribute('aria-checked') === 'true', 5000, 'online on');
  P.same([(await ask('online')).on, text(row('online'), '.value')], [true, '2 games known'], 'online on, two known');
  row('clear').focus(); await P.press('a');
  await P.until(() => document.querySelector('[role=alertdialog]'), 3000, 'Delete asks first');
  P.same([document.querySelector('[role=alertdialog] h1').textContent, document.activeElement.textContent], ['Delete what was found online?', 'Cancel'], 'the question, Cancel first');
  await P.press('a'); await P.wait(300);
  P.same([(await ask('online')).known, P.id()], [2, 'clear'], 'Cancel deletes nothing and comes back to Delete');
  await P.press('a'); await P.until(() => document.querySelector('[role=alertdialog]'), 3000);
  await P.press('right'); await P.press('a');
  await P.until(() => !row('clear'), 5000, 'Delete leaves once done');
  P.same([(await ask('online')).known, text(row('online'), '.value')], [0, '0 games known'], 'what was found online is deleted');
  row('online').focus(); await P.press('a');
  await P.until(() => row('online')?.getAttribute('aria-checked') === 'false', 5000, 'online off');
  P.same((await ask('online')).on, false, 'and the switch goes back');
  await P.press('b');

  // Back, B and Esc: one way back, the shell's, the same three times.
  const settings = oort.layers.at(-1), b = settings.actions.b; let backs = 0;
  settings.actions.b = () => { backs++; b(); };
  const ways = { esc: () => P.key('Escape'), b: () => P.press('b'), hint: async () => { [...document.querySelectorAll('#hints .hint')].find(x => x.textContent.includes('Back')).click(); await P.wait(110); } };
  for (const [name, go] of Object.entries(ways)) {
    row('steam').focus(); const before = asked.length; await go();
    P.same([P.id(), asked.slice(before).filter(m => m.startsWith('integrations'))], ['c-integrations', []], `${name}: back to the list of pages, nothing asked of the core`);
  }
  P.same(backs, 3, 'the three come to the same place');
  settings.actions.b = b;
  await close();

  // A page the row cannot open is refused, including a match page without a game.
  for (const route of ['not-a-real-destination', 'match']) {
    wrongRoute = route; await open(); wrongRoute = null;
    const layers = oort.layers.length; heard.length = 0;
    await detail('prog'); await P.press('a'); await P.wait(300);
    P.same([oort.layers.length, heard.includes('deny')], [layers, true], `${route} is refused here`);
    await close();
  }
  await open();
  await detail('prog'); await P.press('a');
  await P.until(() => document.querySelector('.sheet [data-id=program]'), 3000, 'Programs opens Add a program');
  await close();

  // Asked from a game's page while information online is off: the same question, the core's; No changes nothing.
  P.same((await ask('online')).on, false, 'off');
  await P.press('lt'); oort.act('right'); await P.until(() => oort.library.games.some(g => g.id === document.activeElement?.dataset.id), 5000, 'a game chosen'); await P.press('x');
  const pictures = await P.until(() => document.querySelector('.detail [data-id=look]'), 5000, 'the game’s options');
  P.same(text(pictures, '.what small'), en['No picture'], 'the game’s pictures sentence is the core’s');
  pictures.click();
  const gameOnline = await P.until(() => document.querySelector('.shell [data-id=online]'), 5000, 'its information');
  P.same(text(gameOnline, '.value'), en['Waiting'], 'the game’s online row is the core’s');
  gameOnline.click();
  await P.until(() => document.querySelector('[role=alertdialog]'), 3000, 'asked first');
  P.same([P.text('[role=alertdialog] h1'), P.text('[role=alertdialog] p'), [...document.querySelectorAll('[role=alertdialog] .keys button')].map(b => b.textContent.trim())],
    [en['Information online'], en[ONLINE], [en['No'], en['Yes, look online']]], 'the game’s page asks the core’s question');
  document.querySelector('[role=alertdialog] .keys button').click(); await P.wait(300);
  P.same([(await ask('online')).on, !!document.querySelector('[role=alertdialog]')], [false, false], 'No changes nothing');
  document.querySelector('.shell [data-id=online]').click();
  document.querySelectorAll('[role=alertdialog] .keys button')[1].click();
  await P.until(() => document.querySelector('.sheet [data-id=none]'), 5000, 'Yes opens the match page');
  P.same((await ask('online')).on, true, 'Yes enables online before matching');
  await ask('online.set', { on: false });
  await close();

  // The same rules on the core's own transport: a row changed since it was shown, or done twice, is refused.
  const steamToken = async () => {
    const entries = (await ask('integrations')).sections.flatMap(section => section.entries);
    const rows = entries.find(e => e.id === 'steam').steps.flatMap(step => step.items);
    return rows.find(item => item.row?.id === 'steam').row.token;
  };
  const token = await steamToken();
  await ask('steam.set', { on: false });
  P.same(await ask('integrations.act', { id: 'steam', token }).catch(e => e), 'stale', 'changed since it was shown');
  const now = await steamToken();
  await ask('integrations.act', { id: 'steam', token: now });
  P.same(await ask('integrations.act', { id: 'steam', token: now }).catch(e => e), 'stale', 'done twice');
  P.same((await ask('steam')).on, true, 'once');
});
