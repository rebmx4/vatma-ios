import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { mkdir, appendFile } from 'node:fs/promises';
import { GitHub } from './github.mjs';
import { Controller } from './controller.mjs';
import { createLocalApp } from './app.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
if (process.platform === 'win32' && !/^D:[/\\]/i.test(root)) throw new Error('Apple Lab must be stored on D:');
const outputDir = resolve(root, 'out/apple-lab');
await mkdir(outputDir, { recursive: true });
const github = new GitHub({ repo: 'rebmx4/vatma-ios', cwd: root });
let app;
const controller = new Controller(github, { hasUi: () => app?.hasUi() ?? false });
app = createLocalApp({ controller, outputDir });
controller.on('ended', event => {
  void appendFile(resolve(outputDir, 'sessions.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...event }) + '\n').catch(() => {});
});
app.server.listen(4186, '127.0.0.1', () => console.log('ATMA Apple Lab: http://127.0.0.1:4186/'));
app.server.on('error', error => { console.error(error.code === 'EADDRINUSE' ? 'Apple Lab port is already in use' : error.message); process.exitCode = 1; });
let exiting = false;
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
  if (exiting) return; exiting = true;
  await controller.stop(); app.close();
});
