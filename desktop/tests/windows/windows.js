/* What only Windows can show: the real window stepping aside and coming back, real keys, a game outside its launcher's
   job, one that ignores its X button, a batch file, names with accents. */
probe(async P => {
  const ask = oort.ask, inv = window.__TAURI__.core.invoke, find = n => oort.library.games.find(g => g.name === n), host = P.host;
  if (!(await ask('folders')).folders.length) await ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20);
  const ends = []; await window.__TAURI__.event.listen('session', e => ends.push(e.payload));
  P.same((await host('state')).title, 'Oort NX', 'the window is the app’s');
  P.same([await host('front'), (await host('state')).front], [true, true], 'it is in front');
  P.same(await P.wait(200).then(() => document.hasFocus()), true, 'the page has the keyboard');
  // Keys as Windows sends them.
  await P.press('lt'); const at = P.id(); await host('key', 0x27); await P.wait(400); P.ok(P.id() !== at, 'a real right arrow moves');
  await host('key', 0x48); await P.until(() => document.querySelector('.menu'), 3000, 'H opens the menu'); await P.wait(300); await host('desktop', '39-menu'); P.same([...document.querySelectorAll('.orb')].some(o => o.dataset.id === 'power'), true, 'Power is there'); await host('key', 0x1B); await P.until(() => oort.layers.length === 1, 3000, 'Esc closes it');
  // Back with the mouse, in the installed app: from a row to the list, then out.
  await P.settings(); await P.press('right'); const hint = () => P.at([...document.querySelectorAll('#hints .hint')].find(x => /Retour|Back/.test(x.textContent))); await host('click', ...hint()); await P.wait(300); P.ok(document.activeElement.closest('.side'), 'Back, with the mouse, goes to the list'); await host('click', ...hint()); await P.until(() => oort.layers.length === 1, 3000, 'Back again leaves Settings'); P.say('ok Back, with the mouse, leaves Settings');
  await P.press('lt'); await P.press('right', 4); await host('key', 0x4D); await P.until(() => document.querySelector('.shell'), 3000, 'M opens the options of the chosen game'); await host('key', 0x1B); await P.until(() => oort.layers.length === 1, 3000, 'Esc closes them');
  P.same(await inv('abilities'), ['fullscreen', 'hide', 'restart', 'quit'], 'what Power can do on Windows'); await inv('hide'); await P.until(async () => (await host('state')).minimized, 5000, 'Hide'); await host('front'); await P.until(async () => !(await host('state')).minimized, 5000, 'and back'); P.say('ok Hide, and back');
  await host('key', 0x7A); await P.wait(1200); P.ok(innerHeight >= screen.height - 2, `F11 fills the screen: ${innerWidth}x${innerHeight} of ${screen.width}x${screen.height}`); await host('desktop', '40-fullscreen'); await host('key', 0x7A); await P.wait(800); P.ok(innerHeight < screen.height - 2, 'and back');

  // The window steps aside for the game's own, and comes back in front when it ends.
  const lantern = find('Winter Lantern'); await P.press('lt'); for (let i = oort.library.games.indexOf(lantern) + 2; i > 0; i--) { oort.act('right'); await P.wait(25); } P.same(P.id(), lantern.id, 'on Winter Lantern');
  await host('desktop', '41-before'); await P.press('a'); await P.until(async () => (await host('state')).minimized, 6000, 'Oort steps aside'); P.say('ok Oort steps aside');
  await P.wait(700); const during = await host('state'); P.same(during.frontTitle, 'Invented game', 'the game is in front'); await host('desktop', '42-the-game');
  await P.until(() => ends.length, 15000, 'the game ends'); await P.wait(900); const after = await host('state'); P.same([after.minimized, after.front], [false, true], 'Oort is back in front'); await host('desktop', '43-back'); await P.shot('43-back-page');
  P.ok(ends[0].seconds >= 4 && ends[0].seconds <= 8, 'played ' + ends[0].seconds + ' s'); P.ok(document.querySelector('#card.on')?.textContent.includes('Winter Lantern'), 'the session card names it');
  const run = (await host('read', RUN + '/games/Île d’Été (1)/recompdata/last-run.txt') || '').split(/\r?\n/);
  P.ok(run[0].endsWith('\\Île d’Été (1)\\run.exe'), 'a folder with accents: ' + run[0]); P.same(run.slice(1, 4), ['--name', 'Forêt & « neige »', '100%'], 'arguments arrive whole');
  P.ok(run.some(l => /^RECOMPLAUNCHER_DATA=[A-Z]:\\/.test(l)), 'the data folder is written the Windows way');

  // A launcher whose game leaves its job.
  ends.length = 0; let t0 = performance.now(); await inv('launch', { id: find('Night Ferry').id, fullscreen: false }); await P.until(() => ends.length, 15000); let took = (performance.now() - t0) / 1000;
  P.ok(took > 4.5 && took < 9, 'a game outside the launcher’s job is followed: ' + took.toFixed(1) + ' s');
  // A game that ignores its X button.
  ends.length = 0; await inv('launch', { id: find('Locked Gate').id, fullscreen: false }); await P.wait(2500); P.same(await host('count', RUN + '/games/Ignores'), 1, 'it runs'); t0 = performance.now(); await inv('close_game'); await P.until(() => ends.length, 15000); took = (performance.now() - t0) / 1000;
  P.ok(took > 6 && took < 12, 'it is asked, waited for, then ended: ' + took.toFixed(1) + ' s'); P.same(await host('count', RUN + '/games/Ignores'), 0, 'nothing of it is left'); P.same(ends[0].crashed, false, 'closing is not a crash');
  // A batch file, and a program that fails as Windows reports a fault.
  ends.length = 0; t0 = performance.now(); await inv('launch', { id: find('Old Script').id, fullscreen: false }); await P.until(() => ends.length, 15000); took = (performance.now() - t0) / 1000; P.ok(took > 2 && took < 8 && !ends[0].crashed, 'a batch file is followed: ' + took.toFixed(1) + ' s');
  ends.length = 0; await inv('launch', { id: find('Sudden Stop').id, fullscreen: false }); await P.until(() => ends.length, 15000); P.same(ends[0].crashed, true, 'a fault is a crash');
  P.same(await host('count', RUN + '/games'), 0, 'no game is left running');
  const emulated = await host('read', RUN + '/emulator-args.txt'); if (emulated) P.same(emulated.trim().split(/\r?\n/).slice(0, 2), ['--fullscreen', 'two words'], 'a program’s arguments');
});
