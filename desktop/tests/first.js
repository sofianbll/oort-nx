/* A first start, with the app's own folder: nothing there, then a folder of games. Stays after Quit for the next one. */
probe(async P => {
  P.same(document.documentElement.dataset.ready, '1', 'the window is ready');
  await P.wait(2200); await P.shot('empty');
  P.ok(document.querySelector('.empty'), 'an empty library');
  P.same(P.id(), 'add', 'Add game has the first focus');
  await oort.ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => oort.library.games.length > 20); await P.wait(800); await P.shot('home');
  await oort.ask('game.favorite', { id: oort.library.games[0].id, on: true });
});
