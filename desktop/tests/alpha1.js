/* What a player of 0.1.0-alpha.1 has: a folder of games, a program, a favorite, time played. Run in that version. */
probe(async P => {
  await oort.ask('folders.add', { path: RUN + '/games' }); await oort.ask('programs.add', { program: P.program(RUN + '/programs/lb_x64') });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20); const g = oort.library.games.find(g => g.name === 'lb_x64'); P.ok(g, 'the program has its file’s name');
  await oort.ask('game.favorite', { id: g.id, on: true }); const ends = []; await window.__TAURI__.event.listen('session', e => ends.push(e.payload));
  await window.__TAURI__.core.invoke('launch', { id: g.id, fullscreen: false }); await P.until(() => ends.length, 15000); await P.wait(800); await P.shot('alpha1');
  await oort.ask('settings.set', { id: 'colorThemeID', value: 'nord' }); await oort.ask('settings.save');
});
