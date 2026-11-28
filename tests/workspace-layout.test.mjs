import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {arrangeDock,arrangeEntries,dropEntry,placeDockEntry,placeEntry,removeEntry,shiftEntriesToOppositeEdge} from '../BrowserUI/workspace-model.js';

const shortcut=(id,slot)=>({id,name:id,slots:{4:slot}});
const folder=()=>({id:'folder',type:'folder',name:'Папка',slots:{4:4},children:[shortcut('a',0),shortcut('b',1)]});

test('double-tap layout shifts top icons down and bottom icons up without changing order',()=>{
  const entries=[shortcut('a',0),shortcut('b',3),shortcut('c',8),shortcut('lock',20)];
  const shifted=shiftEntriesToOppositeEdge(entries,4,20);
  assert.deepEqual(shifted.items.map(entry=>entry.slots[4]),[8,11,16,36]);
  assert.deepEqual(entries.map(entry=>entry.slots[4]),[0,3,8,20]);
  assert.deepEqual(shiftEntriesToOppositeEdge([shortcut('bottom',19)],4,20).items[0].slots[4],3);
});

test('a second double tap restores saved positions, including after an app restart',()=>{
  const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
  const start=source.indexOf('function toggleDesktopAlignment()'),end=source.indexOf("$('apps').addEventListener('pointerdown'",start);
  assert.ok(start>0&&end>start);
  const saved=new Map(),context={apps:[shortcut('top',0),shortcut('next',5),shortcut('bottom',19)],
    alignmentSnapshot:null,ALIGNMENT_SNAPSHOT_KEY:'alignment',gridMetrics:()=>({columns:4,rows:5}),
    freezeSlots:entries=>structuredClone(entries),shiftEntriesToOppositeEdge,
    localStorage:{setItem:(key,value)=>saved.set(key,value),removeItem:key=>saved.delete(key)},renderApps(){}};
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  context.toggleDesktopAlignment();
  assert.deepEqual(Array.from(context.apps,app=>app.slots[4]),[0,5,19]);
  // The occupied range spans the page, so use an individual lower-page item.
  context.apps=[shortcut('top',0),shortcut('next',5)];context.toggleDesktopAlignment();
  assert.deepEqual(Array.from(context.apps,app=>app.slots[4]),[12,17]);
  context.alignmentSnapshot=JSON.parse(saved.get('alignment'));
  context.apps=JSON.parse(saved.get('atma-preview-apps'));
  context.toggleDesktopAlignment();
  assert.deepEqual(Array.from(context.apps,app=>app.slots[4]),[0,5]);
  assert.equal(saved.has('alignment'),false);
});

test('editing shortcut metadata keeps the pending double-tap restoration',async()=>{
  const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
  const start=source.indexOf('function saveApps('),end=source.indexOf('\nfunction updatePool(',start);
  const saved=new Map([['alignment','origin']]);
  const context={apps:[shortcut('site',12)],alignmentSnapshot:{columns:4,positions:{site:0}},ALIGNMENT_SNAPSHOT_KEY:'alignment',
    localStorage:{setItem:(key,value)=>saved.set(key,value),removeItem:key=>saved.delete(key)},
    renderApps(){},updateQuickAdd(){},scheduleMessageBadgePoll(){},panel:null};
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  await context.saveApps('public',{render:false,layoutChanged:false});
  assert.equal(saved.get('alignment'),'origin');
  assert.equal(context.alignmentSnapshot.positions.site,0);
});

test('a shortcut can be placed in an empty lower cell',()=>{
  const result=placeEntry([shortcut('a',0),shortcut('b',1)],'a',19,4);
  assert.equal(result.items.find(item=>item.id==='a').slots[4],19);
});

test('extracting from a two-item folder promotes the remaining shortcut in its slot',()=>{
  const result=placeEntry([folder(),shortcut('c',0)],'a',19,4);
  assert.deepEqual(result.items.map(item=>item.id),['b','c','a']);
  assert.equal(result.items[0].slots[4],4);
  assert.equal(result.items[2].slots[4],19);
});

test('combining two shortcuts preserves the target slot on the desktop or dock',()=>{
  for (const docked of [false,true]) {
    const source=shortcut('source',0), target=shortcut('target',5);
    if(docked)target.dockSlot=2;
    const grouped=dropEntry([source,target],'source','target',{combine:true,columns:4,newFolderId:'group'}).items;
    assert.deepEqual(grouped[0].children.map(item=>item.id),['target','source']);
    assert.equal(grouped[0].dockSlot,target.dockSlot);
    assert.equal(grouped[0].children[0].dockSlot,undefined);
    assert.equal(dropEntry(grouped,'source','group',{combine:true,columns:4}).changed,false);
    const split=placeEntry(grouped,'source',18,4).items;
    assert.deepEqual(split.map(item=>item.id),['target','source']);
    assert.equal(split[0].dockSlot,target.dockSlot);
    assert.equal(split[0].slots[4],5);
    assert.equal(split[1].slots[4],18);
  }
});

test('moving or deleting a folder child also dissolves a singleton folder',()=>{
  const moved=dropEntry([folder(),shortcut('c',0)],'a','c',{columns:4});
  assert.ok(moved.changed);
  assert.deepEqual(moved.items.map(item=>item.id),['b','a','c']);
  assert.equal(moved.items[0].slots[4],4);
  const removed=removeEntry([folder()],'a');
  assert.deepEqual(removed.map(item=>item.id),['b']);
  assert.equal(removed[0].slots[4],4);
});

test('moving between the grid and dock swaps only the two occupied slots',()=>{
  const before=[shortcut('keep',1),shortcut('grid',7),{...shortcut('dock',1),dockSlot:2}];
  const pinned=placeDockEntry(before,'grid',2,4).items;
  assert.deepEqual(arrangeDock(pinned).map(item=>item?.id),[undefined,undefined,'grid',undefined]);
  assert.deepEqual(arrangeEntries(pinned,4).map(({entry,slot})=>[entry.id,slot]),[['keep',1],['dock',7]]);
  const returned=placeEntry(pinned,'grid',7,4).items;
  assert.equal(arrangeDock(returned)[2].id,'dock');
  assert.equal(arrangeEntries(returned,4).find(({entry})=>entry.id==='grid').slot,7);
  assert.equal(before[1].dockSlot,undefined);
});

test('a legacy desktop retains its slots and docking keeps double-tap alignment scoped to the grid',()=>{
  const legacy=[shortcut('a',1),shortcut('b',10),shortcut('c',23)];
  assert.deepEqual(arrangeDock(legacy),[null,null,null,null]);
  const pinned=placeDockEntry(legacy,'b',0,4).items;
  const moved=shiftEntriesToOppositeEdge(pinned,4,20).items;
  assert.equal(arrangeDock(moved)[0].id,'b');
  assert.equal(moved.find(item=>item.id==='b').slots[4],10);
  assert.deepEqual(arrangeEntries(pinned).map(({slot})=>slot),[1,23]);
});

test('extracting a docked folder child does not lose the folder or the swapped shortcut',()=>{
  const entries=[{...folder(),dockSlot:0},{...shortcut('dock',1),dockSlot:2},shortcut('keep',0)];
  const result=placeDockEntry(entries,'a',2).items;
  assert.deepEqual(arrangeDock(result).map(item=>item?.id),['b',undefined,'a',undefined]);
  assert.deepEqual(arrangeEntries(result).map(({entry,slot})=>[entry.id,slot]),[['dock',1],['keep',0]]);
  const ungrouped=removeEntry(entries,'folder');
  assert.equal(arrangeDock(ungrouped)[0].id,'a');
  assert.ok(arrangeEntries(ungrouped).some(({entry})=>entry.id==='b'));
});
