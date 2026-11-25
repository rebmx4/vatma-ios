import test from 'node:test';
import assert from 'node:assert/strict';
import {addressSuggestions} from '../BrowserUI/address-suggestions.js';

const tabs = [
  {id:'regular',title:'Дзен',url:'https://dzen.ru/'},
  {id:'private-a',title:'Дзен A',url:'https://a.example/',privateBrowsing:true,privateSessionID:'a'},
  {id:'private-b',title:'Дзен B',url:'https://b.example/',privateBrowsing:true,privateSessionID:'b'},
  {id:'private-current',privateBrowsing:true,privateSessionID:'a'},
  {id:'locked',title:'Дзен закладка',url:'https://locked.example/',privateDesktop:true},
];
const shortcuts = [
  {id:'dzen',name:'Дзен',url:'https://dzen.ru/'},
  {id:'saved',name:'Дзен — новости',url:'https://dzen.ru/news'},
];

test('matches local tabs first and deduplicates the same shortcut URL', () => {
  const found = addressSuggestions('ДЗЕ', {tabs,activeTabId:'blank'}, shortcuts);
  assert.deepEqual(found.map(row => [row.kind, row.entry?.id]), [
    ['tab','regular'],['shortcut','saved'],['search',undefined],
  ]);
});

test('incognito sees only addresses in its own temporary session', () => {
  const found = addressSuggestions('дзе', {tabs,activeTabId:'private-current',privateBrowsing:true}, shortcuts);
  assert.deepEqual(found.map(row => [row.kind, row.entry?.id]), [
    ['tab','private-a'],['search',undefined],
  ]);
  assert.deepEqual(addressSuggestions('   ', {tabs}, shortcuts), []);
});
