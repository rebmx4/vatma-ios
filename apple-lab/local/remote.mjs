import { WebSocket } from 'ws';
import { signRequest } from '../shared/signing.mjs';
import { JpegFrames } from '../shared/stream.mjs';

export class Remote {
  constructor(session, url, callbacks) { Object.assign(this, { session, url, callbacks }); this.abort = new AbortController(); }
  headers(method, path, body) { return signRequest(this.session.key.privateKey, this.session.id, method, path, body); }
  async request(path, method = 'GET', value) {
    const body = value == null ? undefined : Buffer.from(JSON.stringify(value));
    const response = await fetch(this.url + path, { method, headers: this.headers(method, path, body), body,
      signal: AbortSignal.any([this.abort.signal, AbortSignal.timeout(8000)]), redirect: 'error' });
    if (!response.ok) throw new Error(`Удалённый Simulator недоступен (${response.status})`);
    return response.json();
  }
  async health() {
    const value = await this.request('/health');
    if (value.session !== this.session.id || String(value.runId) !== String(this.session.run.id) ||
        value.revision !== this.session.revision || value.device !== this.session.device) throw new Error('Получен ответ другого сеанса');
    this.callbacks.health(value); return value;
  }
  async open() {
    await this.health(); await this.request('/lease', 'POST');
    if (this.abort.signal.aborted) return;
    this.ws = new WebSocket(this.url.replace('https:', 'wss:') + '/control', {
      headers: this.headers('GET', '/control'), handshakeTimeout: 10000, perMessageDeflate: false });
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
    const response = await fetch(this.url + '/stream', { headers: this.headers('GET', '/stream'), signal: this.abort.signal, redirect: 'error' });
    if (!response.ok || !response.body) throw new Error('Экран Simulator недоступен');
    const parser = new JpegFrames(frame => this.callbacks.frame(frame));
    for await (const chunk of response.body) parser.push(Buffer.from(chunk));
    if (!this.abort.signal.aborted) throw new Error('Передача экрана остановлена');
  }
  send(data) { if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(data); }
  close() { this.abort.abort(); this.ws?.terminate(); }
  async stop() {
    try { await this.request('/stop', 'POST'); } catch { /* Actions cancellation is the second independent stop path. */ }
    this.close();
  }
}
