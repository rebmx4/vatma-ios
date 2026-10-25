import test from 'node:test';
import assert from 'node:assert/strict';
import { sessionView } from '../public/session-view.mjs';
import { ConnectionState } from '../local/state.mjs';

test('startup shows the actual stage and elapsed time; stopping never asks the user to connect again', () => {
  const state = new ConnectionState(() => 10000); state.start('ipad'); state.progress('boot');
  const pending = sessionView(state.snapshot(), { now: 135000, live: false });
  assert.match(pending.title, /iOS/); assert.match(pending.timer, /2:05/);
  assert.match(pending.copy, /первый запуск/); assert.equal(pending.button, 'Отменить запуск');
  state.stop();
  const stopping = sessionView(state.snapshot(), { now: 136000, live: false });
  assert.match(stopping.title, /Завершаем/); assert.match(stopping.timer, /Остановка/);
  assert.doesNotMatch(stopping.copy, /нажмите|Выберите/);
});
