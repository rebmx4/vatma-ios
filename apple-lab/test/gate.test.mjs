import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { createSessionKey, signRequest } from '../shared/signing.mjs';
import { createGate } from '../remote/gate.mjs';

test('remote gate rejects unsigned access and host commands; expires without a lease', async t => {
  const helper = http.createServer((req, res) => res.end(JSON.stringify(req.url === '/config' ?
    { width: 1320, height: 2868, orientation: 'portrait' } : { status: 'ok' })));
  helper.listen(0, '127.0.0.1'); await once(helper, 'listening');
  t.after(() => helper.close());
  const key = createSessionKey();
  let time = 100000, expired = null;
  const gate = createGate({ publicKey: key.publicKey, session: 'c'.repeat(32), runId: '123', revision: 'd'.repeat(40),
    device: 'iphone', helperOrigin: `http://127.0.0.1:${helper.address().port}`, now: () => time,
    deadline: 500000, onExpire: reason => { expired = reason; } });
  gate.server.listen(0, '127.0.0.1'); await once(gate.server, 'listening');
  t.after(() => gate.close());
  const base = `http://127.0.0.1:${gate.server.address().port}`;
  assert.equal((await fetch(base + '/health')).status, 401);
  const headers = path => signRequest(key.privateKey, 'c'.repeat(32), 'GET', path, undefined, time);
  const response = await fetch(base + '/health', { headers: headers('/health') });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).config.width, 1320);
  assert.equal((await fetch(base + '/.sim/exec', { headers: headers('/.sim/exec') })).status, 404);
  assert.equal((await fetch(base + '/stream?url=http://evil.test', { headers: headers('/stream?url=http://evil.test') })).status, 404);
  time += 61000; gate.checkLease();
  assert.equal(expired, 'connection-lost');
  assert.equal((await fetch(base + '/health', { headers: headers('/health') })).status, 410);
});

test('lease cannot extend the hard session deadline', async t => {
  const key = createSessionKey(); let time = 100000, expired;
  const gate = createGate({ publicKey: key.publicKey, session: 'c'.repeat(32), now: () => time,
    deadline: 102000, onExpire: value => { expired = value; } });
  gate.server.listen(0, '127.0.0.1'); await once(gate.server, 'listening');
  t.after(() => gate.close());
  const path = '/lease';
  const response = await fetch(`http://127.0.0.1:${gate.server.address().port}` + path, {
    method: 'POST', headers: signRequest(key.privateKey, 'c'.repeat(32), 'POST', path, undefined, time) });
  assert.equal(response.status, 200);
  time = 102001; gate.checkLease(); assert.equal(expired, 'time-limit');
});
