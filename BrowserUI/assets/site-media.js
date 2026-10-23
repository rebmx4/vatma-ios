function installAtmaMediaPage(options = {}) {
  if (window.__atmaMediaPage) { window.__atmaMediaPage.element ||= select; window.__atmaMediaPage.setBackground(options.background !== false); return; }
  let background = options.background !== false, lastSent = 0, current, interval;
  let visibilityOriginal, hiddenOriginal, visibilityPatched = false;
  const watched = new WeakSet();
  const youtube = ['youtube.com','www.youtube.com','m.youtube.com','music.youtube.com'].includes(location.hostname);
  function select() {
    const all = [...document.querySelectorAll('video,audio')].filter(v=>v.readyState > 0);
    const pip = all.find(v=>v.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === v);
    if (pip) return pip;
    const playing = all.filter(v=>!v.paused && !v.ended);
    return (playing.length ? playing : all).sort((a,b)=>{
      const area=v=>{const r=v.getBoundingClientRect();return r.width*r.height;};return area(b)-area(a);
    })[0] || null;
  }
  function state() {
    current = select(); const video = current;
    if (!video) return {available:false, backgroundEnabled:background};
    const duration = Number.isFinite(video.duration) && video.duration >= 0 ? video.duration : null;
    return {available:true, title:String(document.title || '').slice(0,200), paused:video.paused,
      currentTime:Number.isFinite(video.currentTime)?Math.max(0,video.currentTime):0, duration,
      pip:video.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === video,
      pipAvailable:Boolean(video.webkitSupportsPresentationMode?.('picture-in-picture') || (document.pictureInPictureEnabled && video.requestPictureInPicture)),
      backgroundEnabled:background, live:duration === null};
  }
  function report(force = false) {
    const now = Date.now(); if (!force && now-lastSent < 900) return; lastSent = now;
    try { window.webkit?.messageHandlers?.atmaMedia?.postMessage({version:1, ...state()}); } catch {}
  }
  function scan() {
    for (const video of document.querySelectorAll('video,audio')) if (!watched.has(video)) {
      watched.add(video);
      for (const event of ['play','pause','ended','loadedmetadata','durationchange','webkitpresentationmodechanged','enterpictureinpicture','leavepictureinpicture']) video.addEventListener(event,()=>report(true));
      video.addEventListener('timeupdate',()=>report());
    }
    report();
  }
  function setBackground(value) {
    background = value === true;
    // Only the video website sees a visible document while background listening
    // is requested. This does not prevent iOS from suspending the application.
    if (youtube && background && !visibilityPatched) {
      visibilityOriginal=Object.getOwnPropertyDescriptor(document,'visibilityState');hiddenOriginal=Object.getOwnPropertyDescriptor(document,'hidden');
      try {Object.defineProperty(document,'visibilityState',{configurable:true,get:()=> 'visible'});Object.defineProperty(document,'hidden',{configurable:true,get:()=>false});visibilityPatched=true;}catch{}
    } else if (visibilityPatched && !background) {
      if (visibilityOriginal) Object.defineProperty(document,'visibilityState',visibilityOriginal);else delete document.visibilityState;
      if (hiddenOriginal) Object.defineProperty(document,'hidden',hiddenOriginal);else delete document.hidden;
      visibilityPatched=false;
    }
    report(true);
  }
  async function command(body) {
    const video = select(); if (!video) throw new Error('No playable video or audio on this page.');
    switch (body?.type) {
      case 'play': await video.play(); break;
      case 'pause': video.pause(); break;
      case 'seek': case 'skip': {
        if (typeof body.seconds !== 'number' || !Number.isFinite(body.seconds)) throw new Error('Invalid playback position.');
        if (!Number.isFinite(video.duration)) throw new Error('Seeking is not available for this live stream.');
        const seconds=body.type==='skip'?video.currentTime+Math.max(-600,Math.min(600,body.seconds)):body.seconds;
        video.currentTime=Math.max(0,Math.min(video.duration,seconds));break;
      }
      case 'pip':
        if (video.webkitSupportsPresentationMode?.('picture-in-picture') && video.webkitSetPresentationMode) video.webkitSetPresentationMode('picture-in-picture');
        else if (document.pictureInPictureEnabled && video.requestPictureInPicture) await video.requestPictureInPicture();
        else throw new Error('Picture in Picture is not available for this video.');
        break;
      default: throw new Error('Unsupported media command.');
    }
    report(true); return state();
  }
  async function release() {
    for (const video of document.querySelectorAll('video,audio')) {
      video.pause();
      if (video.webkitPresentationMode === 'picture-in-picture') video.webkitSetPresentationMode?.('inline');
    }
    if (document.pictureInPictureElement && document.exitPictureInPicture) await document.exitPictureInPicture();
    report(true); return state();
  }
  window.__atmaMediaPage={state,element:select,command,setBackground,release};
  const observer = new MutationObserver(scan); observer.observe(document,{childList:true,subtree:true});
  setBackground(background); scan(); interval=setInterval(scan,1500);
  window.addEventListener('pagehide',()=>report(true));
}
