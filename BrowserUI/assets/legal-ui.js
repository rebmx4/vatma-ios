import legal from './legal.js';

// Bundled and public pages use the same copy, including when the device is offline.
export function renderLegalInfo(container,{kind='privacy',language='ru',onOpen}={}){
 const locale=language==='en'?'en':'ru',copy=legal.locales[locale];
 const article=document.createElement('article');
 article.dataset.noTranslate='';article.style.padding='4px 4px 24px';article.style.lineHeight='1.55';
 const add=(tag,text)=>{const node=document.createElement(tag);node.textContent=text;article.append(node);return node;};
 add('p',copy.updatedLabel).className='sheet-note';
 add('p',copy.contact);
 if(kind==='support')add('p',copy.free);
 for(const section of copy[kind]){
  const heading=add('h3',section.title);heading.style.marginTop='24px';
  for(const paragraph of section.paragraphs)add('p',paragraph);
 }
 if(onOpen&&kind==='privacy'){
  const source=add('button',locale==='en'?'View source code':'Проверить исходный код');source.className='setting-row';source.addEventListener('click',()=>onOpen('https://github.com/rebmx4/vatma-ios'));
 }
 if(onOpen){
  const button=add('button',locale==='en'?'Open public page':'Открыть публичную страницу');
  button.className='setting-row';
  button.addEventListener('click',()=>onOpen(legal.baseUrl+(locale==='en'?'en/':'')+kind+'.html'));
 }
 container.append(article);
}
