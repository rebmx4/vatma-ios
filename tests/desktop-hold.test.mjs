import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function tileFixture({editing=true}={}){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 class Element{constructor(){this.dataset={};this.events=new Map();this.children=[];this.style={setProperty(){}};this.classList={toggle(){}};}setAttribute(){}addEventListener(name,handler){this.events.set(name,handler);}append(...children){this.children.push(...children);}}
 const app={id:'custom-image',name:'Saved website',type:'website'}, opened=[];
 const page={Element,document:{createElement:()=>new Element(),body:{setPointerCapture(){}}},gesture:null,editing,suppressClickUntil:0,DESKTOP_HOLD_MS:Number(source.match(/DESKTOP_HOLD_MS\s*=\s*(\d+)/)[1]),
  $:()=>({scrollLeft:0}),isFolder:()=>false,appLabel:app=>app.name,brand:()=>'',paintShortcutIcon(){},icon:()=>'',setTimeout:()=>1,navigator:{},shortcutMessageCount:()=>0,messageCounts:{},
  poolFor:()=>[app],findEntry:(apps,id)=>({entry:apps.find(app=>app.id===id)}),activate:app=>opened.push(app.id),
  clearTimeout(){},clearHover(){},removeEntry(){},updatePool(){},freezeSlots(){},gridMetrics:()=>({columns:4})};
 vm.createContext(page);
 const itemBegin=source.indexOf('function createItem('),itemEnd=source.indexOf('function activate(',itemBegin);
 const holdBegin=source.indexOf('function beginGesture('),holdEnd=source.indexOf('function clearHover(',holdBegin);
 const releaseBegin=source.indexOf('async function endGesture('),releaseEnd=source.indexOf("document.addEventListener('pointerup', event=>endGesture(event))",releaseBegin);
 vm.runInContext(source.slice(itemBegin,itemEnd)+source.slice(holdBegin,holdEnd)+source.slice(releaseBegin,releaseEnd),page);
 const item=page.createItem(app);
 const event=target=>({button:0,pointerId:1,clientX:20,clientY:30,target:{closest:selector=>selector===target?{}:null},preventDefault(){}});
 return{page,item,event,opened};
}
test('the remove control never starts the icon hold or drag session',()=>{
 const f=tileFixture();f.item.events.get('pointerdown')(f.event('.app-remove'));assert.equal(f.page.gesture,null);
});
test('the icon label participates in the same desktop hold as the artwork',()=>{
 const f=tileFixture();f.item.events.get('pointerdown')(f.event());assert.equal(f.page.gesture.id,'custom-image');
});
test('a shortcut tap opens once when the button loses its click during a redraw',async()=>{
 const f=tileFixture({editing:false});
 f.item.events.get('pointerdown')(f.event('.app-tile'));
 await f.page.endGesture(f.event());
 assert.deepEqual(f.opened,['custom-image']);
 f.item.children[0].events.get('click')({detail:1});
 assert.deepEqual(f.opened,['custom-image']);
});
test('keyboard activation still opens the shortcut',()=>{
 const f=tileFixture({editing:false});
 f.item.children[0].events.get('click')({detail:0});
 assert.deepEqual(f.opened,['custom-image']);
});
test('holding, cancelling, or moving away does not launch a shortcut',async()=>{
 const f=tileFixture({editing:false});
 const press=()=>f.item.events.get('pointerdown')(f.event('.app-tile'));
 press();f.page.gesture.held=true;await f.page.endGesture(f.event('.app-tile'));
 f.page.suppressClickUntil=0;
 press();await f.page.endGesture(f.event('.app-tile'),true);
 press();await f.page.endGesture({...f.event(),clientX:40});
 assert.deepEqual(f.opened,[]);
});
