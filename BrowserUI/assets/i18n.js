import english from './locale-en.js';
import spanish from './locale-es.js';
import german from './locale-de.js';
import french from './locale-fr.js';
import portuguese from './locale-pt-BR.js';
import italian from './locale-it.js';
import chineseSimplified from './locale-zh-Hans.js';
import korean from './locale-ko.js';
import japanese from './locale-ja.js';

export const LANGUAGE_KEY='atma-interface-language';
export const LANGUAGE_NAMES=Object.freeze({
 ru:'Русский', en:'English', es:'Español', de:'Deutsch', fr:'Français', 'pt-BR':'Português (Brasil)', it:'Italiano',
 'zh-Hans':'简体中文', ko:'한국어', ja:'日本語',
});
const dictionaries={
 en:english,es:spanish,de:german,fr:french,'pt-BR':portuguese,it:italian,'zh-Hans':chineseSimplified,ko:korean,ja:japanese,
};
const matchingLanguage=value=>{
 const [code,...subtags]=String(value??'').trim().toLowerCase().split(/[-_]/);
 if(code==='zh'){
  if(subtags.includes('hans'))return 'zh-Hans';
  return subtags.some(subtag=>['hant','tw','hk','mo'].includes(subtag))?null:'zh-Hans';
 }
 return code==='pt'?'pt-BR':Object.hasOwn(LANGUAGE_NAMES,code)?code:null;
};
export const deviceLanguage=preferred=>preferred.map(matchingLanguage).find(Boolean)||'en';
const russian=new Map(Object.entries(english).filter(([ru,en])=>ru!==en).map(([ru,en])=>[en,ru]));
const patterns=[
 [/^Cookie сайтов: (\d+)$/,'Cookie сайтов: {count}','count'],
 [/^Website cookies: (\d+)$/,'Cookie сайтов: {count}','count'],
 [/^Открытые вкладки: (\d+)$/,'Открытые вкладки: {count}','count'],
 [/^Страница (\d+)$/,'Страница {count}','count'],
 [/^Введено (\d+) из 6 цифр$/,'Введено {count} из 6 цифр','count'],
 [/^Иконка ATMA: (.+)$/,'Иконка ATMA: {name}','name'],
 [/^Удалить выбранные \((\d+)\)$/,'Удалить выбранные ({count})','count'],
 [/^Профиль: (.+)$/,'Профиль: {name}','name'],
 [/^Выбрать cookie: (.+)$/,'Выбрать cookie: {name}','name'],
 [/^Открыть вкладку: (.+)$/,'Открыть вкладку: {name}','name'],
 [/^Закрыть вкладку: (.+)$/,'Закрыть вкладку: {name}','name'],
 [/^Открыть (.+)$/,'Открыть {name}','name'],
 [/^Удалить (.+)$/,'Удалить {name}','name'],
 [/^Расформировать (.+)$/,'Расформировать {name}','name'],
];
const substitute=(text,params)=>text.replace(/\{(\w+)\}/g,(key,name)=>Object.hasOwn(params,name)?params[name]:key);
export function translate(value,language,params={}){
 const text=String(value),trimmed=text.trim();
 let source=Object.hasOwn(english,trimmed)?trimmed:russian.get(trimmed)||trimmed;
 if(!Object.hasOwn(english,source)){
  for(const [pattern,key,name] of patterns){
   const match=source.match(pattern);
   if(match){source=key;params={[name]:match[1],...params};break;}
  }
 }
 const result=substitute(dictionaries[language]?.[source]??source,params);
 return trimmed?text.replace(trimmed,()=>result):text;
}
// Retain original labels for reversible live switching, including labels rebuilt by the UI.
// Site content is a separate renderer. User names and cookie data opt out explicitly.
export function createLocalization(root=document,storage=localStorage,preferred=navigator.languages){
 let system=deviceLanguage(preferred);
 let preference=matchingLanguage(storage.getItem(LANGUAGE_KEY))||'auto';
 let language=preference==='auto'?system:preference;
 const texts=new WeakMap(),attributes=new WeakMap();
 const excluded=element=>!element||element.closest('[data-no-translate],script,style,pre,textarea');
 function apply(element=root.documentElement){
  root.documentElement.lang=language;
  const walker=root.createTreeWalker(element,NodeFilter.SHOW_TEXT);
  let node;
  while((node=walker.nextNode())){
   if(excluded(node.parentElement)||!node.textContent.trim())continue;
   const previous=texts.get(node),source=previous&&node.textContent===previous.output?previous.source:node.textContent;
   const output=translate(source,language);texts.set(node,{source,output});
   if(node.textContent!==output)node.textContent=output;
  }
  for(const target of [element,...element.querySelectorAll('[aria-label],[title],[placeholder]')]){
   if(excluded(target))continue;
   const record=attributes.get(target)||{};
   for(const name of ['aria-label','title','placeholder']){
    if(!target.hasAttribute(name))continue;
    const current=target.getAttribute(name),last=record[name],source=last&&current===last.output?last.source:current;
    const output=translate(source,language);record[name]={source,output};
    if(current!==output)target.setAttribute(name,output);
   }
   attributes.set(target,record);
  }
 }
 let queued=false;
 const observer=new MutationObserver(records=>{
  if(queued||!records.some(record=>!excluded(record.target.nodeType===3?record.target.parentElement:record.target)))return;
  queued=true;queueMicrotask(()=>{queued=false;apply();});
 });
 observer.observe(root.documentElement,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['aria-label','title','placeholder']});
 const refresh=()=>{
  const next=preference==='auto'?system:preference;
  if(language===next)return false;
  language=next;apply();return true;
 };
 apply();
 return{
  get language(){return language;},
  get preference(){return preference;},
  set(value){preference=matchingLanguage(value)||'auto';storage.setItem(LANGUAGE_KEY,preference);return refresh();},
  updateSystem(languages){system=deviceLanguage(languages);return refresh();},
  apply,
  t:(value,params)=>translate(value,language,params),
 };
}
