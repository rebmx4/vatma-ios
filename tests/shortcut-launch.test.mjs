import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function setup({privateScope=false}={}){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const start=source.indexOf('async function launchShortcut('),end=source.indexOf('async function setPanel(',start);
 assert.ok(start>0&&end>start);
 const effects=[],context={shortcutLaunchVersion:0,vaultKey:privateScope?{}:null,profiles:[{id:'actual-device'}],state:{profileId:'actual-device'},api:async()=>{throw Error('Shortcut launch must not resolve or choose a device');},saveApps:async()=>{throw Error('Shortcut launch must not rewrite saved login metadata');},launch:async(url,scope,options)=>effects.push([url,scope,JSON.parse(JSON.stringify(options))]),notify:message=>effects.push(['error',message])};
 vm.createContext(context);vm.runInContext(source.slice(start,end)+';this.launchShortcut=launchShortcut;',context);return{context,effects};
}
for(const profileId of [undefined,'iphone-13-pro-max','windows-chrome'])test('saved shortcut opens directly without device selection: '+profileId,async()=>{
 const f=setup();await f.context.launchShortcut({url:'https://example.com',profileId});
 assert.deepEqual(f.effects,[['https://example.com','public',{webApp:true}]]);
});
test('locked private shortcuts cannot open',async()=>{
 const f=setup();await f.context.launchShortcut({url:'https://private.example.com'},'private');assert.deepEqual(f.effects,[]);
});
test('an unlocked private shortcut opens directly with the normal website session',async()=>{
 const f=setup({privateScope:true});await f.context.launchShortcut({url:'https://private.example.com'},'private');
 assert.deepEqual(f.effects,[['https://private.example.com','private',{webApp:true}]]);
});
