function installAtmaMediaPage(options = {}) {
  if (window.__atmaMediaPage) { window.__atmaMediaPage.element ||= select; window.__atmaMediaPage.setBackground(options.background !== false); return; }
  let background = options.background !== false, lastSent = 0, current, interval;
  let pageVisible = options.visible !== false, screenLocked = options.screenLocked === true;
  let gesture = 0, gestureUntil = 0, playWrapped = false;
  const approved = new WeakSet(), requested = new WeakSet(), blockedAt = new WeakMap(), presentations = new WeakMap();
  let visibilityOriginal, hiddenOriginal, visibilityPatched = false;
  const watched = new WeakSet(), playIntents = new WeakMap(), guardPauses = new WeakMap();
  const capturedStreams = new WeakSet(), seenCaptures = new WeakMap();
  // Observe a stream only after the browser grants capture; never request access here.
  const devices = navigator.mediaDevices, getUserMediaOriginal = devices?.getUserMedia;
  if (typeof getUserMediaOriginal === 'function') try {
    Object.defineProperty(devices, 'getUserMedia', {configurable:true,writable:true,value:function getUserMedia(constraints) {
      return getUserMediaOriginal.apply(this,arguments).then(stream=>{
        if(stream && typeof stream.getTracks==='function')capturedStreams.add(stream);
        return stream;
      });
    }});
  } catch {}
  // Keep the actual document visibility before the YouTube background shim.
  const realHidden=(()=>{
    for(let target=document;target;target=Object.getPrototypeOf(target)){
      const descriptor=Object.getOwnPropertyDescriptor(target,'hidden');
      if(descriptor?.get)return()=>descriptor.get.call(document);
    }
    return()=>document.hidden===true;
  })();
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
  function inPiP(video) { return video.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === video; }
  function inlineVisible(video) {
    if (!pageVisible || realHidden()) return false;
    if(video.tagName==='AUDIO')return true;
    const r=video.getBoundingClientRect();
    if (r.width<=0 || r.height<=0 || (r.bottom??1)<=0 || (r.right??1)<=0 || (r.top??0)>=(window.innerHeight??Infinity) || (r.left??0)>=(window.innerWidth??Infinity)) return false;
    if (typeof getComputedStyle==='function') for(let node=video;node;node=node.parentElement){
      const style=getComputedStyle(node);if(style.display==='none'||style.visibility==='hidden'||Number(style.opacity)===0)return false;
    }
    return true;
  }
  function approve(video) { approved.add(video);requested.add(video);blockedAt.delete(video);playIntents.set(video,{}); }
  function revoke(video) { approved.delete(video);blockedAt.set(video,gesture); }
  function pauseFromGuard(video) {
    if(!video.paused){
      const pending=guardPauses.get(video)||[];pending.push(playIntents.get(video));guardPauses.set(video,pending);
    }
    video.pause();
  }
  function didPause(video) {
    const pending=guardPauses.get(video),guarded=Boolean(pending?.length),intent=guarded?pending.shift():undefined;
    // Media events are queued. A guard pause from an older request must not
    // revoke a newer explicit Play; real system/site pauses still revoke it.
    if(!guarded||video.paused||intent===playIntents.get(video))revoke(video);
    report(true);
  }
  function stop(video) { revoke(video);pauseFromGuard(video); }
  function allowPlay(video) {
    const freshGesture=Date.now()<=gestureUntil && (!blockedAt.has(video)||gesture>blockedAt.get(video));
    // WKWebView's native JS evaluation forces transient activation even for
    // state reads. Only actual trusted page input grants first-play intent.
    const stream=video.srcObject,localCapture=stream && capturedStreams.has(stream) && stream.getTracks().some(track=>track.readyState==='live');
    const firstCapture=localCapture && seenCaptures.get(video)!==stream;
    // A permission dialog can outlast the short playback gesture. A granted local
    // capture may start once while visible; later user pauses still require Play.
    if (!approved.has(video) && inlineVisible(video) && (freshGesture || firstCapture)) approve(video);
    if (approved.has(video) && localCapture) seenCaptures.set(video,stream);
    return approved.has(video);
  }
  function enforcePlay(video,event) {
    // Native controls do not call the page's JavaScript play() method.
    // Scripted calls are checked before WebKit receives them below.
    if(!allowPlay(video) && playWrapped && event?.isTrusted && requested.has(video) && inPiP(video))approve(video);
    if(!approved.has(video))pauseFromGuard(video);
  }
  const mediaPrototype=window.HTMLMediaElement?.prototype;
  const playDescriptor=mediaPrototype&&Object.getOwnPropertyDescriptor(mediaPrototype,'play');
  if(playDescriptor?.value)try{
    const originalPlay=playDescriptor.value;
    Object.defineProperty(mediaPrototype,'play',{...playDescriptor,value:function play(...args){
      if(!allowPlay(this))return Promise.reject(new DOMException('Press Play to start this media.','NotAllowedError'));
      return originalPlay.apply(this,args);
    }});
    playWrapped=true;
  }catch{}
  function presentationChanged(video) {
    const pip=inPiP(video),previous=presentations.get(video);presentations.set(video,pip);
    // A lock may hide the system window without ending intentional listening.
    if(previous && !pip && !(screenLocked&&background) && !inlineVisible(video))stop(video);
    report(true);
  }
  function setPageVisible(visible) {
    const next=visible===true;if(next===pageVisible)return;pageVisible=next;
    if(!pageVisible)for(const video of document.querySelectorAll('video,audio'))if(!inPiP(video))stop(video);
    report(true);
  }
  function setScreenLocked(locked) { screenLocked=locked===true; }
  for(const event of ['pointerdown','pointerup','mousedown','touchend','click','keydown'])document.addEventListener(event,e=>{
    if(e.isTrusted&&pageVisible){gesture++;gestureUntil=Date.now()+2000;}
  },true);
  function scan() {
    for (const video of document.querySelectorAll('video,audio')) if (!watched.has(video)) {
      watched.add(video);
      presentations.set(video,inPiP(video));
      video.addEventListener('play',event=>{enforcePlay(video,event);report(true);});
      video.addEventListener('pause',()=>didPause(video));
      video.addEventListener('ended',()=>{revoke(video);report(true);});
      for (const event of ['loadedmetadata','durationchange']) video.addEventListener(event,()=>report(true));
      for (const event of ['webkitpresentationmodechanged','enterpictureinpicture','leavepictureinpicture']) video.addEventListener(event,()=>presentationChanged(video));
      if(!video.paused)enforcePlay(video);
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
      case 'play': approve(video);await video.play(); break;
      case 'pause': stop(video); break;
      case 'seek': case 'skip': {
        if (typeof body.seconds !== 'number' || !Number.isFinite(body.seconds)) throw new Error('Invalid playback position.');
        if (!Number.isFinite(video.duration)) throw new Error('Seeking is not available for this live stream.');
        const seconds=body.type==='skip'?video.currentTime+Math.max(-600,Math.min(600,body.seconds)):body.seconds;
        video.currentTime=Math.max(0,Math.min(video.duration,seconds));break;
      }
      case 'pip':
        approve(video);
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
      stop(video);
      if (video.webkitPresentationMode === 'picture-in-picture') video.webkitSetPresentationMode?.('inline');
    }
    if (document.pictureInPictureElement && document.exitPictureInPicture) await document.exitPictureInPicture();
    report(true); return state();
  }
  window.__atmaMediaPage={state,element:select,command,setBackground,setPageVisible,setScreenLocked,release};
  const observer = new MutationObserver(scan); observer.observe(document,{childList:true,subtree:true});
  setBackground(background); scan(); interval=setInterval(scan,1500);
  window.addEventListener('pagehide',()=>report(true));
}
