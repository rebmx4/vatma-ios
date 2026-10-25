import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import * as websiteIcons from '../BrowserUI/assets/site-icons.js';
import * as shortcutArtwork from '../BrowserUI/assets/shortcut-artwork.js';
import * as messageBadges from '../BrowserUI/assets/message-badges.js';
const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function setup(){
 const effects=[],elements=new Map(),apps=[];
 const element=id=>{if(!elements.has(id))elements.set(id,{innerHTML:'',hidden:false,disabled:false,value:'',append(){},addEventListener(type,handler){this[type]=handler;},elements:{namedItem:name=>element(name)}});return elements.get(id);};
 const context={...shortcutArtwork,...messageBadges,appEditorVersion:0,panel:'edit',URL,crypto:{randomUUID:()=> 'icon-test'},Date,FormData:class{constructor(form){this.values=form;}get(key){return this.values[key];}},$ :element,escape:String,state:{mode:'browse',profileId:'iphone-13-pro-max'},editorScope:'public',vaultKey:null,pinSiteBusy:false,apps,updateQuickAdd(){},normalizedSiteUrl: url=>new URL(url).href,savedSite:()=>false,freezeSlots:value=>value,poolFor:()=>apps,findEntry:(pool,id)=>{const index=pool.findIndex(app=>app.id===id);return index<0?null:{list:pool,index,entry:pool[index]};},resolveShortcutIcon:async site=>{effects.push(['icon',site.url]);return 'data:image/png;base64,site-icon';},api:async()=>({url:'https://example.com/account',profileId:'iphone-13-pro-max',title:'Example',iconUrl:''}),saveApps:async()=>effects.push(['save',apps[0]?.iconUrl]),settingButton:()=>({}),setPanel:async()=>{},notify:message=>effects.push(['notice',message])};
 vm.createContext(context);
 for(const [startMarker,endMarker] of [['function brand(','async function api('],['function renderAppForm(','async function openAppEditor('],['async function saveCurrentSite(','function updateTabSurface(']]){const start=source.indexOf(startMarker),end=source.indexOf(endMarker,start);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);}
 return {context,apps,effects,element};
}
test('manual shortcut creation resolves and stores the website icon',async()=>{
 const f=setup();f.context.renderAppForm();await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Example',url:'example.com'}});
 assert.equal(f.apps[0].iconUrl,'data:image/png;base64,site-icon');assert.equal(f.apps[0].profileId,undefined);assert.deepEqual(f.effects.filter(item=>item[0]==='icon'),[['icon','https://example.com/']]);
});
test('quick add resolves a durable website icon before storing the shortcut',async()=>{
  const f=setup();await f.context.saveCurrentSite();assert.equal(f.context.apps[0].iconUrl,'data:image/png;base64,site-icon');assert.deepEqual(f.effects.filter(item=>item[0]==='icon'),[['icon','https://example.com/account']]);
});
test('quick add of a messaging site asks before enabling its local count',async()=>{
  const f=setup();f.context.api=async()=>({url:'https://m.vk.ru/feed',title:'ВКонтакте',iconUrl:''});
  f.context.setPanel=async name=>f.effects.push(['panel',name]);
  await f.context.saveCurrentSite();
  assert.equal(f.context.apps[0].messageNotifications,false);
  assert.deepEqual(f.effects.filter(item=>item[0]==='panel'),[['panel','message-prompt']]);
});
test('manual creation saves the simple message-count choice',async()=>{
  const f=setup();f.context.renderAppForm();
  await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'ВК',url:'https://m.vk.ru/',messageNotifications:'on'}});
  assert.equal(f.apps[0].messageNotifications,true);
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
 let finish;const effects=[],context={...shortcutArtwork,vaultKey:{},resolveShortcutIcon:()=>new Promise(resolve=>{finish=resolve;}),Image:class{addEventListener(){}},poolFor:()=>{effects.push('pool');return[];},findEntry:()=>{effects.push('find');return null;},saveApps:async()=>effects.push('save')};
 vm.createContext(context);const start=source.indexOf('function paintShortcutIcon('),end=source.indexOf('let pinSiteBusy=',start);vm.runInContext(source.slice(start,end),context);
 context.paintShortcutIcon({replaceChildren(){}},{id:'private',url:'https://private.example/',custom:true},'private');context.vaultKey=nextKey;finish('data:image/png;base64,private');await Promise.resolve();await Promise.resolve();assert.deepEqual(effects,[]);
});

for(const scope of ['public','private'])test('resolving a '+scope+' shortcut icon preserves the desktop button while saving the icon',async()=>{
 let finish,desktopButton={id:'held-button'},folderButton=desktopButton;const heldButton=desktopButton,stored=new Map();
 const entry={id:'site',custom:true,url:'https://icons.example/'},items=[entry];
 const context={...shortcutArtwork,structuredClone,vaultKey:{},vaultApps:items,vaultRecord:{},vaultWrite:Promise.resolve(),apps:items,panel:'folder',resolveShortcutIcon:()=>new Promise(resolve=>{finish=resolve;}),Image:class{addEventListener(){}},poolFor:()=>items,findEntry:()=>({entry}),localStorage:{setItem:(key,value)=>stored.set(key,JSON.parse(value))},sealVault:async(_key,apps)=>({encrypted:apps}),renderApps(){desktopButton={id:'replacement'};},renderFolder(){folderButton={id:'replacement'};},updateQuickAdd(){},scheduleMessageBadgePoll(){},notify:assert.fail};
 vm.createContext(context);
 for(const [startMarker,endMarker] of [['function paintShortcutIcon(','let pinSiteBusy='],["function saveApps(",'\nfunction ']]){const start=source.indexOf(startMarker),end=source.indexOf(endMarker,start+startMarker.length);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);}
 context.paintShortcutIcon({replaceChildren(){}},entry,scope);finish('data:image/png;base64,loaded');
 await new Promise(resolve=>setImmediate(resolve));await context.vaultWrite;
 assert.equal(desktopButton,heldButton,'An asynchronous icon update must not replace the pressed desktop button');
 assert.equal(folderButton,heldButton,'An asynchronous icon update must not replace the pressed folder button');
 const saved=scope==='private'?stored.get('atma-preview-vault').encrypted:stored.get('atma-preview-apps');
 assert.equal(saved[0].iconUrl,'data:image/png;base64,loaded');
});

test('a selected shortcut icon is saved without fetching unused site artwork',async()=>{
 const f=setup();f.context.renderAppForm();await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Chat',url:'example.com',iconStyle:'chat'}});
 assert.equal(f.apps[0].iconStyle,'chat');assert.equal(f.apps[0].iconUrl,'');assert.deepEqual(f.effects.filter(item=>item[0]==='icon'),[]);
});
test('editing a built-in shortcut to another URL enables the new website artwork',async()=>{
 const f=setup(),app={id:'vk',name:'VK',url:'https://vk.com/',custom:false};f.apps.push(app);f.context.renderAppForm(app);
 await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Other',url:'https://example.com/',iconStyle:'site'}});
 assert.equal(f.apps[0].custom,true);assert.equal(f.apps[0].iconUrl,'data:image/png;base64,site-icon');
});
test('an unsupported icon choice falls back to the real website icon',async()=>{
 const f=setup();f.context.renderAppForm();await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Example',url:'example.com',iconStyle:'not-a-choice'}});
 assert.equal(f.apps[0].iconStyle,'site');assert.equal(f.apps[0].iconUrl,'data:image/png;base64,site-icon');
});
test('a pending original icon cannot override a later custom choice',async()=>{
 let finish,saves=0;const entry={id:'site',url:'https://icons.example/',custom:true},images=[];
 const context={...shortcutArtwork,vaultKey:null,resolveShortcutIcon:()=>new Promise(resolve=>{finish=resolve;}),Image:class{constructor(){images.push(this);}addEventListener(){}},poolFor:()=>[entry],findEntry:()=>({entry}),saveApps:async()=>{saves++;}};
 vm.createContext(context);const start=source.indexOf('function paintShortcutIcon('),end=source.indexOf('let pinSiteBusy=',start);vm.runInContext(source.slice(start,end),context);
 context.paintShortcutIcon({replaceChildren(){}},entry,'public');entry.iconStyle='chat';finish('data:image/png;base64,old');await new Promise(resolve=>setImmediate(resolve));
 assert.equal(images.length,0);assert.equal(saves,0);assert.equal(entry.iconUrl,undefined);
});

test('a delayed save cannot replace a newer edit of the same shortcut',async()=>{
 const f=setup(),app={id:'site',name:'Before',url:'https://example.com/',custom:true};f.apps.push(app);let finish;
 f.context.resolveShortcutIcon=()=>new Promise(resolve=>{finish=resolve;});f.context.renderAppForm(app);
 const oldSave=f.element('app-form').submit({preventDefault(){},currentTarget:{name:'First submit',url:app.url,iconStyle:'site'}});
 f.context.panel=null;f.context.panel='edit';f.context.renderAppForm(app);
 await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Newer choice',url:app.url,iconStyle:'chat'}});
 finish('data:image/png;base64,old');await oldSave;
 assert.equal(f.apps[0].name,'Newer choice');assert.equal(f.apps[0].iconStyle,'chat');assert.equal(f.effects.filter(item=>item[0]==='save').length,1);
});
test('closing the editor cancels an unfinished icon lookup before it saves',async()=>{
 const f=setup();let finish;f.context.resolveShortcutIcon=()=>new Promise(resolve=>{finish=resolve;});f.context.renderAppForm();
 const pending=f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Cancelled',url:'https://example.com/',iconStyle:'site'}});
 f.context.panel=null;finish('data:image/png;base64,old');await pending;assert.equal(f.apps.length,0);assert.equal(f.effects.filter(item=>item[0]==='save').length,0);
});

test('the Add panel saves a new shortcut with the original website icon',async()=>{
 const f=setup();f.context.panel='add';f.context.renderAppForm();await f.element('app-form').submit({preventDefault(){},currentTarget:{name:'Added',url:'example.com',iconStyle:'site'}});
 assert.equal(f.apps.length,1);assert.equal(f.apps[0].iconUrl,'data:image/png;base64,site-icon');
});
