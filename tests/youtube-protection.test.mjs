import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const path=new URL('../BrowserUI/assets/youtube-protection.js',import.meta.url);
function setup(host='www.youtube.com',options={enabled:true}){
 const listeners=new Map(),styles=new Map();
 const document={readyState:'loading',head:{append(n){styles.set(n.id,n);}},documentElement:{},querySelector:()=>null,querySelectorAll:()=>[],getElementById:id=>styles.get(id),createElement:()=>({remove(){styles.delete(this.id);}}),addEventListener(n,f){listeners.set(n,f);},removeEventListener(n){listeners.delete(n);}};
 class Response{async json(){return this.value;}}
 class XMLHttpRequest{get response(){return this.value;}}
 const context={document,location:{hostname:host,href:`https://${host}/watch?v=fixture`},Response,XMLHttpRequest,MutationObserver:class{observe(){}disconnect(){}},setInterval:()=>1,clearInterval(){},setTimeout:()=>1,clearTimeout(){},URL,console};
 context.window=context;
 vm.createContext(context);
 const source=fs.existsSync(path)?fs.readFileSync(path,'utf8'):'';
 if(source)vm.runInContext(`(${source})(${JSON.stringify(options)})`,context);
 return{context,parse:input=>vm.runInContext(`JSON.parse(${JSON.stringify(JSON.stringify(input))})`,context)};
}
const player=()=>({videoDetails:{videoId:'fixture',lengthSeconds:'180'},playabilityStatus:{status:'OK'},streamingData:{formats:[{url:'https://media.invalid/video'}]},playerAds:[{ad:1}],adPlacements:[{placement:1}],adSlots:[{slot:1}]});
test('own adapter removes ad fields while preserving playback, streams and ordinary JSON',()=>{
 const f=setup();assert.ok(f.context.__atmaYouTubeProtection,'YouTube adapter must be installed');
 const result=f.parse(player());assert.equal(result.playerAds,undefined);assert.equal(result.adPlacements,undefined);assert.equal(result.adSlots,undefined);
 assert.equal(result.playabilityStatus.status,'OK');assert.equal(result.streamingData.formats[0].url,'https://media.invalid/video');
 assert.deepEqual(JSON.parse(JSON.stringify(f.parse({playerAds:['application data'],value:7}))),{playerAds:['application data'],value:7});
});
test('initial player object and native Response.json are covered; disabled exception restores parsing',async()=>{
 const f=setup();assert.ok(f.context.__atmaYouTubeProtection,'YouTube adapter must be installed');
 f.context.ytInitialPlayerResponse=player();assert.equal(f.context.ytInitialPlayerResponse.playerAds,undefined);
 const response=new f.context.Response();response.value=player();assert.equal((await response.json()).adPlacements,undefined);
 f.context.__atmaYouTubeProtection.setEnabled(false);assert.equal(f.parse(player()).playerAds.length,1);
 f.context.__atmaYouTubeProtection.setEnabled(true);assert.equal(f.parse(player()).playerAds,undefined);
});
test('unrelated and lookalike hosts are untouched; disabled starts without stripping ads',()=>{
 for(const host of ['example.com','youtube.com.example.invalid']){const f=setup(host);assert.equal(f.context.__atmaYouTubeProtection,undefined);assert.equal(f.parse(player()).playerAds.length,1);}
 const f=setup('www.youtube.com',{enabled:false});assert.equal(f.parse(player()).playerAds.length,1);
});
test('native XHR JSON player responses are filtered, ordinary endpoints and exceptions are preserved',()=>{
 const f=setup(),xhr=new f.context.XMLHttpRequest();xhr.responseType='json';xhr.responseURL='https://www.youtube.com/youtubei/v1/player?prettyPrint=false';xhr.value=player();
 assert.equal(xhr.response.playerAds,undefined);
 xhr.responseURL='https://www.youtube.com/application-data';xhr.value=player();assert.equal(xhr.response.playerAds.length,1);
 xhr.responseURL='https://www.youtube.com/youtubei/v1/player';f.context.__atmaYouTubeProtection.setEnabled(false);assert.equal(xhr.response.playerAds.length,1);
});
test('ad fallback never seeks the main video or unknown/live streams',()=>{
 for(const duration of [180,Infinity,NaN]){
  const f=setup();f.parse(player());const video={duration,currentTime:12,currentSrc:'blob:fixture',muted:false};
  f.context.document.querySelector=()=>({classList:{contains:()=>true},querySelector:selector=>selector==='video'?video:null});
  f.context.__atmaYouTubeProtection.refresh();assert.equal(video.currentTime,12);
  f.context.__atmaYouTubeProtection.setEnabled(false);assert.equal(video.muted,false);
 }
});
test('prefetched metadata and a stale ad class cannot skip or mute main content',()=>{
 const f=setup();f.parse(player());f.parse({...player(),videoDetails:{videoId:'prefetched',lengthSeconds:'250'}});
 const video={duration:180,currentTime:40,currentSrc:'blob:main-content',muted:false};
 f.context.document.querySelector=()=>({classList:{contains:()=>true},querySelector:selector=>selector==='video'?video:null});
 f.context.__atmaYouTubeProtection.refresh();assert.equal(video.currentTime,40);assert.equal(video.muted,false);
});
test('automatic ad skipping preserves an intentional pause',()=>{
 const f=setup(),video={paused:true,ended:false};let clicks=0;
 const button={disabled:false,getClientRects:()=>[{}],click(){clicks++;video.paused=false;}};
 f.context.document.querySelector=()=>({classList:{contains:()=>true},querySelector:selector=>selector==='video'?video:button});
 f.context.__atmaYouTubeProtection.refresh();assert.equal(clicks,0);assert.equal(video.paused,true);
 video.paused=false;f.context.__atmaYouTubeProtection.refresh();assert.equal(clicks,1);
});
