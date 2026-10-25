import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { GitHub } from '../local/github.mjs';
import { Controller } from '../local/controller.mjs';

test('a definitive rejected dispatch reports an error without waiting forever for a nonexistent run', async t => {
  let searches = 0;
  const server = http.createServer((req, res) => {
    res.setHeader('content-type', 'application/json');
    if (req.url.endsWith('/dispatches')) { res.statusCode = 403; res.end('{}'); }
    else if (req.url.includes('/runs?')) { searches++; res.end('{"workflow_runs":[]}'); }
    else if (req.url.includes('/commits/')) res.end(JSON.stringify({ sha: 'd'.repeat(40) }));
    else res.end('{"private":false,"permissions":{"push":true}}');
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => server.close());
  const github = new GitHub({ repo: 'owner/repo', credential: async () => 'test-credential', api: `http://127.0.0.1:${server.address().port}` });
  const controller = new Controller(github, { delay: () => new Promise(() => {}) });
  controller.start('iphone');
  for (let i = 0; i < 30 && controller.snapshot().phase === 'starting'; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(searches, 0);
  assert.equal(controller.current, null);
  assert.equal(controller.snapshot().phase, 'error');
});
