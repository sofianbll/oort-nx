/* A mouse and a finger for a script, through the debugging port: the browser's own events, nothing of the machine's. */
export const hands = (send, wait) => {
  const mouse = (type, x, y, more = {}) => send('Input.dispatchMouseEvent', { type, x, y, ...more }), touch = (type, points) => send('Input.dispatchTouchEvent', { type, touchPoints: points });
  return {
    move: (x, y) => mouse('mouseMoved', x, y),
    click: async (x, y, button = 'left') => { await mouse('mouseMoved', x, y); await mouse('mousePressed', x, y, { button, clickCount: 1 }); await mouse('mouseReleased', x, y, { button, clickCount: 1 }); },
    wheel: (x, y, deltaX, deltaY) => mouse('mouseWheel', x, y, { deltaX, deltaY }),
    swipe: async (x, y, to, steps = 12) => { const at = i => [{ x: x + (to - x) * i / steps, y }]; await touch('touchStart', at(0)); for (let i = 1; i <= steps; i++) { await touch('touchMove', at(i)); await wait(12); } await touch('touchEnd', []); },
    tap: async (x, y) => { await touch('touchStart', [{ x, y }]); await wait(40); await touch('touchEnd', []); },
  };
};
