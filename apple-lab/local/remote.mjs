import { WebSocket } from 'ws';
import https from 'node:https';
import { createTunnelLookup } from './dns.mjs';
import { signRequest } from '../shared/signing.mjs';
import { JpegFrames } from '../shared/stream.mjs';

export class Remote {
  constructor(session, url, callbacks) {
    Object.assign(this, { session, url, callbacks }); this.abort = new AbortController();
    this.agent = new https.Agent({ keepAlive: true, lookup: createTunnelLookup() });
  }
  headers(method, path, body) { return signRequest(this.session.key.privateKey, this.session.id, method, path, body); }
  response(path, method = 'GET', body, signal = this.abort.signal) {
    return new Promise((resolve, reject) => {
      // Keep the original host/SNI and normal certificate verification; only DNS lookup changes.
      const req = https.request(this.url + path, { method, agent: this.agent, signal, headers: this.headers(method, path, body) }, res => {
        clearTimeout(timer);
        if (res.statusCode !== 200) { res.resume(); reject(new Error(`Удалённый Simulator недоступен (${res.statusCode})`)); return; }
        resolve(res);
      });
      const timer = setTimeout(() => req.destroy(new Error('Туннель не отвечает')), 15000);
      req.on('error', error => { clearTimeout(timer); reject(error); }); req.end(body);
    });
  }
  async request(path, method = 'GET', value) {
    const body = value == null ? undefined : Buffer.from(JSON.stringify(value));
    const response = await this.response(path, method, body, AbortSignal.any([this.abort.signal, AbortSignal.timeout(15000)]));
    const chunks = []; let size = 0;
    for await (const chunk of response) { size += chunk.length; if (size > 1048576) { response.destroy(); throw new Error('Ответ Simulator слишком большой'); } chunks.push(chunk); }
    return JSON.parse(Buffer.concat(chunks).toString());
  }
  async health() {
    const value = await this.request('/health');
    if (value.session !== this.session.id || String(value.runId) !== String(this.session.run.id) ||
        value.revision !== this.session.revision || value.device !== this.session.device) throw Object.assign(new Error('Получен ответ другого сеанса'), { fatal: true });
    this.callbacks.health(value); return value;
  }
  async open() {
    await this.health(); await this.request('/lease', 'POST');
    if (this.abort.signal.aborted) return;
    this.ws = new WebSocket(this.url.replace('https:', 'wss:') + '/control', {
      headers: this.headers('GET', '/control'), agent: this.agent, handshakeTimeout: 15000, perMessageDeflate: false });
    this.ws.on('message', (data, binary) => {
      if (!binary) {
        try { if (JSON.parse(data.toString()).type === 'control-ready') this.callbacks.control(true); } catch { /* Other helper metadata is optional. */ }
      }
    });
    this.ws.on('close', () => { this.callbacks.control(false); if (!this.abort.signal.aborted) this.callbacks.failure(new Error('Канал управления закрыт')); });
    this.ws.on('error', () => { if (!this.abort.signal.aborted) this.callbacks.failure(new Error('Потеряно соединение с Mac')); });
    void this.stream().catch(error => { if (!this.abort.signal.aborted) this.callbacks.failure(error); });
  }
  async stream() {
    const response = await this.response('/stream');
    const parser = new JpegFrames(frame => this.callbacks.frame(frame));
    for await (const chunk of response) parser.push(Buffer.from(chunk));
    if (!this.abort.signal.aborted) throw new Error('Передача экрана остановлена');
  }
  send(data) { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(data); }
  close() { this.abort.abort(); this.ws?.terminate(); this.agent.destroy(); }
  async stop() {
    try { await this.request('/stop', 'POST'); } catch { /* Actions cancellation is the second independent stop path. */ }
    this.close();
  }
}
