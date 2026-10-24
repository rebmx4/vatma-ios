import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const path=new URL('../BrowserUI/assets/site-media.js',import.meta.url);
function setup(){
 const video=new EventTarget();Object.assign(video,{tagName:'VIDEO',paused:true,ended:false,currentTime:20,duration:100,readyState:4,videoWidth:640,videoHeight:360,webkitPresentationMode:'inline',getBoundingClientRect:()=>({width:640,height:360}),webkitSupportsPresentationMode:()=>true,webkitSetPresentationMode(mode){this.webkitPresentationMode=mode;},play(){this.paused=false;this.dispatchEvent(new Event('play'));return Promise.resolve();},pause(){this.paused=true;this.dispatchEvent(new Event('pause'));}});
 const document=new EventTarget();Object.assign(document,{title:'Fixture video',readyState:'complete',querySelectorAll:()=>[video],pictureInPictureEnabled:false});
 const context={document,location:{hostname:'example.invalid'},MutationObserver:class{observe(){}disconnect(){}},setInterval:()=>1,clearInterval(){},setTimeout,clearTimeout,Event,URL,console};context.window=context;context.addEventListener=()=>{};context.removeEventListener=()=>{};
 vm.createContext(context);if(fs.existsSync(path))vm.runInContext(`(${fs.readFileSync(path,'utf8')})({background:true})`,context);
 return{context,document,video,api:context.__atmaMediaPage};
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
 const f=setup();await f.video.play();assert.equal(f.video.paused,true);
 await f.api.command({type:'play'});assert.equal(f.video.paused,false);
});
test('closing a hidden PiP pauses and blocks automatic resume until explicit Play',async()=>{
 const f=setup();await f.api.command({type:'play'});await f.api.command({type:'pip'});
 f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 f.api.setPageVisible?.(false);assert.equal(f.video.paused,false,'A visible PiP may play outside its website tab');
 f.video.webkitPresentationMode='inline';f.video.dispatchEvent(new Event('webkitpresentationmodechanged'));
 assert.equal(f.video.paused,true,'Closing PiP must not leave hidden audio');
 await f.video.play();assert.equal(f.video.paused,true,'The website must not undo the closure');
 await f.api.command({type:'play'});assert.equal(f.video.paused,false,'An explicit Play can resume background listening');
});
test('hiding an inline page revokes its playback rather than leaving invisible audio',async()=>{
 const f=setup();await f.api.command({type:'play'});f.api.setPageVisible?.(false);
 assert.equal(f.video.paused,true);await f.video.play();assert.equal(f.video.paused,true);
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
