import test from 'node:test';
import assert from 'node:assert/strict';
import { displayGeometry, rawPoint, fitFrame } from '../public/orientation.mjs';

test('landscape rotates the raw framebuffer and maps displayed touches back to native coordinates', () => {
  assert.deepEqual(displayGeometry(1320, 2868, 'landscape_left'), { width: 2868, height: 1320, degrees: 90 });
  assert.deepEqual(rawPoint('landscape_left', .2, .3), { x: .3, y: .8 });
  assert.deepEqual(rawPoint('landscape_right', .2, .3), { x: .7, y: .2 });
  assert.deepEqual(rawPoint('portrait_upside_down', .2, .3), { x: .8, y: .7 });
});

test('device border does not stretch the screen aspect ratio', () => {
  assert.deepEqual(fitFrame(200, 100, 300, 120, 10), { width: 220, height: 120 });
});
