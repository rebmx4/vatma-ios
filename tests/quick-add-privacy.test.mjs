import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function setup(privateBrowsing=true,iconUrl='https://cdn.private.example/site.png'){
 const requests=[],images=[],elements=new Map(),metadataRequests=[];
 const url='https://private.example/account';
 const logo='data:image/png;base64,site-artwork';
 const element=id=>{if(!elements.has(id))elements.set(id,{dataset:{},innerHTML:'',setAttribute(key,value){this[key]=value;},getAttribute(key){return this[key];},replaceChildren(value){this.content=value;}});return elements.get(id);};
 const context={
  URL,$:element,state:{mode:'browse',url,siteName:'Private',privateBrowsing,iconUrl},apps:[],flattenApps:value=>value,icon:name=>name,
  api:async method=>{metadataRequests.push(method);return {url,iconCandidates:iconUrl?[iconUrl]:[]};},
  resolveShortcutIcon:async site=>{requests.push(site);return iconUrl?logo:'';},
  Image:class{constructor(){images.push(this);}addEventListener(type,handler){this[type]=handler;}set src(value){this.source=value;} },
 };
 vm.createContext(context);const start=source.indexOf('let pinSiteBusy='),end=source.indexOf('async function saveCurrentSite(',start);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);
 return {context,element,requests,images,metadataRequests,logo};
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
for(const icon of ['https://cdn.private.example/site.png',''])test('Incognito quick-add uses the local globe without resolving an external '+(icon?'declared icon':'fallback favicon'),()=>{
 const f=setup(true,icon);f.context.updateQuickAdd();
 assert.deepEqual(f.metadataRequests,[]);assert.deepEqual(f.requests,[]);assert.equal(f.images.length,0);
 assert.equal(f.element('pin-site').hidden,false);assert.equal(f.element('pin-site-art').innerHTML,'globe');
});
test('switching to Incognito discards a pending ordinary icon even at the same URL',async()=>{
 const f=setup(false);f.context.updateQuickAdd();await settle();assert.equal(f.requests.length,1);const oldImage=f.images[0];
 f.context.state.privateBrowsing=true;f.context.updateQuickAdd();oldImage.load();assert.equal(f.requests.length,1);assert.equal(f.element('pin-site-art').content,undefined);
 f.context.state.privateBrowsing=false;f.context.updateQuickAdd();await settle();assert.equal(f.requests.length,2);
 assert.equal(f.images[1].source,f.logo);f.images[1].load();assert.equal(f.element('pin-site-art').content,f.images[1],'Ordinary website icons remain available');
});
test('a page change during metadata lookup does not start a stale icon download',async()=>{
 const f=setup(false);
 let complete;
 f.context.api=()=>new Promise(resolve=>{complete=resolve;});
 f.context.updateQuickAdd();
 f.context.state.mode='home';f.context.updateQuickAdd();
 complete({url:f.context.state.url,iconCandidates:['https://cdn.private.example/site.png']});await settle();
 assert.deepEqual(f.requests,[]);assert.equal(f.images.length,0);
});
test('an unavailable website icon leaves the globe and saving changes the plus to a check',async()=>{
 const f=setup(false,'');f.context.updateQuickAdd();await settle();
 assert.equal(f.images.length,0);assert.equal(f.element('pin-site-art').innerHTML,'globe');
 assert.equal(f.element('pin-site-badge').innerHTML,'plus');
 f.context.apps.push({url:f.context.state.url});f.context.updateQuickAdd();
 assert.equal(f.element('pin-site-badge').innerHTML,'check');
 assert.equal(f.requests.length,1,'Saving the site does not reload the artwork');
});
