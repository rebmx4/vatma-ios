import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

test('desktop retries an early element resize when the WebKit viewport catches up', () => {
  const window = new EventTarget();
  window.innerHeight = 166;
  let observerCallback, observed, disconnected = false;
  class ResizeObserver {
    constructor(callback) { observerCallback = callback; }
    observe(target) { observed = target; }
    disconnect() { disconnected = true; }
  }
  const context = vm.createContext({ window, ResizeObserver });
  const source = fs.readFileSync(new URL('../BrowserUI/desktop-viewport.js', import.meta.url), 'utf8');
  vm.runInContext(source.replace(/\bexport (?=function)/g, ''), context);
  const desktop = {};
  let rendered = 0;
  const dispose = context.observeDesktopViewport(desktop, () => {
    if (window.innerHeight === 812) rendered++;
  });
  assert.equal(observed, desktop);
  observerCallback();
  assert.equal(rendered, 0, 'the element can resize while window.innerHeight still has the footer height');
  window.innerHeight = 812;
  window.dispatchEvent(new Event('resize'));
  assert.equal(rendered, 1, 'the final viewport resize must retry the deferred desktop render');
  dispose();
  window.dispatchEvent(new Event('resize'));
  assert.equal(rendered, 1);
  assert.equal(disconnected, true);
});
