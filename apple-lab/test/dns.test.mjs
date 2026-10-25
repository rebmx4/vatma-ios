import test from 'node:test';
import assert from 'node:assert/strict';
import { createTunnelLookup } from '../local/dns.mjs';
const lookup = (fn, host, options = {}) => new Promise((resolve, reject) => fn(host, options, (error, address, family) => error ? reject(error) : resolve({ address, family })));

test('tunnel DNS uses validated HTTPS answers, caches them and supports Node all-address requests', async () => {
  let calls = 0, now = 10000;
  const fn = createTunnelLookup({ now: () => now, resolve: async name => {
    calls++; return { Status: 0, Answer: [{ name, type: 1, TTL: 60, data: '104.16.230.132' }] };
  } });
  const host = 'test-session.trycloudflare.com';
  assert.deepEqual(await lookup(fn, host), { address: '104.16.230.132', family: 4 });
  assert.deepEqual((await lookup(fn, host, { all: true })).address, [{ address: '104.16.230.132', family: 4 }]);
  assert.equal(calls, 1); now += 61000; await lookup(fn, host); assert.equal(calls, 2);
});

test('a tunnel lookup refuses unrelated domains, DNS failures and private IP answers', async () => {
  const fn = createTunnelLookup({ resolve: async name => ({ Status: 0, Answer: [{ name, type: 1, TTL: 300, data: '127.0.0.1' }] }) });
  await assert.rejects(lookup(fn, 'evil.test'));
  await assert.rejects(lookup(fn, 'test-session.trycloudflare.com'));
  const failed = createTunnelLookup({ resolve: async () => ({ Status: 3 }) });
  await assert.rejects(lookup(failed, 'test-session.trycloudflare.com'));
});
