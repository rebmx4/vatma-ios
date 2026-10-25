import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function fixture(){
 let body;
 class Element extends EventTarget {
  constructor(tag){super();this.tagName=tag.toUpperCase();this.children=[];this.parentElement=null;this.dataset={};this.attributes={};this.className='';this.scrollTop=0;this.classList={contains:name=>this.className.split(/\s+/).includes(name),toggle:(name,on)=>{const names=new Set(this.className.split(/\s+/).filter(Boolean));if(on)names.add(name);else names.delete(name);this.className=[...names].join(' ');}};}
  get isConnected(){return this===body||Boolean(this.parentElement?.isConnected);}
  append(...nodes){for(const node of nodes){node.remove();node.parentElement=this;this.children.push(node);}}
  insertBefore(node,before){node.remove();node.parentElement=this;const index=this.children.indexOf(before);if(index<0)this.children.push(node);else this.children.splice(index,0,node);return node;}
  replaceChildren(...nodes){for(const child of this.children)child.parentElement=null;this.children=[];this.append(...nodes);}
  remove(){if(this.parentElement){const siblings=this.parentElement.children;const index=siblings.indexOf(this);if(index>=0)siblings.splice(index,1);this.parentElement=null;}}
  setAttribute(name,value){this.attributes[name]=String(value);}getAttribute(name){return this.attributes[name]??null;}
  querySelectorAll(selector){const matches=node=>selector==='[data-tab-id]'?Boolean(node.dataset.tabId):selector.startsWith('.')?node.classList.contains(selector.slice(1)):selector.startsWith('#')?node.id===selector.slice(1):node.tagName===selector.toUpperCase();const all=this.children.flatMap(child=>[child,...child.querySelectorAll('*')]);return selector==='*'?all:all.filter(matches);}
  querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
 }
 body=new Element('body');const root=new Element('section');body.append(root);
 class Image extends Element {constructor(){super('img');}set src(value){this._src=value;queueMicrotask(()=>this.dispatchEvent(new Event('load')));}get src(){return this._src;}}
 const document={body,createElement:tag=>new Element(tag)};
 const context=vm.createContext({document,Image,URL,Promise,console});
 const source=fs.readFileSync(new URL('../BrowserUI/tabs-view.js',import.meta.url),'utf8');
 vm.runInContext(source.replace(/\bexport (?=function)/g,''),context);
 const selected=[],closed=[];let added=0;
 const options={tabs:[{id:'one',url:'https://one.example/',title:'One',siteName:'one.example',iconUrl:'',error:null},{id:'two',url:'https://two.example/',title:'Two',siteName:'two.example',iconUrl:'',error:null}],activeTabId:'one',icon:()=>'',onSelect:id=>selected.push(id),onClose:id=>closed.push(id),onNew:()=>added++,loadPreviews:async()=>({previews:{one:'data:image/jpeg;base64,first',two:'data:image/jpeg;base64,second'}})};
 const render=patch=>{Object.assign(options,patch);context.renderTabsOverview(root,options);};
 return {root,options,render,selected,closed,get added(){return added;}};
}
const settle=()=>new Promise(resolve=>setImmediate(resolve));

test('equivalent native tab dictionaries keep the same cards and decoded previews',async()=>{
 const f=fixture();f.render();await settle();
 const card=f.root.querySelector('[data-tab-id]'),image=card.querySelector('.tab-shot');assert.ok(image);
 const reordered=f.options.tabs.map(tab=>Object.fromEntries(Object.entries(tab).reverse()));f.render({tabs:reordered});await settle();
 assert.equal(f.root.querySelector('[data-tab-id]'),card,'An unchanged tab must not be torn down on a state report');
 assert.equal(card.querySelector('.tab-shot'),image,'Keep the decoded website image while data is unchanged');
});

test('title and selection updates keep the already displayed website preview',async()=>{
 const f=fixture();f.render();await settle();
 const card=f.root.querySelector('[data-tab-id]'),image=card.querySelector('.tab-shot');
 f.render({tabs:f.options.tabs.map(tab=>tab.id==='one'?{...tab,title:'Updated title'}:tab),activeTabId:'two'});await settle();
 assert.equal(f.root.querySelector('[data-tab-id]'),card);
 assert.equal(card.querySelector('.tab-shot'),image);
 assert.equal(card.querySelector('.tab-title').textContent,'Updated title');
 assert.equal(card.classList.contains('selected'),false);
});

test('late preview responses cannot restore a closed tab or a previous URL',async()=>{
 const f=fixture();let resolveOld;
 f.render({loadPreviews:()=>new Promise(resolve=>{resolveOld=resolve;})});
 f.render({tabs:[{...f.options.tabs[0],url:'https://new.example/',title:'New'}],loadPreviews:async()=>({previews:{one:'data:image/jpeg;base64,new'}})});await settle();
 resolveOld({previews:{one:'data:image/jpeg;base64,old',two:'data:image/jpeg;base64,closed'}});await settle();
 assert.equal(f.root.querySelectorAll('[data-tab-id]').length,1);
 assert.equal(f.root.querySelector('.tab-shot').src,'data:image/jpeg;base64,new');
});

test('private tab overview never fetches website artwork or displays page snapshots',async()=>{
 const f=fixture();f.render({tabs:[{...f.options.tabs[0],privateBrowsing:true,iconUrl:'https://private.example/identifying.png'}]});await settle();
 assert.equal(f.root.querySelectorAll('img').length,0);
 assert.equal(f.root.querySelector('.tab-title').textContent,'Инкогнито');
 assert.equal(f.root.querySelector('.tab-host').textContent,'Приватная вкладка');
});
test('a tab marked private discards a previously decoded ordinary preview',async()=>{
 const f=fixture();f.render();await settle();assert.ok(f.root.querySelector('.tab-shot'));
 f.render({tabs:[{...f.options.tabs[0],privateBrowsing:true}]});await settle();
 assert.equal(f.root.querySelector('.tab-shot'),null);assert.equal(f.root.querySelectorAll('img').length,0);
});
