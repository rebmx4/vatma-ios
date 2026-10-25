import { progressInfo } from '../shared/progress.mjs';
export class ConnectionState {
  constructor(now = Date.now) { this.now = now; this.frames = new Map(); this.phase = 'idle'; this.message = 'Нет подключения'; }
  start(device) {
    this.startedAt = this.now();
    this.active = true; this.device = device; this.phase = 'starting'; this.progress('source');
    this.lastFrame = this.lastPaint = this.lastHealth = 0; this.controlOpen = false;
    this.deadline = null; this.config = null; this.revision = null; this.runUrl = null; this.frames.clear();
  }
  progress(stage) { if (this.active && progressInfo(stage)) Object.assign(this, progressInfo(stage)); }
  health(value) {
    this.lastHealth = this.now(); this.deadline = Math.min(value.deadline, this.startedAt + 3600000);
    if (value.config) this.config = value.config;
    if (this.phase === 'starting') { this.phase = 'connecting'; this.progress('connect'); }
  }
  control(open) { this.controlOpen = open; }
  frame(sequence) {
    this.lastFrame = this.now(); this.frames.set(sequence, this.now());
    while (this.frames.size > 50) this.frames.delete(this.frames.keys().next().value);
  }
  paint(sequence) {
    const sent = this.frames.get(sequence);
    if (sent != null && this.now() - sent < 8000) this.lastPaint = this.now();
  }
  stop(message) { this.active = false; this.phase = 'stopping'; this.message = message || 'Останавливаем сеанс на Mac…'; }
  finish(error) { this.active = false; this.phase = error ? 'error' : 'idle'; this.message = error || 'Нет подключения'; }
  snapshot() {
    const now = this.now();
    const connected = !!(this.active && this.controlOpen && this.lastFrame && this.lastPaint && this.lastHealth &&
      now - this.lastFrame < 8000 && now - this.lastPaint < 8000 && now - this.lastHealth < 15000 && now < this.deadline);
    return { phase: connected ? 'connected' : this.phase, connected, active: !!this.active,
      message: connected ? 'Связь установлена' : this.message, device: this.device ?? 'iphone',
      revision: this.revision, runUrl: this.runUrl, config: this.config, deadline: this.deadline,
      startedAt: this.startedAt, stage: this.stage, progressHint: this.progressHint,
      lastFrame: this.lastFrame, lastPaint: this.lastPaint };
  }
}
