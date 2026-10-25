import test from 'node:test';
import assert from 'node:assert/strict';
import { once, EventEmitter } from 'node:events';
import http from 'node:http';
import { createLocalApp } from '../local/app.mjs';

test('local API rejects cross-site and tokenless mutations before invoking the controller', async t => {
  const controller = Object.assign(new EventEmitter(), {
    snapshot: () => ({ phase: 'idle', connected: false }),
    start() { throw new Error('must not reach controller'); },
  });
  const app = createLocalApp({ controller });
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  t.after(() => app.close());
  const base = `http://127.0.0.1:${app.server.address().port}`;
  assert.equal((await fetch(base + '/api/start', { method: 'POST', headers: { origin: 'https://evil.test' } })).status, 403);
  assert.equal((await fetch(base + '/api/start', { method: 'POST', headers: { origin: base } })).status, 403);
  const rebound = await new Promise(resolve => {
    const request = http.get(base + '/api/state', { headers: { host: 'evil.test' } }, response => { response.resume(); resolve(response.statusCode); });
    request.on('error', error => { throw error; });
  });
  assert.equal(rebound, 403);
  assert.equal((await fetch(base + '/api/state')).status, 200);
});
