import test from 'node:test';
import assert from 'node:assert/strict';
import {messageProvider, messagesEnabled, enabledMessageProviders, shortcutMessageCount, badgeLabel} from '../BrowserUI/assets/message-badges.js';

test('only supported HTTPS provider hosts qualify', () => {
  assert.equal(messageProvider('https://m.vk.ru/feed'), 'vk');
  assert.equal(messageProvider('https://vk.com/'), 'vk');
  assert.equal(messageProvider('https://www.avito.ru/'), 'avito');
  assert.equal(messageProvider('https://vk.com.evil.example/'), null);
  assert.equal(messageProvider('http://vk.ru/'), null);
});

test('built-in social shortcuts are on by default and user can turn them off', () => {
  assert.equal(messagesEnabled({id: 'vk', url: 'https://vk.com/'}), true);
  assert.equal(messagesEnabled({id: 'vk', url: 'https://vk.com/', messageNotifications: false}), false);
  assert.equal(messagesEnabled({id: 'custom', url: 'https://m.vk.ru/', messageNotifications: true}), true);
  assert.equal(messagesEnabled({id: 'custom', url: 'https://dzen.ru/', messageNotifications: true}), false);
});

test('folder and ATMA totals count each provider once and private shortcuts stay hidden', () => {
  const folder = {id: 'social', children: [
    {id: 'vk', url: 'https://vk.com/'},
    {id: 'vk-other', url: 'https://m.vk.ru/', messageNotifications: true},
    {id: 'avito', url: 'https://avito.ru/'},
  ]};
  const counts = {vk: 2, avito: 4};
  assert.deepEqual(enabledMessageProviders([folder]), ['avito', 'vk']);
  assert.equal(shortcutMessageCount(folder, 'public', counts), 6);
  assert.equal(shortcutMessageCount({id: 'atma-home'}, 'public', counts), 6);
  assert.equal(shortcutMessageCount(folder, 'private', counts), 0);
  assert.equal(badgeLabel(125), '99+');
});
