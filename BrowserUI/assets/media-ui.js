export function renderMediaPlayer(root,{api,notify,openTab,t=value=>value}){
 const glyph=path=>`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>`;
 const play=glyph('<path d="m9 5 11 7-11 7Z" fill="currentColor"/>');
 const pause=glyph('<path d="M9 5v14m6-14v14" stroke-width="4"/>');
 root.innerHTML=`<div class="media-player" id="media-player">
  <div class="media-art" aria-hidden="true">${glyph('<rect x="3" y="5" width="18" height="14" rx="3"/><path d="m10 9 5 3-5 3Z" fill="currentColor"/>')}</div>
  <h2 class="media-title" data-no-translate></h2>
  <p class="media-empty">Откройте видео на сайте, запустите его и вернитесь в медиаплеер.</p>
  <div class="media-controls" hidden>
   <label class="media-seek"><span class="sr-only">Позиция воспроизведения</span><input type="range" id="media-seek" min="0" max="100" step="1" value="0" aria-label="Позиция воспроизведения"></label>
   <div class="media-times" data-no-translate><span id="media-position">0:00</span><span id="media-duration">0:00</span></div>
   <div class="media-transport">
    <button id="media-rewind" aria-label="Назад на 10 секунд">${glyph('<path d="M4 11a8 8 0 1 0 3-6M4 3v8h8"/>')}<span>10</span></button>
    <button id="media-play" class="media-play" aria-label="Воспроизвести">${play}</button>
    <button id="media-forward" aria-label="Вперёд на 10 секунд">${glyph('<path d="M20 11a8 8 0 1 1-3-6m3-2v8h-8"/>')}<span>10</span></button>
   </div>
   <button class="media-pip" id="media-pip">${glyph('<rect x="2" y="4" width="20" height="16" rx="2"/><rect x="12" y="11" width="8" height="6" rx="1" fill="currentColor"/>')}<span>Картинка в картинке</span></button>
   <p class="media-pip-note sheet-note" hidden>Маленькое окно недоступно для этого видео.</p>
   <button class="media-return" id="media-return">Открыть вкладку видео</button>
  </div>
  <label class="media-background"><span>Звук в фоне</span><input type="checkbox" id="media-background" role="switch" aria-label="Звук в фоне"></label>
  <p class="sheet-note">Маленькое окно показывает система. Возможности зависят от сайта и устройства.</p>
  <p class="media-error" role="status" hidden></p>
 </div>`;
 const $=selector=>root.querySelector(selector);let value={available:false},disposed=false,busy=false,timer,dragging=false,epoch=0;
 function clock(seconds){if(!Number.isFinite(seconds))return '—';seconds=Math.max(0,Math.floor(seconds));return `${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`;}
 function paint(next){
  if(disposed)return;value=next||{available:false};const available=value.available===true;
  $('.media-title').textContent=available?value.title||'ATMA':'';
  $('.media-empty').hidden=available;$('.media-controls').hidden=!available;
  $('#media-background').checked=value.backgroundEnabled!==false;
  if(!available)return;
  const seekable=Number.isFinite(value.duration)&&value.duration>0;
  $('#media-seek').disabled=!seekable;$('#media-rewind').disabled=!seekable;$('#media-forward').disabled=!seekable;
  if(!dragging){$('#media-seek').max=seekable?value.duration:100;$('#media-seek').value=value.currentTime||0;}
  $('#media-position').textContent=clock(value.currentTime);$('#media-duration').textContent=seekable?clock(value.duration):t('Прямой эфир');
  $('#media-play').innerHTML=value.paused?play:pause;$('#media-play').setAttribute('aria-label',t(value.paused?'Воспроизвести':'Пауза'));
  $('#media-pip').disabled=!value.pipAvailable;$('#media-pip').setAttribute('aria-pressed',String(value.pip===true));$('.media-pip-note').hidden=value.pipAvailable;
 }
 function failure(error){if(disposed)return;$('.media-error').textContent=t(error.message);$('.media-error').hidden=false;}
 async function run(action,body){
  if(busy||disposed)return;busy=true;epoch++;$('.media-error').hidden=true;
  try{paint(await api(action,body));}catch(error){failure(error);}finally{busy=false;}
 }
 $('#media-play').onclick=()=>run('media/command',{type:value.paused?'play':'pause'});
 $('#media-rewind').onclick=()=>run('media/command',{type:'skip',seconds:-10});
 $('#media-forward').onclick=()=>run('media/command',{type:'skip',seconds:10});
 $('#media-pip').onclick=()=>run('media/command',{type:'pip'});
 $('#media-return').onclick=()=>value.ownerTabId&&openTab(value.ownerTabId).catch(error=>notify(error.message));
 $('#media-background').onchange=()=>run('media/background',{enabled:$('#media-background').checked});
 $('#media-seek').onpointerdown=()=>{dragging=true;};
 $('#media-seek').oninput=()=>{$('#media-position').textContent=clock(Number($('#media-seek').value));};
 $('#media-seek').onchange=()=>{dragging=false;run('media/command',{type:'seek',seconds:Number($('#media-seek').value)});};
 $('#media-seek').onpointercancel=()=>{dragging=false;};
 async function poll(){
  if(disposed)return;
  if(!busy&&!dragging){const version=epoch;try{const next=await api('media/state');if(version===epoch&&!busy)paint(next);}catch(error){if(version===epoch)failure(error);}}
  if(!disposed)timer=setTimeout(poll,1000);
 }
 (async()=>{try{paint(await api('media/state'));paint(await api('media/activate'));}catch(error){failure(error);}finally{if(!disposed)timer=setTimeout(poll,1000);}})();
 return()=>{disposed=true;clearTimeout(timer);};
}
