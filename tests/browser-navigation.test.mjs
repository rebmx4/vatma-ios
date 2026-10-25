import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function setup(){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const begin=source.indexOf("$('address').addEventListener('input'"),end=source.indexOf("document.addEventListener('keydown'",begin);
 assert.ok(begin>0&&end>begin);
 const nodes=new Map(),documentEvents=new Map(),effects=[],timers=new Map();let timerId=0;
 class Element{constructor(){this.events=new Map();this.value='typed address';}addEventListener(name,fn){this.events.set(name,fn);}closest(selector){return selector==='.home'?get('home'):null;}}
 const get=id=>{if(!nodes.has(id))nodes.set(id,new Element());return nodes.get(id);};
 const context={Element,Math,Date,DESKTOP_HOLD_MS:550,setTimeout:fn=>{const id=++timerId;timers.set(id,fn);return id;},clearTimeout:id=>timers.delete(id),$:get,state:{activeTabId:'active',tabs:[{id:'active'}]},editing:false,panel:null,gesture:null,desktopPage:2,
 document:{body:{dataset:{surface:'home'}},querySelector:()=>get('home'),addEventListener:(name,fn)=>documentEvents.set(name,fn)},
 action:async name=>effects.push(['action',name]),setPanel:name=>effects.push(['panel',name]),saveCurrentSite:()=>effects.push(['pin']),
 newBrowserTab:()=>effects.push(['new-tab']),setEditing:value=>{context.editing=value;effects.push(['editing',value]);},
 lockVault:()=>effects.push(['lock']),chooseDesktopSurface:id=>effects.push(['desktop',id]),renderApps:()=>effects.push(['render']),showDesktopPage:n=>effects.push(['page',n])};
 vm.createContext(context);vm.runInContext(source.slice(begin,end),context);
 const click=async id=>{const handler=get(id).events.get('click');assert.equal(typeof handler,'function','Missing button action: '+id);await handler();};
 return{context,effects,get,click,documentEvents,runHolds:()=>{const work=[...timers.values()];timers.clear();work.forEach(fn=>fn());}};
}
test('back, forward, reload and Home remain usable without the device chooser',async()=>{
 const f=setup();for(const id of ['go-back','go-forward','refresh','go-home'])await f.click(id);
 assert.deepEqual(f.effects.filter(e=>e[0]==='action'),[['action','back'],['action','forward'],['action','refresh'],['action','home']]);
 assert.ok(f.effects.some(e=>e[0]==='desktop'&&e[1]==='active'));assert.equal(f.context.desktopPage,0);assert.equal(f.get('address').value,'');
});
test('settings, save site, tabs and panel dismissal retain their button actions',async()=>{
 const f=setup();for(const id of ['settings','pin-site','tabs-button','new-tab-button','scrim','sheet-close'])await f.click(id);
 assert.ok(f.effects.some(e=>e[0]==='pin'));assert.deepEqual(f.effects.filter(e=>e[0]==='panel'),[['panel','settings'],['panel','tabs'],['panel',null],['panel',null]]);
 f.context.state.tabs=[];await f.click('tabs-button');assert.equal(f.effects.filter(e=>e[0]==='new-tab').length,2);
});
test('a tap on empty desktop space still exits editing',async()=>{
 const f=setup();await f.click('edit-apps');assert.equal(f.context.editing,true);
 const event={isPrimary:true,button:0,pointerId:1,clientX:20,clientY:30,target:f.get('home')};
 f.get('home').events.get('pointerdown')(event);f.documentEvents.get('pointerup')(event);assert.equal(f.context.editing,false);
});

test('holding empty desktop space enters editing and releasing does not immediately exit it',()=>{
 const f=setup(),event={isPrimary:true,button:0,pointerId:1,clientX:20,clientY:30,target:f.get('home')};
 f.get('home').events.get('pointerdown')(event);assert.equal(f.context.editing,false);
 f.runHolds();assert.equal(f.context.editing,true);f.documentEvents.get('pointerup')(event);assert.equal(f.context.editing,true);
});
test('moving or cancelling an empty-space hold never starts editing later',()=>{
 for(const cancel of ['move','cancel']){
  const f=setup(),event={isPrimary:true,button:0,pointerId:1,clientX:20,clientY:30,target:f.get('home')};
  f.get('home').events.get('pointerdown')(event);
  if(cancel==='move')f.documentEvents.get('pointermove')({...event,clientX:40});else f.documentEvents.get('pointercancel')(event);
  f.runHolds();assert.equal(f.context.editing,false);
 }
});
