/* The first start after the update from alpha.1: everything is there, the first steps do not come back by force. */
probe(async P => {
  const game = () => oort.library.games.find(g => /Lamp Keeper|lb_x64/.test(g.name));
  // The word about what is new was seen by drive.mjs, at the very first start (`expect`).
  await P.wait(600); P.ok(!document.querySelector('.steps'), 'the first steps stay away'); P.ok(!document.querySelector('.dialog'), 'what is new is said once');
  P.ok(oort.library.games.length > 20, 'the games are there: ' + oort.library.games.length); const g = game(); P.same([g.favorite, g.seconds > 0, g.mark], [true, true, true], 'favorite, time, and now its icon'); P.same(g.name, 'Lamp Keeper', 'and its own name');
  P.same(document.documentElement.dataset.palette, 'nord', 'the settings are kept'); await oort.ask('settings.set', { id: 'colorThemeID', value: 'oort' }); await oort.ask('settings.save');
  const i = oort.library.games.indexOf(g) + 2; await P.press('lt'); for (let k = 0; k < i; k++) { oort.act('right'); await P.wait(25); } await P.wait(600); await P.shot('91-updated'); P.same([(await oort.ask('steam')).on, (await oort.ask('online')).on], [false, false], 'nothing new is turned on by itself');
});
