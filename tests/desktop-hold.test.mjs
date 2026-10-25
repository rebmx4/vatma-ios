import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
function tileFixture(){
 const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
 class Element{constructor(){this.dataset={};this.events=new Map();this.children=[];this.style={setProperty(){}};this.classList={toggle(){}};}setAttribute(){}addEventListener(name,handler){this.events.set(name,handler);}append(...children){this.children.push(...children);}}
 const page={Element,document:{createElement:()=>new Element(),body:{setPointerCapture(){}}},gesture:null,editing:true,DESKTOP_HOLD_MS:Number(source.match(/DESKTOP_HOLD_MS\s*=\s*(\d+)/)[1]),
  $:()=>({scrollLeft:0}),isFolder:()=>false,appLabel:app=>app.name,brand:()=>'',paintShortcutIcon(){},icon:()=>'',setTimeout:()=>1,navigator:{},shortcutMessageCount:()=>0,messageCounts:{},
  poolFor:()=>[],removeEntry(){},updatePool(){},freezeSlots(){},gridMetrics:()=>({columns:4})};
 vm.createContext(page);
 const itemBegin=source.indexOf('function createItem('),itemEnd=source.indexOf('function activate(',itemBegin);
 const holdBegin=source.indexOf('function beginGesture('),holdEnd=source.indexOf('function clearHover(',holdBegin);
 vm.runInContext(source.slice(itemBegin,itemEnd)+source.slice(holdBegin,holdEnd),page);
 const app={id:'custom-image',name:'Saved website',type:'website'},item=page.createItem(app);
 const event=remove=>({button:0,pointerId:1,clientX:20,clientY:30,target:{closest:selector=>remove&&selector==='.app-remove'?{}:null},preventDefault(){}});
 return{page,item,event};
}
test('the remove control never starts the icon hold or drag session',()=>{
 const f=tileFixture();f.item.events.get('pointerdown')(f.event(true));assert.equal(f.page.gesture,null);
});
test('the icon label participates in the same desktop hold as the artwork',()=>{
 const f=tileFixture();f.item.events.get('pointerdown')(f.event(false));assert.equal(f.page.gesture.id,'custom-image');
});
