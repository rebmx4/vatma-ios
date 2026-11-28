import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {freezeSlots,removeEntry} from '../BrowserUI/workspace-model.js';
function tileFixture({editing=true,app={id:'custom-image',name:'Saved website',type:'website'},scope='public'}={}){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 class Element{constructor(){this.dataset={};this.events=new Map();this.children=[];this.style={setProperty(){}};this.classList={toggle(){}};}setAttribute(){}addEventListener(name,handler){this.events.set(name,handler);}append(...children){this.children.push(...children);}}
 const opened=[];
 const page={Element,document:{events:new Map(),addEventListener(name,handler){this.events.set(name,handler);},createElement:()=>new Element(),body:{setPointerCapture(){}}},gesture:null,editing,suppressClickUntil:0,DESKTOP_HOLD_MS:Number(source.match(/DESKTOP_HOLD_MS\s*=\s*(\d+)/)[1]),
  $:()=>({scrollLeft:0}),isFolder:()=>false,usesTranslatedShortcutLabel:()=>false,appLabel:app=>app.name,brand:()=>'',paintShortcutIcon(){},icon:()=>'',setTimeout:()=>1,navigator:{},shortcutMessageCount:()=>0,messageCounts:{},
  poolFor:()=>[app],findEntry:(apps,id)=>({entry:apps.find(app=>app.id===id)}),activate:app=>opened.push(app.id),
  clearTimeout(){},clearHover(){},removeEntry(){},updatePool(){},freezeSlots(){},gridMetrics:()=>({columns:4}),reducedMotion:{matches:true}};
 vm.createContext(page);
 const itemBegin=source.indexOf('function createItem('),itemEnd=source.indexOf('function activate(',itemBegin);
 const holdBegin=source.indexOf('function beginGesture('),holdEnd=source.indexOf('function clearHover(',holdBegin);
 const releaseBegin=source.indexOf('async function endGesture('),releaseEnd=source.indexOf("document.addEventListener('pointerup', event=>endGesture(event))",releaseBegin);
 vm.runInContext(source.slice(itemBegin,itemEnd)+source.slice(holdBegin,holdEnd)+source.slice(releaseBegin,releaseEnd),page);
 const item=page.createItem(app,null,0,scope);
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
test('a completed drop removes the dragged artwork before rendering its new slot',async()=>{
 const f=tileFixture(),order=[];
 f.item.events.get('pointerdown')(f.event('.app-tile'));
 f.page.gesture.active=true;
 f.page.gesture.ghost={remove:()=>order.push('remove')};
 f.page.panel=null;
 f.page.updateDropTarget=()=>{f.page.gesture.targetSlot=10;};
 f.page.placeEntry=()=>({changed:true,items:[]});
 f.page.updatePool=async()=>{order.push('render');assert.equal(f.page.gesture,null);};
 await f.page.endGesture(f.event('.app-tile'));
 assert.deepEqual(order,['remove','render']);
});

test('opening the editor consumes its release click and accepts the next deliberate press',async()=>{
 const f=tileFixture();
 f.item.events.get('pointerdown')(f.event('.app-tile'));
 await f.page.endGesture(f.event('.app-tile'));
 let blocked=0;
 const click={detail:1,preventDefault(){},stopImmediatePropagation(){blocked++;}};
 f.page.document.events.get('click')(click);
 assert.equal(blocked,1);
 f.page.document.events.get('pointerdown')();
 f.page.document.events.get('click')(click);
 assert.equal(blocked,1);
});

test('removing Mail changes only the current desktop and cancels a pending move of the removed public shortcut',()=>{
 const mail={id:'mail',name:'Почта Mail',url:'https://e.mail.ru/',dockSlot:3};
 const privateMail={id:'mail',name:'Личная почта',url:'https://e.mail.ru/'};
 const f=tileFixture({app:mail}),pools={public:[mail],private:[privateMail]};
 Object.assign(f.page,{pendingVaultMove:'mail',vaultKey:{},freezeSlots,removeEntry,poolFor:scope=>pools[scope],updatePool:async(scope,entries)=>{pools[scope]=entries;}});
 let stopped=0;
 const event={stopPropagation(){stopped++;}};
 f.item.children.at(-1).events.get('pointerdown')(event);
 f.item.children.at(-1).events.get('click')(event);
 assert.equal(stopped,2);
 assert.equal(f.page.pendingVaultMove,null);
 assert.deepEqual(pools.public,[]);
 assert.deepEqual(pools.private,[privateMail]);
 assert.deepEqual(f.opened,[]);
});
