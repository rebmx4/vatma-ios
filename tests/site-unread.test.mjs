import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../BrowserUI/assets/site-unread.js', import.meta.url), 'utf8');
const link = ({href, text = 'Сообщения', badge, nav = true, ariaLabel = null}) => ({
  textContent: text,
  getAttribute: name => name === 'href' ? href : name === 'aria-label' ? ariaLabel : null,
  closest: () => nav ? {} : null,
  querySelectorAll: () => badge === undefined ? [] : [{
    textContent: String(badge), className: 'message-counter',
    getAttribute: () => null,
  }],
});
function detect(url, links) {
  const context = {location: new URL(url), URL, document: {querySelectorAll: () => links}};
  return vm.runInNewContext(source, context);
}

test('reads only a message navigation badge and never returns page content', () => {
  const value = detect('https://m.vk.com/feed', [
    link({href: '/notifications', text: 'Новости 91', badge: 91}),
    link({href: '/im', badge: 4}),
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(value)), {provider: 'vk', count: 4});
});

test('accepts the current VK vk.ru domain', () => {
  const value = detect('https://m.vk.ru/feed', [link({href: '/im', badge: 3})]);
  assert.equal(value.count, 3);
});

test('reads Avito message count but ignores an individual conversation', () => {
  const value = detect('https://www.avito.ru/', [
    link({href: '/profile/messenger?chat=secret', badge: 50}),
    link({href: '/profile/messenger', badge: 2}),
  ]);
  assert.equal(value.count, 2);
});

test('returns unknown for an unsupported host or absent message navigation', () => {
  assert.equal(detect('https://vk.com.evil.example/', [link({href: '/im', badge: 7})]), null);
  assert.equal(detect('https://m.vk.com/feed', [link({href: '/notifications', badge: 7})]), null);
});

test('zero means the message navigation exists with no badge', () => {
  const value = detect('https://vk.com/', [link({href: '/im'})]);
  assert.equal(value.count, 0);
});
