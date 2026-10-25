const encoder = new TextEncoder();
const clamp = value => Math.max(0, Math.min(1, value));
export function deviceInput(canvas, { connected, send, paste }) {
  function packet(tag, value) {
    const body = value == null ? new Uint8Array() : encoder.encode(JSON.stringify(value));
    const data = new Uint8Array(body.length + 1); data[0] = tag; data.set(body, 1); send(data);
  }
  function point(event) {
    const rect = canvas.getBoundingClientRect();
    return { x: clamp((event.clientX - rect.left) / rect.width), y: clamp((event.clientY - rect.top) / rect.height) };
  }
  let pointer = null, multi = false, lastMove = 0;
  function touch(type, p) {
    if (!connected()) return;
    packet(multi ? 5 : 3, multi ? { type, x1: p.x, y1: p.y, x2: 1 - p.x, y2: 1 - p.y } : { type, ...p });
  }
  canvas.addEventListener('pointerdown', event => {
    if (!connected() || pointer != null) return;
    event.preventDefault(); canvas.focus(); canvas.setPointerCapture(event.pointerId);
    pointer = event.pointerId; multi = event.altKey; touch('begin', point(event));
  });
  canvas.addEventListener('pointermove', event => {
    if (pointer !== event.pointerId || performance.now() - lastMove < 25) return;
    lastMove = performance.now(); touch('move', point(event));
  });
  for (const name of ['pointerup', 'pointercancel']) canvas.addEventListener(name, event => {
    if (pointer !== event.pointerId) return;
    touch('end', point(event)); pointer = null;
  });
  canvas.addEventListener('contextmenu', event => event.preventDefault());
  let scrolling = false;
  canvas.addEventListener('wheel', event => {
    if (!connected()) return; event.preventDefault();
    if (scrolling || pointer != null) return;
    scrolling = true; multi = false;
    const p = point(event), distance = Math.max(-.45, Math.min(.45, event.deltaY / 800));
    touch('begin', p);
    let step = 0;
    const timer = setInterval(() => {
      step++; touch(step === 6 ? 'end' : 'move', { x: p.x, y: clamp(p.y - distance * step / 6) });
      if (step === 6) { clearInterval(timer); scrolling = false; }
    }, 20);
  }, { passive: false });
  const usages = { Enter: 40, Escape: 41, Backspace: 42, Tab: 43, Space: 44, Minus: 45, Equal: 46,
    BracketLeft: 47, BracketRight: 48, Backslash: 49, Semicolon: 51, Quote: 52, Backquote: 53, Comma: 54,
    Period: 55, Slash: 56, Delete: 76, ArrowRight: 79, ArrowLeft: 80, ArrowDown: 81, ArrowUp: 82,
    ControlLeft: 227, ControlRight: 231, ShiftLeft: 225, ShiftRight: 229, AltLeft: 226, AltRight: 230, MetaLeft: 227, MetaRight: 231 };
  for (let n = 0; n < 26; n++) usages['Key' + String.fromCharCode(65 + n)] = 4 + n;
  for (let n = 1; n < 10; n++) usages['Digit' + n] = 29 + n;
  usages.Digit0 = 39;
  for (const name of ['keydown', 'keyup']) canvas.addEventListener(name, event => {
    if (!connected() || event.isComposing) return;
    if ((event.ctrlKey || event.metaKey) && event.code === 'KeyV') {
      event.preventDefault(); if (name === 'keydown') paste(); return;
    }
    const usage = usages[event.code]; if (usage == null) return;
    event.preventDefault(); packet(6, { type: name === 'keydown' ? 'down' : 'up', usage });
  });
  canvas.addEventListener('blur', () => {
    if (connected()) for (const usage of [225, 229, 226, 230, 227, 231]) packet(6, { type: 'up', usage });
  });
  return { home: () => packet(4, { button: 'home' }), rotate: orientation => packet(7, { orientation }) };
}
