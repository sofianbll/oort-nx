/* Every screen, by the keyboard, with a picture of each. */
probe(async P => {
  if (!(await oort.ask('folders')).folders.length) {
    await P.shot('00-empty');
    P.ok(['steam', 'program'].includes(P.id()), 'an empty library offers a way in: ' + P.id());
    document.querySelector('.empty [data-id=folder]').focus(); await P.press('a'); await P.until(() => document.querySelector('.sheet .row')); await P.shot('01-picker');
    await P.press('b'); await P.until(() => document.querySelector('.empty'), 5000, 'back home').catch(() => {});
    await P.press('menu'); P.same(oort.layers.length, 1, '+ closes the picker'); while (oort.layers.length > 1) await P.press('b');
    await oort.ask('folders.add', { path: RUN + '/games' });
  }
  dispatchEvent(new Event('focus')); await P.until(() => document.querySelectorAll('.shelf .tile').length > 10);
  const first = P.id(); P.ok(document.activeElement.matches('.shelf .tile'), 'the shelf has the focus');
  await P.shot('02-shelf');
  await P.key('ArrowRight'); P.ok(P.id() !== first, 'right moves');
  await P.press('rt'); await P.press('lt'); P.same(P.id(), 'catalog', 'the ends');
  // To the game with files to choose.
  const goTo = async name => { const g = oort.library.games.find(g => g.name === name), i = oort.library.games.indexOf(g) + 2; await P.press('lt'); for (let k = 0; k < i; k++) { oort.act('right'); await P.wait(25); } await P.wait(200); P.same(P.id(), g.id, 'on ' + name); return g; };
  await goTo('Lunar Observatory'); await P.shot('03-needs-files');
  await P.key('ArrowDown'); P.same(P.id(), 'primary', 'down reaches the keys'); await P.shot('04-key-focus');
  await P.press('right'); P.same(P.id(), 'options', 'options'); await P.press('right'); P.same(P.id(), 'heart', 'heart'); await P.press('a');
  P.ok(oort.library.games.find(g => g.name === 'Lunar Observatory').favorite, 'favorite kept'); P.same(P.id(), 'heart', 'the focus stays on the heart');
  await P.press('b'); P.ok(document.activeElement.matches('.tile'), 'B comes back to the shelf');
  await P.press('x'); await P.until(() => document.querySelector('.detail')); await P.wait(300); await P.shot('05-detail');
  await P.press('b'); await P.until(() => oort.layers.length === 1); P.ok(document.activeElement.matches('.tile'), 'the focus is back on its tile');
  // Grid.
  await P.press('view'); await P.until(() => document.querySelector('.grid')); await P.wait(300); await P.shot('06-grid'); await P.press('right', 3); await P.press('down', 1); await P.shot('07-grid-moved');
  P.ok(document.activeElement.matches('.grid .tile'), 'the grid moves'); await P.press('view');
  // Search.
  await P.press('y'); await P.until(() => document.querySelector('.find input')); P.ok(document.activeElement.matches('input'), 'search is ready to type');
  const q = document.querySelector('.find input'); q.value = 'harb'; q.dispatchEvent(new Event('input')); await P.until(() => document.querySelectorAll('.found .tile').length === 2); await P.shot('08-search');
  await P.press('b');
  // Sort.
  await P.press('rs'); await P.until(() => document.querySelector('.dialog')); await P.shot('09-sort'); await P.press('b');
  // Settings, two levels.
  await P.settings(); await P.shot('10-settings');
  const zoom0 = getComputedStyle(document.documentElement).getPropertyValue('--zoom');
  await P.press('down'); P.same(document.querySelector('.col h1').textContent, document.documentElement.lang === 'fr' ? 'Apparence' : 'Appearance', 'the side list turns the page');
  await P.press('right'); P.same(P.id(), 'colorThemeID', 'right enters the rows'); await P.press('down'); P.same(P.id(), 'interfaceZoom', 'the size'); await P.press('right', 2);
  P.ok(getComputedStyle(document.documentElement).getPropertyValue('--zoom') !== zoom0, 'the size is tried at once'); P.ok(document.querySelector('.draft'), 'the draft bar shows'); await P.shot('11-appearance-draft');
  await P.press('down'); await P.press('a'); await P.until(() => document.querySelector('.col h1').textContent === (document.documentElement.lang === 'fr' ? 'Avancé' : 'Advanced')); P.ok(document.activeElement.closest('.list'), 'the second level has the focus'); await P.shot('12-second-level');
  await P.press('b'); P.same(P.id(), 'sub-look', 'B comes back to its row'); await P.press('b'); await P.press('b'); await P.until(() => document.querySelector('.dialog')); await P.shot('13-save'); await P.press('right', 1); await P.press('a'); await P.until(() => oort.layers.length === 1);
  P.same(getComputedStyle(document.documentElement).getPropertyValue('--zoom'), zoom0, 'discarding puts the size back');
  await P.settings(); for (const [i, n] of [[2, 'sound'], [3, 'controllers'], [4, 'account'], [5, 'home'], [7, 'integrations'], [8, 'about']]) { document.querySelectorAll('.side button')[i].click(); await P.wait(250); await P.shot('14-' + n); }
  await P.press('b'); while (oort.layers.length > 1) await P.press('b');
  // Projects, adding.
  await P.press('lt'); await P.press('a'); await P.until(() => document.querySelector('.sheet')); await P.wait(200); await P.shot('15-projects'); P.same(document.querySelectorAll('.sheet .row').length, (await oort.ask('catalog')).length, 'every project is listed'); await P.press('b');
  await P.press('right'); await P.press('a'); await P.until(() => document.querySelector('.sheet')); await P.shot('16-add'); document.querySelector('.sheet [data-id=program]').click(); await P.until(() => document.querySelectorAll('.sheet').length > 1); await P.shot('17-program'); while (oort.layers.length > 1) await P.press('b');
  await goTo('Damaged'); await P.shot('18-damaged'); await goTo('Lunar Observatory'); await P.key('ArrowDown'); await P.press('right'); await P.press('a'); await P.until(() => document.querySelector('.shell')); await P.press('down'); await P.shot('19-game-options'); await P.press('b');
  // Nothing on the page is cut or leaves the window.
  P.ok(document.documentElement.scrollWidth <= innerWidth, 'nothing leaves the window');
});
