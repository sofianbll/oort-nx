/* The first steps, whole: by the keyboard, then again by the controller; stopped and taken up; skipped; then what they
   left. With an invented Steam and invented services. GUIDE=true keeps the steps open. */
window.GUIDE = true;
probe(async P => {
  const ask = oort.ask, title = () => P.text('.steps h1'), at = () => P.text('.steps .count'), step = async (n, what) => { await P.until(() => at() === `${n} / 5`, 8000, what); await P.wait(250); };
  const fits = what => { const s = document.querySelector('.steps'), k = document.querySelector('.steps .keys').getBoundingClientRect(), bar = document.querySelector('#hints').getBoundingClientRect(); P.ok(k.bottom <= Math.min(innerHeight, bar.height ? bar.top + 2 : innerHeight) && s.getBoundingClientRect().top >= -1 && document.documentElement.scrollWidth <= innerWidth, `${what}: all of it is on the screen`); };
  await step(1, 'the first steps open by themselves'); P.same(P.id(), 'continue', 'Continue has the focus'); await P.shot('50-welcome'); fits('welcome');
  // The language changes at once, and back.
  await P.press('up'); P.same(P.id(), 'appLanguage', 'up reaches the language'); const before = title(); await P.press('right'); await P.until(() => title() !== before || document.documentElement.lang === 'en', 4000, 'the language changes'); await P.shot('51-language');
  while ((await ask('settings')).categories.flatMap(c => c.rows).find(r => r.id === 'appLanguage').value !== 'auto') { await P.press('right'); await P.wait(250); }
  await P.until(() => title() === before, 4000, 'and back'); P.same(P.id(), 'appLanguage', 'the focus stays'); await P.press('down'); P.same(P.id(), 'continue', 'down, to Continue'); await P.press('a');
  await step(2, 'the controller'); await P.shot('52-controller'); fits('controller');
  P.pad(); await P.until(() => document.querySelector('[data-id=pad]').textContent.includes('Xbox'), 4000, 'a controller is seen'); await P.until(() => document.querySelector('[data-id=pad] .dot'), 3000); await P.shot('53-controller-found'); P.same(P.id(), 'continue', 'the focus stays on Continue');
  await P.button(0); await step(3, 'A on the controller goes on'); await P.until(() => document.querySelector('.steps [data-id=steam] .sw'), 8000, 'Steam is found'); P.same(P.id(), 'continue', 'Continue has the focus there too'); await P.shot('54-games'); fits('games');
  P.ok(document.querySelector('.steps [data-id=steam]').textContent.includes('5'), 'five games: ' + document.querySelector('.steps [data-id=steam] .value').textContent); P.same((await ask('library')).total, 0, 'nothing is read before the player goes on');
  // A program, with the controller, from the steps.
  const row = id => document.querySelector(`.layer:not([hidden]):not([inert]) [data-id="${id}"]`);
  row('program').click(); await P.until(() => document.querySelector('.sheet [data-id=add]')); row('program').click(); await P.browse(RUN + '/programs');
  await P.until(() => P.rows().some(r => r.textContent.startsWith(P.program('lb_x64')) || r.querySelector('.what')?.firstChild.textContent === P.program('lb_x64'))); P.ok(!P.rows().some(r => r.textContent.includes('lamp.ico')) || window.SYSTEM !== 'windows', 'only programs are listed'); await P.shot('55-program-picker');
  P.rows().find(r => r.querySelector('.what').firstChild.textContent === P.program('lb_x64')).click(); await P.until(() => row('add')); await P.wait(300); await P.shot('56-program');
  if (window.SYSTEM === 'windows') P.ok(row('name').textContent.includes('Lamp Keeper'), 'its own name is offered: ' + row('name').textContent);
  row('add').click(); await step(3, 'back in the steps'); P.same((await ask('library')).total, 1, 'the program is in'); await P.shot('57-games-one');
  // Stopped here: the steps open again at this page.
  P.same((await ask('guide')).page, 'games', 'the place is kept'); P.same((await ask('guide')).open, true, 'and they are still open');
  row('continue').focus(); await P.button(0); await step(4, 'online'); await P.shot('58-online'); fits('online'); P.same((await ask('library')).total, 6, 'Steam’s five games are in'); P.same((await ask('online')).on, false, 'nothing goes out before the answer');
  P.ok(/Wikidata/.test(P.text('.steps .lead')) && /Steam/.test(P.text('.steps .lead')), 'what is sent is written there');
  await P.button(1); await step(3, 'B goes back'); await P.until(() => document.querySelector('.steps [data-id=steam] .sw')); P.same(document.querySelector('.steps [data-id=steam]').getAttribute('aria-checked'), 'true', 'the choice is kept'); row('continue').focus(); await P.button(0); await step(4, 'again');
  await P.button(15); P.same(P.id(), 'yes', 'right, to yes'); await P.button(0); await step(5, 'the end'); await P.shot('59-done'); fits('done'); P.same((await ask('online')).on, true, 'yes was kept');
  await P.button(0); await P.until(() => oort.layers.length === 1, 4000, 'the library opens'); PAD = null; await P.wait(600); await P.shot('60-library');
  P.same((await ask('guide')).open, false, 'the steps are over'); P.same(oort.library.games.length, 6, 'six games');
  // What was found online comes in by itself.
  await P.until(() => oort.library.games.find(g => g.name === 'Quiet Harbour' && !g.look), 60000, 'Quiet Harbour is found online');
  await P.until(() => { const g = oort.library.games.find(g => /Lamp Keeper|lb_x64/.test(g.name)); return g && !g.look; }, 60000, 'and the program'); await P.wait(1500); await P.shot('61-found');
  // Again from Settings, and skipped: nothing changes.
  await P.settings(); await P.until(() => document.querySelector('.shell [data-id=guide]')); document.querySelector('.shell [data-id=guide]').click(); await step(1, 'again from Settings'); await P.shot('62-again'); document.querySelector('[data-id=skip]').click(); await P.until(() => !document.querySelector('.steps') && document.querySelector('.shell')); P.same((await ask('library')).total, 6, 'nothing was lost'); while (oort.layers.length > 1) await P.press('b');
});
