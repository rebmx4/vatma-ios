import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { resolve } from 'node:path';
import { once } from 'node:events';
import { createGate } from './gate.mjs';
import { helperOrigin as discoverHelper } from './discovery.mjs';
import { runtime } from './runtime.mjs';
import { cachedBundle } from './build-cache.mjs';

const r = runtime();
const { root, lab, cache, session, revision, device, runId, childEnv, command, publish, progress } = r;
const cli = resolve(lab, 'remote-tools/node_modules/serve-sim/dist/serve-sim.js');
const serve = (...args) => command(process.execPath, [cli, ...args], { capture: true, timeout: 90000 });
let simulator, gate, tunnel, reason = 'failed';
try {
  const plan = r.readPlan(); simulator = plan.simulator;
  const app = cachedBundle({ directory: cache + '/bundle', identity: plan.identity, inspect: r.inspect });
  if (!app) throw new Error('Verified Simulator app bundle is missing');
  console.log(`Starting ${device}, revision ${revision}, run ${runId}`);
  await progress('boot');
  command('xcrun', ['simctl', 'bootstatus', simulator, '-b']);
  command('xcrun', ['simctl', 'status_bar', simulator, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100']);
  await progress('install');
  command('xcrun', ['simctl', 'install', simulator, app]);
  command('xcrun', ['simctl', 'launch', simulator, 'ru.atma.browser']);
  await progress('stream');
  console.log(serve('--detach', '--no-preview', '--codec', 'mjpeg', simulator, '-q'));
  const helperOrigin = discoverHelper(JSON.parse(serve('--list', '-q')), simulator);
  const startedAt = Date.now();
  let finish;
  const stopped = new Promise(resolveStop => { finish = resolveStop; });
  gate = createGate({ session, publicKey: process.env.LAB_PUBLIC_KEY, runId, revision, device, helperOrigin,
    deadline: startedAt + 60 * 60 * 1000, leaseArmed: false, onExpire: finish,
    action: async value => {
      if (value?.type === 'relaunch') {
        spawnSync('xcrun', ['simctl', 'terminate', simulator, 'ru.atma.browser'], { env: childEnv });
        command('xcrun', ['simctl', 'launch', simulator, 'ru.atma.browser'], { capture: true });
      } else if (value?.type === 'text' && typeof value.text === 'string' && value.text.length <= 4000) {
        // Paste preserves Cyrillic and other Unicode; the clipboard stays on the disposable Mac.
        command('xcrun', ['simctl', 'pbcopy', simulator], { input: value.text, capture: true });
        const { WebSocket } = await import('ws');
        const ws = new WebSocket(helperOrigin.replace('http:', 'ws:') + '/ws');
        await once(ws, 'open');
        const key = (type, usage) => ws.send(Buffer.concat([Buffer.from([6]), Buffer.from(JSON.stringify({ type, usage }))]));
        key('down', 227); key('down', 25); key('up', 25); key('up', 227);
        await new Promise(resolveWait => setTimeout(resolveWait, 150)); ws.close();
      } else throw new Error('Unsupported action');
      return { ok: true };
    } });
  gate.server.listen(3210, '127.0.0.1'); await once(gate.server, 'listening');
  await progress('tunnel');
  const download = await fetch('https://github.com/cloudflare/cloudflared/releases/download/2026.10.3/cloudflared-darwin-arm64.tgz', { signal: AbortSignal.timeout(60000) });
  if (!download.ok) throw new Error('Tunnel download failed');
  const archive = Buffer.from(await download.arrayBuffer());
  if (createHash('sha256').update(archive).digest('hex') !== '1165d14b6f6360a3b8c283d7d1100024d6ec7cd9bc9e32519e96150645f3ec55') throw new Error('Tunnel checksum mismatch');
  writeFileSync(cache + '/cloudflared.tgz', archive);
  command('tar', ['-xzf', cache + '/cloudflared.tgz', '-C', cache]); chmodSync(cache + '/cloudflared', 0o700);
  let tunnelLog = '';
  tunnel = spawn(cache + '/cloudflared', ['tunnel', '--url', 'http://127.0.0.1:3210', '--no-autoupdate', '--protocol', 'http2'], { env: childEnv, stdio: ['ignore', 'ignore', 'pipe'] });
  const tunnelUrl = await new Promise((resolveUrl, reject) => {
    const timeout = setTimeout(() => reject(new Error('Tunnel startup timed out')), 35000);
    tunnel.stderr.on('data', chunk => {
      tunnelLog = (tunnelLog + chunk).slice(-16000);
      const match = tunnelLog.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
      if (match) { clearTimeout(timeout); resolveUrl(match[0]); }
    });
    tunnel.once('error', reject); tunnel.once('exit', () => { clearTimeout(timeout); reject(new Error('Tunnel exited')); });
  });
  tunnel.once('exit', () => finish('tunnel-stopped'));
  await publish('success', `Simulator ready; run ${runId}`, tunnelUrl);
  gate.armLease();
  writeFileSync(resolve(root, 'out/apple-preview-session.json'), JSON.stringify({ session, device, revision, runId, startedAt, tunnelUrl }, null, 2));
  console.log('Authenticated Simulator session is ready.');
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => finish('disconnected'));
  reason = await stopped;
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  gate?.close(); tunnel?.kill('SIGTERM');
  if (simulator) {
    try {
      const log = readFileSync(`${cache}/tmp/serve-sim/server-${simulator}.log`, 'utf8');
      for (const line of log.split('\n').filter(value => /fatal error|heap limit|ENOMEM|ECONNREFUSED|\[hid\].*failed|\[capture\].*failed/i.test(value)).slice(-15)) console.error(line.slice(0, 500));
    } catch { /* The helper may not have reached initialization. */ }
    try { serve('--kill', simulator); } catch { /* Runner cleanup is best effort after cancellation. */ }
    spawnSync('xcrun', ['simctl', 'shutdown', simulator], { env: childEnv, timeout: 20000 });
  }
  try { await publish(process.exitCode ? 'failure' : 'success', `Session ended: ${reason}`); } catch { /* Job status remains available through Actions. */ }
  console.log(`Session ended: ${reason}`);
}
