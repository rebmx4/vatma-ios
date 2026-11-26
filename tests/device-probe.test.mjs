import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { createDeviceProbe } from '../tools/device-probe/server.mjs';

const root = '/atma-device-probe/';
const script = readFileSync(new URL('../tools/device-probe/page.js', import.meta.url), 'utf8');

test('probe correlates separate redirect runs and reports only allowlisted headers', async t => {
  const server = createDeviceProbe();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const redacted = {
    Cookie: 'private-cookie', Authorization: 'Bearer private-token',
    'X-Forwarded-For': '192.0.2.10', Referer: 'https://private.example/path', 'Sec-CH-UA-Arch': 'ignored-arch',
  };
  const begin = userAgent => fetch(`${origin}${root}?secret=private-query`, {
    redirect: 'manual', headers: { ...redacted, 'User-Agent': userAgent },
  });
  const first = await begin('First browser');
  const other = await begin('Second browser');
  const destination = first.headers.get('location');
  assert.equal(first.status, 302);
  assert.match(destination, /^\/atma-device-probe\/run\/[a-f0-9-]+$/);
  assert.notEqual(destination, other.headers.get('location'));
  assert.equal(first.headers.get('accept-ch'), null);

  const html = await fetch(origin + destination, { headers: {
    ...redacted, 'User-Agent': '</script><script>alert(1)</script>', 'Sec-CH-UA-Mobile': '?1',
  } });
  assert.equal(html.status, 200);
  assert.equal(html.headers.get('cache-control'), 'no-store');
  assert.equal(html.headers.get('accept-ch'), 'sec-ch-ua-model, sec-ch-ua-platform-version, sec-ch-ua-full-version-list');
  const body = await html.text();
  const payload = body.match(/<script id="http-observation" type="application\/json">([^<]+)<\/script>/)[1];
  const report = JSON.parse(payload);
  assert.equal(report.firstNavigation['user-agent'], 'First browser');
  assert.equal(report.firstNavigation['sec-ch-ua-model'], null);
  assert.equal(report.navigationAfter302['user-agent'], '</script><script>alert(1)</script>');
  assert.equal(report.navigationAfter302['sec-ch-ua-mobile'], '?1');
  assert.deepEqual(Object.keys(report.navigationAfter302).sort(), [
    'sec-ch-ua', 'sec-ch-ua-full-version-list', 'sec-ch-ua-mobile', 'sec-ch-ua-model',
    'sec-ch-ua-platform', 'sec-ch-ua-platform-version', 'user-agent',
  ]);
  assert.doesNotMatch(body, /private-cookie|private-token|private-query|192\.0\.2\.10|private\.example|ignored-arch|Second browser|<script>alert/);

  const hints = await fetch(`${origin}${root}headers`, { headers: { ...redacted, 'Sec-CH-UA-Model': '""' } });
  const observed = await hints.json();
  assert.equal(observed['sec-ch-ua-model'], '""');
  assert.equal(observed['sec-ch-ua-platform-version'], null);
  assert.deepEqual(Object.keys(observed).sort(), Object.keys(report.navigationAfter302).sort());
  assert.equal((await fetch(origin + destination)).status, 410);
  assert.match(await (await fetch(origin + other.headers.get('location'))).text(), /Second browser/);
});

async function pageObservation(userAgentData) {
  const view = {};
  const listeners = new Map();
  const markers = new Map();
  const document = {
    getElementById(id) {
      if (id === 'report') return view;
      if (id === 'http-observation') return { textContent: '{}' };
      return { addEventListener(_event, handler) { listeners.set(id, handler); } };
    },
    get cookie() { return [...markers.values()].join('; '); },
    set cookie(value) {
      const marker = value.split(';', 1)[0];
      const name = marker.split('=', 1)[0];
      if (value.includes('Max-Age=0')) markers.delete(name);
      else markers.set(name, marker);
    },
  };
  document.cookie = 'other_cookie=private-value';
  const stored = new Map([['unrelated', 'private-storage']]);
  await runInNewContext(script, {
    document,
    location: { protocol: 'https:' },
    navigator: { userAgent: 'Test SM-A546B', platform: 'Test platform', userAgentData },
    screen: { width: 384, height: 854 }, innerWidth: 390, innerHeight: 701, devicePixelRatio: 2.8125,
    window: { isSecureContext: true, visualViewport: { width: 388, height: 640, scale: 1.01 } },
    localStorage: {
      getItem: key => stored.get(key),
      setItem: (key, value) => stored.set(key, value),
      removeItem: key => stored.delete(key),
    },
    fetch: async (url, options) => {
      assert.equal(url, `${root}headers`);
      assert.equal(options.credentials, 'omit');
      return { ok: true, json: async () => ({ 'sec-ch-ua-model': null }) };
    },
  });
  return { observe: () => JSON.parse(view.textContent), press: id => listeners.get(id)() };
}

test('page reports screen and both viewports separately and never infers model from UA', async () => {
  const { observe, press } = await pageObservation(undefined);
  const { page, requests, syntheticMarks } = observe();
  assert.equal(page.secureContext, true);
  assert.deepEqual(page.screenCSSPixels, { width: 384, height: 854 });
  assert.deepEqual(page.layoutViewportCSSPixels, { width: 390, height: 701 });
  assert.deepEqual(page.visualViewportCSSPixels, { width: 388, height: 640, scale: 1.01 });
  assert.match(page.userAgent, /SM-A546B/);
  assert.equal(page.clientHints.apiAvailable, false);
  assert.equal(page.clientHints.model, null);
  assert.deepEqual(requests.afterAcceptCH, { status: 'received', headers: { 'sec-ch-ua-model': null } });
  assert.deepEqual(syntheticMarks, { cookie: false, localStorage: false });
  press('set-mark');
  assert.deepEqual(observe().syntheticMarks, { cookie: true, localStorage: true });
  assert.doesNotMatch(JSON.stringify(observe()), /private-value|private-storage/);
  press('clear-mark');
  assert.deepEqual(observe().syntheticMarks, { cookie: false, localStorage: false });
});

test('page distinguishes an available hints API from an undisclosed model', async () => {
  const { observe } = await pageObservation({
    platform: 'Android', mobile: true,
    async getHighEntropyValues(names) {
      assert.deepEqual(Array.from(names), ['model', 'platformVersion', 'fullVersionList']);
      return { model: '', platformVersion: '14.0.0', fullVersionList: [{ brand: 'Google Chrome', version: '142.0', extra: 'ignored' }] };
    },
  });
  assert.deepEqual(observe().page.clientHints, {
    apiAvailable: true, status: 'resolved', model: null, platform: 'Android', platformVersion: '14.0.0',
    mobile: true, fullVersionList: [{ brand: 'Google Chrome', version: '142.0' }],
  });
});
