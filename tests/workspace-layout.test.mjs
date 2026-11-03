import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {dropEntry,placeEntry,removeEntry,shiftEntriesToOppositeEdge} from '../BrowserUI/workspace-model.js';

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

test('moving or deleting a folder child also dissolves a singleton folder',()=>{
  const moved=dropEntry([folder(),shortcut('c',0)],'a','c',{columns:4});
  assert.ok(moved.changed);
  assert.deepEqual(moved.items.map(item=>item.id),['b','a','c']);
  assert.equal(moved.items[0].slots[4],4);
  const removed=removeEntry([folder()],'a');
  assert.deepEqual(removed.map(item=>item.id),['b']);
  assert.equal(removed[0].slots[4],4);
});
