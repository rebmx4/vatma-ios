import test from 'node:test';
import assert from 'node:assert/strict';
import {selectAddressOnFirstTap} from '../BrowserUI/address-selection.js';

class AddressInput extends EventTarget {
  constructor(value) {
    super();
    this.value = value;
    this.ownerDocument = {activeElement: null};
    this.selection = [0, 0];
  }
  select() { this.selection = [0, this.value.length]; }
  focus() {
    if (this.ownerDocument.activeElement === this) return;
    this.ownerDocument.activeElement = this;
    this.dispatchEvent(new Event('focus'));
  }
}

function event(type, props) {
  return Object.assign(new Event(type, {cancelable: true}), props);
}

function setup(value) {
  const input = new AddressInput(value);
  const clear = new EventTarget();
  const frames = new Map();
  let id = 0;
  const oldRequest = globalThis.requestAnimationFrame;
  const oldCancel = globalThis.cancelAnimationFrame;
  globalThis.requestAnimationFrame = fn => { frames.set(++id, fn); return id; };
  globalThis.cancelAnimationFrame = id => frames.delete(id);
  selectAddressOnFirstTap(input, clear);
  return {
    input, clear,
    flush() { const callbacks = [...frames.values()]; frames.clear(); callbacks.forEach(fn => fn()); },
    restore() {
      globalThis.requestAnimationFrame = oldRequest;
      globalThis.cancelAnimationFrame = oldCancel;
    }
  };
}

function tap(input, x, at) {
  input.dispatchEvent(event('pointerdown', {button: 0, pointerType: 'touch'}));
  input.focus();
  input.selection = [x, x]; // The browser applies its normal caret positioning.
  input.dispatchEvent(event('pointerup', {pointerType: 'touch'}));
  const click = event('click', {detail: 1, clientX: x, clientY: 0});
  Object.defineProperty(click, 'timeStamp', {value: at});
  input.dispatchEvent(click);
}

test('the first tap selects the URL, a second places the caret, and a double tap selects all again', t => {
  const {input, flush, restore} = setup('https://example.com/upload');
  t.after(restore);
  tap(input, 4, 10);
  input.selection = [4, 4]; // WebKit may place the caret after dispatching click.
  flush();
  assert.deepEqual(input.selection, [0, input.value.length]);
  tap(input, 11, 110);
  flush();
  assert.deepEqual(input.selection, [11, 11]);

  tap(input, 9, 610);
  tap(input, 10, 760);
  flush();
  assert.deepEqual(input.selection, [0, input.value.length]);
});

test('the clear button empties the address, keeps focus and emits an input event', t => {
  const {input, clear, flush, restore} = setup('https://example.com/');
  t.after(restore);
  input.focus();
  let inputs = 0;
  input.addEventListener('input', () => inputs++);
  assert.equal(clear.dispatchEvent(event('pointerdown')), false);
  clear.dispatchEvent(event('click'));
  flush();
  assert.equal(input.value, '');
  assert.equal(input.ownerDocument.activeElement, input);
  assert.equal(inputs, 1);
});
