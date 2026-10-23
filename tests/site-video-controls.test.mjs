import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=new URL('../BrowserUI/assets/site-video-controls.js',import.meta.url);

function fixture({supported=true,fullscreen=true,trustedTypes=false}={}){
 const nodes=[],calls=[],timers=new Map();let counter=0,paused=true;
 class Element extends EventTarget{
  constructor(tag){super();this.tagName=tag.toUpperCase();this.style={setProperty(name,value){this[name]=value;}};this.attributes={};this.children=[];this.hidden=false;this.isConnected=true;}
  setAttribute(name,value){this.attributes[name]=value;}getAttribute(name){return this.attributes[name]||null;}
  append(...children){this.children.push(...children);for(const child of children)child.parentElement=this;}
  attachShadow(){this.shadowRoot=new Element('shadow');return this.shadowRoot;}
  set innerHTML(value){if(trustedTypes)throw new TypeError('This document requires TrustedHTML assignment');this.markup=value;}
  remove(){this.isConnected=false;this.parentElement?.children.splice(this.parentElement.children.indexOf(this),1);}
  getBoundingClientRect(){return this.rect||{x:0,y:0,left:0,top:0,right:0,bottom:0,width:0,height:0};}
  querySelectorAll(){return this===player&&fullscreen?[anchor]:[];}
  closest(){return this===video?player:null;}
 }
 const player=new Element('div'),anchor=new Element('button'),video=new Element('video');
 video.rect={x:0,y:40,left:0,top:40,right:390,bottom:260,width:390,height:220};
 anchor.rect={x:346,y:216,left:346,top:216,right:390,bottom:260,width:44,height:44};
 Object.assign(video,{readyState:4,paused:true,ended:false,webkitPresentationMode:'inline',disablePictureInPicture:false});
 anchor.setAttribute('aria-label','Full screen');video.parentElement=player;anchor.parentElement=player;
 const document=new Element('document');document.documentElement=new Element('html');document.documentElement.lang='ru';document.body=new Element('body');
 document.createElement=tag=>{const e=new Element(tag);nodes.push(e);return e;};document.querySelectorAll=selector=>selector.includes('video')?[video]:[];
 document.createElementNS=(_namespace,tag)=>document.createElement(tag);
 const api={element:()=>video,state:()=>({available:true,pipAvailable:supported,pip:video.webkitPresentationMode==='picture-in-picture',paused}),async command(body){calls.push(body);video.webkitPresentationMode='picture-in-picture';return this.state();}};
 const context={document,navigator:{language:'ru'},innerWidth:390,innerHeight:844,Event,console,Date,getComputedStyle:e=>({visibility:'visible',display:'block',opacity:'1',...e.computed}),MutationObserver:class{observe(){}disconnect(){}},setInterval:callback=>{timers.set(++counter,callback);return counter;},clearInterval:id=>timers.delete(id),setTimeout:callback=>{timers.set(++counter,callback);return counter;},clearTimeout:id=>timers.delete(id),requestAnimationFrame:callback=>{callback();return 1;},cancelAnimationFrame(){}};
 context.window=context;context.addEventListener=()=>{};context.removeEventListener=()=>{};context.__atmaMediaPage=api;
 vm.createContext(context);const run=()=>{if(fs.existsSync(source))vm.runInContext(`(${fs.readFileSync(source,'utf8')})()`,context);};run();
 return{context,api,video,anchor,nodes,calls,run,tick(){for(const callback of [...timers.values()])callback();},button:()=>nodes.find(n=>n.tagName==='BUTTON')};
}

test('window button sits immediately left of fullscreen and sends only PiP without resuming a paused video',async()=>{
 const f=fixture(),button=f.button();assert.ok(button,'ATMA window button must be installed');assert.equal(button.hidden,false);
 assert.equal(Number.parseFloat(button.style.left)+44,f.anchor.rect.left);assert.equal(Number.parseFloat(button.style.top),f.anchor.rect.top);
 assert.match(button.getAttribute('aria-label'),/окно|картинк/i);
 button.dispatchEvent(new Event('click',{cancelable:true}));await Promise.resolve();
 assert.deepEqual(JSON.parse(JSON.stringify(f.calls)),[{type:'pip'}]);assert.equal(f.video.paused,true);
 f.tick();assert.equal(button.hidden,true,'Hide the entry button after actual PiP starts');
});

test('hide unsupported and offscreen video buttons and follow control visibility',()=>{
 const f=fixture({supported:false});assert.ok(f.button());assert.equal(f.button().hidden,true);
 const visible=fixture();visible.anchor.computed={visibility:'hidden'};visible.tick();assert.equal(visible.button().hidden,true);
 visible.anchor.computed={};visible.video.rect={...visible.video.rect,top:-400,bottom:-180};visible.tick();assert.equal(visible.button().hidden,true);
});

test('native video controls get a nearby window button and reinstall does not duplicate controls',()=>{
 const f=fixture({fullscreen:false});assert.ok(f.button());assert.equal(f.button().hidden,false);
 const x=Number.parseFloat(f.button().style.left);assert.ok(x>=0&&x+44<=f.video.rect.right-40);
 assert.ok(Number.parseFloat(f.button().style.top)+44<=f.video.rect.bottom-72,'Do not cover the native control bar or timeline');
 f.run();assert.equal(f.nodes.filter(n=>n.tagName==='BUTTON').length,1);
});

test('strict Trusted Types pages install controls without unsafe HTML assignment',()=>{
 const f=fixture({trustedTypes:true});assert.ok(f.button());assert.equal(f.button().hidden,false);
 assert.equal(typeof f.context.__atmaVideoControls.refresh,'function');
});
