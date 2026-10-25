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

test('the session time limit includes startup instead of adding another hour after the build', () => {
  let now = 10000;
  const state = new ConnectionState(() => now); state.start('iphone');
  now += 300000;
  state.health({ deadline: now + 3600000 }); state.control(true); state.frame(1); state.paint(1);
  assert.equal(state.snapshot().deadline, 3610000);
  assert.equal(state.snapshot().connected, true);
  now = 3610001;
  state.health({ deadline: now + 3600000 }); state.frame(2); state.paint(2);
  assert.equal(state.snapshot().connected, false);
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

test('temporary cancellation API failure retains ownership and blocks a second Mac until cleanup succeeds', async () => {
  let dispatchRelease, retryRelease, failed = false, cancelled = false;
  const run = { id: 321, status: 'queued' };
  const github = {
    source: async () => 'd'.repeat(40),
    dispatch: async () => { await new Promise(resolve => { dispatchRelease = resolve; }); },
    findRun: async () => { if (!failed) { failed = true; throw new Error('Temporary API outage'); } return run; },
    run: async () => ({ ...run, status: cancelled ? 'completed' : 'queued' }),
    cancel: async () => { cancelled = true; },
  };
  const controller = new Controller(github, { delay: () => new Promise(resolve => { retryRelease = resolve; }) });
  controller.start('iphone');
  while (!dispatchRelease) await new Promise(resolve => setImmediate(resolve));
  const stopped = controller.stop(); dispatchRelease();
  while (!failed) await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(controller.current, 'must retain the exact owned session until stopped');
  assert.equal(controller.snapshot().phase, 'stopping');
  assert.throws(() => controller.start('ipad'), /остановки/);
  retryRelease(); await stopped;
  assert.equal(cancelled, true); assert.equal(controller.current, null);
});
