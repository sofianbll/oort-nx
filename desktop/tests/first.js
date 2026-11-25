probe(async P => {
  P.same(document.documentElement.dataset.ready, '1', 'the window is ready');
  await P.wait(2200); await P.shot('empty');
  await oort.ask('folders.add', { path: RUN + '/games' });
  location.reload; dispatchEvent(new Event('focus')); await P.wait(800); await P.shot('home');
});
