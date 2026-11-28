import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {bundledSiteArtwork} from '../BrowserUI/desktop-defaults.js';
const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function setup(privateBrowsing=true,iconUrl='https://cdn.private.example/site.png'){
 const requests=[],images=[],elements=new Map(),metadataRequests=[],writes=[],unlocks=[];
 const url='https://private.example/account';
 const logo='data:image/png;base64,site-artwork';
 const element=id=>{if(!elements.has(id))elements.set(id,{dataset:{},innerHTML:'',setAttribute(key,value){this[key]=value;},getAttribute(key){return this[key];},replaceChildren(value){this.content=value;}});return elements.get(id);};
 const context={
  bundledSiteArtwork,restartPinShine(){},
  URL,crypto,$:element,state:{activeTabId:'site',mode:'browse',url,siteName:'Private',privateBrowsing,iconUrl},apps:[],vaultApps:[],vaultKey:null,
  poolFor:scope=>scope==='private'?context.vaultApps:context.apps,
  updatePool:async(scope,entries)=>{writes.push(scope);context[scope==='private'?'vaultApps':'apps']=entries;},
  flattenApps:value=>value,freezeSlots:value=>value,icon:name=>name,reportError:assert.fail,
  requestVault:()=>unlocks.push(vm.runInContext('pendingVaultSite',context)),
  api:async method=>{metadataRequests.push(method);return {url,iconCandidates:iconUrl?[iconUrl]:[]};},
  resolveShortcutIcon:async site=>{requests.push(site);return iconUrl?logo:'';},
  Image:class{constructor(){images.push(this);}addEventListener(type,handler){this[type]=handler;}set src(value){this.source=value;} },
 };
 vm.createContext(context);const start=source.indexOf('let pinSiteBusy='),end=source.indexOf('function updateTabSurface(',start);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);
 return {context,element,requests,images,metadataRequests,logo,writes,unlocks};
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));
test('results show the search engine logo and follow the selected site after navigation',async()=>{
 const f=setup(true);
 f.context.state.url='https://www.google.com/search?q=vk';
 f.context.updateQuickAdd();
 const google=f.images[0];
 assert.match(google.source,/google\.com\.png$/);
 f.context.state.url='https://m.vk.ru/feed';
 f.context.updateQuickAdd();
 const vk=f.images[1];google.load();vk.load();
 assert.match(vk.source,/\/vk\.png$/);
 assert.equal(f.element('pin-site-art').content,vk);
 assert.deepEqual(f.requests,[]);
});
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
for(const flag of ['privateBrowsing','privateDesktop'])test(`quick add from ${flag} authenticates and stores only in the private pool`,async()=>{
 const f=setup(false);
 f.context.state[flag]=true;
 f.context.apps.push({url:f.context.state.url});
 await f.context.saveCurrentSite();
 assert.equal(f.unlocks.length,1);
 assert.deepEqual(f.metadataRequests,[]);
 assert.deepEqual(f.writes,[]);
 f.context.vaultKey={};
 await f.context.saveCurrentSite(f.unlocks[0]);
 assert.deepEqual(f.writes,['private']);
 assert.equal(f.context.apps.length,1);
 assert.equal(f.context.vaultApps[0].url,f.context.state.url);
 assert.equal(f.context.vaultApps[0].iconUrl,f.logo);
 assert.equal(f.element('pin-site-badge').innerHTML,'check');
});
test('a delayed private quick add is discarded when the tab changes or the vault locks',async()=>{
 for(const invalidate of [context=>{context.state.activeTabId='other';},context=>{context.vaultKey=null;}]){
  const f=setup();
  f.context.vaultKey={};
  let finish;
  f.context.resolveShortcutIcon=()=>new Promise(resolve=>{finish=resolve;});
  const pending=f.context.saveCurrentSite();
  await settle();
  invalidate(f.context);
  finish(f.logo);
  await pending;
  assert.deepEqual(f.writes,[]);
  assert.equal(f.context.apps.length,0);
  assert.equal(f.context.vaultApps.length,0);
 }
});
