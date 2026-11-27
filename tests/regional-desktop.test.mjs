import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {createInitialDesktop, bundledShortcutArtwork, hasTranslatedDesktopLabel} from '../BrowserUI/desktop-defaults.js';
import {parseAppearance} from '../BrowserUI/appearance.js';
import * as workspace from '../BrowserUI/workspace-model.js';

const expected = {
  US: ['Google','YouTube','Amazon','Reddit','Instagram','Wikipedia','Walmart','Facebook'],
  DE: ['Google','YouTube','Kleinanzeigen','Amazon','BILD','Wikipedia','Instagram','Reddit'],
  FR: ['Google','YouTube','leboncoin','Amazon','Le Monde','Wikipédia','Instagram','Facebook'],
  BR: ['Google','YouTube','g1','Mercado Livre','UOL','Instagram','Shopee','Facebook'],
  PT: ['Google','YouTube','SAPO','Worten','Record','A BOLA','Instagram','Wikipédia'],
  JP: ['Yahoo! JAPAN','YouTube','楽天市場','Google','Amazon.co.jp','X','ウィキペディア','Instagram'],
  CN: ['百度','哔哩哔哩','淘宝','DeepSeek','微博','知乎','抖音','小红书'],
  KR: ['네이버','YouTube','쿠팡','Google','티스토리','인벤','Instagram','넷플릭스'],
  ES: ['Google','YouTube','MARCA','Amazon','EL PAÍS','El Mundo','Wikipedia','Instagram'],
  IT: ['Google','YouTube','Corriere','Amazon','Gazzetta','la Repubblica','Wikipedia','Instagram'],
};

test('each regional layout has the approved row, dock and bundled PNGs',()=>{
  const artwork=new Set();
  for(const [country,names] of Object.entries(expected)){
    const apps=createInitialDesktop(country,'ru-RU');
    assert.deepEqual(workspace.arrangeEntries(apps).map(({entry})=>entry.name),names.slice(0,4),country);
    assert.deepEqual(workspace.arrangeDock(apps).map(entry=>entry.name),names.slice(4),country);
    assert.equal(new Set(apps.map(app=>app.id)).size,8,country);
    for(const app of apps){
      const path=bundledShortcutArtwork(app);
      assert.match(path,/^\/assets\/regional-desktop-icons\/[a-z0-9.-]+\.png$/);
      const image=readFileSync(new URL(`../BrowserUI${path}`,import.meta.url));
      assert.equal(image.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
      assert.equal(bundledShortcutArtwork({...app,url:'https://example.test/'}),null);
      assert.equal(bundledShortcutArtwork({...app,custom:true}),null);
      assert.equal(hasTranslatedDesktopLabel(app),false);
      artwork.add(path);
    }
  }
  assert.equal(artwork.size,42);
});

test('the device region takes priority and Brazil and Portugal remain distinct',()=>{
  assert.deepEqual(createInitialDesktop('br','pt-PT').map(app=>app.name),expected.BR);
  assert.deepEqual(createInitialDesktop('PT','pt-BR').map(app=>app.name),expected.PT);
  assert.deepEqual(createInitialDesktop(undefined,'pt-PT').map(app=>app.name),expected.PT);
  assert.deepEqual(createInitialDesktop(undefined,'zh-Hans-CN').map(app=>app.name),expected.CN);
  for(const [region,locale] of [['GB','de-DE'],['419','es-ES'],[undefined,'pt'],[undefined,'unknown_locale']]){
    assert.deepEqual(createInitialDesktop(region,locale).map(app=>app.name),expected.US);
  }
});

test('Russia keeps the approved sites and dedicated bundled artwork',()=>{
  const apps=createInitialDesktop('RU','en-US');
  assert.deepEqual(workspace.arrangeEntries(apps).map(({entry})=>entry.id),['vk','dzen','vtb','tbank']);
  assert.deepEqual(workspace.arrangeDock(apps).map(entry=>entry.id),['rutube','avito','youtube','mail']);
  for(const app of apps){
    const path=`/assets/desktop-icons/${app.id}.png`;
    assert.equal(bundledShortcutArtwork(app),path);
    assert.equal(readFileSync(new URL(`../BrowserUI${path}`,import.meta.url)).subarray(0,8).toString('hex'),'89504e470d0a1a0a');
  }
});

const appSource=readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
function seedDesktop(existing,region){
  const storage=new Map([['atma-preview-vault','encrypted desktop'],['atma-preview-desktop-layout','five-rows']]);
  if(existing!==undefined)storage.set('atma-preview-apps',JSON.stringify(existing));
  const localStorage={getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value)};
  const document={body:{dataset:{runtime:'ios'}}};
  const start=appSource.indexOf('const SYSTEM_APPS=');
  const end=appSource.indexOf('let state, profiles',start);
  const source=appSource.slice(start,end);
  runInNewContext(source,{...workspace,structuredClone,createInitialDesktop,localStorage,document,
    localization:{language:'pt-BR'},navigator:{language:'pt-BR'},query:new URLSearchParams({desktopRegion:region})});
  return {apps:JSON.parse(storage.get('atma-preview-apps')),vault:storage.get('atma-preview-vault')};
}

test('the ordinary desktop seeds once and retains deleted positions and the encrypted private desktop',()=>{
  const fresh=seedDesktop(undefined,'RU').apps;
  const existing=fresh.filter(app=>app.id!=='mail');
  existing.find(app=>app.id==='dzen').slots={4:6,6:8};
  existing.push({id:'personal',name:'Saved site',url:'https://example.test/',custom:true,slots:{4:15,6:17}});
  assert.deepEqual(seedDesktop(existing,'JP'),{apps:existing,vault:'encrypted desktop'});
  const empty=seedDesktop([],'CN');
  assert.ok(empty.apps.every(app=>app.type==='system'));
  assert.equal(empty.vault,'encrypted desktop');
});

function quickAccess(entries,showDock){
  class Element {
    children=[];
    dataset={};
    attrs=new Map();
    append(...children){children.forEach(child=>{child.parentElement=this;});this.children.push(...children);}
    replaceChildren(...children){this.children=[];this.append(...children);}
    setAttribute(key,value){this.attrs.set(key,value);}
    hasAttribute(key){return this.attrs.has(key);}
    querySelectorAll(){return [];}
  }
  const ids=new Map();
  const $=id=>{if(!ids.has(id))ids.set(id,new Element());return ids.get(id);};
  $('address').value='';
  const context={...workspace,$,vaultKey:null,appearance:{showDock},desktopPage:0,privatePageStart:2,quickAccessExpanded:false,
    poolFor:()=>entries,gridMetrics:()=>({columns:4,rows:5}),appLabel:app=>app.name,
    document:{createElement:()=>new Element()},createItem:app=>({id:app.id})};
  const start=appSource.indexOf('function updateQuickAccessExpansion()');
  const end=appSource.indexOf('function syncDesktopSearch(',start);
  runInNewContext(appSource.slice(start,end),context);
  context.renderDesktopQuickAccess();
  return {rows:$('desktop-suggested-apps').children,toggle:$('desktop-suggestion-toggle'),expand(){
    context.quickAccessExpanded=true;context.updateQuickAccessExpansion();
  }};
}

test('hidden dock uses the two top grid rows and keeps the second row behind expansion',async()=>{
  const desktop=Array.from({length:8},(_,i)=>({id:`grid-${i}`,name:`Grid ${i}`,slots:{4:i}}));
  const dock=Array.from({length:4},(_,i)=>({id:`dock-${i}`,name:`Dock ${i}`,dockSlot:i}));
  assert.equal(parseAppearance('{}').showDock,true);
  const disabled=parseAppearance('{"showDock":false}');
  assert.equal(disabled.showDock,false);
  const enabled=quickAccess([...desktop,...dock],true);
  assert.deepEqual(Array.from(enabled.rows[0].children,entry=>entry.id),dock.map(entry=>entry.id));
  const hidden=quickAccess([...desktop,...dock],disabled.showDock);
  assert.deepEqual(Array.from(hidden.rows[0].children,entry=>entry.id),desktop.slice(0,4).map(entry=>entry.id));
  assert.equal(hidden.rows[1].hidden,true);
  await new Promise(resolve=>setImmediate(resolve));
  hidden.expand();
  assert.equal(hidden.rows[1].hidden,false);
  assert.deepEqual(Array.from(hidden.rows[1].children,entry=>entry.id),desktop.slice(4).map(entry=>entry.id));

  const emptyTop=quickAccess(desktop.slice(4),false);
  assert.equal(emptyTop.rows[0].children.length,0);
  assert.equal(emptyTop.rows[1].hidden,true);
  assert.equal(emptyTop.toggle.hidden,false);
});
