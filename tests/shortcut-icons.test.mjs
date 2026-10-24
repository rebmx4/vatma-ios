import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import * as websiteIcons from '../BrowserUI/assets/site-icons.js';
const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function setup(){
 const effects=[],elements=new Map(),apps=[];
 const element=id=>{if(!elements.has(id))elements.set(id,{innerHTML:'',append(){},addEventListener(type,handler){this[type]=handler;}});return elements.get(id);};
 const context={URL,crypto:{randomUUID:()=> 'icon-test'},Date,FormData:class{constructor(form){this.values=form;}get(key){return this.values[key];}},$ :element,escape:String,state:{mode:'browse',profileId:'iphone-13-pro-max'},editorScope:'public',vaultKey:null,pinSiteBusy:false,apps,updateQuickAdd(){},normalizedSiteUrl: url=>new URL(url).href,savedSite:()=>false,freezeSlots:value=>value,poolFor:()=>apps,findEntry:(pool,id)=>{const index=pool.findIndex(app=>app.id===id);return index<0?null:{list:pool,index,entry:pool[index]};},resolveShortcutIcon:async site=>{effects.push(['icon',site.url]);return 'data:image/png;base64,site-icon';},api:async()=>({url:'https://example.com/account',profileId:'iphone-13-pro-max',title:'Example',iconUrl:''}),saveApps:async()=>effects.push(['save',apps[0]?.iconUrl]),setPanel:async()=>{},notify:message=>effects.push(['notice',message])};
 vm.createContext(context);
 for(const [startMarker,endMarker] of [['function renderAppForm(','async function openAppEditor('],['async function saveCurrentSite(','function updateTabSurface(']]){const start=source.indexOf(startMarker),end=source.indexOf(endMarker,start);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);}
 return {context,apps,effects,element};
}
test('manual shortcut creation resolves and stores the website icon',async()=>{
 const f=setup();f.context.renderAppForm();await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Example',url:'example.com'}});
 assert.equal(f.apps[0].iconUrl,'data:image/png;base64,site-icon');assert.equal(f.apps[0].profileId,'iphone-13-pro-max');assert.deepEqual(f.effects.filter(item=>item[0]==='icon'),[['icon','https://example.com/']]);
});
test('quick add resolves a durable website icon before storing the shortcut',async()=>{
 const f=setup();await f.context.saveCurrentSite();assert.equal(f.context.apps[0].iconUrl,'data:image/png;base64,site-icon');assert.deepEqual(f.effects.filter(item=>item[0]==='icon'),[['icon','https://example.com/account']]);
});

function cacheFixture(){
 let online=false,clock=1000;const requests=[];
 const request=async(kind,url)=>{requests.push([kind,url]);if(online&&kind==='image'&&url.endsWith('/favicon.ico'))return{dataUrl:'data:image/png;base64,recovered'};throw Error('unavailable');};
 const options={now:()=>clock,normalize:async value=>value};
 const context={shortcutIconRequests:new Map(),shortcutIcons:websiteIcons.createWebsiteIconLoader?.(request,options),resolveWebsiteIcon:(site,request)=>websiteIcons.resolveWebsiteIcon(site,request,options),api:(_action,{kind,url})=>request(kind,url),Date:{now:()=>clock}};
 vm.createContext(context);const start=source.indexOf('function resolveShortcutIcon('),end=source.indexOf('function paintShortcutIcon(',start);vm.runInContext(source.slice(start,end),context);
 return{context,requests,goOnline(){online=true;},advance(ms){clock+=ms;}};
}
test('a failed icon lookup retries after the backoff when the website is reachable again',async()=>{
 const f=cacheFixture(),site={url:'https://retry.example/'};assert.equal(await f.context.resolveShortcutIcon(site),'');const first=f.requests.length;
 assert.equal(await f.context.resolveShortcutIcon(site),'');assert.equal(f.requests.length,first,'Failed lookups must not create a request storm');
 f.goOnline();f.advance(10001);assert.equal(await f.context.resolveShortcutIcon(site),'data:image/png;base64,recovered');assert.ok(f.requests.length>first);
 const successful=f.requests.length;assert.equal(await f.context.resolveShortcutIcon(site),'data:image/png;base64,recovered');assert.equal(f.requests.length,successful);
});

test('quick add waits for the new document rather than saving the preceding page during navigation',async()=>{
 const f=setup();f.context.state.loading=true;await f.context.saveCurrentSite();assert.equal(f.context.apps.length,0);assert.deepEqual(f.effects,[]);
});

for(const nextKey of [null,{}])test('late private icon lookup does not write after vault lock or re-opening',async()=>{
 let finish;const effects=[],context={vaultKey:{},resolveShortcutIcon:()=>new Promise(resolve=>{finish=resolve;}),Image:class{addEventListener(){}},poolFor:()=>{effects.push('pool');return[];},findEntry:()=>{effects.push('find');return null;},saveApps:async()=>effects.push('save')};
 vm.createContext(context);const start=source.indexOf('function paintShortcutIcon('),end=source.indexOf('let pinSiteBusy=',start);vm.runInContext(source.slice(start,end),context);
 context.paintShortcutIcon({replaceChildren(){}},{id:'private',url:'https://private.example/',custom:true},'private');context.vaultKey=nextKey;finish('data:image/png;base64,private');await Promise.resolve();await Promise.resolve();assert.deepEqual(effects,[]);
});
