/* Steam gone and no network: what was known is shown, nothing complains. */
probe(async P => {
  P.ok(!document.querySelector('.dialog,.steps'), 'nothing to answer'); P.same((await oort.ask('online')).on, true, 'information online is on'); const lamp = oort.library.games.find(g => /Lamp Keeper|lb_x64/.test(g.name)); P.ok(lamp, 'the program is there'); P.ok((await oort.ask('game', { id: lamp.id })).about || window.SYSTEM !== 'windows', 'and what was found of it'); P.same((await oort.ask('steam')).found, false, 'Steam is gone'); P.same(oort.library.games.filter(g => g.kind === 'steam').length, 0, 'and its games with it');
  let got = ''; try { await window.__TAURI__.core.invoke('online_search', { id: lamp.id, text: 'Anything' }); } catch (e) { got = String(e); } P.same(got, 'online', 'a search says there is no answer'); await P.wait(1500); P.ok(!document.querySelector('.dialog'), 'and nothing else'); await P.shot('95-offline');
});
