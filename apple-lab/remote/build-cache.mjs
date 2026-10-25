import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export function buildIdentity({ revision, xcode, sdk, arch, recipe }) {
  if (!/^[a-f0-9]{40}$/.test(revision) || !xcode || !sdk || arch !== 'arm64' || !/^[a-f0-9]{64}$/.test(recipe)) throw new Error('Invalid build identity');
  const manifest = { schema: 1, revision, xcode, sdk, arch, recipe, configuration: 'Debug', platform: 'iphonesimulator' };
  return { manifest, key: 'apple-lab-app-' + createHash('sha256').update(JSON.stringify(manifest)).digest('hex') };
}
function verify(app, inspect) {
  const { info, arch } = inspect(app);
  if (info.CFBundleIdentifier !== 'ru.atma.browser' || info.CFBundleExecutable !== 'ATMA' ||
      !info.CFBundleSupportedPlatforms?.includes('iPhoneSimulator') || ![1, 2].every(family => info.UIDeviceFamily?.includes(family)) ||
      arch.trim() !== 'arm64' || !existsSync(join(app, 'ATMA'))) throw new Error('Invalid universal Simulator bundle');
}
export function cachedBundle({ directory, identity, inspect }) {
  try {
    if (JSON.stringify(JSON.parse(readFileSync(join(directory, 'manifest.json'), 'utf8'))) !== JSON.stringify(identity.manifest)) return null;
    const app = join(directory, 'ATMA.app'); verify(app, inspect); return app;
  } catch { return null; }
}
export function prepareBundle({ directory, identity, inspect, build }) {
  const hit = cachedBundle({ directory, identity, inspect });
  if (hit) return { app: hit, cacheHit: true };
  const source = build(); verify(source, inspect);
  rmSync(directory, { recursive: true, force: true }); mkdirSync(directory, { recursive: true });
  const app = join(directory, 'ATMA.app'); cpSync(source, app, { recursive: true });
  writeFileSync(join(directory, 'manifest.json'), JSON.stringify(identity.manifest));
  return { app, cacheHit: false };
}
