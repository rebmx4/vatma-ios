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
test('YouTube adapter removes known ad fields and keeps playable metadata',()=>{
 const f=setup(),result=f.parse(player());
 assert.ok(f.context.__atmaYouTubeProtection);
 assert.equal(result.playerAds,undefined);
 assert.equal(result.adPlacements,undefined);
 assert.equal(result.adSlots,undefined);
 assert.equal(result.videoDetails.videoId,'fixture');
 assert.equal(result.streamingData.formats.length,1);
});
