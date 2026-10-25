import test from 'node:test';
import assert from 'node:assert/strict';
import { helperOrigin } from '../remote/discovery.mjs';

test('serve-sim single-object and multiple-stream envelopes resolve the selected device', () => {
  const stream = { device: 'device-one', port: 3100, pid: 100, url: 'http://localhost:3100', streamUrl: 'http://localhost:3100/stream.mjpeg', wsUrl: 'ws://localhost:3100/ws' };
  assert.equal(helperOrigin({ running: true, ...stream }, 'device-one'), 'http://127.0.0.1:3100');
  const second = { ...stream, device: 'device-two', port: 3101, url: 'http://localhost:3101', streamUrl: 'http://localhost:3101/stream.mjpeg', wsUrl: 'ws://localhost:3101/ws' };
  assert.equal(helperOrigin({ running: true, streams: [stream, second] }, 'device-two'), 'http://127.0.0.1:3101');
  assert.throws(() => helperOrigin({ running: false }, 'device-one'), /stream/i);
  assert.throws(() => helperOrigin({ running: true, ...stream }, 'wrong-device'), /stream/i);
  const routed = { running: true, ...stream, streamUrl: 'http://127.0.0.1:3100/helper/device-one/stream.mjpeg', wsUrl: 'ws://127.0.0.1:3100/helper/device-one/ws' };
  assert.equal(helperOrigin(routed, 'device-one'), 'http://127.0.0.1:3100/helper/device-one');
});
