import english from './locale-en.js';
export const LANGUAGE_KEY='atma-interface-language';
export const LANGUAGES=Object.freeze(['ru','en']);
export const normalizeLanguage=value=>LANGUAGES.includes(value)?value:'ru';
const russian=new Map(Object.entries(english).filter(([ru,en])=>ru!==en).map(([ru,en])=>[en,ru]));
export function translate(value,language){
 const text=String(value),trimmed=text.trim();
 const source=russian.get(trimmed)||trimmed;
 let result=language==='en'?(english[source]||source):source;
 if(language==='en'&&!english[source]){
  const patterns=[
   [/^Автоматическая · сейчас (тёмная|светлая)$/,(_,theme)=>`Automatic · currently ${theme==='тёмная'?'dark':'light'}`],
   [/^Открытые вкладки: (\d+)$/,(_,n)=>`Open tabs: ${n}`],
   [/^Страница (\d+)$/,(_,n)=>`Page ${n}`],
   [/^Введено (\d+) из 6 цифр$/,(_,n)=>`${n} of 6 digits entered`],
   [/^Иконка ATMA: (.+)$/,(_,name)=>`ATMA icon: ${name}`],
   [/^Удалить выбранные \((\d+)\)$/,(_,n)=>`Delete selected (${n})`],
   [/^Профиль: (.+)$/,(_,name)=>`Profile: ${name}`],
   [/^Выбрать cookie: (.+)$/,(_,name)=>`Select cookie: ${name}`],
   [/^Открыть вкладку: (.+)$/,(_,name)=>`Open tab: ${name}`],
   [/^Закрыть вкладку: (.+)$/,(_,name)=>`Close tab: ${name}`],
   [/^Открыть (.+)$/,(_,name)=>`Open ${name}`],
   [/^Удалить (.+)$/,(_,name)=>`Delete ${name}`],
   [/^Расформировать (.+)$/,(_,name)=>`Ungroup ${name}`],
  ];
  for(const [pattern,replacement]of patterns)if(pattern.test(source)){result=source.replace(pattern,replacement);break;}
 }
 return trimmed?text.replace(trimmed,()=>result):text;
}
// Retain original labels for reversible live switching, including labels rebuilt by the UI.
// Site content is a separate renderer. User names and cookie data opt out explicitly.
export function createLocalization(root=document,storage=localStorage){
 let language=normalizeLanguage(storage.getItem(LANGUAGE_KEY));
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
 apply();
 return{get language(){return language;},set(value){language=normalizeLanguage(value);storage.setItem(LANGUAGE_KEY,language);apply();},apply,t:value=>translate(value,language)};
}
