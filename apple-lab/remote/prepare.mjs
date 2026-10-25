import { createHash } from 'node:crypto';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { runtime } from './runtime.mjs';
import { buildIdentity, cachedBundle, prepareBundle } from './build-cache.mjs';

const r = runtime();
const { root, cache, command, progress } = r;
if (process.argv[2] === 'plan') {
  await progress('prepare');
  const recipe = createHash('sha256');
  for (const name of ['prepare.mjs', 'build-cache.mjs', 'runtime.mjs']) recipe.update(readFileSync(new URL(name, import.meta.url)));
  const sdk = command('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-version'], { capture: true });
  const identity = buildIdentity({ revision: r.revision, sdk, recipe: recipe.digest('hex'),
    xcode: command('xcodebuild', ['-version'], { capture: true }), arch: command('uname', ['-m'], { capture: true }) });
  const devices = command('xcrun', ['simctl', 'list', 'devices', 'available', '-j'], { capture: true });
  const simulator = JSON.parse(command('python3', ['-B', 'release/simulators.py', '--ios-version', sdk], { capture: true, input: devices }))[r.device];
  // Boot continues while the cache is restored or the native app is compiled.
  command('xcrun', ['simctl', 'boot', simulator]);
  writeFileSync(r.planFile, JSON.stringify({ identity, simulator, device: r.device }));
  appendFileSync(process.env.GITHUB_OUTPUT, `cache-key=${identity.key}\n`);
  await progress('cache');
} else if (process.argv[2] === 'build') {
  const { identity } = r.readPlan();
  // Publish before synchronous compilation so the panel can display the real stage.
  const bundle = { directory: cache + '/bundle', identity, inspect: r.inspect };
  await progress(cachedBundle(bundle) ? 'boot' : 'build');
  const result = prepareBundle({ ...bundle, build: () => {
    command('bash', ['release/ci.sh', 'prepare']);
    command('xcodebuild', ['build', '-project', 'ATMA.xcodeproj', '-scheme', 'ATMA', '-configuration', 'Debug',
      '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', cache + '/derived',
      'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES']);
    return cache + '/derived/Build/Products/Debug-iphonesimulator/ATMA.app';
  } });
  console.log(result.cacheHit ? 'Reused verified Simulator app bundle.' : 'Built new universal Simulator app bundle.');
  writeFileSync(resolve(root, 'out/apple-lab-build.json'), JSON.stringify({ revision: r.revision, key: identity.key, cacheHit: result.cacheHit, preparedAt: Date.now() }));
  await progress('boot');
} else throw new Error('Expected plan or build');
