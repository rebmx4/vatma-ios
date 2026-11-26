(async () => {
  const view = document.getElementById('report');
  const requests = JSON.parse(document.getElementById('http-observation').textContent);
  const marker = 'atma_device_probe_synthetic';
  const cookieMarker = `${marker}=present`;
  const cookieOptions = `Path=/atma-device-probe/; SameSite=Strict${location.protocol === 'https:' ? '; Secure' : ''}`;

  function storageMarks() {
    const marks = { cookie: null, localStorage: null };
    try { marks.cookie = document.cookie.split(';').some(cookie => cookie.trim() === cookieMarker); } catch {}
    try { marks.localStorage = localStorage.getItem(marker) === 'present'; } catch {}
    return marks;
  }

  async function clientHints() {
    const data = navigator.userAgentData;
    const hints = { apiAvailable: Boolean(data), status: 'unavailable', model: null,
      platform: data?.platform ?? null, platformVersion: null, mobile: data?.mobile ?? null,
      fullVersionList: null };
    if (typeof data?.getHighEntropyValues !== 'function') return hints;
    try {
      const result = await data.getHighEntropyValues(['model', 'platformVersion', 'fullVersionList']);
      hints.status = 'resolved';
      hints.model = result.model || null;
      hints.platformVersion = result.platformVersion || null;
      if (Array.isArray(result.fullVersionList)) {
        hints.fullVersionList = result.fullVersionList.map(({ brand, version }) => ({ brand, version }));
      }
    } catch { hints.status = 'rejected'; }
    return hints;
  }

  async function afterAcceptCH() {
    try {
      const response = await fetch('/atma-device-probe/headers', { cache: 'no-store', credentials: 'omit' });
      if (response.ok) return { status: 'received', headers: await response.json() };
    } catch {}
    return { status: 'unavailable', headers: null };
  }

  const [pageClientHints, negotiatedRequest] = await Promise.all([clientHints(), afterAcceptCH()]);
  const visual = window.visualViewport;
  const report = {
    requests: { ...requests, afterAcceptCH: negotiatedRequest },
    page: {
      secureContext: window.isSecureContext,
      userAgent: navigator.userAgent,
      platform: navigator.platform,
      screenCSSPixels: { width: screen.width, height: screen.height },
      layoutViewportCSSPixels: { width: innerWidth, height: innerHeight },
      visualViewportCSSPixels: visual ? { width: visual.width, height: visual.height, scale: visual.scale } : null,
      devicePixelRatio,
      clientHints: pageClientHints,
    },
  };
  const render = () => { view.textContent = JSON.stringify({ ...report, syntheticMarks: storageMarks() }, null, 2); };
  document.getElementById('set-mark').addEventListener('click', () => {
    try { document.cookie = `${cookieMarker}; ${cookieOptions}`; } catch {}
    try { localStorage.setItem(marker, 'present'); } catch {}
    render();
  });
  document.getElementById('clear-mark').addEventListener('click', () => {
    try { document.cookie = `${marker}=; ${cookieOptions}; Max-Age=0`; } catch {}
    try { localStorage.removeItem(marker); } catch {}
    render();
  });
  render();
})();
