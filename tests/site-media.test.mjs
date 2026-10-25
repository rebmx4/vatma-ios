import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const path=new URL('../BrowserUI/assets/site-media.js',import.meta.url);
function setup({queuedMediaEvents=false,mediaDevices}={}){
 const listeners=new Map(),pendingMediaEvents=[];
 const emit=(target,type)=>{const fire=()=>target.dispatchEvent(new Event(type));if(queuedMediaEvents)pendingMediaEvents.push(fire);else fire();};
 class Media extends EventTarget {addEventListener(type,callback,...args){if(!listeners.has(type))listeners.set(type,[]);listeners.get(type).push(callback);super.addEventListener(type,callback,...args);}play(){const changed=this.paused;this.paused=false;if(changed)emit(this,'play');return Promise.resolve();}pause(){if(this.paused)return;this.paused=true;emit(this,'pause');}}
 const video=new Media();Object.assign(video,{tagName:'VIDEO',paused:true,ended:false,currentTime:20,duration:100,readyState:4,videoWidth:640,videoHeight:360,webkitPresentationMode:'inline',getBoundingClientRect:()=>({width:640,height:360}),webkitSupportsPresentationMode:()=>true,webkitSetPresentationMode(mode){this.webkitPresentationMode=mode;}});
 const inputs=new Map(),document=new EventTarget(),addInput=document.addEventListener.bind(document);document.addEventListener=(type,callback,...args)=>{if(!inputs.has(type))inputs.set(type,[]);inputs.get(type).push(callback);addInput(type,callback,...args);};Object.assign(document,{title:'Fixture video',readyState:'complete',querySelectorAll:()=>[video],pictureInPictureEnabled:false});
 const context={document,HTMLMediaElement:Media,DOMException,navigator:{userActivation:{isActive:false},mediaDevices},location:{hostname:'example.invalid'},MutationObserver:class{observe(){}disconnect(){}},setInterval:()=>1,clearInterval(){},setTimeout,clearTimeout,Event,URL,console};context.window=context;context.addEventListener=()=>{};context.removeEventListener=()=>{};
 vm.createContext(context);if(fs.existsSync(path))vm.runInContext(`(${fs.readFileSync(path,'utf8')})({background:true})`,context);
 return{context,document,video,api:context.__atmaMediaPage,trustedInput(){for(const callback of inputs.get('pointerup')||[])callback({isTrusted:true});},nativePlay(){video.paused=false;const fire=()=>{for(const callback of listeners.get('play')||[])callback({isTrusted:true});};if(queuedMediaEvents)pendingMediaEvents.push(fire);else fire();},nativePause(){video.paused=true;emit(video,'pause');},flushNextMediaEvent(){pendingMediaEvents.shift()?.();},flushMediaEvents(){let count=0;while(pendingMediaEvents.length){if(++count>30)throw Error('Media event loop did not settle');pendingMediaEvents.shift()();}} };
}
test('media commands use the original element, preserve position and honor deliberate pause',async()=>{
 const f=setup();assert.ok(f.api,'Media controller must be installed');
 assert.equal(f.api.state().title,'Fixture video');await f.api.command({type:'play'});assert.equal(f.video.paused,false);
 await f.api.command({type:'skip',seconds:10});assert.equal(f.video.currentTime,30);
 await f.api.command({type:'seek',seconds:999});assert.equal(f.video.currentTime,100);
 await f.api.command({type:'pause'});assert.equal(f.video.paused,true);
});
test('PiP reports actual presentation and invalid commands/values reject',async()=>{
 const f=setup();assert.ok(f.api,'Media controller must be installed');
 await f.api.command({type:'pip'});assert.equal(f.api.state().pip,true);
 await assert.rejects(()=>f.api.command({type:'navigate',url:'https://example.invalid'}));
 await assert.rejects(()=>f.api.command({type:'seek',seconds:NaN}));
 f.video.webkitSupportsPresentationMode=()=>false;f.video.webkitSetPresentationMode=undefined;
 await assert.rejects(()=>f.api.command({type:'pip'}));
});
test('releasing a media page pauses playback and closes the page presentation',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 assert.equal(typeof f.api.release,'function');await f.api.release();assert.equal(f.video.paused,true);assert.equal(f.video.webkitPresentationMode,'inline');
});

test('a website cannot start video before the user requests playback',async()=>{
 const f=setup();await f.video.play().catch(()=>{});assert.equal(f.video.paused,true);
 await f.api.command({type:'play'});assert.equal(f.video.paused,false);
});
test('closing a hidden PiP pauses and blocks automatic resume until explicit Play',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 f.api.setPageVisible?.(false);assert.equal(f.video.paused,false,'A visible PiP may play outside its website tab');
 f.video.webkitPresentationMode='inline';f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 assert.equal(f.video.paused,true,'Closing PiP must not leave hidden audio');
 await f.video.play().catch(()=>{});assert.equal(f.video.paused,true,'The website must not undo the closure');
 await f.api.command({type:'play'});assert.equal(f.video.paused,false,'An explicit Play can resume background listening');
});
test('hiding an inline page revokes its playback rather than leaving invisible audio',async()=>{
 const f=setup();await f.api.command({type:'play'});f.api.setPageVisible?.(false);
 assert.equal(f.video.paused,true);await f.video.play().catch(()=>{});assert.equal(f.video.paused,true);
 f.api.setPageVisible?.(true);await f.api.command({type:'play'});assert.equal(f.video.paused,false);
});
test('locking the screen preserves an intentionally started player',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));f.api.setScreenLocked?.(true);
 f.document.hidden=true;f.document.dispatchEvent(new Event('visibilitychange'));
 assert.equal(f.video.paused,false);
 f.video.webkitPresentationMode='inline';f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 assert.equal(f.video.paused,false,'Locking may hide the system window but must keep intentional audio');
});

test('closing PiP outside the app pauses even when its tab remains selected',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 f.document.hidden=true;f.video.webkitPresentationMode='inline';f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 assert.equal(f.video.paused,true);
});

test('a website cannot undo a pause made in the system PiP controls',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));f.api.setPageVisible(false);
 f.video.pause();await f.video.play().catch(()=>{});assert.equal(f.video.paused,true);
 await f.api.command({type:'play'});assert.equal(f.video.paused,false);
});
test('a user can play audio from a custom button without a visible audio rectangle',async()=>{
 const f=setup();f.video.tagName='AUDIO';f.video.getBoundingClientRect=()=>({width:0,height:0});
 f.trustedInput();await f.video.play().catch(()=>{});
 assert.equal(f.video.paused,false);
});

test('an internal autoplay event is rejected before the first user playback request',()=>{
 const f=setup();f.nativePlay();assert.equal(f.video.paused,true);
});
test('native PiP Play remains available after a deliberate system pause',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));f.api.setPageVisible(false);
 f.video.pause();assert.equal(f.video.paused,true);f.nativePlay();assert.equal(f.video.paused,false);
});

test('native JavaScript activation without actual page input cannot authorize playback',async()=>{
 const f=setup();f.context.navigator.userActivation.isActive=true;await f.video.play().catch(()=>{});assert.equal(f.video.paused,true,'WKWebView script evaluation can force activation without a real user request');
});

test('an internal inline play event cannot undo a user pause',async()=>{
 const f=setup();await f.api.command({type:'play'});f.video.pause();f.nativePlay();assert.equal(f.video.paused,true);
});

test('a queued autoplay-denial pause cannot cancel a newer explicit Play',async()=>{
 const f=setup({queuedMediaEvents:true});f.nativePlay();f.flushNextMediaEvent();assert.equal(f.video.paused,true,'Unrequested autoplay must stop immediately');
 await f.api.command({type:'play'});f.flushMediaEvents();assert.equal(f.video.paused,false,'The old guard pause must not revoke the newer user Play');
});
test('a genuine system pause still defeats an automatic restart before its pause event arrives',async()=>{
 const f=setup({queuedMediaEvents:true});await f.api.command({type:'play'});f.flushMediaEvents();
 f.nativePause();f.nativePlay();f.flushMediaEvents();assert.equal(f.video.paused,true,'A real pause must revoke the existing playback even when website events are queued');
});

function captureFixture(){
 let finish,clock=1000,requests=[];const stream={getTracks:()=>[{readyState:'live',kind:'video'}]};
 const devices={getUserMedia(constraints){requests.push({receiver:this,constraints});return new Promise(resolve=>{finish=()=>resolve(stream);});}};
 const f=setup({mediaDevices:devices});f.context.Date={now:()=>clock};
 return {...f,stream,devices,requests,finish:()=>finish(),advance:ms=>clock+=ms};
}
test('an approved camera preview can start after the permission prompt outlasts the playback gesture',async()=>{
 const f=captureFixture();f.trustedInput();const constraints={video:true,audio:false},permission=f.context.navigator.mediaDevices.getUserMedia(constraints);f.advance(5000);f.finish();f.video.srcObject=await permission;
 await f.video.play();assert.equal(f.video.paused,false);assert.equal(f.requests.length,1);assert.equal(f.requests[0].constraints,constraints);assert.equal(f.requests[0].receiver,f.devices);
});
test('camera approval never authorizes an unrelated or hidden media stream',async()=>{
 const f=captureFixture();f.trustedInput();const permission=f.context.navigator.mediaDevices.getUserMedia({video:true});f.advance(5000);f.finish();await permission;
 f.video.srcObject={getTracks:()=>[{readyState:'live',kind:'audio'}]};await assert.rejects(()=>f.video.play(),{name:'NotAllowedError'});
 f.video.srcObject=f.stream;f.trustedInput();await f.video.play();f.api.setPageVisible(false);assert.equal(f.video.paused,true);await assert.rejects(()=>f.video.play(),{name:'NotAllowedError'});
 f.api.setPageVisible(true);await assert.rejects(()=>f.video.play(),{name:'NotAllowedError'});f.trustedInput();await f.video.play();assert.equal(f.video.paused,false);
});
test('camera permission denials remain unchanged and never start capture automatically',async()=>{
 const denial=new DOMException('Permission denied','NotAllowedError');let calls=0;const devices={getUserMedia(){calls++;return Promise.reject(denial);}},f=setup({mediaDevices:devices});
 assert.equal(calls,0);await assert.rejects(()=>f.context.navigator.mediaDevices.getUserMedia({audio:true}),error=>error===denial);assert.equal(calls,1);await assert.rejects(()=>f.video.play(),{name:'NotAllowedError'});
});

test('a newly permitted camera can reuse an element that was deliberately paused for ordinary media',async()=>{
 const f=captureFixture();await f.api.command({type:'play'});await f.api.command({type:'pause'});f.trustedInput();const permission=f.context.navigator.mediaDevices.getUserMedia({video:true});f.advance(5000);f.finish();f.video.srcObject=await permission;await f.video.play();assert.equal(f.video.paused,false);
});
test('a user pause of a granted camera preview cannot be undone automatically',async()=>{
 const f=captureFixture();const permission=f.context.navigator.mediaDevices.getUserMedia({video:true});f.advance(5000);f.finish();f.video.srcObject=await permission;await f.video.play();f.nativePause();await assert.rejects(()=>f.video.play(),{name:'NotAllowedError'});f.trustedInput();await f.video.play();assert.equal(f.video.paused,false);
});
