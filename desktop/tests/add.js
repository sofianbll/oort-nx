/* The first game: no detour to a list of projects. A synthetic folder is added by the core. */
probe(async P => {
  const active = () => document.querySelector('.layer:not([inert])'), empty = () => active().querySelector('.empty');
  await P.until(empty); await P.shot('01-vide');
  P.same([...empty().querySelectorAll('button')].map(b => b.querySelector('.what')?.textContent.trim()), [document.documentElement.lang === 'fr' ? 'Ajouter un jeu' : 'Add game'], 'one way to add on the empty home');
  P.same(P.id(), 'add', 'the empty home is already on Add game');
  P.pad(); await P.wait(350); await P.button(0);
  await P.until(() => active().querySelector('.sheet'));
  await P.shot('02-ajouter');
  P.same([...active().querySelectorAll('.sheet .row')].map(b => b.dataset.id).filter(id => id !== 'steam'), ['program', 'folder'], 'Add game keeps programs and folders');
  await P.press('b'); await P.until(() => oort.layers.length === 1);
  await oort.ask('folders.add', { path: RUN + '/games' });
  dispatchEvent(new Event('focus')); await P.until(() => active().querySelector('.shelf .tile[data-id=add]'));
  await P.shot('03-jeux');
  P.same([...active().querySelectorAll('.shelf .tile')].slice(0, 2).map(b => b.dataset.id), ['add', oort.library.games[0].id], 'no gap or other card before the first game');
  P.same([...active().querySelectorAll('.shelf .tile')].slice(0, 2).map(b => b.dataset.i), ['0', '1'], 'the two tiles are next to each other');
  P.same(P.id(), oort.library.games[0].id, 'the first game has the focus');
  await P.press('lt'); P.same(P.id(), 'add', 'the first tile opens Add game');
  await P.press('a'); await P.until(() => active().querySelector('.sheet')); P.ok(active().querySelector('[data-id=folder]'), 'a folder of games is still offered');
});
