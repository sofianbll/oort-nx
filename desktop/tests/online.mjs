/* Invented public services, on this computer: what the Steam store, Wikidata and Wikipedia answer, for invented games,
   and the ways a service fails. Node 22, no package. usage: online.mjs <port> <log file>
   An address comes as /<host>/<path>. What a game's name makes it do: see `fails`. */
import { createServer } from 'node:http';
import { appendFileSync, writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

const [port, log] = process.argv.slice(2);
writeFileSync(log, '');
const crc = b => { let c = ~0; for (const x of b) { c ^= x; for (let k = 0; k < 8; k++) c = c & 1 ? c >>> 1 ^ 0xedb88320 : c >>> 1; } return ~c >>> 0; };
const png = (w, h, seed) => {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3, far = y > h * (.62 + .07 * Math.sin(x / w * 7 + seed)); raw[o] = far ? 22 + seed * 7 % 60 : 40 + 150 * y / h; raw[o + 1] = far ? 48 : 60 + 100 * y / h; raw[o + 2] = far ? 70 : 120 + seed * 13 % 90; }
  const chunk = (t, d) => { const b = Buffer.concat([Buffer.from(t), d]), n = Buffer.alloc(4), c = Buffer.alloc(4); n.writeUInt32BE(d.length); c.writeUInt32BE(crc(b)); return Buffer.concat([n, b, c]); };
  const head = Buffer.alloc(13); head.writeUInt32BE(w); head.writeUInt32BE(h, 4); head[8] = 8; head[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', head), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
};
const games = {
  991000100: { name: 'Lamp Keeper', about: { french: 'Une baie tranquille, ses lampes et un bateau à réparer. Un jeu inventé pour les essais d’Oort NX.', english: 'A quiet bay, its lamps and a boat to mend. A game invented for the trials of Oort NX.' }, genres: { french: ['Aventure', 'Indépendant'], english: ['Adventure', 'Indie'] }, date: '21 nov. 2023', by: 'Invented Works' },
  991000200: { name: 'Coast Runner', about: { french: 'Courir le long de la côte, de phare en phare.', english: 'Run along the coast, from light to light.' }, genres: { french: ['Course'], english: ['Racing'] }, date: '2 mai 2019', by: 'Small Waves' },
  991000201: { name: 'Coast Runner Soundtrack', type: 'music' },
  990000010: { name: 'Quiet Harbour', about: { french: 'Un port, la nuit, et le temps de le regarder.', english: 'A harbour at night, and time to look at it.' }, genres: { french: ['Détente'], english: ['Casual'] }, date: '3 juin 2021', by: 'Invented Works' },
  991000300: { name: 'Open Circuit', about: { french: 'Des images qui n’en sont pas.', english: 'Pictures that are none.' }, genres: { french: [], english: [] }, date: '2018', by: 'Small Waves', html: true },
};
const fails = { 'Broken Service': 'error', 'Slow Service': 'slow', 'Silent Service': 'silent', 'Cut Service': 'cut', 'Huge Service': 'huge', 'Moved Service': 'moved', 'Nonsense Service': 'nonsense' };
const wiki = { 'Tidal Works': 'Q99000001' };
const json = (r, value) => { r.writeHead(200, { 'Content-Type': 'application/json' }); r.end(JSON.stringify(value)); };

createServer((q, r) => {
  const url = new URL(q.url, 'http://x'), [, host, ...rest] = url.pathname.split('/'), path = '/' + rest.join('/'), p = url.searchParams;
  appendFileSync(log, JSON.stringify({ host, path, query: url.search, agent: q.headers['user-agent'], cookie: q.headers.cookie, language: q.headers['accept-language'], referer: q.headers.referer }) + '\n');
  const name = p.get('term') || p.get('search');
  switch (fails[name]) {
    case 'error': r.writeHead(500); return r.end('no');
    case 'slow': r.writeHead(429); return r.end();
    case 'silent': return;
    case 'cut': r.writeHead(200, { 'Content-Length': 900 }); r.write('{"items":['); return setTimeout(() => r.destroy(), 100);
    case 'huge': r.writeHead(200); { const b = Buffer.alloc(1 << 20, 32); const more = () => { for (let i = 0; i < 40; i++) if (!r.write(b)) return r.once('drain', more); r.end(); }; return more(); }
    case 'moved': r.writeHead(302, { Location: 'http://127.0.0.1:' + port + '/elsewhere/' }); return r.end();
    case 'nonsense': return r.end('<html>');
  }
  if (host === 'store.steampowered.com' && path.startsWith('/api/storesearch')) { const term = name.toLowerCase(); return json(r, { items: Object.entries(games).filter(([, g]) => g.name.toLowerCase().includes(term)).map(([id, g]) => ({ type: g.type || 'app', name: g.name, id: +id })) }); }
  if (host === 'store.steampowered.com' && path === '/api/appdetails') {
    const id = p.get('appids'), g = games[id], l = p.get('l');
    return json(r, { [id]: g?.about ? { success: true, data: { steam_appid: +id, name: g.name, short_description: g.about[l] || g.about.english, genres: (g.genres[l] || g.genres.english).map(description => ({ description })), developers: [g.by], publishers: [g.by], release_date: { date: g.date } } } : { success: false } });
  }
  const picture = /\/apps\/(\d+)\/(library_600x900|library_hero|logo)(_2x)?\.(jpg|png)$/.exec(path);
  if (host.endsWith('.steamstatic.com') && picture && games[picture[1]] && !picture[3] && picture[2] !== 'logo') {
    if (games[picture[1]].html) { r.writeHead(200, { 'Content-Type': 'image/jpeg' }); return r.end('<html>not a picture</html>'); }
    r.writeHead(200, { 'Content-Type': 'image/jpeg' });
    return r.end(picture[2] === 'library_hero' ? png(960, 310, +picture[1] % 97) : png(300, 450, +picture[1] % 97));
  }
  if (host === 'www.wikidata.org') {
    if (p.get('action') === 'wbsearchentities') return json(r, { search: wiki[name] ? [{ id: wiki[name], label: name }] : [] });
    if (p.get('action') === 'query') return json(r, { query: { search: [] } });
    if (p.get('ids') === 'Q99000001') return json(r, { entities: { Q99000001: { labels: { en: { value: 'Tidal Works' } }, claims: { P31: [{ mainsnak: { datavalue: { value: { id: 'Q7889' } } } }], P136: [{ mainsnak: { datavalue: { value: { id: 'Q99000002' } } } }], P577: [{ mainsnak: { datavalue: { value: { time: '+1998-11-21T00:00:00Z' } } } }] }, sitelinks: { frwiki: { title: 'Tidal Works' }, enwiki: { title: 'Tidal Works' } } } } });
    if (p.get('ids') === 'Q99000002') return json(r, { entities: { Q99000002: { labels: { fr: { value: 'jeu de réflexion' }, en: { value: 'puzzle game' } } } } });
  }
  if (host.endsWith('.wikipedia.org')) return json(r, { query: { pages: [{ extract: host.startsWith('fr') ? 'Tidal Works est un jeu inventé pour les essais d’Oort NX. On y construit des moulins à marée.' : 'Tidal Works is a game invented for the trials of Oort NX. You build tide mills in it.', fullurl: `https://${host}/wiki/Tidal_Works` }] } });
  r.writeHead(404); r.end();
}).listen(+port, '127.0.0.1', () => console.log('invented services on', port));
