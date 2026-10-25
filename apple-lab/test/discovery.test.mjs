import test from 'node:test';
import assert from 'node:assert/strict';
import { helperOrigin } from '../remote/discovery.mjs';

test('serve-sim single-object and multiple-stream envelopes resolve the selected device', () => {
  const stream = { device: 'device-one', port: 3100, pid: 100, url: 'http://localhost:3100', streamUrl: 'http://localhost:3100/stream.mjpeg', wsUrl: 'ws://localhost:3100/ws' };
  assert.equal(helperOrigin({ running: true, ...stream }, 'device-one'), 'http://127.0.0.1:3100');
  assert.equal(helperOrigin({ running: true, streams: [stream, { ...stream, device: 'device-two', port: 3101 }] }, 'device-two'), 'http://127.0.0.1:3101');
  assert.throws(() => helperOrigin({ running: false }, 'device-one'), /stream/i);
  assert.throws(() => helperOrigin({ running: true, ...stream }, 'wrong-device'), /stream/i);
});
