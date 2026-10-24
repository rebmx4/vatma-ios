import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function setup(app,{profile='iphone-13-pro-max',privateScope=false}={}){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const start=source.indexOf('async function launchShortcut('),end=source.indexOf('async function setPanel(',start);
 assert.ok(start>0&&end>start);
 const effects=[],context={shortcutLaunchVersion:0,vaultKey:privateScope?{}:null,profiles:[{id:'actual-device'},{id:'iphone-13-pro-max'}],state:{profileId:'actual-device'},pendingShortcut:null,api:async(action,body)=>{effects.push(['resolve',action,body.url]);return{profileId:profile};},saveApps:async scope=>{effects.push(['save',scope,app.profileId]);},launch:async(url,scope,options)=>effects.push(['open',url,scope,options.profileId]),setPanel:async panel=>effects.push(['panel',panel]),notify:message=>effects.push(['error',message])};
 vm.createContext(context);vm.runInContext(source.slice(start,end)+';this.launchShortcut=launchShortcut;',context);return{context,effects};
}
test('a pinned app launches its original profile without consulting the global selection',async()=>{
 const app={url:'https://example.com',profileId:'iphone-13-pro-max'},f=setup(app);await f.context.launchShortcut(app);
 assert.deepEqual(f.effects,[['open','https://example.com','public','iphone-13-pro-max']]);
});
test('a legacy app resolves and saves its existing profile before launch without a model chooser',async()=>{
 const app={url:'https://example.com'},f=setup(app);await f.context.launchShortcut(app);
 assert.equal(app.profileId,'iphone-13-pro-max');
 assert.deepEqual(f.effects,[['resolve','shortcut-profile','https://example.com'],['save','public','iphone-13-pro-max'],['open','https://example.com','public','iphone-13-pro-max']]);
});
test('locking the private desktop while legacy lookup waits cancels its launch',async()=>{
 const app={url:'https://private.example.com'},f=setup(app,{privateScope:true});let resolve;f.context.api=()=>new Promise(done=>{resolve=done;});
 const pending=f.context.launchShortcut(app,'private');f.context.vaultKey=null;assert.equal(typeof resolve,'function','Legacy launch must start lookup before waiting');resolve({profileId:'iphone-13-pro-max'});await pending;
 assert.deepEqual(f.effects,[]);assert.equal(app.profileId,undefined);
});
