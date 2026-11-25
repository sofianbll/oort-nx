/* Plays what oort-core makes (OortSynth, PCM): no sound is made or stored here. */
export const sounds = ask => {
  let ac, out, on = true, volume = .6, pack = 'oort', figure = 'rise', octave = 0, step = 0, at = 0;
  const cache = new Map();
  const boot = () => { const A = window.AudioContext || window.webkitAudioContext; if (!A) return null; if (!ac) { ac = new A(); out = ac.createGain(); out.gain.value = volume; out.connect(ac.destination); } if (ac.state === 'suspended') ac.resume().catch(() => {}); return ac; };
  const load = (event, i) => {
    const key = [pack, event, i, figure, octave].join();
    if (!cache.has(key)) {
      const get = ask('sound', { pack, event, step: i, figure, octave }).then(text => text && ac.decodeAudioData(Uint8Array.from(atob(text), c => c.charCodeAt(0)).buffer));
      cache.set(key, get.catch(() => null));
      if (cache.size > 120) cache.delete(cache.keys().next().value);
    }
    return cache.get(key);
  };
  const play = async (event, el, i = 0) => {
    if (!on || !boot()) return;
    const t0 = performance.now(), buffer = await load(event, i);
    // Late is worse than silent: a first load that took too long is kept for next time.
    if (!buffer || performance.now() - t0 > 180 && event === 'move') return;
    const s = ac.createBufferSource(), p = ac.createStereoPanner(), r = el && el.getBoundingClientRect && el.getBoundingClientRect();
    s.buffer = buffer; p.pan.value = r ? Math.max(-.6, Math.min(.6, (r.left + 20) / innerWidth * 1.4 - .7)) : 0;
    s.connect(p); p.connect(out); s.start(); api.played++;
  };
  const api = {
    played: 0, play,
    /* The note climbs a step per move, and starts again after a pause. */
    move(el) { const now = performance.now(); step = now - at < 900 ? (step + 1) % 8 : 0; at = now; play('move', el, step); },
    set(v) { const other = v.pack !== pack || v.figure !== figure || v.octave !== octave; on = v.sounds; volume = v.volume; pack = v.pack; figure = v.figure; octave = v.octave; if (out) out.gain.value = volume; if (other && ac) api.warm(); },
    warm() { if (on && boot()) { for (let i = 0; i < 8; i++) load('move', i); for (const e of ['select', 'back', 'confirm', 'open']) load(e, 0); } },
  };
  return api;
};
