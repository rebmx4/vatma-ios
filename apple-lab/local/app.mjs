import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { WebSocket, WebSocketServer } from 'ws';
import { readBody, json, safeError } from '../shared/http.mjs';
import { validControl } from '../remote/gate.mjs';

const publicRoot = new URL('../public/', import.meta.url);
const assets = new Map([['/', ['index.html', 'text/html']], ['/style.css', ['style.css', 'text/css']],
  ['/app.mjs', ['app.mjs', 'text/javascript']], ['/input.mjs', ['input.mjs', 'text/javascript']]]);

export function createLocalApp({ controller, outputDir }) {
  const csrf = randomBytes(24).toString('hex');
  let client, lastPong = 0, latestFrame;
  const wss = new WebSocketServer({ noServer: true, maxPayload: 8192, perMessageDeflate: false });
  const origin = () => `http://127.0.0.1:${server.address().port}`;
  function trusted(req) { return req.headers.host === new URL(origin()).host && (!req.headers.origin || req.headers.origin === origin()); }
  const server = http.createServer(async (req, res) => {
    try {
      if (!trusted(req)) return json(res, 403, { error: 'Недопустимый источник запроса' });
      if (req.method === 'POST') {
        if (req.headers.origin !== origin() || req.headers['x-lab-csrf'] !== csrf) return json(res, 403, { error: 'Недопустимый источник запроса' });
        const value = JSON.parse((await readBody(req)).toString() || '{}');
        if (req.url === '/api/start') {
          if (!hasUi()) return json(res, 409, { error: 'Окно устройства не подключено' });
          return json(res, 202, controller.start(value.device));
        }
        if (req.url === '/api/stop') { void controller.stop(); return json(res, 202, controller.snapshot()); }
        if (req.url === '/api/action') return json(res, 200, await controller.action(value));
        if (req.url === '/api/capture') {
          if (!controller.snapshot().connected || !latestFrame || !outputDir) return json(res, 409, { error: 'Нет живого экрана' });
          const folder = resolve(outputDir, 'screenshots'); await mkdir(folder, { recursive: true });
          const path = resolve(folder, `${controller.snapshot().device}-${new Date().toISOString().replace(/[:.]/g, '-')}.jpg`);
          await writeFile(path, latestFrame); return json(res, 200, { path });
        }
        return json(res, 404, { error: 'Неизвестное действие' });
      }
      if (req.method === 'GET' && req.url === '/api/state') return json(res, 200, { app: 'ATMA Apple Lab', ...controller.snapshot() });
      if (req.method === 'GET' && assets.has(req.url)) {
        const [name, mime] = assets.get(req.url);
        let body = await readFile(new URL(name, publicRoot));
        if (name === 'index.html') body = Buffer.from(body.toString().replace('__CSRF__', csrf));
        res.writeHead(200, { 'content-type': mime + '; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff',
          'content-security-policy': "default-src 'self'; connect-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" });
        return res.end(body);
      }
      json(res, 404, { error: 'Not found' });
    } catch (error) { json(res, error.status ?? 400, { error: safeError(error) }); }
  });
  function hasUi() { return client?.readyState === WebSocket.OPEN && Date.now() - lastPong < 20000; }
  const timer = setInterval(() => {
    if (!client) return;
    if (!hasUi()) { client.terminate(); return; }
    client.ping();
  }, 5000); timer.unref();
  server.on('upgrade', (req, socket, head) => {
    if (!trusted(req) || req.headers.origin !== origin() || req.url !== `/live?csrf=${csrf}`) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    wss.handleUpgrade(req, socket, head, ws => {
      const old = client; client = ws; lastPong = Date.now(); old?.close(1000, 'New window');
      ws.send(JSON.stringify({ type: 'state', ...controller.snapshot() }));
      ws.on('pong', () => { if (client === ws) lastPong = Date.now(); });
      ws.on('message', (data, binary) => {
        if (client !== ws) return;
        if (binary) { if (validControl(data)) controller.control(data); return; }
        try {
          const value = JSON.parse(data.toString());
          if (value.type === 'paint' && Number.isSafeInteger(value.sequence)) controller.paint(value.sequence);
        } catch { ws.close(1008, 'Invalid message'); }
      });
      ws.on('error', () => {});
      ws.on('close', () => { if (client === ws) { client = null; void controller.stop(); } });
    });
  });
  const sendState = state => { if (client?.readyState === WebSocket.OPEN) client.send(JSON.stringify({ type: 'state', ...state })); };
  const sendFrame = ({ sequence, frame }) => {
    latestFrame = frame;
    if (client?.readyState !== WebSocket.OPEN || client.bufferedAmount > 2 * 1024 * 1024) return;
    const prefix = Buffer.alloc(4); prefix.writeUInt32BE(sequence);
    client.send(Buffer.concat([prefix, frame]), { binary: true });
  };
  controller.on('state', sendState); controller.on('frame', sendFrame);
  return { server, hasUi, close() { clearInterval(timer); client?.terminate(); wss.close();
    controller.off('state', sendState); controller.off('frame', sendFrame); server.closeAllConnections(); server.close(); } };
}
