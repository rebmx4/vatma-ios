import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function setup(){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const begin=source.indexOf('function consume(next)'),end=source.indexOf('async function newBrowserTab()',begin);
 assert.ok(begin>0&&end>begin);
 const nodes=new Map(),get=id=>{if(!nodes.has(id))nodes.set(id,{dataset:{},value:'',setAttribute(){}});return nodes.get(id);};
 const context={$:get,icon:name=>name,escape:value=>String(value??''),profiles:[],state:undefined,panel:null,renderedPanels:[],location:{origin:'http://127.0.0.1:9999'},
  document:{body:{dataset:{}},documentElement:{style:{setProperty(){}}},activeElement:null},
  chooseDesktopSurface(){},updateTabSurface(){},renderApps(){},updateQuickAdd(){},renderTabs(){}};
 context.renderPanel=()=>context.renderedPanels.push(context.panel);
 vm.createContext(context);vm.runInContext(source.slice(begin,end),context);
 const snapshot=(sequence,extra={})=>({sequence,profileId:'actual-device',mode:'home',panel:null,width:440,height:894,footerHeight:128,activeTabId:'a',tabs:[{id:'a',url:''}],...extra});
 return{context,consume:context.consume,snapshot,get};
}
test('an older native push cannot reopen Settings after its close reply',()=>{
 const f=setup();f.consume(f.snapshot(10,{panel:'settings'}));f.consume(f.snapshot(12));
 f.consume(f.snapshot(11,{panel:'settings'}));
 assert.equal(f.context.panel,null);assert.equal(f.context.state.sequence,12);
 assert.deepEqual(f.context.renderedPanels,['settings',null]);
});
test('out-of-order native state cannot undo a newer tab or its compact toolbar',()=>{
 const f=setup();f.consume(f.snapshot(30,{mode:'browse',activeTabId:'b',url:'https://example.invalid/new',webApp:true,footerHeight:86}));
 f.consume(f.snapshot(29,{activeTabId:'a',url:'https://example.invalid/old'}));
 assert.equal(f.context.state.activeTabId,'b');assert.equal(f.context.state.url,'https://example.invalid/new');
 assert.equal(f.context.document.body.dataset.webApp,'true');
 f.consume(f.snapshot(31,{mode:'browse',activeTabId:'b',url:'https://example.invalid/new',webApp:true,footerHeight:86,media:{playing:true}}));
 assert.equal(f.context.state.media.playing,true,'Newer media updates must still arrive');
});
test('a native sequence cannot be replaced by an unsequenced stale message',()=>{
 const f=setup();f.consume(f.snapshot(20));f.consume(f.snapshot(undefined,{panel:'settings'}));
 assert.equal(f.context.panel,null);assert.equal(f.context.state.sequence,20);
});
