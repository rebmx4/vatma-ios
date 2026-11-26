import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const root = '/atma-device-probe/';
const detailHints = ['sec-ch-ua-model', 'sec-ch-ua-platform-version', 'sec-ch-ua-full-version-list'];
const reportHeaders = ['user-agent', 'sec-ch-ua', 'sec-ch-ua-mobile', 'sec-ch-ua-platform', ...detailHints];
const pageScript = readFileSync(new URL('./page.js', import.meta.url));
const runLifetime = 2 * 60 * 1000;
const maxRuns = 32;

function observeHeaders(headers) {
  return Object.fromEntries(reportHeaders.map(name => {
    const value = headers[name];
    return [name, typeof value === 'string' && value.length <= 1024 ? value : null];
  }));
}

function reportPage(observation) {
  // Even a permitted HTTP header can contain HTML supplied by an untrusted client.
  const data = JSON.stringify(observation).replaceAll('<', '\\u003c');
  return `<!doctype html>
<html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Проверка совместимости ATMA</title>
<style>body{font:16px system-ui,sans-serif;margin:16px}pre{font-size:13px;white-space:pre-wrap;overflow-wrap:anywhere}button,a{margin:0 0.5rem 0.5rem 0}</style>
<h1>Проверка совместимости ATMA</h1>
<p>Значение null означает «не предоставлено». Размеры указаны в CSS-пикселях.</p>
<p><a href="${root}">Повторить</a><a href="${root}" target="_blank" rel="opener">Открыть дочернее окно</a></p>
<p><button id="set-mark" type="button">Поставить тестовые метки</button><button id="clear-mark" type="button">Удалить тестовые метки</button></p>
<pre id="report">Собираем показания страницы…</pre>
<script id="http-observation" type="application/json">${data}</script>
<script src="${root}page.js" defer></script>
</html>`;
}

export function createDeviceProbe() {
  const pending = new Map();
  return createServer({ requestTimeout: 10_000, maxHeaderSize: 16_384 }, (request, response) => {
    const respond = (status, headers = {}, body = '') => {
      response.writeHead(status, {
        'Cache-Control': 'no-store',
        'Referrer-Policy': 'no-referrer',
        'X-Content-Type-Options': 'nosniff',
        ...headers,
      });
      response.end(body);
    };
    if (request.method !== 'GET') return respond(405, { Allow: 'GET' });
    const path = request.url.split('?', 1)[0];
    if (path === `${root}page.js`) return respond(200, { 'Content-Type': 'text/javascript; charset=utf-8' }, pageScript);
    if (path === `${root}headers`) {
      return respond(200, { 'Content-Type': 'application/json' }, JSON.stringify(observeHeaders(request.headers)));
    }

    const now = Date.now();
    for (const [id, run] of pending) {
      if (now - run.startedAt < runLifetime) break;
      pending.delete(id);
    }
    if (path === root) {
      const id = randomUUID();
      if (pending.size >= maxRuns) pending.delete(pending.keys().next().value);
      pending.set(id, { startedAt: now, headers: observeHeaders(request.headers) });
      return respond(302, { Location: `${root}run/${id}` });
    }
    if (!path.startsWith(`${root}run/`)) return respond(404);
    const id = path.slice(`${root}run/`.length);
    const run = pending.get(id);
    if (!run) return respond(410, { 'Content-Type': 'text/plain; charset=utf-8' }, `Откройте ${root} заново.`);
    pending.delete(id);
    const observation = {
      firstNavigation: run.headers,
      navigationAfter302: observeHeaders(request.headers),
    };
    return respond(200, {
      'Accept-CH': detailHints.join(', '),
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Security-Policy': "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    }, reportPage(observation));
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.ATMA_DEVICE_PROBE_PORT ?? 8765);
  createDeviceProbe().listen(port, '127.0.0.1', () => {
    console.log(`ATMA device probe · http://127.0.0.1:${port}${root}`);
  });
}
