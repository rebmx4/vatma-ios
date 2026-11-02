import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../BrowserUI/assets/device-identity.js', import.meta.url), 'utf8');

test('private device script reports the selected profile without changing read-only fields', () => {
  const navigator = { platform: 'iPhone', hardwareConcurrency: 6, maxTouchPoints: 5 };
  const screen = { width: 390, height: 844, availWidth: 390, availHeight: 844 };
  Object.defineProperty(screen, 'colorDepth', { value: 24, configurable: false });
  const window = { devicePixelRatio: 3 };
  const context = vm.createContext({ navigator, screen, window });
  vm.runInContext(`${source}\ninstallAtmaPrivateDeviceIdentity({platform:'Win32',cores:8,touch:0,width:1280,height:720,dpr:1});`, context);
  assert.equal(navigator.platform, 'Win32');
  assert.equal(navigator.hardwareConcurrency, 8);
  assert.equal(navigator.maxTouchPoints, 0);
  assert.equal(screen.width, 1280);
  assert.equal(screen.height, 720);
  assert.equal(window.devicePixelRatio, 1);
  assert.equal(screen.colorDepth, 24);
});
