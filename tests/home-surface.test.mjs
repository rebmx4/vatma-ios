import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function browser(){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 const begin=source.indexOf('function updateTabSurface()'),end=source.indexOf('async function newBrowserTab()',begin);
 assert.ok(begin>0&&end>begin);
 const controls=new Map();
 const element=id=>{if(!controls.has(id))controls.set(id,{dataset:{},value:'',setAttribute(){}});return controls.get(id);};
 const context={state:undefined,profiles:[],panel:null,busy:false,desktopTabId:null,desktopSurfaceKey:'desktop',
  document:{body:{dataset:{}},documentElement:{style:{setProperty(){}}},activeElement:null},
  sessionStorage:{setItem(){},removeItem(){}},location:{origin:'https://ui.invalid'},$:element,
  icon:name=>name,renderPanel(){},renderApps(){},renderTabs(){},updateQuickAdd(){}};
 vm.createContext(context);
 vm.runInContext(source.slice(begin,end)+';this.consume=consume;this.chooseDesktopSurface=chooseDesktopSurface;',context);
 return context;
}
function payload(id,tabs=[{id,url:''}]){return{profileId:'actual-device',mode:'home',activeTabId:id,tabs,width:440,height:950,footerHeight:166};}

test('a fresh launch shows the saved website desktop, not an empty new-tab surface',()=>{
 const page=browser();page.consume(payload('initial'));
 assert.equal(page.document.body.dataset.surface,'home');
});
test('new blank tabs stay blank after the initial desktop is chosen',()=>{
 const page=browser();page.consume(payload('initial'));page.consume(payload('new'));
 assert.equal(page.document.body.dataset.surface,'blank');
 page.chooseDesktopSurface('new');page.consume(payload('new'));
 assert.equal(page.document.body.dataset.surface,'home');
});

test('a loaded first page keeps both history arrows disabled',()=>{
 const page=browser();page.consume({...payload('first'),mode:'browse',url:'https://example.test/a',canGoBack:false,canGoForward:false});
 assert.equal(page.$('go-back').disabled,true);assert.equal(page.$('go-forward').disabled,true);
});
test('history arrows follow native navigation and a return to an earlier page',()=>{
 const page=browser();const state={...payload('active'),mode:'browse',url:'https://example.test/b'};
 page.consume({...state,canGoBack:true,canGoForward:false});
 assert.equal(page.$('go-back').disabled,false);assert.equal(page.$('go-forward').disabled,true);
 page.consume({...state,url:'https://example.test/a',canGoBack:false,canGoForward:true});
 assert.equal(page.$('go-back').disabled,true);assert.equal(page.$('go-forward').disabled,false);
 page.consume({...state,url:'https://example.test/c',canGoBack:true,canGoForward:false});
 assert.equal(page.$('go-forward').disabled,true);
});
test('switching tabs and returning home cannot reuse another tabs history availability',()=>{
 const page=browser();page.consume({...payload('older'),mode:'browse',canGoBack:true,canGoForward:true});
 page.consume({...payload('fresh'),mode:'browse',canGoBack:false,canGoForward:false});
 assert.equal(page.$('go-back').disabled,true);assert.equal(page.$('go-forward').disabled,true);
 page.consume({...payload('older'),canGoBack:true,canGoForward:true});
 assert.equal(page.$('go-back').disabled,true);assert.equal(page.$('go-forward').disabled,true);
});

test('an incognito blank tab opens its own start surface rather than the saved desktop',()=>{
 const page=browser();page.consume({...payload('private'),privateBrowsing:true});
 assert.equal(page.document.body.dataset.surface,'incognito');
 assert.equal(page.document.body.dataset.privateBrowsing,'true');
});
test('private mode remains marked on a website and clears when switching to an ordinary tab',()=>{
 const page=browser();page.consume({...payload('regular'),privateBrowsing:false});
 page.consume({...payload('private'),mode:'browse',url:'https://example.test/',privateBrowsing:true});
 assert.equal(page.document.body.dataset.surface,'site');assert.equal(page.document.body.dataset.privateBrowsing,'true');
 page.consume({...payload('regular'),privateBrowsing:false});
 assert.equal(page.document.body.dataset.surface,'home');assert.equal(page.document.body.dataset.privateBrowsing,'false');
});
