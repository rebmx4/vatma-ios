import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function setup({privateScope=false}={}){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const start=source.indexOf('async function launchShortcut('),end=source.indexOf('async function setPanel(',start);
 assert.ok(start>0&&end>start);
 const effects=[],context={vaultKey:privateScope?{}:null,setEditing:()=>{},lockVault:()=>effects.push(['lock']),action:async(name,body)=>effects.push([name,JSON.parse(JSON.stringify(body))]),$:()=>({blur:()=>effects.push(['blur'])})};
 vm.createContext(context);vm.runInContext(source.slice(start,end)+';this.launchShortcut=launchShortcut;',context);return{context,effects};
}
for(const profileId of [undefined,'iphone-13-pro-max','windows-chrome'])test('saved shortcut opens directly without device selection: '+profileId,async()=>{
 const f=setup();await f.context.launchShortcut({id:'custom-1',url:'https://example.com',profileId});
 assert.deepEqual(f.effects,[['shortcut/open',{url:'https://example.com',shortcutId:'public:custom-1'}],['blur']]);
});
test('locked private shortcuts cannot open',async()=>{
 const f=setup();await f.context.launchShortcut({id:'private-1',url:'https://private.example.com'},'private');assert.deepEqual(f.effects,[]);
});
test('an unlocked private shortcut opens directly with the normal website session',async()=>{
 const f=setup({privateScope:true});await f.context.launchShortcut({id:'private-1',url:'https://private.example.com'},'private');
 assert.deepEqual(f.effects,[['lock'],['shortcut/open',{url:'https://private.example.com',shortcutId:'private:private-1'}],['blur']]);
});
