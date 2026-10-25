import http from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';
import { createVerifier } from '../shared/signing.mjs';
import { readBody, json } from '../shared/http.mjs';

export function validControl(data) {
  if (data.length < 1 || data.length > 1024) return false;
  if (data[0] === 0x10 || data[0] === 0x11) {
    const multi = data[0] === 0x11;
    if (!(multi ? [20] : [12, 13]).includes(data.length) || data[1] > 2) return false;
    for (let offset = 2; offset < (multi ? 18 : 10); offset += 4) {
      const value = data.readFloatLE(offset);
      if (!Number.isFinite(value) || value < 0 || value > 1) return false;
    }
    return true;
  }
  if ([0x09, 0x0c].includes(data[0])) return data.length === 1;
  try {
    const value = JSON.parse(data.subarray(1).toString());
    if ([0x03, 0x05].includes(data[0])) {
      const fields = data[0] === 0x03 ? ['x', 'y'] : ['x1', 'y1', 'x2', 'y2'];
      return ['begin', 'move', 'end'].includes(value.type) && fields.every(key =>
        Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 1) &&
        (value.edge == null || Number.isInteger(value.edge) && value.edge >= 0 && value.edge <= 4);
    }
    if (data[0] === 0x04) return ['home', 'lock', 'siri', 'volume_up', 'volume_down'].includes(value.button) && value.page == null && value.usage == null;
    if (data[0] === 0x06) return ['down', 'up'].includes(value.type) && Number.isInteger(value.usage) && value.usage >= 0 && value.usage <= 255;
    if (data[0] === 0x07) return ['portrait', 'portrait_upside_down', 'landscape_left', 'landscape_right'].includes(value.orientation);
  } catch { /* Malformed control packets are never forwarded. */ }
  return false;
}

export function createGate(options) {
  const { session, publicKey, helperOrigin, runId, revision, device, deadline,
    now = Date.now, onExpire = () => {}, action = async () => { throw new Error('Action unavailable'); } } = options;
  const verify = createVerifier({ session, publicKey, now });
  let lastLease = now(), expired = null;
  const streams = new Set();
  const controls = new Set();
  const wss = new WebSocketServer({ noServer: true, maxPayload: 1024, perMessageDeflate: false });
  function expire(reason) {
    if (expired) return;
    expired = reason;
    for (const stream of streams) stream.destroy();
    for (const ws of controls) ws.terminate();
    onExpire(reason);
  }
  function checkLease() {
    if (now() >= deadline) expire('time-limit');
    else if (now() - lastLease > 60000) expire('connection-lost');
    return expired;
  }
  const timer = setInterval(checkLease, 1000); timer.unref();
  const server = http.createServer(async (req, res) => {
    try {
      if (checkLease()) return json(res, 410, { error: expired });
      const body = await readBody(req);
      if (!verify(req.headers, req.method, req.url, body)) return json(res, 401, { error: 'Unauthorized' });
      if (req.method === 'POST' && req.url === '/lease') {
        lastLease = now(); return json(res, 200, { deadline });
      }
      if (req.method === 'POST' && req.url === '/stop') {
        json(res, 200, { stopped: true }); expire('disconnected'); return;
      }
      if (req.method === 'POST' && req.url === '/action') {
        return json(res, 200, await action(JSON.parse(body.toString())));
      }
      if (req.method === 'GET' && req.url === '/health') {
        const [health, config] = await Promise.all(['/health', '/config'].map(async path => {
          const response = await fetch(helperOrigin + path, { signal: AbortSignal.timeout(5000) });
          if (!response.ok) throw new Error('Simulator unavailable');
          return response.json();
        }));
        if (health.status !== 'ok' || !(config.width > 0 && config.height > 0)) throw new Error('Simulator unavailable');
        return json(res, 200, { session, runId, revision, device, deadline, config });
      }
      if (req.method === 'GET' && req.url === '/stream') {
        const upstream = http.get(helperOrigin + '/stream.mjpeg?raw=1', upstreamResponse => {
          if (upstreamResponse.statusCode !== 200) { json(res, 502, { error: 'Stream unavailable' }); upstream.destroy(); return; }
          res.writeHead(200, { 'content-type': 'application/octet-stream', 'cache-control': 'no-store', 'x-accel-buffering': 'no' });
          upstreamResponse.pipe(res);
        });
        streams.add(upstream);
        upstream.on('error', () => res.destroy());
        res.on('close', () => { upstream.destroy(); streams.delete(upstream); });
        return;
      }
      json(res, 404, { error: 'Not found' });
    } catch (error) { if (!res.headersSent) json(res, error.status ?? 502, { error: 'Simulator request failed' }); else res.destroy(); }
  });
  server.on('upgrade', (req, socket, head) => {
    if (checkLease() || req.url !== '/control' || !verify(req.headers, 'GET', req.url)) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return;
    }
    wss.handleUpgrade(req, socket, head, client => {
      // A new authorized connection replaces the old one; only one operator per simulator.
      for (const old of controls) old.terminate();
      controls.add(client);
      const upstream = new WebSocket(helperOrigin.replace('http:', 'ws:') + '/ws', { perMessageDeflate: false, handshakeTimeout: 8000 });
      client.on('message', (data, binary) => {
        if (binary && validControl(data) && upstream.readyState === WebSocket.OPEN) upstream.send(data);
        else if (!binary || !validControl(data)) client.close(1008, 'Invalid input');
      });
      upstream.on('message', (data, binary) => { if (client.readyState === WebSocket.OPEN) client.send(data, { binary }); });
      upstream.on('open', () => client.send(JSON.stringify({ type: 'control-ready' })));
      upstream.on('error', () => client.close(1011, 'Simulator unavailable'));
      upstream.on('close', () => client.close());
      client.on('close', () => { controls.delete(client); upstream.terminate(); });
      client.on('error', () => upstream.terminate());
    });
  });
  return { server, checkLease, close() { clearInterval(timer); for (const ws of controls) ws.terminate();
    for (const stream of streams) stream.destroy(); wss.close(); server.closeAllConnections(); server.close(); } };
}
