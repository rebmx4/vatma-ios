import test from 'node:test';
import assert from 'node:assert/strict';
import {selectAddressOnFirstTap} from '../BrowserUI/address-selection.js';

class AddressInput extends EventTarget {
  constructor(value) {
    super();
    this.value = value;
    this.ownerDocument = {activeElement: null};
    this.selected = 0;
  }
  select() { this.selected++; }
  fire(type) { this.dispatchEvent(new Event(type)); }
}

test('first address tap selects the existing URL; second tap can place the caret', () => {
  const input = new AddressInput('https://vk.com/video');
  selectAddressOnFirstTap(input);
  input.fire('pointerdown');
  input.ownerDocument.activeElement = input;
  input.fire('focus');
  input.fire('click');
  assert.equal(input.selected, 2, 'selection survives the first click after focus');
  input.fire('pointerdown');
  input.fire('click');
  assert.equal(input.selected, 2, 'second tap leaves native caret placement alone');
});

test('blank fields stay blank and keyboard focus selects existing text', () => {
  const input = new AddressInput('');
  selectAddressOnFirstTap(input);
  input.fire('focus');
  assert.equal(input.selected, 0);
  input.value = 'https://dzen.ru/';
  input.fire('blur');
  input.fire('focus');
  assert.equal(input.selected, 1);
});
