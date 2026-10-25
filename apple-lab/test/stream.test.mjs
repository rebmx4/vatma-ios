import test from 'node:test';
import assert from 'node:assert/strict';
import { JpegFrames } from '../shared/stream.mjs';

test('MJPEG parser emits complete JPEGs across arbitrary network chunk boundaries', () => {
  const frames = [];
  const parser = new JpegFrames(frame => frames.push([...frame]));
  for (const chunk of [[45, 45, 13, 255], [216, 1, 2, 255], [217, 13, 255, 216, 3], [255, 217]]) parser.push(Buffer.from(chunk));
  assert.deepEqual(frames, [[255, 216, 1, 2, 255, 217], [255, 216, 3, 255, 217]]);
});

test('oversized unfinished frames fail instead of growing memory indefinitely', () => {
  const parser = new JpegFrames(() => {}, 8);
  assert.throws(() => parser.push(Buffer.from([255, 216, ...Array(10).fill(0)])), /large/i);
});
