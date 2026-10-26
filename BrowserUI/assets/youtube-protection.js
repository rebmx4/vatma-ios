function installAtmaYouTubeProtection(options = {}) {
  const allowed = ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'];
  if (!allowed.includes(location.hostname)) return;
  if (window.__atmaYouTubeProtection) {
    window.__atmaYouTubeProtection.setEnabled(options.enabled !== false); return;
  }
  let enabled = false, filteredResponses = 0, skipClicks = 0;
  let initialValue, initialDescriptor, initialInstalled = false, observer, timer;
  const originalParse = JSON.parse, responsePrototype = window.Response?.prototype;
  const originalResponseJSON = responsePrototype?.json;
  const xhrPrototype = window.XMLHttpRequest?.prototype;
  const xhrResponse = xhrPrototype && Object.getOwnPropertyDescriptor(xhrPrototype, 'response');
  const adFields = ['playerAds', 'adPlacements', 'adSlots', 'adBreakHeartbeatParams', 'adPlaybackTracking', 'adSafetyReason'];
  const clean = (value, depth = 0) => {
    if (!enabled || !value || typeof value !== 'object' || depth > 2) return value;
    if (value.videoDetails?.videoId || (value.playabilityStatus && value.streamingData)) {
      let changed = false;
      for (const key of adFields) if (Object.prototype.hasOwnProperty.call(value, key)) {
        try { changed = delete value[key] || changed; } catch {}
      }
      if (changed) filteredResponses++;
    }
    for (const key of ['playerResponse', 'response']) if (value[key] && value[key] !== value) clean(value[key], depth + 1);
    return value;
  };
  const parse = function (...args) { return clean(Reflect.apply(originalParse, this, args)); };
  const responseJSON = async function (...args) { return clean(await Reflect.apply(originalResponseJSON, this, args)); };
  const xhrJSON = function () {
    const value = Reflect.apply(xhrResponse.get, this, []);
    if (this.responseType !== 'json') return value;
    try {
      const url = new URL(this.responseURL);
      return allowed.includes(url.hostname) && url.pathname === '/youtubei/v1/player' ? clean(value) : value;
    } catch { return value; }
  };
  function refresh() {
    if (!enabled) return;
    const player = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
    const ad = player?.classList?.contains('ad-showing') || player?.classList?.contains('ad-interrupting');
    if (!ad) return;
    const video = player.querySelector('video');
    if (!video || video.paused !== false || video.ended) return;
    const button = player.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
    if (button && !button.disabled && (!button.getClientRects || button.getClientRects().length)) {
      button.click(); skipClicks++;
    }
  }
  function style(on) {
    const id = 'atma-youtube-video-protection', existing = document.getElementById(id);
    if (!on) { existing?.remove(); return; }
    if (existing || !document.head) return;
    const element = document.createElement('style'); element.id = id;
    element.textContent = '#player-ads,ytd-ad-slot-renderer,ytm-promoted-sparkles-web-renderer,.ytp-ad-overlay-container,.ytp-ad-text-overlay{display:none!important}';
    document.head.append(element);
  }
  function initial(on) {
    if (on) {
      initialDescriptor = Object.getOwnPropertyDescriptor(window, 'ytInitialPlayerResponse');
      if (initialDescriptor?.configurable === false || initialDescriptor?.get || initialDescriptor?.set) return;
      initialValue = clean(initialDescriptor?.value);
      Object.defineProperty(window, 'ytInitialPlayerResponse', {configurable:true, enumerable:initialDescriptor?.enumerable ?? true, get:()=>initialValue, set:value=>{initialValue=clean(value);}});
      initialInstalled = true;
    } else if (initialInstalled) {
      Object.defineProperty(window, 'ytInitialPlayerResponse', {...(initialDescriptor || {configurable:true, enumerable:true, writable:true}), value:initialValue});
      initialInstalled = false;
    }
  }
  function setEnabled(value) {
    const next = value === true; if (next === enabled) return;
    enabled = next;
    if (enabled) {
      JSON.parse = parse;
      if (originalResponseJSON) responsePrototype.json = responseJSON;
      if (xhrResponse?.configurable && xhrResponse.get) Object.defineProperty(xhrPrototype, 'response', {...xhrResponse, get:xhrJSON});
      initial(true); style(true);
      observer = new MutationObserver(()=>{style(true);refresh();});
      observer.observe(document, {childList:true, subtree:true, attributes:true, attributeFilter:['class']});
      timer = setInterval(refresh, 500); refresh();
    } else {
      if (JSON.parse === parse) JSON.parse = originalParse;
      if (responsePrototype?.json === responseJSON) responsePrototype.json = originalResponseJSON;
      if (xhrPrototype && Object.getOwnPropertyDescriptor(xhrPrototype, 'response')?.get === xhrJSON) Object.defineProperty(xhrPrototype, 'response', xhrResponse);
      initial(false); observer?.disconnect(); clearInterval(timer); style(false);
    }
  }
  window.__atmaYouTubeProtection = {setEnabled, refresh, state:()=>({enabled, filteredResponses, skipClicks})};
  setEnabled(options.enabled !== false);
}
