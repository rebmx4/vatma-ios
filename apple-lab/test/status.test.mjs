import test from 'node:test';
import assert from 'node:assert/strict';
import { createPublisher } from '../remote/status.mjs';

const config = { repo: 'owner/repo', sha: 'a'.repeat(40), session: 'b'.repeat(32), token: 'test-only', delay: async () => {}, warn: () => {} };
test('a progress network failure cannot abort startup; publishing readiness retries transient failures', async () => {
  let calls = 0;
  const sender = createPublisher({ ...config, fetchImpl: async () => {
    calls++; if (calls <= 2) throw Object.assign(new TypeError('fetch failed'), { cause: { code: 'ECONNRESET' } });
    return new Response('{}', { status: 201 });
  } });
  await sender.progress('stream');
  await sender.publish('success', 'Simulator ready', 'https://test.trycloudflare.com');
  assert.equal(calls, 3);
});
test('readiness stops after bounded failures and never retries a permanent permission error', async () => {
  let calls = 0;
  const network = createPublisher({ ...config, fetchImpl: async () => { calls++; throw new Error('offline'); } });
  await assert.rejects(network.publish('success', 'ready'), /publish/); assert.equal(calls, 3);
  calls = 0;
  const forbidden = createPublisher({ ...config, fetchImpl: async () => { calls++; return new Response('{}', { status: 403 }); } });
  await assert.rejects(forbidden.publish('success', 'ready'), /403/); assert.equal(calls, 1);
});
