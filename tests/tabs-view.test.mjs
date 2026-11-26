import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function fixture(){
 let body,document;
 class Element extends EventTarget {
  constructor(tag){super();this.tagName=tag.toUpperCase();this.children=[];this.parentElement=null;this.dataset={};this.attributes={};this.className='';this.scrollTop=0;this.classList={contains:name=>this.className.split(/\s+/).includes(name),toggle:(name,on)=>{const names=new Set(this.className.split(/\s+/).filter(Boolean));if(on)names.add(name);else names.delete(name);this.className=[...names].join(' ');}};}
  get isConnected(){return this===body||Boolean(this.parentElement?.isConnected);}
  append(...nodes){for(const node of nodes){node.remove();node.parentElement=this;this.children.push(node);}}
  insertBefore(node,before){node.remove();node.parentElement=this;const index=this.children.indexOf(before);if(index<0)this.children.push(node);else this.children.splice(index,0,node);return node;}
  replaceChildren(...nodes){for(const child of this.children)child.parentElement=null;this.children=[];this.append(...nodes);}
  remove(){if(this.parentElement){const siblings=this.parentElement.children;const index=siblings.indexOf(this);if(index>=0)siblings.splice(index,1);this.parentElement=null;}}
  setAttribute(name,value){this.attributes[name]=String(value);}getAttribute(name){return this.attributes[name]??null;}
  removeAttribute(name){delete this.attributes[name];}
  focus(){document.activeElement=this;}blur(){if(document.activeElement===this)document.activeElement=null;}
  querySelectorAll(selector){const matches=node=>selector==='[data-tab-id]'?Boolean(node.dataset.tabId):selector.startsWith('.')?node.classList.contains(selector.slice(1)):selector.startsWith('#')?node.id===selector.slice(1):node.tagName===selector.toUpperCase();const all=this.children.flatMap(child=>[child,...child.querySelectorAll('*')]);return selector==='*'?all:all.filter(matches);}
  querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
 }
 body=new Element('body');const root=new Element('section');body.append(root);
 class Image extends Element {constructor(){super('img');}set src(value){this._src=value;queueMicrotask(()=>this.dispatchEvent(new Event('load')));}get src(){return this._src;}}
 document={body,createElement:tag=>new Element(tag)};
 const context=vm.createContext({document,Image,URL,Promise,console,setTimeout,clearTimeout});
 const source=fs.readFileSync(new URL('../BrowserUI/tabs-view.js',import.meta.url),'utf8');
 vm.runInContext(source.replace(/\bexport (?=function)/g,''),context);
 const selected=[],closed=[],added=[];
 const options={tabs:[{id:'one',url:'https://one.example/',title:'One',siteName:'one.example',iconUrl:'',error:null},{id:'two',url:'https://two.example/',title:'Two',siteName:'two.example',iconUrl:'',error:null}],activeTabId:'one',icon:()=>'',onSelect:id=>selected.push(id),onClose:id=>closed.push(id),onNew:group=>added.push(group),loadPreviews:async()=>({previews:{one:'data:image/jpeg;base64,first',two:'data:image/jpeg;base64,second'}})};
 const render=patch=>{Object.assign(options,patch);context.renderTabsOverview(root,options);};
 return {root,options,render,selected,closed,added};
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

test('private group shows its own real names and device models without requesting artwork or snapshots',async()=>{
 const f=fixture();let previewRequests=0,iconRequests=0;
 f.render({tabs:[{...f.options.tabs[0],privateBrowsing:true,profileId:'test-phone',iconUrl:'https://private.example/identifying.png'}],
  profiles:[{id:'test-phone',name:'iPhone 15'}],
  loadPreviews:async()=>{previewRequests++;return {previews:{}};},
  loadIcon:async()=>{iconRequests++;return '';},
 });await settle();
 assert.equal(f.root.querySelectorAll('img').length,0);
 assert.equal(f.root.querySelector('.tab-title').textContent,'One');
 assert.equal(f.root.querySelector('.tab-device').textContent,'iPhone 15');
 assert.equal(f.root.querySelector('.tab-open').getAttribute('aria-label'),'Открыть вкладку: One, iPhone 15');
 assert.equal(previewRequests,0);
 assert.equal(iconRequests,0);
 f.root.querySelector('#tabs-group-regular').dispatchEvent(new Event('click'));
 assert.equal(f.root.querySelector('.tab-title'),null,'Private titles must leave the ordinary group DOM');
});
test('a tab marked private discards a previously decoded ordinary preview',async()=>{
 const f=fixture();f.render();await settle();assert.ok(f.root.querySelector('.tab-shot'));
 f.render({tabs:[{...f.options.tabs[0],privateBrowsing:true}]});await settle();
 assert.equal(f.root.querySelector('.tab-shot'),null);assert.equal(f.root.querySelectorAll('img').length,0);
});

test('a late snapshot updates the card without a change to metadata',async()=>{
 const f=fixture();
 f.render({previewVersion:0,loadPreviews:async()=>({previews:{}})});await settle();
 const card=f.root.querySelector('[data-tab-id]');
 assert.equal(card.querySelector('.tab-favicon').children[0].textContent,'O');
 f.render({previewVersion:1,loadPreviews:async()=>({previews:{one:'data:image/jpeg;base64,late'}})});await settle();
 assert.equal(f.root.querySelector('[data-tab-id]'),card);
 assert.equal(card.querySelector('.tab-shot').src,'data:image/jpeg;base64,late');
 f.render({tabs:f.options.tabs.map(tab=>tab.id==='one'?{...tab,previewDocument:2}:tab),
   previewVersion:2,loadPreviews:async()=>({previews:{}})});await settle();
 assert.equal(card.querySelector('.tab-shot'),null,'A different document may have the same URL');
});

test('group changes, search, density and plus use the overview selection',async()=>{
 const f=fixture();
 f.render({tabs:[...f.options.tabs,{id:'private',url:'https://isolated.example/',title:'Isolated',privateBrowsing:true}]});
 f.root.querySelector('#new-tab').dispatchEvent(new Event('click'));
 const layout=f.root.querySelector('.tabs-layout');
 for(const columns of [3,5,2]){
  layout.dispatchEvent(new Event('click'));
  assert.equal(f.root.querySelector('.tabs-overview').dataset.cols,columns);
 }
 const query=f.root.querySelector('.tabs-query');
 query.value='two.example';
 query.dispatchEvent(new Event('input'));
 assert.deepEqual(f.root.querySelectorAll('[data-tab-id]').map(card=>card.dataset.tabId),['two']);
 f.root.querySelector('#tabs-group-private').dispatchEvent(new Event('click'));
 assert.equal(f.root.querySelectorAll('[data-tab-id]').length,0);
 f.root.querySelector('.tabs-search-clear').dispatchEvent(new Event('click'));
 assert.equal(f.root.querySelector('.tab-title').textContent,'Isolated');
 f.root.querySelector('#new-tab').dispatchEvent(new Event('click'));
 assert.deepEqual(f.added,[false,true]);
});

test('selection closes only the visible picked rows in one operation',async()=>{
 const f=fixture();let closed;
 f.render({onCloseMany:async ids=>{closed=[...ids];}});
 const query=f.root.querySelector('.tabs-query');
 query.value='one';query.dispatchEvent(new Event('input'));
 f.root.querySelector('.tabs-tools').children[0].dispatchEvent(new Event('click'));
 f.root.querySelector('.tabs-menu').children[1].dispatchEvent(new Event('click'));
 assert.equal(f.root.querySelector('.tab-open').getAttribute('aria-pressed'),'false');
 f.root.querySelector('.tabs-bulk').children[0].dispatchEvent(new Event('click'));
 assert.equal(f.root.querySelector('.tab-open').getAttribute('aria-pressed'),'true');
 f.root.querySelector('.tabs-bulk-close').dispatchEvent(new Event('click'));await settle();
 assert.deepEqual(closed,['one']);
 assert.equal(f.root.querySelector('.tabs-bulk').hidden,true);
});
