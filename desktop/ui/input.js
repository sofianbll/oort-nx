/* What the player has in hand, and how a wheel or a finger moves the shelf. No page here: tests/nav.test.mjs. */

/* The last thing used: keys, pad, mouse or touch. A knock on the mouse is not a use: it takes a real movement. */
const REACH = 12, PAUSE = 500;
export const handOf = changed => {
  let moved = 0, at = -PAUSE;
  const to = next => { moved = 0; hand.uses++; if (next !== hand.now) { hand.now = next; changed(next); } };
  const hand = {
    now: 'keys', uses: 0,
    keys: () => to('keys'), pad: () => to('pad'),
    down: e => to(e.pointerType === 'touch' ? 'touch' : 'mouse'),
    /* A press, told once it is over; what came since has the last word. */
    lifted: (e, later) => { const uses = hand.uses; later(() => { if (hand.uses === uses) hand.down(e); }); },
    move: e => {
      if (e.pointerType !== 'mouse') return;
      if (e.timeStamp - at > PAUSE) moved = 0;
      at = e.timeStamp; moved += Math.abs(e.movementX) + Math.abs(e.movementY);
      if (moved >= REACH) to('mouse');
    },
  };
  return hand;
};

/* A notch of a wheel is one step; a touchpad's small pushes add up, and start again the other way or after a pause. */
const NOTCH = 80, REST = 300, LINE = 40, PAGE = 400;
export const stepper = act => {
  let sum = 0, at = -REST;
  return e => {
    const unit = [1, LINE, PAGE][e.deltaMode || 0] ?? 1, d = (Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY) * unit;
    if (e.timeStamp - at > REST || Math.sign(d) !== Math.sign(sum)) sum = 0;
    at = e.timeStamp;
    if (Math.abs(d) >= NOTCH) { sum = 0; return act(Math.sign(d)); }
    for (sum += d; Math.abs(sum) >= NOTCH; sum -= Math.sign(sum) * NOTCH) act(Math.sign(sum));
  };
};

/* One finger: a step for each tile's width it travels. `up` tells a swipe from a tap. */
export const swiper = (act, pitch) => {
  let finger = null, from = 0, swiped = false;
  return {
    down(x, id) { finger = id; from = x; swiped = false; },
    move(x, id) { if (id !== finger) return; for (const size = pitch(); Math.abs(x - from) >= size;) { const d = Math.sign(from - x); from -= d * size; swiped = true; act(d); } },
    up(id) { if (id === finger) finger = null; return swiped; },
  };
};
