const overviews = new WeakMap();
const layouts = [2, 3, 5];
const russianPlural = new Intl.PluralRules('ru');
const tabWord = {one:'вкладка', few:'вкладки', many:'вкладок', other:'вкладки'};
const overviewGlyphs = {
 grid:'<rect x="3.5" y="4" width="17" height="16" rx="2.5"/><path d="M12 4v16M3.5 12h17"/>',
 history:'<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
 copy:'<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
 blank:'<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M4 9h16"/>',
};

function element(tag, className, text) {
 const node = document.createElement(tag);
 node.className = className;
 if (text !== undefined) node.textContent = text;
 return node;
}

function label(view, source, values = {}) {
 const translation = view.options.t?.(source) ?? source;
 return translation.replace(/\{(\w+)\}/g, (_, name) => String(values[name]));
}

function glyph(view, name) {
 const path = overviewGlyphs[name];
 return path ? `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>` : view.options.icon(name);
}

function control(view, className, iconName, handler) {
 const node = element('button', className);
 node.type = 'button';
 if (iconName) node.innerHTML = glyph(view, iconName);
 node.addEventListener('click', handler);
 return node;
}

function labeled(node, value) {
 node.setAttribute('aria-label', value);
}

function setText(node, value) {
 if (node.textContent !== value) node.textContent = value;
}

function createOverview(root, options) {
 const view = {options, cards:new Map(), selected:new Set(), layout:2, request:0};
 const shell = element('div', 'tabs-overview');
 shell.dataset.noTranslate = '';
 shell.tabIndex = -1;
 const top = element('header', 'tabs-top');
 const normal = element('div', 'tabs-top-line');
 const search = element('div', 'tabs-search');
 search.setAttribute('role', 'search');
 const symbol = element('span', 'tabs-search-icon');
 symbol.innerHTML = glyph(view, 'search');
 const query = element('input', 'tabs-query');
 query.type = 'search';
 query.autocomplete = 'off';
 query.spellcheck = false;
 const clear = control(view, 'tabs-control tabs-search-clear', 'close', () => {
  query.value = '';
  filterTabs(view);
  query.focus();
 });
 search.append(symbol, query, clear);
 const tools = element('div', 'tabs-tools');
 const actions = control(view, 'tabs-control', 'dots', () => showActions(view));
 actions.setAttribute('aria-haspopup', 'dialog');
 actions.setAttribute('aria-expanded', 'false');
 const layout = control(view, 'tabs-control tabs-layout', null, () => {
  view.layout = layouts[(layouts.indexOf(view.layout) + 1) % layouts.length];
  updateLayout(view);
 });
 const layoutCount = element('span', 'tabs-layout-count');
 layout.innerHTML = glyph(view, 'grid');
 layout.append(layoutCount);
 tools.append(actions, layout);
 normal.append(search, tools);
 const selection = element('div', 'tabs-top-line tabs-selection-top');
 const selectionCount = element('h2', 'tabs-selection-count');
 selectionCount.setAttribute('aria-live', 'polite');
 const cancel = control(view, 'tabs-control', null, () => finishSelection(view));
 selection.append(selectionCount, cancel);
 top.append(normal, selection);
 const deck = element('div', 'tabs-deck');
 const groups = element('div', 'tabs-groups');
 groups.setAttribute('role', 'tablist');
 const switches = [], grids = [];
 for (const [index, group] of ['regular','private'].entries()) {
  const button = control(view, 'tabs-group', index ? 'incognito' : null, () => switchGroup(view, index));
  button.id = 'tabs-group-' + group;
  button.setAttribute('role', 'tab');
  button.setAttribute('aria-controls', 'tabs-grid-' + group);
  const text = element('span', '');
  button.append(text);
  button.addEventListener('keydown', event => {
   if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
   event.preventDefault();
   const next = event.key === 'Home' ? 0 : event.key === 'End' ? 1 : 1 - index;
   switchGroup(view, next);
   switches[next].button.focus({preventScroll:true});
  });
  const grid = element('section', 'tabs-grid');
  grid.id = 'tabs-grid-' + group;
  grid.setAttribute('role', 'tabpanel');
  grid.setAttribute('aria-labelledby', button.id);
  switches.push({button, text});
  grids.push(grid);
  groups.append(button);
  deck.append(grid);
 }
 const bottom = element('footer', 'tabs-bottom');
 const add = control(view, 'tabs-control tabs-new', 'plus', () => {
  query.blur();
  view.options.onNew(view.group === 1);
 });
 add.id = 'new-tab';
 const home = control(view, 'tabs-control tabs-home', 'home', () => {
  query.blur();
  view.options.onHome?.();
 });
 bottom.append(add, groups, home);
 const bulk = element('footer', 'tabs-bulk');
 const all = control(view, 'tabs-control', null, () => {
  view.selected = new Set(view.selected.size === view.visible.length ? [] : view.visible.map(tab => tab.id));
  updateSelection(view);
 });
 const closeSelected = control(view, 'tabs-control tabs-bulk-close', null, () => closeTabs(view, [...view.selected]));
 bulk.append(all, closeSelected);
 const scrim = element('div', 'tabs-menu-scrim');
 const menu = element('div', 'tabs-menu');
 menu.setAttribute('role', 'dialog');
 menu.setAttribute('aria-modal', 'true');
 menu.tabIndex = -1;
 scrim.hidden = true;
 scrim.append(menu);
 scrim.addEventListener('click', event => {if (event.target === scrim) dismissMenu(view);});
 shell.append(top, deck, bottom, bulk, scrim);
 Object.assign(view, {shell, top, normal, query, clear, actions, layoutButton:layout, layoutCount,
  selection, selectionCount, cancel, deck, grids, switches, groups, bottom, add, home, bulk, all, closeSelected, scrim, menu});
 query.addEventListener('input', () => filterTabs(view));
 shell.addEventListener('keydown', event => handleKeyboard(view, event));
 installDeckGestures(view);
 root.replaceChildren(shell);
 return view;
}

function filterTabs(view) {
 view.selected.clear();
 view.deck.scrollTop = 0;
 updateGroup(view);
 if (view.group === 0 && view.visible.some(tab => tab.url && !tab.privatePreview && !view.cards.get(tab.id).src)) refreshPreviews(view);
}

function switchGroup(view, group) {
 if (view.group === group) return;
 finishSelection(view, false);
 view.group = group;
 view.deck.scrollTop = 0;
 updateGroup(view);
 if (group === 0) refreshPreviews(view);
 else view.request++;
}

function updateLayout(view) {
 const {layout, layoutButton, layoutCount} = view;
 const next = layouts[(layouts.indexOf(layout) + 1) % layouts.length];
 view.shell.dataset.cols = layout;
 setText(layoutCount, String(layout));
 layoutButton.title = layout + ' → ' + next;
 labeled(layoutButton, label(view, 'В ряду {count}. Переключить на {next}', {count:layout, next}));
}

function tabDetails(tab, view, devices) {
 let host = '';
 try { host = new URL(tab.url).hostname; } catch {}
 const privateBrowsing = tab.privateBrowsing === true;
 const protectedShortcut = tab.privateDesktop === true && !privateBrowsing;
 const name = protectedShortcut ? label(view, 'Приватная вкладка')
  : tab.title || tab.siteName || host || label(view, 'Новая вкладка');
 const device = privateBrowsing ? devices.get(tab.profileId) || label(view, 'Это устройство') : '';
 return {id:tab.id, name, device, group:privateBrowsing ? 1 : 0, url:tab.url,
  host:protectedShortcut ? '' : host, privatePreview:privateBrowsing || protectedShortcut,
  iconUrl:tab.iconUrl, document:tab.previewDocument};
}

function createCard(view, id) {
 const card = element('article', 'tab-card');
 card.dataset.tabId = id;
 const open = control(view, 'tab-open', null, () => {
  if (!view.scrim.hidden) return;
  if (view.selecting) {
   if (view.selected.has(id)) view.selected.delete(id);
   else view.selected.add(id);
   updateSelection(view);
  } else view.options.onSelect(id);
 });
 open.dataset.selectTab = id;
 const head = element('span', 'tab-head');
 const favicon = element('span', 'tab-favicon');
 const initial = element('span', '');
 favicon.setAttribute('aria-hidden', 'true');
 favicon.append(initial);
 const title = element('span', 'tab-title');
 head.append(favicon, title);
 const preview = element('span', 'tab-preview');
 preview.setAttribute('aria-hidden', 'true');
 const device = element('span', 'tab-device');
 const close = control(view, 'tab-close', 'close', () => closeTabs(view, [id]));
 close.dataset.closeTab = id;
 const mark = element('span', 'tab-mark');
 const check = element('span', '');
 check.innerHTML = glyph(view, 'check');
 mark.setAttribute('aria-hidden', 'true');
 mark.append(check);
 open.append(head, preview, device);
 card.append(open, close, mark);
 const entry = {card, open, close, mark, title, device, initial, favicon, preview};
 open.addEventListener('contextmenu', event => {
  event.preventDefault();
  cancelPress(view);
  if (!view.selecting) showCardMenu(view, entry);
 });
 open.addEventListener('pointerdown', event => {
  if (event.button !== 0 || !event.isPrimary || view.selecting) return;
  cancelPress(view);
  view.press = {id:event.pointerId, x:event.clientX, y:event.clientY, timer:setTimeout(() => showCardMenu(view, entry), 475)};
 });
 return entry;
}

function updateCard(view, entry, tab) {
 const {close, title, device, initial, preview} = entry;
 const prior = entry.tab;
 entry.tab = tab;
 if (!prior || prior.url !== tab.url || prior.document !== tab.document || prior.privatePreview !== tab.privatePreview) {
  entry.src = null;
  entry.pending = null;
  const fallback = element('span', 'tab-fallback');
  fallback.innerHTML = glyph(view, tab.privatePreview ? 'incognito' : 'blank');
  setText(initial, (tab.name[0] || 'A').toUpperCase());
  preview.replaceChildren(fallback);
 }
 if (!prior || prior.iconUrl !== tab.iconUrl || prior.name !== tab.name || prior.privatePreview !== tab.privatePreview) {
  setText(initial, (tab.name[0] || 'A').toUpperCase());
  if (tab.privatePreview) initial.innerHTML = glyph(view, 'incognito');
  updateFavicon(view, entry, tab);
 }
 setText(title, tab.name);
 setText(device, tab.device);
 device.hidden = !tab.device;
 labeled(close, label(view, 'Закрыть {name}', {name:tab.name}));
}

function updateFavicon(view, entry, tab) {
 const {favicon, initial} = entry;
 const key = tab.privatePreview || !tab.url ? '' : tab.iconUrl;
 if (key === entry.iconKey) return;
 entry.iconKey = key;
 favicon.replaceChildren(initial);
 if (!key || !view.options.loadIcon) return;
 Promise.resolve(view.options.loadIcon(key)).then(source => {
  if (!source || entry.iconKey !== key) return;
  const image = new Image();
  image.alt = '';
  image.draggable = false;
  image.addEventListener('load', () => {
   if (entry.iconKey === key) favicon.replaceChildren(image);
  });
  image.src = source;
 }).catch(() => {});
}

function updateGroup(view) {
 const {group, tabs, cards, grids, switches, query} = view;
 const search = (query.value || '').trim().toLocaleLowerCase(view.options.language);
 const current = tabs.filter(tab => tab.group === group);
 view.visible = current.filter(tab => [tab.name, tab.host, tab.device].join(' ').toLocaleLowerCase(view.options.language).includes(search));
 const visibleIds = new Set(view.visible.map(tab => tab.id));
 const tabsById = new Map(tabs.map(tab => [tab.id, tab]));
 for (const [id, entry] of cards) {
  const tab = tabsById.get(id);
  if (!visibleIds.has(id)) entry.card.remove();
  if (!tab || tab.group !== group) cards.delete(id);
 }
 for (const id of view.selected) if (!visibleIds.has(id)) view.selected.delete(id);
 view.empty?.remove();
 const grid = grids[group];
 view.visible.forEach((tab, index) => {
  const entry = cards.get(tab.id) || createCard(view, tab.id);
  cards.set(tab.id, entry);
  updateCard(view, entry, tab);
  if (grid.children[index] !== entry.card) grid.insertBefore(entry.card, grid.children[index] || null);
 });
 if (!view.visible.length) {
  const empty = current.length ? 'Ничего не найдено' : group ? 'Нет вкладок инкогнито' : 'Нет открытых вкладок';
  view.empty = element('p', 'tabs-empty', label(view, empty));
  grid.append(view.empty);
 }
 const count = view.regularCount;
 const unit = view.options.language === 'en' ? (count === 1 ? 'tab' : 'tabs') : tabWord[russianPlural.select(count)];
 setText(switches[0].text, count + ' ' + unit);
 setText(switches[1].text, label(view, 'Приватные'));
 switches.forEach(({button}, index) => {
  button.setAttribute('aria-selected', String(index === group));
  button.tabIndex = index === group ? 0 : -1;
  grids[index].hidden = index !== group;
 });
 view.clear.hidden = !query.value;
 updateSelection(view);
}

function updateSelection(view) {
 const {selecting, selected, visible} = view;
 view.selection.hidden = view.bulk.hidden = !selecting;
 view.normal.hidden = view.bottom.hidden = Boolean(selecting);
 setText(view.selectionCount, label(view, 'Выбрано {count}', {count:selected.size}));
 setText(view.closeSelected, label(view, 'Закрыть') + (selected.size ? ' (' + selected.size + ')' : ''));
 view.closeSelected.disabled = !selected.size || view.closing;
 setText(view.all, label(view, selected.size && selected.size === visible.length ? 'Снять выбор' : 'Выделить все'));
 view.all.disabled = !visible.length;
 for (const {card, open, close, mark, tab} of view.cards.values()) {
  const active = tab.id === view.options.activeTabId;
  const name = tab.device ? tab.name + ', ' + tab.device : tab.name;
  labeled(open, selecting ? name : label(view, 'Открыть вкладку: {name}', {name}));
  card.classList.toggle('selected', !selecting && active);
  card.classList.toggle('tab-picked', selected.has(tab.id));
  if (selecting) {
   open.setAttribute('aria-pressed', String(selected.has(tab.id)));
   open.removeAttribute('aria-current');
  } else {
   open.removeAttribute('aria-pressed');
   open.setAttribute('aria-current', String(active));
  }
  close.hidden = Boolean(selecting);
  mark.hidden = !selecting;
 }
}

function finishSelection(view, focus = true) {
 if (!view.selecting) return;
 view.selecting = false;
 view.selected.clear();
 updateSelection(view);
 if (focus) view.actions.focus({preventScroll:true});
}

async function closeTabs(view, ids) {
 if (view.closing) return;
 view.closing = true;
 const restoreFocus = !view.scrim.hidden || view.selecting
  || ids.some(id => view.cards.get(id)?.close === document.activeElement);
 dismissMenu(view, false);
 try {
  if (view.options.onCloseMany) await view.options.onCloseMany(ids);
  else for (const id of ids) await view.options.onClose(id);
  finishSelection(view, false);
 } catch (error) {
  view.options.onError?.(error.message);
 } finally {
  view.closing = false;
  updateSelection(view);
  if (restoreFocus && view.shell.isConnected) (view.selecting ? view.closeSelected : view.actions).focus({preventScroll:true});
 }
}

function menuItem(view, text, iconName, run, danger = false) {
 const button = control(view, danger ? 'tabs-menu-danger' : '', iconName, run);
 button.append(element('span', '', label(view, text)));
 return button;
}

function showMenu(view, title, items, trigger) {
 view.trigger = trigger || view.trigger;
 view.menu.replaceChildren(element('h2', '', title), ...items);
 labeled(view.menu, title);
 view.scrim.hidden = false;
 view.top.inert = view.deck.inert = view.bottom.inert = view.bulk.inert = true;
 view.actions.setAttribute('aria-expanded', String(view.trigger === view.actions));
 view.menu.focus({preventScroll:true});
}

function dismissMenu(view, focus = true) {
 if (view.scrim.hidden) return;
 view.scrim.hidden = true;
 view.top.inert = view.deck.inert = view.bottom.inert = view.bulk.inert = false;
 view.actions.setAttribute('aria-expanded', 'false');
 if (focus) {
  const target = view.trigger?.isConnected ? view.trigger : view.actions;
  target.focus({preventScroll:true});
 }
 view.trigger = null;
}

function showActions(view) {
 view.query.blur();
 const current = view.tabs.filter(tab => tab.group === view.group);
 const select = menuItem(view, 'Выбрать вкладки', 'check', () => {
  dismissMenu(view, false);
  view.selecting = true;
  updateSelection(view);
  view.cancel.focus({preventScroll:true});
 });
 select.disabled = !view.visible.length;
 const close = menuItem(view, 'Закрыть все в группе', 'close', () => {
  showMenu(view, label(view, 'Закрыть {count} вкладок?', {count:current.length}), [
   menuItem(view, 'Отмена', null, () => dismissMenu(view)),
   menuItem(view, 'Закрыть', 'close', () => closeTabs(view, current.map(tab => tab.id)), true),
  ]);
 }, true);
 close.disabled = !current.length || view.closing;
 const items = [select, close];
 if (view.options.loadHistory && view.group === 0) items.unshift(menuItem(view, 'История', 'history', () => showHistory(view)));
 if (view.options.onSettings) items.push(menuItem(view, 'Настройки', 'dots', () => view.options.onSettings()));
 showMenu(view, label(view, 'Действия'), items, view.actions);
}

async function showHistory(view) {
 const back = menuItem(view, 'К вкладкам', 'left', () => dismissMenu(view));
 const content = element('div', 'tabs-history');
 content.append(element('p', '', label(view, 'Загрузка…')));
 showMenu(view, label(view, 'История'), [content, back]);
 try {
  const {entries} = await view.options.loadHistory();
  if (!content.isConnected || view.scrim.hidden) return;
  content.replaceChildren();
  for (const entry of entries || []) {
   const open = control(view, 'tabs-history-item', null, async () => {
    try { await view.options.onOpenHistory(entry); }
    catch (error) {view.options.onError?.(error.message);}
   });
   const title = element('strong', '', entry.title || entry.url);
   const url = element('small', '', entry.url);
   open.append(title, url);
   content.append(open);
  }
  if (!entries?.length) content.append(element('p', '', label(view, 'В открытых вкладках нет истории')));
 } catch (error) {
  content.replaceChildren(element('p', '', error.message));
 }
}

function showCardMenu(view, {tab, open}) {
 if (!open.isConnected || (!view.scrim.hidden && view.trigger === open)) return;
 const items = [
  menuItem(view, 'Открыть вкладку', 'blank', () => {
   dismissMenu(view, false);
   view.options.onSelect(tab.id);
  }),
  menuItem(view, 'Закрыть вкладку', 'close', () => closeTabs(view, [tab.id]), true),
 ];
 if (view.options.onDuplicate) items.splice(1, 0, menuItem(view, 'Создать копию', 'copy', async () => {
  dismissMenu(view);
  try { await view.options.onDuplicate(tab.id); }
  catch (error) {view.options.onError?.(error.message);}
 }));
 showMenu(view, tab.name, items, open);
}

function cancelPress(view) {
 if (!view.press) return;
 clearTimeout(view.press.timer);
 view.press = null;
}

function installDeckGestures(view) {
 const {deck} = view;
 let start, suppressClick = false;
 deck.addEventListener('pointerdown', event => {
  suppressClick = false;
  if (event.pointerType === 'touch' && event.isPrimary) start = {x:event.clientX, y:event.clientY, id:event.pointerId};
 });
 deck.addEventListener('pointermove', event => {
  const press = view.press;
  if (press?.id === event.pointerId && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 9) cancelPress(view);
 }, {passive:true});
 deck.addEventListener('pointercancel', event => {
  if (start?.id === event.pointerId) start = null;
  cancelPress(view);
 }, {passive:true});
 deck.addEventListener('pointerleave', () => cancelPress(view));
 deck.addEventListener('pointerup', event => {
  cancelPress(view);
  if (start?.id !== event.pointerId) return;
  const dx = event.clientX - start.x, dy = event.clientY - start.y;
  start = null;
  if (Math.abs(dx) < 54 || Math.abs(dx) < Math.abs(dy) * 1.4 || !view.scrim.hidden) return;
  suppressClick = true;
  switchGroup(view, dx < 0 ? 1 : 0);
 }, {passive:true});
 deck.addEventListener('click', event => {
  if (!suppressClick || !event.detail) return;
  suppressClick = false;
  event.preventDefault();
  event.stopImmediatePropagation();
 }, true);
}

function handleKeyboard(view, event) {
 if (event.key === 'Escape' && (!view.scrim.hidden || view.selecting || view.query.value)) {
  event.preventDefault();
  event.stopPropagation();
  if (!view.scrim.hidden) dismissMenu(view);
  else if (view.selecting) finishSelection(view);
  else { view.query.value = ''; filterTabs(view); }
 }
 if (event.key !== 'Tab') return;
 const region = view.scrim.hidden ? view.shell : view.menu;
 const nodes = [...region.querySelectorAll('button, input')].filter(node => !node.disabled && node.tabIndex >= 0 && node.getClientRects().length);
 const first = nodes[0], last = nodes[nodes.length - 1];
 if (!first) return;
 const active = document.activeElement;
 if ((event.shiftKey && active === first) || (!event.shiftKey && active === last) || !nodes.includes(active)) {
  event.preventDefault();
  (event.shiftKey ? last : first).focus();
 }
}

function refreshPreviews(view) {
 const request = ++view.request;
 const candidates = new Map(view.tabs.filter(tab => !tab.privatePreview && tab.url).map(tab => [tab.id, tab]));
 if (!candidates.size || !view.options.loadPreviews) return;
 view.options.loadPreviews().then(({previews}) => {
  if (!view.shell.isConnected || view.request !== request) return;
  for (const [id, captured] of candidates) {
   const entry = view.cards.get(id);
   const source = previews?.[id];
   if (!entry || !source || entry.tab.privatePreview || entry.tab.url !== captured.url
    || entry.tab.document !== captured.document || source === entry.src || source === entry.pending) continue;
   const image = new Image();
   image.className = 'tab-shot';
   image.alt = '';
   image.draggable = false;
   entry.pending = source;
   image.addEventListener('load', () => {
    if (!view.shell.isConnected || view.cards.get(id) !== entry || entry.pending !== source) return;
    entry.preview.replaceChildren(image);
    entry.src = source;
    entry.pending = null;
   });
   image.addEventListener('error', () => { if (entry.pending === source) entry.pending = null; });
   image.src = source;
  }
 }).catch(() => {});
}

export function renderTabsOverview(root, options) {
 let view = overviews.get(root);
 const initial = !view || view.shell.parentElement !== root;
 if (initial) {
  view = createOverview(root, options);
  view.group = Number(options.tabs.some(tab => tab.id === options.activeTabId && tab.privateBrowsing === true));
  overviews.set(root, view);
 }
 view.options = options;
 const devices = new Map((options.profiles || []).map(({id, name}) => [id, name]));
 if (options.deviceName && !devices.has('actual-device')) devices.set('actual-device', options.deviceName);
 // Ignore unrelated navigation and playback state while the overview is open.
 const signature = JSON.stringify([options.language, options.activeTabId, options.previewVersion, [...devices],
  options.tabs.map(tab => [tab.id, tab.url, tab.previewDocument, tab.title, tab.siteName, tab.iconUrl,
   tab.privateBrowsing === true, tab.privateDesktop === true, tab.profileId])]);
 if (view.signature === signature) return;
 view.signature = signature;
 view.tabs = options.tabs.map(tab => tabDetails(tab, view, devices));
 view.regularCount = view.tabs.filter(tab => tab.group === 0).length;
 const search = label(view, 'Поиск по вкладкам');
 view.query.placeholder = search;
 labeled(view.query, search);
 labeled(view.clear, label(view, 'Очистить поиск'));
 labeled(view.actions, label(view, 'Действия с вкладками'));
 labeled(view.groups, label(view, 'Группы вкладок'));
 labeled(view.add, label(view, 'Новая вкладка'));
 labeled(view.home, label(view, 'Домой'));
 setText(view.cancel, label(view, 'Отмена'));
 updateLayout(view);
 updateGroup(view);
 if (view.group === 0) refreshPreviews(view);
 if (initial) view.shell.focus({preventScroll:true});
}

export function showTabsHistory(root) {
 const view = overviews.get(root);
 if (!view?.options.loadHistory || !view.shell.isConnected) return;
 switchGroup(view, 0);
 showHistory(view);
}
