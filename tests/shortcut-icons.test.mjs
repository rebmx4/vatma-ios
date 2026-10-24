import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
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
