function installAtmaPrivateDeviceIdentity(profile) {
  if (!profile || typeof profile !== 'object') return;
  const set = (object, key, value) => {
    if (!object || value === undefined || value === null) return;
    try {
      const own = Object.getOwnPropertyDescriptor(object, key);
      if (own?.configurable === false) return;
      Object.defineProperty(object, key, { configurable: true, enumerable: own?.enumerable ?? true, get: () => value });
    } catch { /* WebKit may keep a surface read-only. */ }
  };
  set(navigator, 'platform', profile.platform);
  set(navigator, 'hardwareConcurrency', profile.cores);
  set(navigator, 'maxTouchPoints', profile.touch);
  set(screen, 'width', profile.width);
  set(screen, 'height', profile.height);
  set(screen, 'availWidth', profile.width);
  set(screen, 'availHeight', profile.height);
  set(window, 'devicePixelRatio', profile.dpr);
}
