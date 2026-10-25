import { randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { createSessionKey } from '../shared/signing.mjs';
import { safeError } from '../shared/http.mjs';
import { Remote } from './remote.mjs';
import { ConnectionState } from './state.mjs';

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export class Controller extends EventEmitter {
  constructor(github, { now = Date.now, delay = sleep, hasUi = () => true, remoteFactory = (s, url, cb) => new Remote(s, url, cb), pollMs = 1500 } = {}) {
    super(); Object.assign(this, { github, now, delay, hasUi, remoteFactory, pollMs });
    this.state = new ConnectionState(now); this.sequence = 0;
  }
  snapshot() { return this.state.snapshot(); }
  change() { this.emit('state', this.snapshot()); }
  start(device) {
    if (!['iphone', 'ipad'].includes(device)) throw new Error('Выберите iPhone или iPad');
    if (this.current) throw new Error('Дождитесь остановки текущего сеанса');
    this.state.start(device);
    const session = { id: randomBytes(16).toString('hex'), device, key: createSessionKey(), started: this.now(), stop: false };
    this.current = session; this.change();
    session.done = this.open(session);
    return this.snapshot();
  }
  async open(s) {
    try {
      s.revision = await this.github.source(); this.state.revision = s.revision;
      if (s.stop) return;
      s.dispatchSent = true;
      await this.github.dispatch(s);
      while (!s.stop && !s.remote) {
        if (!this.hasUi()) throw new Error('Окно подключения закрыто');
        if (this.now() - s.started > 15 * 60 * 1000) throw new Error('Mac не запустился за 15 минут');
        s.run ??= await this.github.findRun(s);
        if (s.run) {
          this.state.runUrl = s.run.html_url; this.change();
          const run = await this.github.run(s.run.id);
          if (run.status === 'completed') throw new Error(`Сеанс Mac завершён: ${run.conclusion}`);
          const url = await this.github.previewUrl(s);
          if (url && !s.stop) await this.attach(s, url);
        }
        if (!s.stop && !s.remote) await this.delay(this.pollMs);
      }
      let nextHealth = 0, nextRun = 0;
      while (!s.stop && s.remote) {
        if (!this.hasUi()) throw new Error('Окно подключения закрыто');
        const now = this.now();
        if (now >= this.state.deadline) throw new Error('Достигнут предел сеанса — 60 минут');
        if (s.connected && !this.snapshot().connected) throw new Error('Связь потеряна. Сеанс останавливается');
        if (!s.connected && now - s.attached > 45000) throw new Error('Экран или управление не подключились');
        if (now >= nextHealth) {
          await s.remote.health();
          if (s.stop) break;
          await s.remote.request('/lease', 'POST'); nextHealth = this.now() + 4000;
        }
        if (now >= nextRun) {
          const run = await this.github.run(s.run.id);
          if (run.status === 'completed') throw new Error(`Сеанс Mac завершён: ${run.conclusion}`);
          nextRun = this.now() + 15000;
        }
        this.change(); await this.delay(500);
      }
    } catch (error) {
      if (!s.stop) { s.error = safeError(error); this.state.stop(s.error); this.change(); }
    } finally {
      s.stop = true;
      await this.cleanup(s);
    }
  }
  async attach(s, url) {
    const callbacks = {
      health: value => { if (!s.stop) { this.state.health(value); this.change(); } },
      control: open => { if (!s.stop) { this.state.control(open); this.change(); } },
      frame: frame => {
        if (s.stop || this.now() - (s.sentAt ?? 0) < 100) return;
        s.sentAt = this.now(); const sequence = ++this.sequence;
        this.state.frame(sequence); this.emit('frame', { sequence, frame });
      },
      failure: error => { if (!s.stop) { s.error = safeError(error); void this.stop(s.error); } },
    };
    const remote = this.remoteFactory(s, url, callbacks);
    s.remote = remote; s.attached = this.now();
    try { await remote.open(); } catch (error) {
      remote.close(); s.remote = null;
      if (this.now() - (s.firstTunnelAt ??= this.now()) > 45000) throw error;
      this.state.message = 'Ожидаем готовности защищённого канала…';
    }
  }
  paint(sequence) {
    this.state.paint(sequence);
    if (this.snapshot().connected && this.current) this.current.connected = true;
    this.change();
  }
  control(data) { if (this.snapshot().connected) this.current?.remote?.send(data); }
  async action(value) {
    if (!this.snapshot().connected || !this.current?.remote) throw new Error('Нет подключения');
    if (!['text', 'relaunch'].includes(value?.type)) throw new Error('Неизвестное действие');
    return this.current.remote.request('/action', 'POST', value);
  }
  stop(error) {
    const s = this.current;
    if (!s) return Promise.resolve();
    s.stop = true; if (error) s.error = error;
    this.state.stop(error); this.change();
    return s.done;
  }
  async cleanup(s) {
    if (s.remote) void s.remote.stop().catch(() => {});
    while (this.current === s) {
      try {
        if (s.dispatchSent) {
        // A dispatch response can be lost; discover the exact owned run before cancelling.
        for (let attempt = 0; !s.run && attempt < 40; attempt++) {
          s.run = await this.github.findRun(s);
          if (!s.run) await this.delay(this.pollMs);
        }
        if (!s.run) throw new Error('Не удалось подтвердить остановку Mac; проверка доступна в GitHub Actions');
        try { await this.github.cancel(s); } catch (error) {
          if ((await this.github.run(s.run.id)).status !== 'completed') throw error;
        }
        let finished = false;
        for (let attempt = 0; attempt < 40; attempt++) {
          if ((await this.github.run(s.run.id)).status === 'completed') { finished = true; break; }
          await this.delay(1500);
        }
          if (!finished) throw new Error('GitHub ещё завершает задачу');
        }
        s.remote?.close();
        this.current = null; this.state.finish(s.error); this.change();
        this.emit('ended', { session: s.id, device: s.device, revision: s.revision, runId: s.run?.id, error: s.error || null });
      } catch (error) {
        s.remote?.close();
        this.state.stop('Повторяем остановку Mac: ' + safeError(error)); this.change();
        // Keep the run handle during an API outage. A second run must never hide the first.
        await this.delay(5000);
      }
    }
  }
}
