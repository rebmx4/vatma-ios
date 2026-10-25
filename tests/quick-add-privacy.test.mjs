import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function setup(privateBrowsing=true,iconUrl='https://cdn.private.example/site.png'){
 const requests=[],images=[],elements=new Map();
 const element=id=>{if(!elements.has(id))elements.set(id,{dataset:{},innerHTML:'',setAttribute(key,value){this[key]=value;},getAttribute(key){return this[key];},replaceChildren(value){this.content=value;}});return elements.get(id);};
 const context={URL,$:element,state:{mode:'browse',url:'https://private.example/account',siteName:'Private',privateBrowsing,iconUrl},apps:[],flattenApps:value=>value,brand:()=> 'local-placeholder',icon:name=>name,Image:class{constructor(){images.push(this);}addEventListener(type,handler){this[type]=handler;}set src(value){requests.push(value);} }};
 vm.createContext(context);const start=source.indexOf('let pinSiteBusy='),end=source.indexOf('async function saveCurrentSite(',start);assert.ok(start>=0&&end>start);vm.runInContext(source.slice(start,end),context);
 return {context,element,requests,images};
}
for(const icon of ['https://cdn.private.example/site.png',''])test('Incognito quick-add never loads an external '+(icon?'declared icon':'fallback favicon'),()=>{
 const f=setup(true,icon);f.context.updateQuickAdd();assert.deepEqual(f.requests,[],'Private website artwork must not be fetched by the persistent browser UI');assert.equal(f.element('pin-site').hidden,false);assert.equal(f.element('pin-site-art').innerHTML,'local-placeholder');
});
test('switching to Incognito discards a pending ordinary icon even at the same URL',()=>{
 const f=setup(false);f.context.updateQuickAdd();assert.equal(f.requests.length,1);const oldImage=f.images[0];
 f.context.state.privateBrowsing=true;f.context.updateQuickAdd();oldImage.load();assert.equal(f.requests.length,1);assert.equal(f.element('pin-site-art').content,undefined);
 f.context.state.privateBrowsing=false;f.context.updateQuickAdd();assert.equal(f.requests.length,2);f.images[1].load();assert.equal(f.element('pin-site-art').content,f.images[1],'Ordinary website icons remain available');
});
