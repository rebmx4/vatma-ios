(async () => {
  const report = {
    headersReceivedByServer: window.__atmaRequestHeaders,
    userAgent: navigator.userAgent, platform: navigator.platform,
    languages: [...navigator.languages], timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    screen: { width: screen.width, height: screen.height },
    viewport: { width: innerWidth, height: innerHeight },
    pixelRatio: devicePixelRatio, touchPoints: navigator.maxTouchPoints,
    hardwareConcurrency: navigator.hardwareConcurrency,
    clientHints: navigator.userAgentData ? await navigator.userAgentData.getHighEntropyValues(['model', 'platformVersion', 'architecture', 'bitness']) : null,
    limitation: 'Это управляемые признаки Chromium. Графика, движок и сетевой стек не стали другим устройством.',
  };
  document.getElementById('report').textContent = JSON.stringify(report, null, 2);
})();
