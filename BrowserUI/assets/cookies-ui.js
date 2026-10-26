const TYPE_NAMES={
  WKWebsiteDataTypeCookies:'Cookie',
  WKWebsiteDataTypeLocalStorage:'Локальное хранилище',
  WKWebsiteDataTypeSessionStorage:'Хранилище сеанса',
  WKWebsiteDataTypeIndexedDBDatabases:'Базы данных сайта',
  WKWebsiteDataTypeDiskCache:'Кеш',
  WKWebsiteDataTypeMemoryCache:'Кеш в памяти',
  WKWebsiteDataTypeWebSQLDatabases:'Базы данных сайта',
  WKWebsiteDataTypeServiceWorkerRegistrations:'Фоновые сценарии сайта',
  WKWebsiteDataTypeFetchCache:'Кеш сайта',
};

export async function renderCookieBrowser(root,{api,onBack,notify,t=value=>value,backLabel='Рабочий стол'}){
  const make=(tag,className,text)=>{
    const node=document.createElement(tag);
    if(className)node.className=className;
    if(text!==undefined)node.textContent=t(text);
    return node;
  };
  root.replaceChildren();root.classList.add('cookie-browser');
  const back=make('button','file-back',`‹ ${backLabel}`);back.id='cookies-back';
  back.addEventListener('click',()=>{root.classList.remove('cookie-browser');onBack();});
  const heading=make('h2','file-title','Данные сайтов');
  const explanation=make('p','site-data-explanation','Здесь видны сайты, типы локальных данных и cookie без секретных значений. Данные на серверах сайтов браузеру недоступны.');
  const profile=make('p','file-meta','Загрузка…');
  const tabs=make('div','site-data-tabs');
  const siteTab=make('button','','Сайты'),cookieTab=make('button','','Cookie'),passwordTab=make('button','','Пароли');
  siteTab.id='site-data-tab';cookieTab.id='cookie-data-tab';passwordTab.id='password-data-tab';
  tabs.append(siteTab,cookieTab,passwordTab);
  const controls=make('div','cookie-actions');
  const selectAll=make('button','secondary-button','Выбрать все');selectAll.id='cookies-select-all';
  const removeSelected=make('button','secondary-button','Удалить выбранные');removeSelected.id='cookies-delete-selected';
  const removeAll=make('button','cookie-delete','Удалить все');removeAll.id='cookies-delete-all';
  controls.append(selectAll,removeSelected,removeAll);
  const list=make('div','cookie-list');list.id='cookie-list';
  const tools=make('div','files-tools'),label=make('label','model-search'),search=make('input');
  search.placeholder=t('Поиск cookie или сайта');search.setAttribute('aria-label',t('Поиск cookie или сайта'));search.id='cookie-search';
  label.append(search);tools.append(label);
  root.append(back,heading,explanation,profile,tabs,controls,list,tools);
  let cookies=[],records=[],selected=new Set(),busy=false,active='sites',confirmAll=false,confirmTimer;
  const current=()=>list.isConnected;
  const filteredCookies=()=>cookies.filter(row=>`${row.domain} ${row.name}`.toLocaleLowerCase().includes(search.value.toLocaleLowerCase()));
  const filteredSites=()=>records.filter(row=>row.name.toLocaleLowerCase().includes(search.value.toLocaleLowerCase()));

  function resetConfirmation(){confirmAll=false;clearTimeout(confirmTimer);updateControls();}
  function updateControls(){
    const cookieMode=active==='cookies';
    controls.hidden=active==='passwords';tools.hidden=active==='passwords';
    selectAll.hidden=removeSelected.hidden=!cookieMode;
    selectAll.disabled=busy||!cookies.length;
    removeSelected.disabled=busy||!selected.size;
    removeSelected.textContent=t('Удалить выбранные')+(selected.size?` (${selected.size})`:'');
    removeAll.disabled=busy||!(cookieMode?cookies.length:records.length);
    removeAll.textContent=confirmAll?t('Подтвердить удаление'):t(cookieMode?'Удалить все cookie':'Удалить данные всех сайтов');
    siteTab.setAttribute('aria-selected',String(active==='sites'));
    cookieTab.setAttribute('aria-selected',String(cookieMode));
    passwordTab.setAttribute('aria-selected',String(active==='passwords'));
  }
  function detailRow(table,name,value){
    const row=make('div','cookie-detail-row'),key=make('span','',name),content=make('code','',String(value));
    content.dataset.noTranslate='';row.append(key,content);table.append(row);
  }
  function renderCookies(){
    const visible=filteredCookies();
    if(!visible.length)list.append(make('p','files-empty',cookies.length?'Cookie не найдены':'Сохранённых cookie нет'));
    for(const cookie of visible){
      const card=make('details','cookie-card');card.dataset.cookieId=cookie.id;
      const summary=make('summary'),check=make('input');check.type='checkbox';check.checked=selected.has(cookie.id);
      check.setAttribute('aria-label',`${t('Выбрать cookie')}: ${cookie.name}`);check.dataset.cookieSelect=cookie.id;
      check.addEventListener('click',event=>event.stopPropagation());
      check.addEventListener('change',()=>{check.checked?selected.add(cookie.id):selected.delete(cookie.id);updateControls();});
      const names=make('span','cookie-name'),title=make('strong','',cookie.name),domain=make('small','',cookie.domain+cookie.path);
      title.dataset.noTranslate='';domain.dataset.noTranslate='';names.append(title,domain);summary.append(check,names);
      const table=make('div','cookie-details');
      detailRow(table,'Сайт',cookie.domain);detailRow(table,'Имя',cookie.name);detailRow(table,'Путь',cookie.path);
      detailRow(table,'Срок',cookie.session?t('До закрытия сеанса'):cookie.expires?new Date(cookie.expires*1000).toLocaleString(document.documentElement.lang==='en'?'en-US':'ru-RU'):t('Не указан'));
      detailRow(table,'Secure',cookie.secure?t('Да'):t('Нет'));detailRow(table,'HttpOnly',cookie.httpOnly?t('Да'):t('Нет'));
      card.append(summary,table);list.append(card);
    }
  }
  function renderSites(){
    const visible=filteredSites();
    if(!visible.length)list.append(make('p','files-empty',records.length?'Сайты не найдены':'Данных сайтов нет'));
    for(const record of visible){
      const card=make('div','site-data-card'),name=make('strong','',record.name);
      const types=make('small','',record.types.map(type=>t(TYPE_NAMES[type]||type.replace('WKWebsiteDataType',''))).join(' · '));
      name.dataset.noTranslate='';
      const remove=make('button','site-data-remove','Удалить данные');remove.setAttribute('aria-label',`${t('Удалить данные')}: ${record.name}`);
      remove.disabled=busy;remove.addEventListener('click',()=>removeSites({names:[record.name]}));
      card.append(name,types,remove);list.append(card);
    }
  }
  function renderPasswords(){
    const card=make('div','site-data-card');
    card.append(make('strong','','Пароли сайтов недоступны ATMA'),make('p','','WebKit не предоставляет браузеру пароли, введённые на сайтах. Cookie и токены входа здесь не показываются как пароли.'));
    list.append(card);
  }
  function render(){
    list.replaceChildren();
    if(active==='sites')renderSites();else if(active==='cookies')renderCookies();else renderPasswords();
    updateControls();
  }
  async function refresh(){
    const [cookieResult,siteResult]=await Promise.all([api('cookies'),api('site-data')]);
    if(!current())return;
    cookies=Array.isArray(cookieResult.cookies)?cookieResult.cookies:[];
    records=Array.isArray(siteResult.records)?siteResult.records:[];
    profile.textContent=siteResult.preview?t('Данные сайтов доступны в приложении на iPhone'):`${t('Сайтов')}: ${records.length} · ${t('Cookie')}: ${cookies.length}`;render();
  }
  async function removeCookies(selection){
    if(busy)return;busy=true;updateControls();
    try{await api('cookies/delete',selection);selected.clear();await refresh();notify(t('Cookie удалены'));}
    catch(error){notify(error.message);}finally{busy=false;if(current())resetConfirmation();}
  }
  async function removeSites(selection){
    if(busy)return;busy=true;updateControls();
    try{await api('site-data/delete',selection);selected.clear();await refresh();notify(t('Данные сайтов удалены'));}
    catch(error){notify(error.message);}finally{busy=false;if(current())resetConfirmation();}
  }
  function switchTab(value){active=value;resetConfirmation();render();}
  siteTab.addEventListener('click',()=>switchTab('sites'));
  cookieTab.addEventListener('click',()=>switchTab('cookies'));
  passwordTab.addEventListener('click',()=>switchTab('passwords'));
  search.addEventListener('input',render);
  selectAll.addEventListener('click',()=>{selected=new Set(filteredCookies().map(row=>row.id));render();});
  removeSelected.addEventListener('click',()=>removeCookies({ids:[...selected]}));
  removeAll.addEventListener('click',()=>{
    if(!confirmAll){confirmAll=true;updateControls();confirmTimer=setTimeout(resetConfirmation,6000);return;}
    if(active==='cookies')removeCookies({all:true});else removeSites({all:true});
  });
  updateControls();
  try{await refresh();}catch(error){if(current()){list.replaceChildren(make('p','files-empty',error.message));profile.textContent='';}}
}
