import test from 'node:test';
import assert from 'node:assert/strict';
import { ConnectionState } from '../local/state.mjs';
import { Controller } from '../local/controller.mjs';

test('green requires a rendered recent frame, healthy remote and an open control channel', () => {
  let now = 10000;
  const state = new ConnectionState(() => now);
  state.start('iphone');
  state.health({ config: { width: 1320, height: 2868 }, deadline: 90000 });
  assert.equal(state.snapshot().connected, false);
  state.control(true); state.frame(1);
  assert.equal(state.snapshot().connected, false);
  state.paint(1);
  assert.equal(state.snapshot().connected, true);
  state.control(false);
  assert.equal(state.snapshot().connected, false);
});

test('stale frames, missing rendered acknowledgements and disconnect all turn green off', () => {
  let now = 10000;
  const state = new ConnectionState(() => now);
  state.start('ipad'); state.control(true); state.health({ deadline: 90000 }); state.frame(2); state.paint(999);
  assert.equal(state.snapshot().connected, false);
  state.paint(2); assert.equal(state.snapshot().connected, true);
  now += 8100; assert.equal(state.snapshot().connected, false);
  state.health({ deadline: 90000 }); state.frame(3); state.paint(3);
  assert.equal(state.snapshot().connected, true);
  state.stop(); assert.equal(state.snapshot().connected, false);
});

test('disconnect during dispatch still discovers and cancels only the owned queued run', async () => {
  let resolveDispatch, dispatched = false, cancelled = false;
  const run = { id: 123, status: 'queued', html_url: 'https://github.com/owner/repo/actions/runs/123' };
  const github = {
    source: async () => 'd'.repeat(40),
    dispatch: async s => { dispatched = true; run.display_title = `Apple Lab · ${s.id} · ${s.device}`; await new Promise(resolve => { resolveDispatch = resolve; }); },
    findRun: async () => run,
    run: async () => ({ ...run, status: cancelled ? 'completed' : 'queued' }),
    cancel: async s => { assert.equal(s.run.id, 123); cancelled = true; },
  };
  const controller = new Controller(github, { delay: async () => {} });
  controller.start('ipad');
  while (!dispatched) await new Promise(resolve => setImmediate(resolve));
  const stopped = controller.stop();
  assert.equal(controller.snapshot().connected, false);
  assert.equal(controller.snapshot().active, false);
  resolveDispatch(); await stopped;
  assert.equal(cancelled, true); assert.equal(controller.snapshot().phase, 'idle');
  controller.start('iphone'); resolveDispatch(); await controller.stop();
});
