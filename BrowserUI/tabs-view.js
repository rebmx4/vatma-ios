export function renderTabsOverview(root,{tabs,activeTabId,icon,onSelect,onClose,onNew,loadPreviews}){
 const scroll=root.scrollTop;root.replaceChildren();
 const grid=document.createElement('div');grid.className='tabs-grid';grid.id='tabs-grid';
 for(const tab of tabs){
  const card=document.createElement('article');card.className='tab-card';card.dataset.tabId=tab.id;card.classList.toggle('selected',tab.id===activeTabId);
  const open=document.createElement('button');open.className='tab-open';open.dataset.selectTab=tab.id;open.setAttribute('aria-label',`Открыть вкладку: ${tab.title||tab.siteName||'Новая вкладка'}`);if(tab.id===activeTabId)open.setAttribute('aria-current','true');
  const preview=document.createElement('div');preview.className='tab-preview';
  preview.classList.toggle('tab-blank-preview',!tab.url);
  if(tab.url){
  const fallback=document.createElement('div');fallback.className='tab-fallback';
  const logo=document.createElement('img');logo.src=tab.iconUrl||'/assets/atma.png';logo.alt='';logo.referrerPolicy='no-referrer';logo.addEventListener('error',()=>{if(logo.getAttribute('src')!=='/assets/atma.png')logo.src='/assets/atma.png';});fallback.append(logo);preview.append(fallback);
  }
  const title=document.createElement('strong');title.className='tab-title';title.textContent=tab.title||tab.siteName||(tab.url?new URL(tab.url).hostname:'Новая вкладка');if(tab.url)title.dataset.noTranslate='';
  const subtitle=document.createElement('span');subtitle.className='tab-host';subtitle.textContent=tab.error?'Не удалось открыть':tab.url?new URL(tab.url).hostname:'Пустая вкладка';
  open.append(preview,title,subtitle);open.addEventListener('click',()=>onSelect(tab.id));
  const close=document.createElement('button');close.className='tab-close';close.dataset.closeTab=tab.id;close.setAttribute('aria-label',`Закрыть вкладку: ${title.textContent}`);close.innerHTML=icon('close');close.addEventListener('click',()=>onClose(tab.id));card.append(open,close);grid.append(card);
 }
 if(!tabs.length){const empty=document.createElement('p');empty.className='tabs-empty';empty.textContent='Нет открытых вкладок';grid.append(empty);}
 const add=document.createElement('button');add.id='new-tab';add.className='tabs-new';add.setAttribute('aria-label','Новая вкладка');add.innerHTML=icon('plus');add.addEventListener('click',onNew);root.append(grid,add);root.scrollTop=scroll;
 loadPreviews().then(({previews})=>{if(!grid.isConnected)return;for(const card of grid.querySelectorAll('[data-tab-id]')){const src=previews[card.dataset.tabId];if(!src)continue;const image=new Image();image.className='tab-shot';image.alt='';image.addEventListener('load',()=>{if(card.isConnected)card.querySelector('.tab-preview').replaceChildren(image);});image.src=src;}}).catch(()=>{});
}
