import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../BrowserUI/assets/site-ad-protection.js', import.meta.url), 'utf8');

function install(host) {
  class SiteResponse {
    constructor(url, value) { this.url = url; this.value = value; }
    async json() { return this.value; }
  }
  const context = vm.createContext({
    location: { hostname: host, href: `https://${host}/video` },
    window: { Response: SiteResponse }, URL,
  });
  vm.runInContext(`${source}\ninstallAtmaSiteAdProtection({enabled:true});`, context);
  return SiteResponse;
}

test('Rutube player keeps playback fields while clearing the known ad breaks', async () => {
  const Response = install('rutube.ru');
  const input = { acl_access: { allowed: true }, effective_video: 'stream', duration: 90,
    advert: { video: { ad_breaks: [{ start: 5 }], other: 1 } }, playback: { formats: ['hls'] } };
  const filtered = await new Response('https://rutube.ru/api/play/options/abc123', input).json();
  assert.deepEqual(Array.from(filtered.advert.video.ad_breaks), []);
  assert.equal(filtered.playback, input.playback);
  assert.equal(input.advert.video.ad_breaks.length, 1);
  assert.equal(await new Response('https://rutube.ru/api/play/options/abc123/stream', input).json(), input);
});

test('VK adapter changes only the video.getAds response', async () => {
  const Response = install('vk.com');
  const input = { response: { banners: { a: 1 }, instream: { b: 2 }, playback: ['mp4'] } };
  const filtered = await new Response('https://api.vk.com/method/video.getAds', input).json();
  assert.deepEqual(Object.keys(filtered.response.banners), []);
  assert.deepEqual(Object.keys(filtered.response.instream), []);
  assert.equal(filtered.response.playback, input.response.playback);
  assert.equal(await new Response('https://api.vk.com/method/video.get', input).json(), input);
  const unknown = { response: { banners: [1], instream: [2] } };
  assert.equal(await new Response('https://api.vk.com/method/video.getAds', unknown).json(), unknown);
});
