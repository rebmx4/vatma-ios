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
