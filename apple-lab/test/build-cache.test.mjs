import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildIdentity, prepareBundle } from '../remote/build-cache.mjs';

const details = { revision: 'a'.repeat(40), xcode: 'Xcode 26.4\nBuild version 17E192', sdk: '26.4', arch: 'arm64', recipe: 'b'.repeat(64) };
const info = { CFBundleIdentifier: 'ru.atma.browser', CFBundleExecutable: 'ATMA', CFBundleSupportedPlatforms: ['iPhoneSimulator'], UIDeviceFamily: [1, 2] };

test('an unchanged Simulator bundle is reused for either device; source and toolchain changes rebuild it', t => {
  const root = mkdtempSync(join(tmpdir(), 'apple-lab-cache-')); t.after(() => rmSync(root, { recursive: true, force: true }));
  let builds = 0;
  const build = () => { builds++; const app = join(root, 'products', 'ATMA.app'); mkdirSync(app, { recursive: true }); writeFileSync(join(app, 'ATMA'), 'binary'); return app; };
  const options = { directory: join(root, 'bundle'), inspect: () => ({ info, arch: 'arm64' }), build };
  const identity = buildIdentity(details);
  assert.equal(prepareBundle({ ...options, identity }).cacheHit, false);
  assert.equal(prepareBundle({ ...options, identity }).cacheHit, true);
  assert.equal(builds, 1);
  const changedSource = buildIdentity({ ...details, revision: 'c'.repeat(40) });
  assert.notEqual(changedSource.key, identity.key);
  assert.equal(prepareBundle({ ...options, identity: changedSource }).cacheHit, false);
  const changedXcode = buildIdentity({ ...details, xcode: 'Xcode 26.4\nBuild version 17E193' });
  assert.notEqual(changedXcode.key, identity.key);
  assert.equal(prepareBundle({ ...options, identity: changedXcode }).cacheHit, false);
  assert.equal(builds, 3);
});

test('a cached device build or a bundle without both device families is rejected', t => {
  const root = mkdtempSync(join(tmpdir(), 'apple-lab-cache-')); t.after(() => rmSync(root, { recursive: true, force: true }));
  const app = join(root, 'products', 'ATMA.app'); mkdirSync(app, { recursive: true }); writeFileSync(join(app, 'ATMA'), 'binary');
  const options = { directory: join(root, 'bundle'), identity: buildIdentity(details), build: () => app };
  assert.throws(() => prepareBundle({ ...options, inspect: () => ({ info: { ...info, CFBundleSupportedPlatforms: ['iPhoneOS'] }, arch: 'arm64' }) }), /Simulator/);
  assert.throws(() => prepareBundle({ ...options, inspect: () => ({ info: { ...info, UIDeviceFamily: [1] }, arch: 'arm64' }) }), /Simulator/);
  assert.equal(prepareBundle({ ...options, inspect: () => ({ info, arch: 'arm64' }) }).cacheHit, false);
});
