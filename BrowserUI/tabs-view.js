const overviews = new WeakMap();

export function renderTabsOverview(root, options) {
 const {tabs, activeTabId, icon, loadPreviews} = options;
 let view = overviews.get(root);
 if (!view || view.grid.parentElement !== root) {
  const grid = document.createElement('div');grid.className = 'tabs-grid';grid.id = 'tabs-grid';
  const add = document.createElement('button');add.id = 'new-tab';add.className = 'tabs-new';
  add.setAttribute('aria-label', 'Новая вкладка');add.innerHTML = icon('plus');
  view = {grid, cards:new Map(), options, request:0};
  add.addEventListener('click', () => view.options.onNew());
  root.replaceChildren(grid, add);overviews.set(root, view);
 }
 view.options = options;
 // Native dictionaries do not guarantee property order. Compare the visible
 // fields in a fixed order, leaving unrelated playback/loading updates alone.
 const signature = JSON.stringify([activeTabId, tabs.map(tab => [tab.id, tab.url, tab.title, tab.siteName, tab.iconUrl, tab.error, tab.privateBrowsing === true])]);
 if (signature === view.signature) return;
 view.signature = signature;
 const scroll = root.scrollTop, ids = new Set(tabs.map(tab => tab.id));
 for (const [id, entry] of view.cards) if (!ids.has(id)) {entry.card.remove();view.cards.delete(id);}
 view.empty?.remove();
 tabs.forEach((tab, index) => {
  let entry = view.cards.get(tab.id);
  if (!entry) {
   const card = document.createElement('article');card.className = 'tab-card';card.dataset.tabId = tab.id;
   const open = document.createElement('button');open.className = 'tab-open';open.dataset.selectTab = tab.id;
   const preview = document.createElement('div');preview.className = 'tab-preview';
   const title = document.createElement('strong');title.className = 'tab-title';
   const subtitle = document.createElement('span');subtitle.className = 'tab-host';
   const close = document.createElement('button');close.className = 'tab-close';close.dataset.closeTab = tab.id;close.innerHTML = icon('close');
   open.append(preview, title, subtitle);card.append(open, close);
   open.addEventListener('click', () => view.options.onSelect(tab.id));
   close.addEventListener('click', () => view.options.onClose(tab.id));
   entry = {card, open, preview, title, subtitle, close};view.cards.set(tab.id, entry);
  }
  const isPrivate = tab.privateBrowsing === true;
  if (entry.url !== tab.url || entry.privateBrowsing !== isPrivate) {
   entry.url = tab.url;entry.privateBrowsing = isPrivate;entry.src = null;entry.pending = null;entry.fallback = null;entry.preview.replaceChildren();
  }
  entry.preview.classList.toggle('tab-blank-preview', !tab.url);
  if (isPrivate && entry.fallback !== 'private') {entry.preview.innerHTML=icon('incognito');entry.fallback='private';}
  const fallback = tab.iconUrl || '/assets/atma.png';
  if (!isPrivate && tab.url && !entry.src && entry.fallback !== fallback) {
   const container = document.createElement('div');container.className = 'tab-fallback';
   const logo = document.createElement('img');logo.src = fallback;logo.alt = '';logo.referrerPolicy = 'no-referrer';
   logo.addEventListener('error', () => {if (logo.getAttribute('src') !== '/assets/atma.png') logo.src = '/assets/atma.png';});
   container.append(logo);entry.preview.replaceChildren(container);entry.fallback = fallback;
  }
  const name = isPrivate ? 'Инкогнито' : tab.title || tab.siteName || (tab.url ? new URL(tab.url).hostname : 'Новая вкладка');
  entry.title.textContent = name;if (tab.url && !isPrivate) entry.title.dataset.noTranslate = '';else delete entry.title.dataset.noTranslate;
  entry.subtitle.textContent = isPrivate ? 'Приватная вкладка' : tab.error ? 'Не удалось открыть' : tab.url ? new URL(tab.url).hostname : 'Пустая вкладка';
  entry.open.setAttribute('aria-label', 'Открыть вкладку: ' + name);
  entry.open.setAttribute('aria-current', String(tab.id === activeTabId));
  entry.close.setAttribute('aria-label', 'Закрыть вкладку: ' + name);
  entry.card.classList.toggle('selected', tab.id === activeTabId);
  entry.card.classList.toggle('private-tab', isPrivate);
  if (view.grid.children[index] !== entry.card) view.grid.insertBefore(entry.card, view.grid.children[index] || null);
 });
 if (!tabs.length) {
  view.empty = document.createElement('p');view.empty.className = 'tabs-empty';view.empty.textContent = 'Нет открытых вкладок';view.grid.append(view.empty);
 }
 root.scrollTop = scroll;
 const request = ++view.request, urls = new Map(tabs.map(tab => [tab.id, tab.url]));
 loadPreviews().then(({previews}) => {
  if (!view.grid.isConnected || view.request !== request) return;
  for (const [id, entry] of view.cards) {
   if(entry.privateBrowsing)continue;
   const src = previews[id];
   if (!src || entry.url !== urls.get(id) || src === entry.src || src === entry.pending) continue;
   const image = new Image();image.className = 'tab-shot';image.alt = '';entry.pending = src;
   image.addEventListener('load', () => {
    if (entry.card.isConnected && entry.url === urls.get(id) && entry.pending === src) {
     entry.preview.replaceChildren(image);entry.src = src;entry.pending = null;
    }
   });
   image.addEventListener('error', () => {if (entry.pending === src) entry.pending = null;});
   image.src = src;
  }
 }).catch(() => {});
}
