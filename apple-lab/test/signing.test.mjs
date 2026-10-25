import test from 'node:test';
import assert from 'node:assert/strict';
import { createSessionKey, signRequest, createVerifier } from '../shared/signing.mjs';

test('request signatures bind the method, path, body and session; replay is refused', () => {
  const key = createSessionKey();
  const verify = createVerifier({ publicKey: key.publicKey, session: 'a'.repeat(32), now: () => 100000 });
  const headers = signRequest(key.privateKey, 'a'.repeat(32), 'POST', '/action', Buffer.from('one'), 100000);
  assert.equal(verify(headers, 'POST', '/action', Buffer.from('two')), false);
  assert.equal(verify(headers, 'POST', '/other', Buffer.from('one')), false);
  assert.equal(verify(headers, 'GET', '/action', Buffer.from('one')), false);
  assert.equal(verify(headers, 'POST', '/action', Buffer.from('one')), true);
  assert.equal(verify(headers, 'POST', '/action', Buffer.from('one')), false);
});

test('expired requests and signatures from another key or session are refused', () => {
  const key = createSessionKey();
  const verify = createVerifier({ publicKey: key.publicKey, session: 'a'.repeat(32), now: () => 100000 });
  assert.equal(verify(signRequest(key.privateKey, 'a'.repeat(32), 'GET', '/health', undefined, 1), 'GET', '/health'), false);
  assert.equal(verify(signRequest(key.privateKey, 'b'.repeat(32), 'GET', '/health', undefined, 100000), 'GET', '/health'), false);
  assert.equal(verify(signRequest(createSessionKey().privateKey, 'a'.repeat(32), 'GET', '/health', undefined, 100000), 'GET', '/health'), false);
});
