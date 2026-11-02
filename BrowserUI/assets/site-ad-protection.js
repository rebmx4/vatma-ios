function installAtmaSiteAdProtection(options = {}) {
  if (options.enabled === false) return;
  const host = location.hostname.toLowerCase();
  const rutube = host === 'rutube.ru' || host.endsWith('.rutube.ru');
  const vk = host === 'vk.com' || host.endsWith('.vk.com') || host === 'vkvideo.ru' || host.endsWith('.vkvideo.ru');
  if (!rutube && !vk) return;

  function clean(urlText, value) {
    let url;
    try { url = new URL(urlText, location.href); } catch { return value; }
    if (url.protocol !== 'https:') return value;
    if (rutube && ['rutube.ru', 'www.rutube.ru'].includes(url.hostname) &&
        /^\/api\/play\/options\/[a-z0-9_-]+\/?$/.test(url.pathname) &&
        value?.acl_access?.allowed === true && typeof value.effective_video === 'string' &&
        Number.isFinite(value.duration) && Array.isArray(value.advert?.video?.ad_breaks) &&
        value.advert.video.ad_breaks.length) {
      return { ...value, advert: { ...value.advert, video: { ...value.advert.video, ad_breaks: [] } } };
    }
    if (vk && ['api.vk.ru', 'api.vk.com', 'api.vkvideo.ru'].includes(url.hostname) &&
        url.pathname === '/method/video.getAds' && value?.response?.banners &&
        value?.response?.instream && typeof value.response.banners === 'object' &&
        typeof value.response.instream === 'object' &&
        !Array.isArray(value.response.banners) && !Array.isArray(value.response.instream) &&
        (Object.keys(value.response.banners).length || Object.keys(value.response.instream).length)) {
      return { ...value, response: { ...value.response, banners: {}, instream: {} } };
    }
    return value;
  }

  const response = window.Response?.prototype;
  const originalJSON = response?.json;
  if (originalJSON) response.json = async function (...args) {
    const value = await Reflect.apply(originalJSON, this, args);
    return clean(this.url, value);
  };

  const xhr = window.XMLHttpRequest?.prototype;
  if (!xhr) return;
  for (const key of ['response', 'responseText']) {
    const original = Object.getOwnPropertyDescriptor(xhr, key);
    if (!original?.get || !original.configurable) continue;
    Object.defineProperty(xhr, key, { ...original, get() {
      const value = Reflect.apply(original.get, this, []);
      if (this.readyState !== 4 || this.status < 200 || this.status >= 300) return value;
      try {
        if (key === 'response' && this.responseType === 'json') return clean(this.responseURL, value);
        if (typeof value !== 'string' || value.length > 1024 * 1024 ||
            !['', 'text'].includes(this.responseType)) return value;
        const parsed = JSON.parse(value);
        const filtered = clean(this.responseURL, parsed);
        return filtered === parsed ? value : JSON.stringify(filtered);
      } catch { return value; }
    } });
  }
}
