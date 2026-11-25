/* A later start: what first.js left is there. */
probe(async P => {
  P.ok(oort.library.games.length > 20, 'the games are still there: ' + oort.library.games.length);
  P.same(oort.library.games.filter(g => g.favorite).length, 1, 'and the favorite');
  await P.shot('again');
});
