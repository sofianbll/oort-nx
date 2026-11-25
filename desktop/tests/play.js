/* Playing invented games: files to choose, settings, launch, following what a stub starts, time, crash, close, setup step. */
probe(async P => {
  const ask = oort.ask, inv = window.__TAURI__.core.invoke, find = n => oort.library.games.find(g => g.name === n);
  if (!(await ask('folders')).folders.length) await ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20);
  const ends = []; await window.__TAURI__.event.listen('session', e => ends.push(e.payload));
  const back = () => P.until(() => !oort.layers.some(l => l.launch), 12000, 'back from the game');
  // The shelf is drawn again after a session: settle first.
  const goTo = async name => { await P.wait(700); const i = oort.library.games.findIndex(g => g.name === name) + 1; await P.press('lt'); for (let k = 0; k < i; k++) { oort.act('right'); await P.wait(20); } await P.wait(150); };
  const refused = async (p, code, what) => { let got = 'nothing'; try { await p; } catch (e) { got = String(e); } P.same(got, code, what); };

  const lunar = find('Lunar Observatory');
  await refused(inv('launch', { id: lunar.id, fullscreen: false }), 'inputs-missing', 'a game without its files does not start');
  await refused(ask('launch.plan', { id: lunar.id }), 'method', 'the page cannot ask for a plan');
  await refused(inv('open_link', { url: 'https://example.com' }), 'link', 'only listed pages open');
  await refused(inv('open_link', { url: 'file:///etc/hosts' }), 'link', 'never a file');
  // Choosing the copy by hand, through the app's own picker.
  await goTo('Lunar Observatory'); await P.press('x'); await P.until(() => document.querySelector('[data-id=input-game]'));
  await P.press('a'); P.same(P.id(), 'input-game', 'A leads to the file to choose'); await P.press('a'); await P.browse(RUN + '/copies'); await P.until(() => P.rows().some(r => r.textContent.includes('lunar.iso')));
  P.ok(![...document.querySelectorAll('.sheet .row')].some(r => r.textContent.includes('.rom')), 'only the kind of file the game takes'); await P.shot('20-file');
  [...document.querySelectorAll('.sheet .row')].find(r => r.textContent.includes('lunar.iso')).click();
  await P.until(async () => document.querySelector('.detail [data-id=primary]')?.textContent.includes(document.documentElement.lang === 'fr' ? 'Jouer' : 'Play')); await P.shot('21-ready');
  const set = await ask('game.setting', { id: lunar.id, setting: 'sens', value: 1.5 }); P.same(set.settings.find(s => s.id === 'sens').text, '1.5', 'a slider is kept');
  document.querySelector('.detail [data-id=primary]').click(); await P.until(() => document.querySelector('.launch')); await P.shot('22-launch');
  await refused(inv('launch', { id: find('Harbour').id, fullscreen: false }), 'already-playing', 'one game at a time');
  await back(); await P.wait(200);
  P.same(ends.length, 1, 'the end is announced once'); P.ok(ends[0].seconds >= 2 && ends[0].seconds <= 6, 'played ' + ends[0].seconds + ' s'); P.same(ends[0].crashed, false, 'no crash');
  await P.shot('23-session-card'); P.ok(document.querySelector('#card.on'), 'the session card shows');
  P.ok((await ask('game', { id: lunar.id })).seconds >= 2, 'the time is kept');
  while (oort.layers.length > 1) await P.press('b');
  P.same(oort.library.games.find(g => g.id === lunar.id).last > 1e9, true, 'last played');
  // A stub that leaves at once: the session is the game's.
  const coast = find('Coast Runner'); let t0 = performance.now(); ends.length = 0;
  await inv('launch', { id: coast.id, fullscreen: false }); await P.until(() => ends.length, 15000); const took = (performance.now() - t0) / 1000;
  P.ok(took > 3.5 && took < 8, 'the session lasts as long as the game the stub started: ' + took.toFixed(1) + ' s');
  // A crash in the game's own words.
  ends.length = 0; await goTo('Broken Compass'); await P.press('a'); await P.until(() => document.querySelector('.dialog'), 12000); await P.shot('24-crash');
  P.ok(P.text('.dialog').includes('wrong edition'), 'the manifest’s own message'); await P.press('a'); await P.until(() => oort.layers.length === 1);
  // A program that does not end: closed from Oort.
  ends.length = 0; await goTo('Endless Garden'); await P.press('a'); await P.until(() => document.querySelector('.launch [data-id=close]'), 9000); await P.shot('25-running'); await P.press('a'); await P.until(() => document.querySelector('.dialog')); await P.press('right'); await P.press('a');
  await P.until(() => ends.length, 12000, 'closed'); P.same(ends[0].crashed, false, 'closing is not a crash'); await P.until(() => oort.layers.length === 1);
  // The setup step, then the game.
  const tidal = find('Tidal Works'); await refused(inv('launch', { id: tidal.id, fullscreen: false }), 'prepare-first', 'set up first');
  await goTo('Tidal Works'); await P.press('a'); await P.until(() => document.querySelector('[data-id=option-hd]')); await P.shot('26-setup'); document.querySelector('.detail [data-id=primary]').click(); await P.until(() => document.querySelector('.bar')); await P.wait(900); await P.shot('27-setting-up');
  P.ok(parseFloat(document.querySelector('.bar').style.getPropertyValue('--at')) > .1, 'progress moves');
  await P.until(async () => (await ask('game', { id: tidal.id })).state === 'ready', 12000, 'ready'); await P.wait(400); await P.shot('28-set-up');
  while (oort.layers.length > 1) await P.press('b');
  // Any program, with its arguments.
  await ask('programs.add', { program: P.program(RUN + '/emulator'), args: '--fullscreen "two words"', target: RUN + '/copies/Sunken City.rom' }); dispatchEvent(new Event('focus')); await P.until(() => find('Sunken City')); ends.length = 0;
  await inv('launch', { id: find('Sunken City').id, fullscreen: true }); await P.until(() => ends.length, 10000); P.ok(ends[0].seconds >= 1, 'a program is followed too');
  await refused(inv('launch', { id: find('Glass Forest').id, fullscreen: false }), 'unsupported-placing', 'what is not done is refused');
  await refused(inv('launch', { id: find('Damaged').id, fullscreen: false }), 'manifest-json', 'a broken manifest does not start');
  const art = p => new Promise(r => { const i = new Image(); i.onload = () => r(true); i.onerror = () => r(false); i.src = window.__TAURI__.core.convertFileSrc(p, 'oort-art').replace(/%2F/gi, '/'); });
  P.ok(await art(lunar.id + '/cover'), 'a cover is served'); P.ok(!await art('../../etc/hosts'), 'nothing else is'); P.ok(!await art(lunar.id + '/..%2f..%2fsettings'), 'nor by a path');
});
