function installAtmaVideoControls() {
  if (window.__atmaVideoControls?.version===1) { window.__atmaVideoControls.refresh(); return; }
  window.__atmaVideoControls?.dispose();
  const host=document.createElement('div'),root=host.attachShadow({mode:'open'});
  host.id='atma-video-controls';
  const style=document.createElement('style'),button=document.createElement('button'),notice=document.createElement('div');
  const russian=/^ru\b/i.test(document.documentElement?.lang||navigator.language||'');
  style.textContent=`
    :host{all:initial!important;position:fixed!important;inset:0!important;pointer-events:none!important;z-index:2147483647!important;display:block!important}
    button{all:unset;box-sizing:border-box;position:fixed;width:44px;height:44px;display:flex;align-items:center;justify-content:center;border-radius:10px;background:#0005;color:white;cursor:pointer;pointer-events:auto;touch-action:manipulation;-webkit-tap-highlight-color:transparent}
    button:focus-visible{outline:2px solid white;outline-offset:-3px}button:active{background:#0009}button[hidden],[role=status][hidden]{display:none!important}
    svg{width:25px;height:25px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linejoin:round;pointer-events:none;filter:drop-shadow(0 1px 2px #0009)}
    [role=status]{position:fixed;box-sizing:border-box;max-width:min(290px,calc(100vw - 24px));padding:9px 12px;border-radius:10px;background:#20252ff2;color:white;font:13px/1.4 -apple-system,system-ui,sans-serif;pointer-events:none}
  `;
  button.type='button';button.id='atma-pip-button';button.hidden=true;
  button.setAttribute('aria-label',russian?'Маленькое окно — картинка в картинке':'Floating window — Picture in Picture');
  button.title=button.getAttribute('aria-label');
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.setAttribute('viewBox','0 0 28 28');svg.setAttribute('aria-hidden','true');
  for(const attributes of [{x:3,y:5,width:22,height:18,rx:2.5},{x:13,y:13,width:9,height:7,rx:1,fill:'currentColor',stroke:'none'}]){
    const rect=document.createElementNS('http://www.w3.org/2000/svg','rect');
    for(const [key,value]of Object.entries(attributes))rect.setAttribute(key,String(value));svg.append(rect);
  }
  button.append(svg);
  notice.setAttribute('role','status');notice.hidden=true;root.append(style,button,notice);
  let lastInteraction=Date.now(),queued=false,frame,stopped=false,noticeTimer;
  const listeners=[];
  function listen(target,type,callback){target.addEventListener(type,callback,{passive:true});listeners.push(()=>target.removeEventListener(type,callback));}
  function visible(element,stop){
    for(let e=element;e&&e!==stop;e=e.parentElement){const s=getComputedStyle(e);if(s.display==='none'||s.visibility==='hidden'||Number(s.opacity)===0)return false;}
    return true;
  }
  function render(){
    if(stopped)return;
    const media=window.__atmaMediaPage,video=media?.element?.(),state=media?.state();
    button.hidden=true;
    if(!video||video.tagName!=='VIDEO'||video.disablePictureInPicture||!state?.pipAvailable||state.pip||video.webkitDisplayingFullscreen)return;
    const r=video.getBoundingClientRect();
    if(r.width<100||r.height<64||r.bottom<=0||r.top>=innerHeight||r.right<=0||r.left>=innerWidth||!visible(video))return;
    const player=video.closest('.player-container,#player-container-id,ytm-player')||video.closest('.html5-video-player,#player')||video.parentElement;
    const candidates=[...player.querySelectorAll('.ytp-fullscreen-button,.fullscreen-button,.player-controls-fullscreen-button,button[aria-label],[role="button"][aria-label],button[title]')];
    const fullscreen=candidates.find(e=>/fullscreen|full screen|полноэкран|на весь экран/i.test(`${e.className} ${e.getAttribute('aria-label')} ${e.getAttribute('title')}`));
    let left,top;
    if(fullscreen){
      const f=fullscreen.getBoundingClientRect();
      if(f.width<1||f.height<1||!visible(fullscreen))return;
      left=f.left-44;top=f.top+(f.height-44)/2;
    }else{
      // Native controls live in a closed shadow tree. Keep the fallback above
      // their control bar instead of covering playback or the seek timeline.
      if(!video.paused&&Date.now()-lastInteraction>3200)return;
      if(r.height<128)return;
      left=r.right-136;top=r.bottom-122;
    }
    left=Math.max(0,Math.min(innerWidth-44,left));top=Math.max(0,Math.min(innerHeight-44,top));
    button.style.left=`${Math.round(left)}px`;button.style.top=`${Math.round(top)}px`;
    notice.style.left=`${Math.max(12,Math.min(innerWidth-302,left-200))}px`;notice.style.top=`${Math.max(12,top-62)}px`;
    const container=document.fullscreenElement||document.documentElement;
    if(host.parentElement!==container)container.append(host);
    button.hidden=false;
  }
  function schedule(){if(!queued&&!stopped){queued=true;frame=requestAnimationFrame(()=>{queued=false;render();});}}
  function interact(){lastInteraction=Date.now();schedule();}
  button.addEventListener('click',event=>{
    event.preventDefault();event.stopPropagation();notice.hidden=true;clearTimeout(noticeTimer);
    // Call before yielding so the browser retains the actual user activation.
    const operation=window.__atmaMediaPage.command({type:'pip'});
    Promise.resolve(operation).catch(()=>{
      notice.textContent=russian?'Для этого видео режим маленького окна недоступен.':'Picture in Picture is unavailable for this video.';
      notice.hidden=false;noticeTimer=setTimeout(()=>{notice.hidden=true;},4000);
    }).finally(schedule);
  });
  for(const event of ['pointerdown','pointermove','touchstart'])listen(document,event,interact);
  for(const event of ['scroll','fullscreenchange'])listen(document,event,schedule);
  listen(window,'resize',schedule);
  const timer=setInterval(render,500);
  window.__atmaVideoControls={version:1,refresh:render,dispose(){stopped=true;clearInterval(timer);clearTimeout(noticeTimer);cancelAnimationFrame(frame);for(const remove of listeners)remove();host.remove();delete window.__atmaVideoControls;}};
  render();
}
