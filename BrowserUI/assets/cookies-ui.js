export async function renderCookieBrowser(root,{api,onBack,notify,t=value=>value}){
 const make=(tag,className,text)=>{const node=document.createElement(tag);if(className)node.className=className;if(text!==undefined)node.textContent=t(text);return node;};
 root.replaceChildren();
 root.classList.add('cookie-browser');
 const back=make('button','file-back','‹ Файлы');back.id='cookies-back';back.addEventListener('click',()=>{root.classList.remove('cookie-browser');onBack();});
 const heading=make('h2','file-title','Cookie сайтов'),profile=make('p','file-meta','Загрузка…');
 const controls=make('div','cookie-actions'),selectAll=make('button','secondary-button','Выбрать все'),removeSelected=make('button','secondary-button','Удалить выбранные'),removeAll=make('button','cookie-delete','Удалить все');
 selectAll.id='cookies-select-all';removeSelected.id='cookies-delete-selected';removeAll.id='cookies-delete-all';controls.append(selectAll,removeSelected,removeAll);
 const list=make('div','cookie-list');list.id='cookie-list';
 const tools=make('div','files-tools'),label=make('label','model-search'),search=make('input');search.placeholder=t('Поиск cookie или сайта');search.setAttribute('aria-label',t('Поиск cookie или сайта'));search.id='cookie-search';label.append(search);tools.append(label);
 root.append(back,heading,profile,controls,list,tools);
 let cookies=[],selected=new Set(),busy=false;
 const current=()=>list.isConnected;
 function updateControls(){removeSelected.disabled=busy||!selected.size;removeAll.disabled=busy||!cookies.length;selectAll.disabled=busy||!cookies.length;removeSelected.textContent=t('Удалить выбранные')+(selected.size?` (${selected.size})`:'');}
 function detailRow(table,name,value){const row=make('div','cookie-detail-row'),key=make('span','',name),content=make('code','',String(value));content.dataset.noTranslate='';row.append(key,content);table.append(row);}
 function render(){
  list.replaceChildren();const filter=search.value.toLocaleLowerCase(),visible=cookies.filter(c=>`${c.domain} ${c.name}`.toLocaleLowerCase().includes(filter));
  if(!visible.length)list.append(make('p','files-empty',cookies.length?'Cookie не найдены':'Сохранённых cookie нет'));
  for(const cookie of visible){
   const card=make('details','cookie-card');card.dataset.cookieId=cookie.id;
   const summary=make('summary'),check=make('input');check.type='checkbox';check.checked=selected.has(cookie.id);check.setAttribute('aria-label',`${t('Выбрать cookie')}: ${cookie.name}`);check.dataset.cookieSelect=cookie.id;
   check.addEventListener('click',event=>event.stopPropagation());check.addEventListener('change',()=>{check.checked?selected.add(cookie.id):selected.delete(cookie.id);updateControls();});
   const names=make('span','cookie-name'),title=make('strong','',cookie.name),domain=make('small','',cookie.domain+cookie.path);title.dataset.noTranslate='';domain.dataset.noTranslate='';names.append(title,domain);summary.append(check,names);
   const table=make('div','cookie-details');detailRow(table,'Сайт',cookie.domain);detailRow(table,'Имя',cookie.name);detailRow(table,'Значение',cookie.value);detailRow(table,'Путь',cookie.path);
   detailRow(table,'Срок',cookie.session?t('До закрытия сеанса'):cookie.expires?new Date(cookie.expires*1000).toLocaleString(document.documentElement.lang==='en'?'en-US':'ru-RU'):t('Не указан'));
   detailRow(table,'Secure',cookie.secure?t('Да'):t('Нет'));detailRow(table,'HttpOnly',cookie.httpOnly?t('Да'):t('Нет'));card.append(summary,table);list.append(card);
  }
  updateControls();
 }
 async function refresh(){const result=await api('cookies');if(!current())return;cookies=result.cookies;profile.textContent=t(`Cookie сайтов: ${cookies.length}`);render();}
 async function remove(selection){
  if(busy)return;busy=true;updateControls();
  try{const result=await api('cookies/delete',selection);if(!current())return;cookies=result.cookies;selected.clear();profile.textContent=t(`Cookie сайтов: ${cookies.length}`);render();notify(t('Cookie удалены'));}catch(error){notify(error.message);}finally{busy=false;if(current())updateControls();}
 }
 search.addEventListener('input',render);
 selectAll.addEventListener('click',()=>{const filter=search.value.toLocaleLowerCase();selected=new Set(cookies.filter(c=>`${c.domain} ${c.name}`.toLocaleLowerCase().includes(filter)).map(c=>c.id));render();});
 removeSelected.addEventListener('click',()=>remove({ids:[...selected]}));removeAll.addEventListener('click',()=>remove({all:true}));
 updateControls();try{await refresh();}catch(error){if(current()){list.replaceChildren(make('p','files-empty',error.message));profile.textContent='';}}
}
