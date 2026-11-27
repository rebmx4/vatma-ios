import {APPEARANCE_KEY,ICON_CHOICES,WALLPAPERS,wallpaperForTheme,normalizeAppearance,parseAppearance,resolveTheme,appIconArtwork} from './appearance.js';
import { isFolder, flattenApps, findEntry, dropEntry, removeEntry, arrangeEntries, arrangeDock, shiftEntriesToOppositeEdge, collapseSingletonFolders, freezeSlots, placeEntry, placeDockEntry } from './workspace-model.js';
import { createVault, openVault, sealVault, pinVaultSecret, randomVaultSecret, createVaultWithSecret, openVaultWithSecret } from './vault.js';
import {renderTabsOverview,showTabsHistory} from './tabs-view.js';
import {observeDesktopViewport} from './desktop-viewport.js';
import {selectAddressOnFirstTap} from './address-selection.js';
import {addressSuggestions, installAddressSuggestions} from './address-suggestions.js';
import {previewCookieRequest} from './assets/cookie-rpc.js';
import {previewMediaRequest} from './assets/media-rpc.js';
import {renderMediaPlayer} from './assets/media-ui.js';
import {renderCookieBrowser} from './assets/cookies-ui.js';
import {createLocalization,LANGUAGE_NAMES} from './assets/i18n.js';
import {renderLegalInfo} from './assets/legal-ui.js';
import {createWebsiteIconLoader} from './assets/site-icons.js';
import {SHORTCUT_ICON_CHOICES,normalizeShortcutIconStyle,shortcutIconArtwork} from './assets/shortcut-artwork.js';
import {messageProvider,messagesEnabled,enabledMessageProviders,shortcutMessageCount,badgeLabel} from './assets/message-badges.js';
const localization=createLocalization();
document.body.dataset.runtime=window.webkit?.messageHandlers?.atma?'ios':'preview';
const usesTranslatedShortcutLabel=app=>app.type==='system'||!app.custom&&DEFAULT_APPS.some(entry=>entry.id===app.id&&entry.name===app.name&&entry.url===app.url);
const appLabel=app=>usesTranslatedShortcutLabel(app)?localization.t(app.name):app.name;
const query = new URLSearchParams(location.search);
const context = query.get('context');
const token = query.get('token');
const $ = id => document.getElementById(id);
const escape = text => String(text).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const interfaceLanguageOptions='<option value="auto">Язык устройства</option>'+Object.entries(LANGUAGE_NAMES)
  .map(([code,name])=>`<option value="${code}" data-no-translate>${escape(name)}</option>`).join('');
function bindInterfaceLanguage(select) {
  select.value=localization.preference;
  select.addEventListener('change',()=>{
    localization.set(select.value);
    renderApps();
    syncPageTranslationLanguage();
  });
}
const paths = {
  search: '<circle cx="10.7" cy="10.7" r="6.7"/><path d="m16 16 4.8 4.8"/>',
  translate: '<path d="M2 6h11M7.5 3v3m3.5 0c-1 5-4 8-9 10m2-7c1 3 3 5 6 6m3 6 4.5-10L22 21m-7.5-3h6"/>',
  left: '<path d="m14.5 5-7 7 7 7"/>', right: '<path d="m9.5 5 7 7-7 7"/>',
  up: '<path d="m7 14 5-5 5 5"/>', down: '<path d="m7 10 5 5 5-5"/>',
  home: '<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
  arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<circle cx="12" cy="12" r="12" fill="#e3e7e9" stroke="none"/><path d="M6 12h12"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  edit: '<path d="m14 5 5 5M4 20l1.4-5.4L16 4a2.8 2.8 0 0 1 4 4L9.4 18.6 4 20Z"/>',
  phone: '<rect x="6.5" y="2" width="11" height="20" rx="2.5"/><path d="M10 5h4m-3 14h2"/>',
  computer: '<rect x="3" y="3" width="18" height="13" rx="2"/><path d="M8 21h8m-4-5v5"/>',
  tablet: '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M11 19h2"/>',
  check: '<path d="m5 12 4.5 4.5L19 7"/>',
  share: '<path d="M12 15V2m-4 4 4-4 4 4M8 9H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2h-2"/>',
  refresh: '<path d="M20 7v5h-5m5-1a8 8 0 1 0-2.3 7"/>',
  dots: '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c-5 5-5 13 0 18m0-18c5 5 5 13 0 18"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.4"/>',
  play: '<rect x="2" y="4" width="20" height="16" rx="3"/><path d="m10 9 5 3-5 3Z" fill="currentColor"/>',
  incognito: '<path d="M2 10h20M5.5 10l2.1-6h8.8l2.1 6"/><circle cx="7.4" cy="16.4" r="3.4"/><circle cx="16.6" cy="16.4" r="3.4"/><path d="M10.8 16h2.4"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.phone}</svg>`;
$('lock-private').innerHTML=icon('lock');
$('share-page').innerHTML=icon('share');
$('show-original').innerHTML=icon('translate');
$('incognito-mark').innerHTML=icon('incognito');
$('go-home').innerHTML=`<span class="home-glyph">${icon('home')}</span>`;
for (const [id, name] of Object.entries({ 'edit-apps': 'edit', 'search-symbol': 'search', 'address-go': 'arrow', 'go-back': 'left', 'go-forward': 'right', 'refresh': 'refresh', 'tabs-button': 'plus', 'new-tab-button': 'plus', 'settings': 'dots', 'sheet-close': 'close' })) $(id).innerHTML = icon(name);

const DEFAULT_APPS = [
  { id: 'vk', name: 'ВКонтакте', url: 'https://vk.com/', color: '#087fff' },
  { id: 'dzen', name: 'Дзен', url: 'https://dzen.ru/', color: '#1c1c1c' },
  { id: 'avito', name: 'Авито', url: 'https://www.avito.ru/', color: '#fff' },
  { id: 'youtube', name: 'YouTube', url: 'https://www.youtube.com/', color: '#fff' },
  { id: 'rutube', name: 'RUTUBE', url: 'https://rutube.ru/', color: '#111729' },
  { id: 'vtb', name: 'ВТБ', url: 'https://online.vtb.ru/', color: '#0b48b2' },
  { id: 'tbank', name: 'Т-Банк', url: 'https://www.tbank.ru/', color: '#ffdf00' },
  { id: 'mail', name: 'Почта Mail', url: 'https://e.mail.ru/', color: '#087cf1' },
];
const SYSTEM_APPS=[{id:'atma-incognito',type:'system',action:'incognito',name:'Инкогнито',color:'#fff'},{id:'atma-settings',type:'system',action:'settings',name:'Настройки',color:'#c4c7ce'},{id:'atma-cookies',type:'system',action:'cookies',name:'Куки',color:'#fff'},{id:'atma-private-desktop',type:'system',action:'private-desktop',name:'Приватный стол',color:'#183747'}];
const RETIRED_DEFAULTS=new Map([
  ['ozonbank',['Ozon Банк','https://finance.ozon.ru/']],
  ['ozon',['Ozon','https://www.ozon.ru/']],
  ['wb',['Wildberries','https://www.wildberries.ru/']],
  ['wiki',['Википедия','https://ru.wikipedia.org/']],
]);
const RETIRED_SYSTEM_IDS=new Set(['atma-files','atma-home']);
function withoutRetiredDefaults(entries){
  return entries.flatMap(entry=>{
    if(RETIRED_SYSTEM_IDS.has(entry.id)&&entry.type==='system')return [];
    const original=RETIRED_DEFAULTS.get(entry.id);
    if(original&&entry.name===original[0]&&entry.url===original[1]&&!entry.iconStyle)return [];
    if(!isFolder(entry))return [entry];
    const children=withoutRetiredDefaults(entry.children||[]);
    return children.length?[{...entry,children}]:[];
  });
}
let apps;
try { apps = JSON.parse(localStorage.getItem('atma-preview-apps')); } catch {}
const desktopLayoutKey='atma-preview-desktop-layout';
const usesLegacyDesktopRows=Array.isArray(apps)&&localStorage.getItem(desktopLayoutKey)!=='five-rows';
if(!Array.isArray(apps)){
  const dockIds=['vk','dzen','youtube','mail'];
  apps=DEFAULT_APPS.map(app=>dockIds.includes(app.id)?{...app,dockSlot:dockIds.indexOf(app.id)}:{...app});
  try{localStorage.setItem(desktopLayoutKey,'five-rows');}catch{}
}
apps=collapseSingletonFolders(withoutRetiredDefaults(apps));
for(const system of SYSTEM_APPS)if(!flattenApps(apps).some(app=>app.id===system.id)){
  apps=freezeSlots(freezeSlots(apps,4),6);apps.push({...system});
}
try{localStorage.setItem('atma-preview-apps',JSON.stringify(apps));}catch{}
let state, profiles = [], panel = null, editing = false, busy = false;
let messageCounts={},messagePollBusy=false,messagePollTimer;
let stateActionVersion=0;
let shortcutLaunchVersion=0;
let appEditorVersion=0;
const DESKTOP_HOLD_MS = 750; // iPhone SpringBoard 26.4.1: 0.6875s failed, 0.75s entered editing.
let openFolderId = null, gesture = null, suppressClickUntil = 0;
let desktopPage=0, publicPages=Math.max(2,Number(localStorage.getItem('atma-preview-page-count'))||2);
const ALIGNMENT_SNAPSHOT_KEY='atma-preview-alignment-origin';
let alignmentSnapshot;try{alignmentSnapshot=JSON.parse(localStorage.getItem(ALIGNMENT_SNAPSHOT_KEY));}catch{}
let privatePageStart=publicPages, privatePageCount=1, folderScope='public', editorScope='public';
let vaultRecord;try{vaultRecord=JSON.parse(localStorage.getItem('atma-preview-vault'))}catch{}
let vaultKey=null, vaultApps=[], vaultWrite=Promise.resolve(), vaultIdleTimer, pageLockTimer;
let pinDigits='',firstPin=null,pinBusy=false,pinEpoch=0,pendingVaultMove=null,pendingVaultAdd=false,autoLockAfter=0;
let pinSetup='choice',biometricStatus={available:false,kind:'none'},enableBiometryAfterPIN=false;
let filePreviewUrl=null;
let disposeMediaPanel;
const desktopSurfaceKey=`atma-preview-desktop-tab:${context}`;
let desktopTabId=null;try{desktopTabId=sessionStorage.getItem(desktopSurfaceKey);}catch{}
const poolFor=scope=>scope==='private'?vaultApps:apps;
const currentScope=()=>$('apps').children[desktopPage]?.dataset.scope==='private'?'private':'public';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const wallpaperKey = 'atma-preview-wallpaper';
let wallpaper = localStorage.getItem(wallpaperKey);
if (wallpaper !== 'custom' && !WALLPAPERS.some(choice => choice.id === wallpaper)) wallpaper = 'auto';
let customWallpaperURL = '';
let searchEngine = localStorage.getItem('atma-preview-search') || 'google';

const brandLogoSource=document.querySelector('.wordmark img').getAttribute('src');
let appearance=parseAppearance(localStorage.getItem(APPEARANCE_KEY));
const systemColorScheme=matchMedia('(prefers-color-scheme: dark)');
let nativeThemeSent,changingIcon=false;
function applyAppearance() {
  const resolved=resolveTheme(appearance.theme,systemColorScheme.matches);
  document.body.dataset.theme=resolved;document.documentElement.style.colorScheme=resolved;
  document.documentElement.style.setProperty('--text-scale',String(appearance.textSize/100));
  applyWallpaper();
  if (panel === 'wallpaper') renderWallpapers();
  renderToolbarMessageBadge();
  if(window.webkit?.messageHandlers?.atma&&nativeThemeSent!==appearance.theme){nativeThemeSent=appearance.theme;api('appearance',{theme:appearance.theme}).catch(error=>{nativeThemeSent=undefined;reportError(error.message);});}
}
async function changeAppearance(patch) {
  let next=normalizeAppearance({...appearance,...patch});
  if(window.webkit?.messageHandlers?.atma&&patch.icon){
    if(changingIcon)return;changingIcon=true;for(const button of document.querySelectorAll('[data-icon-choice]'))button.disabled=true;
    try{await api('app-icon',{icon:next.icon});}catch(error){reportError(error.message);if(panel==='app-icon')renderAppIconPicker();return;}finally{changingIcon=false;for(const button of document.querySelectorAll('[data-icon-choice]'))button.disabled=false;}
  }
  const previous=appearance;next=normalizeAppearance({...appearance,...patch});
  try{localStorage.setItem(APPEARANCE_KEY,JSON.stringify(next));}catch{reportError('Не удалось сохранить оформление');return;}
  appearance=next;applyAppearance();
  if(previous.icon!==next.icon){renderApps();if(panel==='folder')renderFolder();}
  updateAppearanceControls();if(panel==='app-icon')renderAppIconPicker();
}
function updateAppearanceControls() {
  const modes=['auto','light','dark'],control=$('theme-control');
  if(control){
    control.style.setProperty('--theme-index',String(modes.indexOf(appearance.theme)));
    for(const mode of modes)$(`theme-${mode}`).checked=appearance.theme===mode;
    $('theme-description').textContent=appearance.theme==='auto'?`Автоматическая · сейчас ${resolveTheme('auto',systemColorScheme.matches)==='dark'?'тёмная':'светлая'}`:appearance.theme==='dark'?'Тёмная тема':'Светлая тема';
    $('text-size').value=appearance.textSize;$('text-size-value').textContent=`${appearance.textSize}%`;
    document.querySelector('.appearance-current-icon').innerHTML=appIconArtwork(appearance.icon,brandLogoSource);
  }
}
systemColorScheme.addEventListener('change',()=>{if(appearance.theme==='auto'){applyAppearance();updateAppearanceControls();}});
function appearanceBack(label,target) {
  const button=document.createElement('button');button.className='appearance-back';button.id=target==='appearance'?'back-appearance':'back-settings';
  button.innerHTML=`${icon('left')}<span>${label}</span>`;button.addEventListener('click',()=>setPanel(target));return button;
}
function renderAppearance() {
  const root=$('sheet-content');root.replaceChildren(appearanceBack('Настройки','settings'));
  const heading=document.createElement('h2');heading.className='appearance-title';heading.textContent='Тема интерфейса';root.append(heading);
  const wallpaperCard=document.createElement('div');wallpaperCard.className='setting-card';
  const wallpaperButton=settingButton('Обои','image',()=>setPanel('wallpaper'));wallpaperButton.id='appearance-wallpaper';wallpaperCard.append(wallpaperButton);root.append(wallpaperCard);
  const theme=document.createElement('section');theme.className='appearance-section';
  theme.innerHTML=`<h2 class="appearance-title">Тема</h2><div class="theme-control" id="theme-control"><span class="theme-thumb" aria-hidden="true"></span>${[['auto','Авто'],['light','Светлая'],['dark','Тёмная']].map(([value,label])=>`<label><input type="radio" name="atma-interface-theme" id="theme-${value}" value="${value}" aria-label="${value==='auto'?'Автоматическая тема':label+' тема'}"><span>${label}</span></label>`).join('')}</div><p class="theme-description" id="theme-description"></p>`;
  root.append(theme);for(const input of theme.querySelectorAll('input'))input.addEventListener('change',()=>changeAppearance({theme:input.value}));
  const languageRow=document.createElement('label');
  languageRow.className='setting-row';
  languageRow.innerHTML=`<span>Язык интерфейса</span><select aria-label="Язык интерфейса">${interfaceLanguageOptions}</select>`;
  bindInterfaceLanguage(languageRow.querySelector('select'));
  root.append(languageRow);
  const text=document.createElement('section');text.className='appearance-section';
  text.innerHTML='<div class="text-size-card"><label for="text-size" class="text-size-heading"><span>Размер текста</span><output id="text-size-value" for="text-size"></output></label><div class="text-size-slider"><span class="small-a" aria-hidden="true">А</span><input id="text-size" type="range" min="85" max="130" step="5" value="100" aria-label="Размер текста интерфейса"><span class="large-a" aria-hidden="true">А</span></div></div>';
  root.append(text);$('text-size').addEventListener('input',event=>changeAppearance({textSize:Number(event.target.value)}));
  const icons=document.createElement('div');icons.className='setting-card';
  const iconButton=settingButton('Иконка приложения','image',()=>setPanel('app-icon'));iconButton.id='appearance-icon';
  const preview=document.createElement('span');preview.className='appearance-current-icon';iconButton.insertBefore(preview,iconButton.lastElementChild);icons.append(iconButton);root.append(icons);
  updateAppearanceControls();
}
function renderAppIconPicker() {
  const root=$('sheet-content');root.replaceChildren(appearanceBack('Оформление','appearance'));
  const list=document.createElement('div');list.className='icon-option-list';
  for(const choice of ICON_CHOICES){
    const button=document.createElement('button');button.className='icon-option';button.dataset.iconChoice=choice.id;
    button.setAttribute('aria-pressed',String(appearance.icon===choice.id));button.setAttribute('aria-label',`Иконка ATMA: ${choice.label}`);
    button.innerHTML=`<span class="icon-option-art">${appIconArtwork(choice.id,brandLogoSource)}</span><span>${choice.label}</span>${appearance.icon===choice.id?`<span class="icon-option-tick">${icon('check')}</span>`:''}`;
    button.addEventListener('click',()=>changeAppearance({icon:choice.id}));list.append(button);
  }
  const done=document.createElement('button');done.className='primary-button';done.textContent='Готово';done.addEventListener('click',()=>setPanel(null));root.append(list,done);
}

function brand(app, useStoredIcon = false) {
  if(app.id==='atma-private-desktop')return '<span class="private-desktop-artwork" aria-hidden="true"><span class="private-desktop-keyhole"></span></span>';
  if(app.id==='atma-home')return appIconArtwork(appearance.icon,brandLogoSource);
  if(app.id==='atma-incognito')return `<span class="incognito-artwork" aria-hidden="true">
    <span class="incognito-glyph">
      <span class="incognito-crown"></span>
      <span class="incognito-brim"></span>
      <span class="incognito-bridge"></span>
      <span class="incognito-lens"></span>
      <span class="incognito-lens"></span>
    </span>
  </span>`;
  if(app.type!=='system'){
    const customArtwork=shortcutIconArtwork(app.iconStyle);
    if(customArtwork)return customArtwork;
    if(useStoredIcon&&/^data:image\/png;base64,/i.test(app.iconUrl||''))
      return `<img src="${escape(app.iconUrl)}" alt="" draggable="false">`;
  }
  if(!app.custom&&!app.iconUrl&&app.url&&DEFAULT_APPS.some(entry=>entry.id===app.id&&entry.url===app.url)){
    return `<img class="shortcut-brand-icon" src="/assets/desktop-icons/${app.id}.png" alt="" draggable="false">`;
  }
  const content = {
    'atma-settings': `<g fill="#555c68">${Array.from({length:12},(_,i)=>`<rect x="28" y="8" width="6" height="11" rx="1.2" transform="rotate(${i*30} 31 31)"/>`).join('')}</g><circle cx="31" cy="31" r="19" fill="#555c68"/><circle cx="31" cy="31" r="15.2" fill="#d9dce2"/><circle cx="31" cy="31" r="11.4" fill="#626a77"/><circle cx="31" cy="31" r="6.7" fill="#c6cbd3"/><circle cx="31" cy="31" r="23.5" fill="none" stroke="#eceef1" stroke-width="1.6"/>`,
    'atma-files':'<path d="M8 20a4 4 0 0 1 4-4h12l5 5h21a4 4 0 0 1 4 4v23a4 4 0 0 1-4 4H12a4 4 0 0 1-4-4Z" fill="#79c3ff"/><rect x="8" y="24" width="46" height="28" rx="4" fill="#0787f8"/><path d="M12 24h38" stroke="#409fff" stroke-width="1.5"/>',
    'atma-cookies':'<circle cx="31" cy="31" r="23" fill="#c58c53"/><path d="M47 12a10 10 0 0 0 5 14 23 23 0 0 1-19 28A23 23 0 1 1 47 12Z" fill="#dba66c"/><g fill="#765039"><circle cx="20" cy="20" r="3"/><circle cx="35" cy="20" r="2.5"/><circle cx="26" cy="35" r="3"/><circle cx="40" cy="39" r="2.5"/><circle cx="17" cy="43" r="2"/></g>',
    vk: '<path fill="white" d="M10 20h7c1 10 5 14 7 14V20h7v8c3 0 8-4 9-8h7c-2 7-8 10-9 11 4 1 9 5 11 11h-8c-2-5-6-8-10-8v8h-4C16 42 10 35 10 20Z"/>',
    dzen: '<path fill="white" d="M31 10c1 16 6 21 21 22-15 1-20 6-21 22-1-16-6-21-21-22 15-1 20-6 21-22Z"/>',
    youtube: '<rect x="9" y="17" width="44" height="29" rx="9" fill="#ff0033"/><path d="m27 24 13 8-13 8Z" fill="white"/>',
    rutube: '<circle cx="46" cy="15" r="5" fill="#f64757"/><path fill="white" d="M15 18h18c12 0 13 18 3 21l10 12H35L25 38h-2v13h-8zm8 7v7h9c5 0 5-7 0-7z"/>',
    mail: '<text x="31" y="43" text-anchor="middle" fill="#ffce32" font-size="42" font-family="Arial" font-weight="600">@</text>',
    avito: '<circle cx="19" cy="20" r="9" fill="#00aaff"/><circle cx="42" cy="20" r="12" fill="#a169f7"/><circle cx="18" cy="43" r="7" fill="#ff4064"/><circle cx="41" cy="45" r="10" fill="#97cf25"/>',
    vtb: '<path fill="white" d="M13 18h36l-3 6H10zm-4 9h36l-3 6H6zm-4 9h36l-3 6H2z" transform="translate(5 -1)"/>',
    tbank: '<path fill="#263645" d="M13 13h36v22c0 10-10 15-18 19-8-4-18-9-18-19z"/><path fill="#ffdf00" d="M20 21h22v7h-7v16h-8V28h-7z"/>',
    ozonbank: '<path fill="white" d="M13 28 31 16l18 12v4H13zm4 8h5v11h-5zm12 0h5v11h-5zm12 0h5v11h-5zM12 49h38v5H12z"/>',
    ozon: '<text x="31" y="39" text-anchor="middle" fill="white" font-size="19" font-family="Arial" font-weight="800" letter-spacing="-1">OZON</text>',
    wb: '<text x="31" y="40" text-anchor="middle" fill="white" font-size="26" font-family="Arial" font-weight="650" letter-spacing="-2">WB</text>',
    wiki: '<text x="31" y="46" text-anchor="middle" fill="#111" font-size="46" font-family="Georgia">W</text>',
  }[app.id] || `<text x="31" y="43" text-anchor="middle" fill="white" font-size="34" font-family="Arial">${escape(app.name.slice(0,1).toUpperCase())}</text>`;
  if(app.id==='atma-cookies')return `<svg class="desktop-artwork-mark" viewBox="0 0 62 62" aria-hidden="true">${content}</svg>`;
  return `<svg viewBox="0 0 62 62" aria-hidden="true"><rect width="62" height="62" rx="15" fill="${/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(app.color || '') ? app.color : '#337b96'}"/>${content}</svg>`;
}

async function api(action, body) {
  if(window.webkit?.messageHandlers?.atma)return window.webkit.messageHandlers.atma.postMessage({action,body:body||{}});
  if(action==='vault/biometry/status')return {available:false,kind:'none'};
  if(action.startsWith('vault/biometry/'))throw new Error('Биометрия доступна только на iPhone или iPad');
  if(action==='site-resource'){
    const response=await fetch(body.url,{credentials:'omit',referrerPolicy:'no-referrer',signal:AbortSignal.timeout(8000)});
    if(!response.ok)throw new Error('Значок сайта недоступен');
    if(body.kind!=='image')return {url:response.url,text:await response.text()};
    const blob=await response.blob();if(blob.size>1048576)throw new Error('Значок слишком большой');
    const dataUrl=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(blob);});
    return {url:response.url,dataUrl};
  }

  if(action==='cookies'||action==='cookies/delete')return previewCookieRequest(action,body);
  if(action==='site-data'||action==='site-data/delete')return {records:[],preview:true};
  if(action.startsWith('media/'))return previewMediaRequest(action,body);
  const response = await fetch(`/api/${action}${body ? '' : `?context=${encodeURIComponent(context)}`}`, {
    method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', 'X-Atma-Token': token },
    body: body ? JSON.stringify({ ...body, context }) : undefined,
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Не удалось выполнить действие');
  return result;
}
function reportError(message) {
  const status = $(panel ? 'sheet-error' : 'action-error');
  status.textContent = localization.t(message);
  status.hidden = !message;
}
async function action(name, data = {}) {
  const version=++stateActionVersion;
  try { const result = await api(name, data); if(version===stateActionVersion)consume(result); return result; }
  catch (error) { reportError(error.message); throw error; }
}
const shortcutIcons=createWebsiteIconLoader((kind,url)=>api('site-resource',{kind,url}));
window.addEventListener('online',()=>{shortcutIcons.retryFailed();renderApps();});
function resolveShortcutIcon(site){return shortcutIcons.resolve(site);}
function paintShortcutIcon(target,app,scope){
  if((!app.custom&&!app.iconStyle&&!app.iconUrl)||normalizeShortcutIconStyle(app.iconStyle)!=='site')return;
  const source=app.iconUrl||'',url=app.url,id=app.id,key=vaultKey;
  const paint=source=>{if(!source)return;const image=new Image();image.alt='';image.draggable=false;image.referrerPolicy='no-referrer';image.addEventListener('load',()=>target.replaceChildren(image));image.src=source;};
  if(/^data:image\/png;base64,/i.test(source)){paint(source);return;}
  resolveShortcutIcon(app).then(iconUrl=>{
    if(!iconUrl||scope==='private'&&(!vaultKey||key!==vaultKey))return;
    const current=findEntry(poolFor(scope),id)?.entry;
    if(current?.url!==url||normalizeShortcutIconStyle(current.iconStyle)!=='site')return;
    paint(iconUrl);
    if(current.iconUrl!==iconUrl){current.iconUrl=iconUrl;saveApps(scope,{render:false,layoutChanged:false}).catch(()=>{});}
  });
}
let pinSiteBusy=false,pinSiteArtKey='',pendingVaultSite=null;
function normalizedSiteUrl(value) {
  try{const url=new URL(value);return /^https?:$/.test(url.protocol)?url.href:'';}catch{return '';}
}
function shortcutDestination() {
  if(state?.mode==='browse')return state.privateBrowsing===true||state.privateDesktop===true?'private':'public';
  return currentScope();
}
function savedSite(url,scope) {return flattenApps(poolFor(scope)).some(app=>normalizedSiteUrl(app.url)===url);}
function updateQuickAdd() {
  const button=$('pin-site'),url=normalizedSiteUrl(state?.url);
  button.hidden=state?.mode!=='browse'||!url;
  if(button.hidden){pinSiteArtKey='';return;}
  const name=state.siteName||state.title||new URL(url).hostname;
  const scope=shortcutDestination(),saved=!pinSiteBusy&&savedSite(url,scope);
  button.dataset.saved=String(saved);button.disabled=pinSiteBusy||saved||Boolean(state.loading);
  const label=scope==='private'?(saved?'Уже на приватном столе':'Добавить на приватный стол')
    :saved?`${name} уже на рабочем столе`:`Добавить ${name} на рабочий стол`;
  button.setAttribute('aria-label',label);
  button.title=button.getAttribute('aria-label');$('pin-site-badge').innerHTML=icon(saved?'check':'plus');
  const key=JSON.stringify([state.activeTabId,url,scope,Boolean(state.loading)]);
  if(key===pinSiteArtKey)return;pinSiteArtKey=key;
  const art=$('pin-site-art');art.innerHTML=icon('globe');delete art.dataset.logo;
  if(scope==='private'||state.loading)return;
  void paintQuickAddLogo(art,key,{url,iconUrl:state.iconUrl||''});
}
async function paintQuickAddLogo(art,key,site) {
  const metadata=await api('current-site').catch(()=>null);
  if(pinSiteArtKey!==key)return;
  const iconUrl=await resolveShortcutIcon(normalizedSiteUrl(metadata?.url)===site.url?metadata:site);
  if(!iconUrl||pinSiteArtKey!==key)return;
  const image=new Image();image.alt='';image.draggable=false;image.referrerPolicy='no-referrer';
  image.addEventListener('load',()=>{
    if(pinSiteArtKey!==key)return;
    art.dataset.logo='true';
    art.replaceChildren(image);
  });
  image.src=iconUrl;
}
async function saveCurrentSite(target) {
  if(pinSiteBusy||state?.mode!=='browse'||state.loading)return;
  target??={tabId:state.activeTabId,url:normalizedSiteUrl(state.url),scope:shortcutDestination()};
  const {tabId,url,scope}=target;
  const isCurrent=()=>state?.mode==='browse'&&!state.loading&&state.activeTabId===tabId&&normalizedSiteUrl(state.url)===url&&shortcutDestination()===scope;
  if(!url||!isCurrent())return;
  if(scope==='private'&&!vaultKey){
    pendingVaultSite=target;
    return requestVault();
  }
  const key=vaultKey,canSave=()=>isCurrent()&&(scope==='public'||vaultKey===key);
  pinSiteBusy=true;updateQuickAdd();
  try{
    const site=await api('current-site');
    if(!canSave()||normalizedSiteUrl(site.url)!==url||savedSite(url,scope))return;
    const iconUrl=await resolveShortcutIcon(site);
    if(!canSave()||savedSite(url,scope))return;
    const entry={id:`custom-${crypto.randomUUID()}`,name:site.siteName||site.title||new URL(url).hostname,url,iconUrl,color:'#337b96',custom:true,messageNotifications:false};
    const previous=poolFor(scope),items=freezeSlots(freezeSlots([...previous,entry],4),6);
    try{await updatePool(scope,items);}catch(error){
      if(poolFor(scope)===items)await updatePool(scope,previous).catch(()=>{});
      throw error;
    }
  }catch(error){if(canSave())reportError(error.message);}
  finally{pinSiteBusy=false;updateQuickAdd();}
}
function updateTabSurface(){
  const tab=state?.tabs?.find(item=>item.id===state.activeTabId);
  const blank=state?.mode==='home'&&tab&&!tab.url&&desktopTabId!==tab.id;
  const privateStart=state?.mode==='home'&&state.privateBrowsing===true&&tab&&!tab.url;
  document.body.dataset.surface=privateStart?'incognito':blank?'blank':state?.mode==='browse'?'site':'home';
  $('address').placeholder='Поиск или адрес сайта';
}
function chooseDesktopSurface(tabId){
  desktopTabId=tabId||null;
  try{if(desktopTabId)sessionStorage.setItem(desktopSurfaceKey,desktopTabId);else sessionStorage.removeItem(desktopSurfaceKey);}catch{}
  updateTabSurface();
}
function consume(next) {
  if (!next?.profileId) return;
  // Commands, polling and native push events can finish out of order.
  if(Number.isSafeInteger(state?.sequence)&&(!Number.isSafeInteger(next.sequence)||next.sequence<state.sequence))return;
  const previousMode=state?.mode,previousLoading=state?.loading,changedTab=state?.activeTabId!==next.activeTabId;
  const previousTranslation=state?.translationStatus;
  const translationChanged=previousMode!==next.mode||previousTranslation!==next.translationStatus||state?.translationOffered!==next.translationOffered;
  const geometryChanged=state?.width!==next.width||state?.height!==next.height||state?.footerHeight!==next.footerHeight;
  state = next;
  const languageChanged=Array.isArray(next.preferredLanguages)&&localization.updateSystem(next.preferredLanguages);
  if(languageChanged)syncPageTranslationLanguage();
  if(Array.isArray(next.profiles))profiles=next.profiles;
  if(previousMode===undefined&&next.mode==='home')chooseDesktopSurface(next.activeTabId);
  document.body.dataset.mode = next.mode;
  document.body.dataset.webApp=String(Boolean(next.webApp));
  document.body.dataset.privateBrowsing=String(next.privateBrowsing===true);
  $('search-symbol').innerHTML=icon(next.privateBrowsing===true?'incognito':'search');
  const privateDevice=profiles.find(profile=>profile.id===next.profileId);
  $('incognito-device').innerHTML=`${icon(privateDevice?.family==='Компьютер'?'computer':privateDevice?.family==='iPad'?'tablet':'phone')}<span>${escape(privateDevice?.name||next.deviceName)}</span>${icon('down')}`;
  document.body.dataset.controlsCollapsed=String(Boolean(next.controlsCollapsed));
  if(Number.isFinite(next.footerHeight))document.documentElement.style.setProperty('--bar-height',`min(100vh, ${next.footerHeight}px)`);
  const safeBottom=Number.isFinite(next.safeAreaBottom)?Math.max(0,next.safeAreaBottom):0;
  document.documentElement.style.setProperty('--native-safe-area-bottom',`${safeBottom}px`);
  updateTabSurface();
  $('go-back').disabled = next.mode !== 'browse' || next.canGoBack !== true;
  $('go-forward').disabled = next.mode !== 'browse' || next.canGoForward !== true;
  $('go-forward').hidden = next.canGoForward !== true;
  $('share-page').hidden = next.canGoForward === true;
  $('share-page').disabled = next.mode !== 'browse' || !next.url;
  $('refresh').disabled = next.mode !== 'browse';
  if(translationChanged){
    const translateButton=$('show-original');
    const translated=next.translationStatus==='translated',translating=next.translationStatus==='translating';
    translateButton.hidden=next.mode!=='browse'||!(next.translationOffered||translated||translating);
    translateButton.disabled=translating;
    const translationLabel=translated?'Показать оригинал':translating?'Перевод страницы…':'Перевести страницу';
    translateButton.setAttribute('aria-label',translationLabel);
    translateButton.setAttribute('title',translationLabel);
    translateButton.setAttribute('aria-pressed',String(translated));
  }
  if (!changedTab && previousTranslation === 'translating') {
    if (next.translationStatus === 'languages-not-installed') {
      reportError(localization.t('Дождитесь загрузки языков для перевода и нажмите «Перевести» ещё раз.'));
    } else if (next.translationStatus === 'unavailable') {
      reportError(localization.t('Перевод страницы сейчас недоступен.'));
    }
  }
  if(changedTab){
    $('address').value=next.mode==='browse'?(next.url||''):'';
    document.dispatchEvent?.(new Event('atma-address-context-change'));
  }
  else if (document.activeElement !== $('address') && next.mode === 'browse') $('address').value = next.url === `${location.origin}/probe` ? '' : (next.url || '');
  if (panel !== next.panel) {
    panel = next.panel;
    renderPanel();
  }
  if(previousMode!==next.mode||geometryChanged||languageChanged)renderApps();
  const count=next.tabs?.length||0,button=$('tabs-button');
  if(button.dataset.count!==String(count)){button.dataset.count=String(count);button.innerHTML=count?`<span class="tab-counter">${count}</span>`:icon('plus');button.setAttribute('aria-label',count?`Открытые вкладки: ${count}`:'Новая вкладка');}
  if(panel==='tabs')renderTabs();
  updateQuickAdd();
  if(next.capabilities?.messageBadges&&(changedTab||previousMode!==next.mode||previousLoading&&!next.loading))scheduleMessageBadgePoll();
}
function scheduleMessageBadgePoll(){clearTimeout(messagePollTimer);messagePollTimer=setTimeout(pollMessageBadges,1200);}
function renderToolbarMessageBadge(){
  const button=$('go-home'),total=Object.values(messageCounts).reduce((sum,count)=>sum+count,0);
  button.querySelector('.toolbar-message-badge')?.remove();
  button.setAttribute('aria-label',total?`Рабочий стол, ${total} непрочитанных`:'Рабочий стол');
  if(total>0){const badge=document.createElement('span');badge.className='toolbar-message-badge';badge.textContent=badgeLabel(total);badge.setAttribute('aria-hidden','true');button.append(badge);}
}
async function pollMessageBadges(){
  if(messagePollBusy||document.hidden||!state?.capabilities?.messageBadges)return;
  const providers=enabledMessageProviders(apps);
  if(!providers.length){if(Object.keys(messageCounts).length){messageCounts={};renderToolbarMessageBadge();renderApps();if(panel==='folder')renderFolder();}return;}
  messagePollBusy=true;
  try{
    const response=await api('message-badges',{providers});
    if(providers.join(',')!==enabledMessageProviders(apps).join(','))return;
    const next={};
    for(const provider of providers){const count=response?.counts?.[provider];if(Number.isSafeInteger(count)&&count>=0&&count<=999)next[provider]=count;}
    const changed=JSON.stringify(messageCounts)!==JSON.stringify(next);messageCounts=next;
    if(changed){renderToolbarMessageBadge();renderApps();if(panel==='folder')renderFolder();}
  }catch{}finally{messagePollBusy=false;}
}
async function newBrowserTab(){
 setEditing(false);lockVault();desktopPage=0;
 try{await action('tabs/new');chooseDesktopSurface(null);$('address').value='';}catch{}
}
async function newIncognitoTab({sourceTabId}={}){
 setEditing(false);lockVault();
 try{
  await action('tabs/new',{privateBrowsing:true,...(sourceTabId?{sourceTabId}:{})});
  if(!state?.privateBrowsing)throw new Error('Инкогнито недоступно в этом режиме предпросмотра');
  chooseDesktopSurface(null);$('incognito-address').value='';
 }catch(error){reportError(error.message);}
}
async function selectBrowserTab(tabId){
 try{await action('tabs/select',{tabId});chooseDesktopSurface(null);if(!state.url)$('address').value='';}catch{}
}
function renderTabs(){
 const native=Boolean(window.webkit?.messageHandlers?.atma),tabs=state?.tabs||[];
 if(Number.isFinite(state?.safeAreaBottom))$('sheet').style.setProperty('--tabs-native-bottom',Math.max(0,state.safeAreaBottom)+'px');
 renderTabsOverview($('sheet-content'),{
  tabs,activeTabId:state?.activeTabId,previewVersion:state?.tabPreviewVersion,profiles,deviceName:state?.deviceName,
  icon,t:localization.t,language:localization.language,
  onSelect:selectBrowserTab,
  onClose:id=>action('tabs/close',{tabId:id}),
  onCloseMany:native?tabIds=>action('tabs/close-many',{tabIds}):null,
  onDuplicate:native?tabId=>action('tabs/duplicate',{tabId}):null,
  onNew:privateGroup=>{
   if(!privateGroup)return newBrowserTab();
   const privateTabs=tabs.filter(tab=>tab.privateBrowsing===true);
   const source=privateTabs.find(tab=>tab.id===state?.activeTabId)||privateTabs.at(-1);
   return newIncognitoTab({sourceTabId:source?.id});
  },
  onHome:()=>$('go-home').click(),
  onSettings:()=>setPanel('settings'),
  onError:reportError,
  loadPreviews:()=>api('tab-previews'),
  loadIcon:native?async url=>(await api('site-resource',{kind:'image',url})).dataUrl:null,
  loadHistory:native?()=>api('tabs/history'):null,
  onOpenHistory:async ({tabId,url})=>{
   await action('tabs/history/open',{tabId,url});
   chooseDesktopSurface(null);
  },
 });
}
async function openBrowserHistory(){
 await setPanel('tabs');
 if(panel==='tabs')showTabsHistory($('sheet-content'));
}
function saveApps(scope='public',{render=true,layoutChanged=true}={}) {
  if(scope==='private') {
    if(!vaultKey)return Promise.reject(new Error('Закрытая страница заблокирована'));
    const items=structuredClone(vaultApps),key=vaultKey,record=vaultRecord;
    vaultWrite=vaultWrite.catch(()=>{}).then(async()=>{
      const next=await sealVault(key,items,record);localStorage.setItem('atma-preview-vault',JSON.stringify(next));vaultRecord=next;
    });
    vaultWrite.catch(()=>reportError('Не удалось сохранить закрытую страницу'));
  } else {
    if(layoutChanged){alignmentSnapshot=null;localStorage.removeItem(ALIGNMENT_SNAPSHOT_KEY);}
    localStorage.setItem('atma-preview-apps', JSON.stringify(apps));
  }
  if(render){renderApps();if(panel==='folder')renderFolder();}
  updateQuickAdd();
  if(scope==='public')scheduleMessageBadgePoll();
  return scope==='private'?vaultWrite:Promise.resolve();
}
function updatePool(scope,items) { if(scope==='private')vaultApps=items;else apps=items;return saveApps(scope); }
function setEditing(value) {
  editing = value; document.body.classList.toggle('editing', value);
  $('edit-apps').hidden = !value;
  $('edit-apps').innerHTML = value ? 'Готово' : icon('edit');
  $('edit-apps').setAttribute('aria-label', value ? 'Завершить редактирование' : 'Редактировать приложения');
  renderApps(); if (panel === 'folder') renderFolder();
}
function positions(container) { return new Map([...container.querySelectorAll('.app-item:not(.dragging)')].map(item => [item.dataset.app, item.getBoundingClientRect()])); }
function animatePositions(container, previous) {
  if (reducedMotion.matches) return;
  for (const item of container.querySelectorAll('.app-item')) {
    const before = previous.get(item.dataset.app), after = item.getBoundingClientRect();
    if (before && (Math.abs(before.x-after.x) > 1 || Math.abs(before.y-after.y) > 1))
      item.animate([{ transform:`translate(${before.x-after.x}px,${before.y-after.y}px)` }, { transform:'translate(0,0)' }], { duration:260, easing:'cubic-bezier(.2,.8,.2,1)' });
  }
}
function createItem(app, parentId = null, index = 0, scope='public', quickAccess=false) {
  const item = document.createElement('div'); item.className = 'app-item'; item.dataset.app = app.id;
  item.dataset.scope=scope;
  if (parentId) item.dataset.folder = parentId;
  item.style.setProperty('--jiggle-delay', `${-(index % 7) * 67}ms`);
  item.classList.toggle('dragging', Boolean(gesture?.active && gesture.id === app.id && gesture.scope === scope));
  const tile = document.createElement('button'); tile.className = 'app-tile';
  tile.setAttribute('aria-label', `Открыть ${appLabel(app)}`);
  if (isFolder(app)) {
    item.classList.add('folder-item'); tile.classList.add('folder-tile');
    tile.innerHTML = `<span class="folder-miniatures">${app.children.slice(0,9).map(child=>`<span>${brand(child,quickAccess)}</span>`).join('')}</span>`;
    if(!quickAccess)
      for(const [index,miniature] of [...tile.querySelectorAll('.folder-miniatures > span')].entries())paintShortcutIcon(miniature,app.children[index],scope);
  } else {
    tile.innerHTML = brand(app,quickAccess);
    if(!quickAccess)paintShortcutIcon(tile,app,scope);
  }
  // Pointer taps are handled by the gesture even if the grid replaces this button.
  tile.addEventListener('click', event => {
    if (quickAccess) closeDesktopSearch();
    if (quickAccess || event.detail === 0 && Date.now() >= suppressClickUntil) activate(app,scope);
  });
  if(quickAccess)item.addEventListener('click',event=>{
    if(event.target.closest('.app-tile'))return;
    closeDesktopSearch();activate(app,scope);
  });
  else item.addEventListener('pointerdown', event => {if(event.target.closest?.('.app-remove'))return;beginGesture(event, app, parentId,scope);});
  item.addEventListener('contextmenu', event => event.preventDefault());
  tile.addEventListener('dragstart', event => event.preventDefault());
  const label = document.createElement('span'); label.className = 'app-name'; label.textContent = app.name;if(!usesTranslatedShortcutLabel(app))label.dataset.noTranslate='';
  item.append(tile, label);
  const unread=shortcutMessageCount(app,scope,messageCounts);
  if(unread>0){const badge=document.createElement('span');badge.className='message-badge';badge.textContent=badgeLabel(unread);badge.setAttribute('aria-hidden','true');item.append(badge);tile.setAttribute('aria-label',`${tile.getAttribute('aria-label')}, ${unread} непрочитанных`);}
  if (editing&&!quickAccess&&app.type!=='system') {
    const remove = document.createElement('button'); remove.className = 'app-remove'; remove.innerHTML=icon('minus');
    remove.setAttribute('aria-label', isFolder(app) ? `Расформировать ${app.name}` : `Удалить ${app.name}`);
    remove.addEventListener('click', () => updatePool(scope,removeEntry(freezeSlots(poolFor(scope),gridMetrics().columns),app.id))); item.append(remove);
  }
  return item;
}
function activate(app,scope='public') {
  if (isFolder(app)) openFolder(app.id,scope);
  else if(app.type==='system'){setEditing(false);if(app.action==='home')$('go-home').click();else if(app.action==='incognito')newIncognitoTab();else if(app.action==='private-desktop')requestVault();else setPanel(app.action);}
  else if (editing) openAppEditor(app,scope);
  else launchShortcut(app,scope);
}
function renderApps() {
  $('lock-private').hidden=!vaultKey;
  if(state?.mode==='browse'||['blank','incognito'].includes(document.body.dataset.surface))return;
  if(document.body.hasAttribute('data-desktop-search'))renderDesktopQuickAccess();
  if(document.body.dataset.runtime==='ios'&&state&&Math.abs(innerHeight-state.height)>1)return;
  const previous = positions($('apps'));
  $('apps').replaceChildren();
  $('apps').classList.toggle('editing', editing);
  const {columns,rows}=gridMetrics(), capacity=columns*rows;
  const privateShortcut=findEntry(apps,'atma-private-desktop')?.entry;
  if(privateShortcut&&!Number.isInteger(privateShortcut.slots?.[columns])){
    privateShortcut.slots={...privateShortcut.slots,[columns]:capacity};
    localStorage.setItem('atma-preview-apps',JSON.stringify(apps));
  }
  const arranged=arrangeEntries(apps,columns);
  const pageCount=Math.max(publicPages,Math.ceil((Math.max(-1,...arranged.map(p=>p.slot))+1)/capacity));
  publicPages=pageCount;
  renderDesktopPages(arranged,'public',pageCount,0,columns,rows);
  privatePageStart=pageCount;
  const privateLayout=arrangeEntries(vaultApps,columns);
  privatePageCount=vaultKey?Math.max(1,Math.ceil((Math.max(-1,...privateLayout.map(p=>p.slot))+1)/capacity)):0;
  renderDesktopPages(privateLayout,'private',privatePageCount,pageCount,columns,rows);
  desktopPage=Math.max(0,Math.min(desktopPage,pageCount+privatePageCount-1));
  $('apps').scrollLeft=desktopPage*$('apps').clientWidth;
  $('desktop-dots').replaceChildren();
  for(let page=0;page<pageCount+privatePageCount;page++) {
    const dot=document.createElement('button');dot.setAttribute('aria-label',page>=pageCount?'Закрытая страница':`Страница ${page+1}`);
    if(page>=pageCount){dot.classList.add('private-dot');dot.innerHTML=icon('lock');}
    dot.addEventListener('click',()=>showDesktopPage(page));$('desktop-dots').append(dot);
  }
  updateDesktopPageIndicators();
  renderDesktopDock(currentScope());
  animatePositions($('apps'), previous);
}
function desktopCell(app,slot,scope) {
  const item=app?createItem(app,null,slot,scope):document.createElement('div');
  if(!app){item.className='desktop-slot';item.setAttribute('aria-hidden','true');}
  item.dataset.slot=slot;
  item.dataset.scope=scope;
  return item;
}
function renderDesktopPages(layout,scope,count,offset,columns,rows) {
  const bySlot=new Map(layout.map(({entry,slot})=>[slot,entry])),capacity=columns*rows;
  for(let page=0;page<count;page++){
    const grid=document.createElement('div');grid.className=scope==='private'?'app-grid desktop-page private-page':'app-grid desktop-page';
    grid.dataset.page=page+offset;grid.dataset.scope=scope;
    grid.style.setProperty('--desktop-page-rows',String(rows));
    for(let cell=0;cell<capacity;cell++){
      const slot=page*capacity+cell;
      grid.append(desktopCell(bySlot.get(slot),slot,scope));
    }
    $('apps').append(grid);
  }
}
function renderDesktopDock(scope) {
  const dock=$('desktop-dock'), grid=$('desktop-dock-grid'), previous=positions(grid);
  dock.dataset.scope=scope;
  grid.replaceChildren(...arrangeDock(poolFor(scope)).map((app,slot)=>desktopCell(app,slot,scope)));
  animatePositions(grid,previous);
}
observeDesktopViewport($('apps'),()=>{if(!gesture)renderApps();});
function gridMetrics() {
  const tablet=innerWidth>=700,columns=tablet?6:4;
  if(!usesLegacyDesktopRows)return{columns,rows:5};
  // Existing slot indices were assigned using the old viewport-dependent page length.
  const footer=Number.isFinite(state?.footerHeight)?Math.min(innerHeight,state.footerHeight):128;
  const oldTop=Math.max(12,parseFloat(getComputedStyle($('apps').parentElement).paddingTop)-12||0);
  const gap=tablet?32:20,cell=tablet?98:86,dotsMargin=tablet?16:12;
  const height=innerHeight-footer-oldTop-8-dotsMargin-14;
  return{columns,rows:Math.max(1,Math.floor((height-14+gap)/(cell+gap)))};
}
function showDesktopPage(page) { $('apps').scrollTo({left:page*$('apps').clientWidth,behavior:reducedMotion.matches?'instant':'smooth'}); }
function updateDesktopPageIndicators() {
  [...$('apps').children].forEach((page,index)=>{page.inert=index!==desktopPage;});
  [...$('desktop-dots').children].forEach((dot,index)=>{
    dot.classList.toggle('active',index===desktopPage);
    dot.setAttribute('aria-current',index===desktopPage?'page':'false');
  });
}
$('apps').addEventListener('scroll',event=>{
  if(event.target!==$('apps')||!$('apps').clientWidth)return;
  const next=Math.round($('apps').scrollLeft/$('apps').clientWidth);
  if(next!==desktopPage){
    desktopPage=next;updateDesktopPageIndicators();
    const scope=currentScope();
    if($('desktop-dock').dataset.scope!==scope)renderDesktopDock(scope);
  }
  clearTimeout(pageLockTimer);pageLockTimer=setTimeout(()=>{if(vaultKey&&currentScope()==='public'&&Date.now()>autoLockAfter)lockVault();},220);
});
let quickAccessExpanded=false;
const desktopSearchTarget=element=>element instanceof Element&&Boolean(element.closest('#address-form,#desktop-focus-dock'));
function updateQuickAccessExpansion() {
  const toggle=$('desktop-suggestion-toggle');
  const secondRow=$('desktop-suggested-apps').children[1];
  toggle.hidden=!secondRow;
  toggle.textContent=quickAccessExpanded?'Свернуть':'Развернуть';
  toggle.setAttribute('aria-expanded',String(quickAccessExpanded));
  if(secondRow)secondRow.hidden=!quickAccessExpanded||!secondRow.hasAttribute('data-ready');
}
function renderDesktopQuickAccess() {
  const scope=vaultKey?currentScope():'public', entries=poolFor(scope);
  const grid=arrangeEntries(entries,gridMetrics().columns).sort((first,second)=>first.slot-second.slot);
  const ordered=[...arrangeDock(entries).filter(Boolean),...grid.map(position=>position.entry)];
  const needle=$('address').value.trim().toLocaleLowerCase();
  const matches=app=>[app.name,appLabel(app),app.url].some(value=>value?.toLocaleLowerCase().includes(needle));
  const suggested=(needle?ordered.flatMap(app=>matches(app)?[app]:isFolder(app)?app.children.filter(matches):[]):ordered).slice(0,8);
  const host=$('desktop-focus-dock'), suggestions=$('desktop-suggested-apps');
  host.dataset.scope=scope;
  host.hidden=suggested.length===0;
  const rows=[];
  for(let start=0;start<suggested.length;start+=4) {
    const row=document.createElement('div');
    row.className='desktop-suggestion-row';
    row.hidden=start!==0;
    row.append(...suggested.slice(start,start+4).map((app,index)=>createItem(app,null,start+index,scope,true)));
    rows.push(row);
  }
  suggestions.replaceChildren(...rows);
  updateQuickAccessExpansion();
  const secondRow=rows[1];
  if(secondRow) {
    // Decode the entire row before revealing it, including icons stored as PNGs.
    const images=[...secondRow.querySelectorAll('img')];
    Promise.all(images.map(image=>image.decode().catch(()=>{}))).then(()=>{
      if(secondRow.parentElement!==suggestions)return;
      secondRow.setAttribute('data-ready','');
      updateQuickAccessExpansion();
    });
  }
}
function syncDesktopSearch(target=document.activeElement) {
  const body=document.body, wasActive=body.hasAttribute('data-desktop-search');
  const active=body.dataset.surface==='home'&&(target===$('address')||wasActive&&desktopSearchTarget(target));
  if(active===wasActive)return;
  body.toggleAttribute('data-desktop-search',active);
  $('apps').inert=$('desktop-dots').inert=active;
  $('desktop-dock').inert=active;
  $('desktop-search-dismiss').hidden=!active;
  $('desktop-focus-dock').hidden=!active;
  quickAccessExpanded=false;
  if(active){
    if(editing)setEditing(false);
    else renderDesktopQuickAccess();
  }else {
    delete $('desktop-focus-dock').dataset.scope;
    $('desktop-suggested-apps').replaceChildren();
  }
}
function closeDesktopSearch() {
  const active=document.activeElement;
  if(desktopSearchTarget(active))active.blur();
  syncDesktopSearch(null);
}
$('desktop-search-dismiss').addEventListener('pointerdown',event=>event.preventDefault());
$('desktop-search-dismiss').addEventListener('click',closeDesktopSearch);
const keepDesktopSearchFocused=event=>{
  if(document.activeElement===$('address')&&event.target.closest('button,.app-item'))event.preventDefault();
};
for(const type of ['pointerdown','mousedown'])$('desktop-focus-dock').addEventListener(type,keepDesktopSearchFocused);
const quickAccessToggle=$('desktop-suggestion-toggle');
const toggleQuickAccess=()=>{quickAccessExpanded=!quickAccessExpanded;updateQuickAccessExpansion();};
quickAccessToggle.addEventListener('touchstart',keepDesktopSearchFocused,{passive:false});
quickAccessToggle.addEventListener('touchend',event=>{
  if(document.activeElement!==$('address'))return;
  // Complete the tap before WebKit can transfer focus away from the address.
  event.preventDefault();
  const touch=event.changedTouches[0];
  if(!event.touches.length&&touch&&quickAccessToggle.contains(document.elementFromPoint(touch.clientX,touch.clientY)))toggleQuickAccess();
},{passive:false});
quickAccessToggle.addEventListener('click',toggleQuickAccess);
document.addEventListener('focusin',event=>syncDesktopSearch(event.target));
document.addEventListener('focusout',event=>{if(desktopSearchTarget(event.target))syncDesktopSearch(event.relatedTarget);});
new MutationObserver(()=>syncDesktopSearch()).observe(document.body,{attributes:true,attributeFilter:['data-surface']});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&!panel&&document.body.hasAttribute('data-desktop-search'))closeDesktopSearch();
});
let blankPointer=null,lastBlankTap=null;
function toggleDesktopAlignment(){
  const {columns,rows}=gridMetrics(),capacity=columns*rows;
  if(alignmentSnapshot?.columns===columns&&alignmentSnapshot?.positions){
    apps=freezeSlots(apps,columns);
    for(const app of apps){
      const slot=alignmentSnapshot.positions[app.id];
      if(Number.isInteger(slot)&&slot>=0&&slot<10000)app.slots={...app.slots,[columns]:slot};
    }
    alignmentSnapshot=null;localStorage.removeItem(ALIGNMENT_SNAPSHOT_KEY);
  }else{
    const original=freezeSlots(apps,columns),shifted=shiftEntriesToOppositeEdge(original,columns,capacity);
    if(!shifted.changed)return;
    alignmentSnapshot={columns,positions:Object.fromEntries(original.map(app=>[app.id,app.slots?.[columns]]))};
    apps=shifted.items;localStorage.setItem(ALIGNMENT_SNAPSHOT_KEY,JSON.stringify(alignmentSnapshot));
  }
  localStorage.setItem('atma-preview-apps',JSON.stringify(apps));renderApps();
}
$('apps').addEventListener('pointerdown',event=>{
  const page=event.target.closest('.desktop-page');
  blankPointer=!editing&&!panel&&!gesture&&page?.dataset.scope==='public'&&!event.target.closest('.app-item')
    ?{id:event.pointerId,x:event.clientX,y:event.clientY,page:page.dataset.page}:null;
});
$('apps').addEventListener('pointerup',event=>{
  const start=blankPointer;blankPointer=null;
  if(!start||event.pointerId!==start.id||gesture||Math.hypot(event.clientX-start.x,event.clientY-start.y)>12)return;
  const now=Date.now();
  if(lastBlankTap&&lastBlankTap.page===start.page&&now-lastBlankTap.time<380&&Math.hypot(event.clientX-lastBlankTap.x,event.clientY-lastBlankTap.y)<40){
    lastBlankTap=null;toggleDesktopAlignment();
  }else lastBlankTap={time:now,x:event.clientX,y:event.clientY,page:start.page};
});
function beginGesture(event, app, parentId,scope='public') {
  if (event.button !== 0 || gesture) return;
  const current = gesture = { id: app.id, parentId, scope, pointerId: event.pointerId, x:event.clientX, y:event.clientY, wasEditing:editing, active:false, scrollStart:$('apps').scrollLeft, onTile:Boolean(event.target.closest('.app-tile')), fromDock:Boolean(event.target.closest('.desktop-dock')) };
  if (editing) { event.preventDefault(); capturePointer(current); }
  current.hold = setTimeout(() => {
    if (gesture !== current) return;
    current.held = true; capturePointer(current); setEditing(true);
    navigator.vibrate?.(12);
  }, DESKTOP_HOLD_MS);
}
function capturePointer(current) { try { document.body.setPointerCapture(current.pointerId); } catch {} }
function clearHover() {
  if (gesture) { clearTimeout(gesture.hoverTimer); gesture.targetId = null; gesture.targetSlot = null; gesture.targetDockSlot = null; gesture.hoverKey = null; gesture.combine = false; }
}
document.addEventListener('pointermove', event => {
  const current = gesture; if (!current || event.pointerId !== current.pointerId) return;
  const distance = Math.hypot(event.clientX-current.x, event.clientY-current.y);
  if(current.swipe){event.preventDefault();$('apps').scrollLeft=current.scrollStart-(event.clientX-current.x);return;}
  if (!current.active && distance > 7) {
    if (!editing) {
      clearTimeout(current.hold);
      if(!panel&&!current.fromDock&&Math.abs(event.clientX-current.x)>Math.abs(event.clientY-current.y)){current.swipe=true;capturePointer(current);event.preventDefault();}
      else gesture=null;
      return;
    }
    current.active = true; clearTimeout(current.hold); suppressClickUntil = Date.now()+1000;
    const original = [...document.querySelectorAll('.app-item')].find(item=>item.dataset.app===current.id&&item.dataset.scope===current.scope);
    if(!original){gesture=null;return;}
    const tile = original.querySelector('.app-tile');
    const rect = tile.getBoundingClientRect();
    current.ghost = original.cloneNode(true); current.ghost.classList.add('drag-ghost');
    current.ghost.setAttribute('aria-hidden','true');
    const artwork = current.ghost.querySelector('.app-tile');
    current.ghost.replaceChildren(artwork);
    current.ghost.style.width = artwork.style.width = `${tile.offsetWidth}px`;
    current.offsetX = current.x-rect.x; current.offsetY = current.y-rect.y;
    document.body.append(current.ghost); original.classList.add('dragging');
  }
  if (!current.active) return;
  event.preventDefault();
  current.ghost.style.left = `${event.clientX-current.offsetX}px`; current.ghost.style.top = `${event.clientY-current.offsetY}px`;
  current.lastX=event.clientX;current.lastY=event.clientY;
  if(!panel) {
    const r=$('apps').getBoundingClientRect();
    const direction=event.clientY>=r.top&&event.clientY<=r.bottom?(event.clientX<r.left+25?-1:event.clientX>r.right-25?1:0):0;
    if(direction!==current.pageDirection){clearTimeout(current.pageTimer);current.pageDirection=direction;
      if(direction)current.pageTimer=setTimeout(()=>{let next=desktopPage+direction;
        if(current.scope==='private'){if(next<privatePageStart||next>=privatePageStart+privatePageCount)return;}
        else {if(next<0)return;if(next>=publicPages){publicPages=next+1;localStorage.setItem('atma-preview-page-count',publicPages);renderApps();}}
        showDesktopPage(next);clearHover();setTimeout(()=>{if(gesture===current)updateDropTarget(current.lastX,current.lastY,current)},380);
      },500);
    }
  }
  if (panel === 'folder' && current.parentId === openFolderId) {
    const card = document.querySelector('.folder-card')?.getBoundingClientRect();
    if (card && (event.clientX < card.left-22 || event.clientX > card.right+22 || event.clientY < card.top-26 || event.clientY > card.bottom+26)) {
      current.extracted = true; openFolderId = null; setPanel(null, { immediate:true });
    }
  }
  updateDropTarget(event.clientX,event.clientY,current);
}, { passive:false });
function updateDropTarget(x,y,current) {
  if(!panel) {
    const viewport=$('apps'),bounds=viewport.getBoundingClientRect();
    if(x>=bounds.left&&x<=bounds.right&&y>=bounds.top&&y<=bounds.bottom){
      const padding=getComputedStyle(viewport.parentElement);
      x=Math.max(bounds.left+parseFloat(padding.paddingLeft)+1,Math.min(x,bounds.right-parseFloat(padding.paddingRight)-1));
    }
  }
  const hit=document.elementsFromPoint(x,y);
  const dockTarget=hit.map(item=>item.closest('.desktop-dock [data-slot]')).find(item=>item?.dataset.scope===current.scope);
  if(dockTarget&&!panel){
    const slot=Number(dockTarget.dataset.slot);
    if(current.targetDockSlot===slot)return;
    clearHover();current.targetDockSlot=slot;return;
  }
  const empty=hit.map(item=>item.closest('.desktop-slot')).find(item=>item&&(item.dataset.scope||'public')===current.scope);
  if(empty&&!panel){const slot=Number(empty.dataset.slot);if(current.targetSlot===slot)return;clearHover();current.targetSlot=slot;return;}
  const target = hit.map(item=>item.closest('.app-item')).find(item=>item?.dataset.scope===current.scope);
  if(target?.dataset.app===current.id){clearHover();current.targetId=current.id;return;}
  const targetId = target?.dataset.app || null;
  if (!target) {
    if(!panel){
      const grid=$('apps').children[desktopPage],bounds=$('apps').getBoundingClientRect();
      if(grid?.dataset.scope===current.scope&&x>=bounds.left&&x<=bounds.right&&y>=bounds.top&&y<=bounds.bottom){
        const slots=[...grid.querySelectorAll('.desktop-slot')];
        const nearest=slots.reduce((best,item)=>{
          const rect=item.getBoundingClientRect(),distance=Math.hypot(x-rect.left-rect.width/2,y-rect.top-rect.height/2);
          return !best||distance<best.distance?{item,distance}:best;
        },null)?.item;
        if(nearest){const slot=Number(nearest.dataset.slot);if(current.targetSlot===slot)return;clearHover();current.targetSlot=slot;return;}
      }
    }
    clearHover(); return;
  }
  const pool=poolFor(current.scope),sourceEntry = findEntry(pool,current.id)?.entry, targetEntry = findEntry(pool,targetId)?.entry;
  const rect = target.querySelector('.app-tile').getBoundingClientRect();
  const center = Math.abs(x-(rect.x+rect.width/2)) < rect.width*.36 && Math.abs(y-(rect.y+rect.height/2)) < rect.height*.36;
  const canCombine = panel !== 'folder' && center && !isFolder(sourceEntry) && !!targetEntry && sourceEntry?.id!=='atma-private-desktop' && targetEntry.id!=='atma-private-desktop';
  const hoverKey = `${targetId}:${canCombine}`;
  if (hoverKey === current.hoverKey) return;
  clearHover(); current.hoverKey=hoverKey;
  current.targetId = targetId;
  current.hoverTimer = setTimeout(() => {
    if (gesture !== current || current.targetId !== targetId) return;
    if (canCombine) { current.combine = true; }
    else if(!current.fromDock) {
      const result = panel==='folder'?dropEntry(poolFor(current.scope),current.id,targetId,{destinationFolderId:openFolderId}):placeEntry(poolFor(current.scope),current.id,Number(target.dataset.slot),gridMetrics().columns);
      if (result.changed) { current.reorderedTargetId=targetId; updatePool(current.scope,result.items); }
    }
  }, canCombine ? 430 : 170);
}
async function endGesture(event, cancelled = false) {
  const current = gesture; if (!current || event.pointerId !== current.pointerId) return;
  clearTimeout(current.hold); clearTimeout(current.pageTimer);
  // Recheck after scrolling even when the pointer stayed still at the edge.
  if(current.active&&!cancelled)updateDropTarget(event.clientX,event.clientY,current);
  clearTimeout(current.hoverTimer);
  const targetId = current.targetId, combine = current.combine, targetSlot=current.targetSlot, targetDockSlot=current.targetDockSlot;
  clearHover();
  try { document.body.releasePointerCapture(current.pointerId); } catch {}
  if(current.swipe){gesture=null;suppressClickUntil=Date.now()+350;showDesktopPage(Math.round($('apps').scrollLeft/$('apps').clientWidth));return;}
  if (current.active) {
    let result={changed:false};
    if(!cancelled) {
      if(Number.isInteger(targetDockSlot))result=placeDockEntry(poolFor(current.scope),current.id,targetDockSlot,gridMetrics().columns);
      else if(Number.isInteger(targetSlot))result=placeEntry(poolFor(current.scope),current.id,targetSlot,gridMetrics().columns);
      else if((targetId||panel==='folder')&&!(!combine&&targetId&&current.reorderedTargetId===targetId)) {
        if(!panel&&targetId&&!combine) {
          const columns=gridMetrics().columns;
          const slot=arrangeEntries(poolFor(current.scope),columns).find(({entry})=>entry.id===targetId)?.slot;
          result=placeEntry(poolFor(current.scope),current.id,slot,columns);
        } else result=dropEntry(poolFor(current.scope),current.id,targetId,{combine,columns:gridMetrics().columns,destinationFolderId:panel==='folder'?openFolderId:null});
      }
    }
    current.ghost.remove();
    gesture = null; suppressClickUntil=Date.now()+350;
    if (result.changed) { updatePool(current.scope,result.items); } else { renderApps(); if(panel==='folder') renderFolder(); }
    if (result.folderId) await openFolder(result.folderId,current.scope);
  } else {
    gesture=null;
    const shortTap = current.onTile && Date.now() >= suppressClickUntil
      && Math.hypot(event.clientX-current.x, event.clientY-current.y)<=7;
    if (current.held || current.wasEditing) suppressClickUntil=Date.now()+350;
    if (!cancelled && !current.held && (current.wasEditing || shortTap)) {
      const app=findEntry(poolFor(current.scope),current.id)?.entry;
      if(app) activate(app,current.scope);
    }
  }
}
document.addEventListener('pointerup', event=>endGesture(event));
document.addEventListener('pointercancel', event=>endGesture(event,true));
async function openFolder(id,scope='public') { openFolderId=id;folderScope=scope;await setPanel('folder'); }
function folderOrigin() {
  const item = [...document.querySelectorAll('#apps .app-item,#desktop-dock .app-item')].find(item=>item.dataset.app===openFolderId&&item.dataset.scope===folderScope);
  return item?.querySelector('.app-tile').getBoundingClientRect();
}
function animateFolder(opening) {
  const sheet=$('sheet'), origin=folderOrigin(), rect=sheet.getBoundingClientRect();
  if (!origin || reducedMotion.matches) return Promise.resolve();
  const collapsed={ transform:`translate(${origin.x+origin.width/2-rect.x-rect.width/2}px,${origin.y+origin.height/2-rect.y-rect.height/2}px) scale(.16)`,opacity:.05 };
  const expanded={ transform:'translate(0,0) scale(1)',opacity:1 };
  return sheet.animate(opening?[collapsed,expanded]:[expanded,collapsed],{duration:opening?360:230,easing:'cubic-bezier(.2,.8,.2,1)'}).finished.catch(()=>{});
}
function renderFolder() {
  const folder=findEntry(poolFor(folderScope),openFolderId)?.entry;
  if (!isFolder(folder)) { setPanel(null,{immediate:true}); return; }
  const previous=positions($('sheet-content'));
  const page = Math.round((document.querySelector('.folder-pages')?.scrollLeft||0)/(document.querySelector('.folder-pages')?.clientWidth||1));
  $('sheet-title').textContent=folder.name;
  $('sheet-content').innerHTML=`<div class="folder-heading"><input id="folder-name" aria-label="Название папки" maxlength="32" value="${escape(folder.name)}" ${editing?'':'readonly'}><button id="folder-done">${editing?'Готово':'Изменить'}</button></div><div class="folder-card"><div class="folder-pages" id="folder-pages"></div><div class="folder-dots" id="folder-dots"></div></div><p class="folder-hint">${editing?'Чтобы вынести приложение, перетащите его за край папки':'Удерживайте иконку, чтобы переместить её'}</p>`;
  for(let start=0;start<folder.children.length;start+=9){
    const grid=document.createElement('div'); grid.className='folder-page';
    folder.children.slice(start,start+9).forEach((app,index)=>grid.append(createItem(app,folder.id,index,folderScope)));
    $('folder-pages').append(grid);
    const dot=document.createElement('button'); dot.setAttribute('aria-label',`Страница ${start/9+1}`);
    dot.addEventListener('click',()=>$('folder-pages').scrollTo({left:grid.offsetLeft,behavior:reducedMotion.matches?'instant':'smooth'})); $('folder-dots').append(dot);
  }
  const updateDots=()=>{const index=Math.round($('folder-pages').scrollLeft/$('folder-pages').clientWidth);[...$('folder-dots').children].forEach((dot,i)=>dot.classList.toggle('active',i===index));};
  $('folder-pages').scrollLeft=page*$('folder-pages').clientWidth; updateDots(); $('folder-pages').addEventListener('scroll',updateDots);
  $('folder-done').addEventListener('click',()=>setEditing(!editing));
  $('folder-name').addEventListener('change',event=>{folder.name=event.target.value.trim()||'Папка';saveApps(folderScope,{layoutChanged:false});});
  $('folder-name').addEventListener('keydown',event=>{if(event.key==='Enter')event.currentTarget.blur();});
  animatePositions($('sheet-content'),previous);
}
async function launch(url,scope='public',options={}) {
  setEditing(false);
  if(scope==='private')lockVault();
  try { await action('open', { url, webApp:state?.mode==='browse'&&Boolean(state.webApp), ...(scope==='private'?{privateDesktop:true}:{}), ...options }); $('address').blur(); } catch {}
}
async function launchShortcut(app,scope='public') {
  if(scope==='private'&&!vaultKey)return;
  setEditing(false);
  if(scope==='private')lockVault();
  try { await action('shortcut/open',{url:app.url,shortcutId:`${scope}:${app.id}`});$('address').blur(); } catch {}
}
async function setPanel(name, options = {}) {
  if (panel==='folder' && name!=='folder' && !options.immediate) await animateFolder(false);
  if(panel==='pin'&&name!=='pin'){pinEpoch++;pinDigits='';firstPin=null;pinBusy=false;if(!options.keepVaultAction){pendingVaultMove=null;pendingVaultAdd=false;pendingVaultSite=null;}}
  panel = name; renderPanel();
  try { await action('panel', { panel: name }); } catch {}
}
function renderPanel() {
  const error = $('sheet-error');
  error.hidden = true;
  error.textContent = '';
  disposeMediaPanel?.();disposeMediaPanel=null;
  $('sheet-content').classList.remove('cookie-browser');
  if(filePreviewUrl){URL.revokeObjectURL(filePreviewUrl);filePreviewUrl=null;}
  const wasFolder=$('overlay').classList.contains('folder-overlay');
  $('overlay').classList.toggle('folder-overlay',panel==='folder');
  $('overlay').classList.toggle('pin-overlay',panel==='pin');
  $('overlay').classList.toggle('tabs-overlay',panel==='tabs');
  $('overlay').dataset.panel = panel || '';
  document.body.classList.toggle('folder-open',panel==='folder');
  $('overlay').hidden = !panel;
  $('sheet-content').replaceChildren();
  if (!panel) return;
  const titles = {tabs:'Вкладки', settings: 'Настройки', cookies:'Куки', 'private-device':'Устройство инкогнито', wallpaper: 'Обои', appearance:'Оформление', 'app-icon':'Иконка приложения', add: 'Новое веб-приложение', edit: 'Веб-приложение', privacy:'Политика конфиденциальности',support:'Поддержка',about: window.webkit?.messageHandlers?.atma?'О браузере':'О предпросмотре' };
  $('sheet-title').textContent = titles[panel] || 'ATMA';
  if(panel==='desktop-menu')$('sheet-title').textContent='Меню браузера';
  if(panel==='media')$('sheet-title').textContent='Медиаплеер';
  if(panel==='pin')renderPIN();
  else if (panel === 'folder') { renderFolder(); if(!wasFolder) requestAnimationFrame(()=>animateFolder(true)); }
  else if (panel === 'settings') renderSettings();
  else if (panel === 'desktop-menu') renderDesktopMenu();
  else if(panel==='privacy'||panel==='support')renderLegalInfo($('sheet-content'),{kind:panel,language:localization.language,onOpen:async url=>{try{await action('tabs/new');await action('open',{url,webApp:false});}catch{reportError('Не удалось открыть страницу');}}});
  else if(panel==='media')disposeMediaPanel=renderMediaPlayer($('sheet-content'),{api,t:localization.t,openTab:async tabId=>{await action('tabs/select',{tabId});}});
  else if(panel==='appearance')renderAppearance();
  else if(panel==='app-icon')renderAppIconPicker();
  else if(panel==='tabs')renderTabs();
  else if(panel==='private-device')renderPrivateDevices();
  else if(panel==='cookies')renderCookieBrowser($('sheet-content'),{api,onBack:()=>setPanel(null),reportError,t:localization.t,backLabel:'Рабочий стол'});
  else if (panel === 'files') {$('sheet-title').textContent='Файлы';renderFiles();}
  else if (panel === 'wallpaper') renderWallpapers();
  else if (panel === 'add') renderAppForm();
  else if (panel === 'about') $('sheet-content').innerHTML = window.webkit?.messageHandlers?.atma?'<div class="setting-card"><div class="setting-row">Независимый браузер ATMA на WebKit Apple</div></div><p class="sheet-note">Сайты открываются через системный WebKit текущего iPhone или iPad. Cookie и входы сохраняются в браузере.</p>':'<div class="setting-card"><div class="setting-row">Локальный прототип ATMA в Responsively</div></div><p class="sheet-note">Это предпросмотр интерфейса. Работа сайтов в приложении iOS использует системный WebKit.</p><p class="sheet-note">Уведомления, синхронизация, перевод и диктовка Apple в этом этапе не подключены.</p>';
}
function settingButton(text, glyph, handler) {
  const button = document.createElement('button'); button.className = 'setting-row'; button.innerHTML = `${icon(glyph)}<span>${escape(text)}</span>${icon('right')}`;
  button.addEventListener('click', handler); return button;
}
function fileSize(bytes) {
  const [value,unit]=bytes<1024?[bytes,'byte']:bytes<1048576?[bytes/1024,'kilobyte']:[bytes/1048576,'megabyte'];
  return new Intl.NumberFormat(localization.language,{style:'unit',unit,maximumFractionDigits:1}).format(value);
}
function fileSymbol(file){return `<span class="file-symbol ${file.kind}"><svg viewBox="0 0 36 44" aria-hidden="true"><path d="M6 1h17l9 9v30a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V4a3 3 0 0 1 3-3Z" fill="currentColor" opacity=".12"/><path d="M23 1v10h9M10 24h16M10 30h16" fill="none" stroke="currentColor" stroke-width="1.5"/></svg><b>${escape(file.extension.slice(1,5).toUpperCase()||'ФАЙЛ')}</b></span>`;}
async function renderFiles(){
  $('sheet-content').classList.remove('cookie-browser');
  if(filePreviewUrl){URL.revokeObjectURL(filePreviewUrl);filePreviewUrl=null;}
  $('sheet-content').innerHTML=`<div class="files-location"><span>На ATMA</span>${icon('right')}<strong>Загрузки</strong></div><div id="file-list" class="file-list"><p class="files-empty">Загрузка…</p></div><div class="files-tools"><label class="model-search">${icon('search')}<input id="file-search" placeholder="Поиск файлов" aria-label="Поиск файлов"></label><button id="files-refresh" aria-label="Обновить список файлов">${icon('refresh')}</button></div>`;
  $('files-refresh').addEventListener('click',renderFiles);
  const cookieFolder=document.createElement('button');cookieFolder.className='cookies-folder';cookieFolder.id='open-cookies';cookieFolder.innerHTML=`${icon('globe')}<span><strong>Cookie сайтов</strong><small>Просмотр и выборочное удаление</small></span>${icon('right')}`;
  cookieFolder.addEventListener('click',()=>renderCookieBrowser($('sheet-content'),{api,onBack:renderFiles,reportError}));$('file-list').before(cookieFolder);
  try{
    const {files}=await api('files');if(panel!=='files'||!$('file-list'))return;
    function list(){
      const filter=$('file-search').value.toLocaleLowerCase(),visible=files.filter(file=>file.name.toLocaleLowerCase().includes(filter));$('file-list').replaceChildren();
      if(!visible.length){$('file-list').innerHTML=`<p class="files-empty">${filter?'Файлы не найдены':'Здесь появятся файлы,<br>которые вы скачаете в ATMA'}</p>`;return;}
      for(const file of visible){
        const button=document.createElement('button');button.className='file-row';button.dataset.file=file.id;
        button.innerHTML=`${fileSymbol(file)}<span class="file-details"><strong data-no-translate>${escape(file.name)}</strong><small>${new Date(file.modified).toLocaleDateString(localization.language)} · ${fileSize(file.size)}</small></span>${icon('right')}`;
        button.addEventListener('click',()=>showFile(file.id));$('file-list').append(button);
      }
    }
    $('file-search').addEventListener('input',list);list();
  }catch(error){if(panel==='files')reportError(error.message);}
}
async function showFile(id){
  try{
    const file=await api('file',{fileId:id});if(panel!=='files')return;
    if(filePreviewUrl){URL.revokeObjectURL(filePreviewUrl);filePreviewUrl=null;}
    $('sheet-content').innerHTML=`<button class="file-back" id="file-back">${icon('left')}Загрузки</button><h2 class="file-title" data-no-translate>${escape(file.name)}</h2><p class="file-meta">${fileSize(file.size)}</p><div id="file-preview" class="file-preview"></div>`;
    $('file-back').addEventListener('click',renderFiles);
    if(file.kind==='text'){const pre=document.createElement('pre');pre.className='file-text';pre.textContent=file.text+(file.truncated?'\n\n'+localization.t('…Файл показан не полностью.'):'');$('file-preview').append(pre);}
    else if(['image','pdf','audio','video'].includes(file.kind)){
      const bytes=Uint8Array.from(atob(file.base64),char=>char.charCodeAt(0));filePreviewUrl=URL.createObjectURL(new Blob([bytes],{type:file.mime}));
      const element=document.createElement(file.kind==='image'?'img':file.kind==='pdf'?'iframe':file.kind);element.src=filePreviewUrl;element.className=file.kind==='image'?'file-image':file.kind==='pdf'?'file-pdf':'file-media';
      if(file.kind==='audio'||file.kind==='video'){element.controls=true;element.preload='metadata';}
      if(file.kind==='image')element.alt=file.name;else element.title=file.name;
      $('file-preview').append(element);
    }else{$('file-preview').textContent=file.note;}
  }catch(error){reportError(error.message);}
}
function settingsPickers(container) {
  for(const select of container.querySelectorAll('select')) {
    select.hidden=true;
    const trigger=document.createElement('button');trigger.type='button';trigger.className='setting-choice';
    trigger.setAttribute('aria-label',select.getAttribute('aria-label'));trigger.setAttribute('aria-haspopup','dialog');
    trigger.dataset.settingPicker=select.id;trigger.disabled=select.disabled;
    const sync=()=>{trigger.innerHTML=`<span>${escape(select.selectedOptions[0]?.textContent||'')}</span>${icon('down')}`;};
    sync();select.after(trigger);select.addEventListener('change',sync);
    trigger.addEventListener('click',event=>{
      event.preventDefault();
      container.querySelector('dialog[open]')?.close();
      const dialog=document.createElement('dialog');dialog.className='settings-picker';
      const titleId=`${select.id}-title`;dialog.setAttribute('aria-labelledby',titleId);
      dialog.innerHTML=`<div class="picker-heading"><h2 id="${titleId}">${escape(select.getAttribute('aria-label'))}</h2><button class="sheet-close" aria-label="Закрыть выбор">${icon('close')}</button></div><div class="picker-options"></div>`;
      for(const option of select.options) {
        const button=document.createElement('button');button.type='button';button.dataset.value=option.value;button.disabled=option.disabled;
        button.setAttribute('aria-pressed',String(option.selected));
        button.innerHTML=`<span>${escape(option.textContent)}</span>${option.selected?icon('check'):''}`;
        button.addEventListener('click',()=>{select.value=option.value;select.dispatchEvent(new Event('change',{bubbles:true}));dialog.close();});
        dialog.querySelector('.picker-options').append(button);
      }
      dialog.querySelector('.sheet-close').addEventListener('click',()=>dialog.close());
      dialog.addEventListener('close',()=>{dialog.remove();if(trigger.isConnected)trigger.focus({preventScroll:true});});
      dialog.addEventListener('click',event=>{
        if(event.target!==dialog)return;
        const r=dialog.getBoundingClientRect();
        if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();
      });
      dialog.addEventListener('keydown',event=>{
        if(event.key==='Escape'){event.stopPropagation();return;}
        if(!['ArrowDown','ArrowUp'].includes(event.key))return;
        const choices=[...dialog.querySelectorAll('.picker-options button:not(:disabled)')],index=choices.indexOf(document.activeElement);
        event.preventDefault();choices[(index+(event.key==='ArrowDown'?1:-1)+choices.length)%choices.length]?.focus({preventScroll:true});
      });
      select.parentElement.append(dialog);dialog.showModal();
      dialog.querySelector('[aria-pressed="true"]')?.focus({preventScroll:true});
    });
  }
}
function renderPrivateDevices(){
  const root=$('sheet-content');
  if(!state?.privateBrowsing){root.textContent='Выбор устройства доступен только в инкогнито.';return;}
  root.replaceChildren();
  const search=document.createElement('input');search.id='private-device-filter';search.className='private-device-filter';search.placeholder='Найти устройство';search.setAttribute('aria-label','Найти устройство');
  const list=document.createElement('div');list.className='model-list';list.id='private-devices';
  const separate=document.createElement('input');separate.type='checkbox';
  const session=document.createElement('label');session.className='private-session-choice';
  session.append(separate,localization.t('Открыть в отдельном сеансе'));
  const note=document.createElement('p');note.className='sheet-note';
  note.textContent=localization.t('Отдельный сеанс открывает сайты без входов из других вкладок. Открытая страница остаётся в своей вкладке.');
  root.append(search,session,list,note);
  const render=()=>{
    list.replaceChildren();
    const needle=search.value.trim().toLocaleLowerCase();
    for(const profile of profiles.filter(item=>String(item.name||'').toLocaleLowerCase().includes(needle))){
      const button=document.createElement('button');button.className='model-row';button.dataset.profile=profile.id;
      button.classList.toggle('selected',profile.id===state.profileId);
      button.setAttribute('aria-pressed',String(profile.id===state.profileId));
      button.innerHTML=`<span class="model-symbol">${icon(profile.family==='Компьютер'?'computer':profile.family==='iPad'?'tablet':'phone')}</span><span class="model-name">${escape(profile.name)}</span>${profile.id===state.profileId?`<span class="model-check">${icon('check')}</span>`:''}`;
      button.addEventListener('click',async()=>{
        if(busy)return;busy=true;button.disabled=true;
        try{await action('private-device',{profileId:profile.id,separateSession:separate.checked});await setPanel(null);}
        catch(error){reportError(error.message);}finally{busy=false;button.disabled=false;}
      });
      list.append(button);
    }
  };
  search.addEventListener('input',render);render();
}
function renderDesktopMenu() {
  const root=$('sheet-content');
  const entries=[
    ['Вкладки','globe',()=>setPanel('tabs')],
    ['Новая вкладка','plus',newBrowserTab],
    ['Открыть Инкогнито','incognito',newIncognitoTab],
    ['Куки и данные сайтов','lock',()=>setPanel('cookies')],
    ['История','left',openBrowserHistory],
    ['Добавить веб-приложение','plus',openAddShortcut],
    [editing?'Завершить редактирование':'Изменить приложения','edit',async()=>{await setPanel(null);setEditing(!editing);}],
    ['Оформление и язык','image',()=>setPanel('appearance')],
  ];
  for (const [label,glyph,handler] of entries) root.append(settingButton(label,glyph,handler));
  const settings=settingButton('Настройки','dots',()=>setPanel('settings'));
  settings.id='desktop-menu-settings';
  root.append(settings);
}
function renderSettings() {
  const card = document.createElement('div'); card.className = 'setting-card';
  if (state?.mode === 'browse' && state.capabilities?.pageTranslation) {
    const label = state.translationStatus === 'translated' ? 'Показать оригинал' : 'Перевести страницу';
    const translation = settingButton(label, 'globe', () => action('translation/toggle').catch(() => {}));
    translation.disabled = state.loading || state.translationStatus === 'translating';
    card.append(translation);
  }
  const appearanceButton=settingButton('Оформление','image',()=>setPanel('appearance'));appearanceButton.id='open-appearance';card.append(appearanceButton);
  const incognitoButton=settingButton('Открыть Инкогнито','incognito',newIncognitoTab);incognitoButton.id='open-incognito';card.append(incognitoButton);
  if(state?.privateBrowsing){const deviceButton=settingButton('Устройство инкогнито','phone',()=>setPanel('private-device'));deviceButton.id='open-private-device';card.append(deviceButton);}
  const cookiesButton=settingButton('Куки и данные сайтов','globe',()=>setPanel('cookies'));cookiesButton.id='open-cookies-settings';card.append(cookiesButton);
  const downloadsButton=settingButton('Загрузки','image',()=>setPanel('files'));downloadsButton.id='open-downloads';card.append(downloadsButton);
  const policyButton=settingButton('Политика конфиденциальности','lock',()=>setPanel('privacy'));policyButton.id='open-privacy';card.append(policyButton);
  const supportButton=settingButton('Поддержка','info',()=>setPanel('support'));supportButton.id='open-support';card.append(supportButton);
  const mediaButton=settingButton('Медиаплеер','image',()=>setPanel('media'));mediaButton.id='open-media';card.append(mediaButton);
  card.append(settingButton('Приватный стол','lock',requestVault));
  card.append(settingButton('Добавить страницу рабочего стола','plus',async()=>{publicPages++;localStorage.setItem('atma-preview-page-count',publicPages);await setPanel(null);renderApps();showDesktopPage(publicPages-1);}));
  const addDesktopButton=settingButton('Добавить веб-приложение','plus',openAddShortcut);addDesktopButton.id='add-desktop-app';card.append(addDesktopButton);
  const probe=settingButton('Проверить, что видит сайт', 'phone', async () => { try { await action('probe'); } catch {} });probe.disabled=state?.capabilities?.probe===false;card.append(probe);
  card.append(settingButton(editing ? 'Завершить редактирование' : 'Изменить приложения', 'edit', async () => { setEditing(!editing); await action('home'); $('address').value = ''; renderApps(); }));
  $('sheet-content').append(card);
  const preferences = document.createElement('div'); preferences.className = 'setting-card';
  const useDeviceLanguage=state?.capabilities?.localeEmulation===false;
  const useDeviceTimezone=state?.capabilities?.timezoneEmulation===false;
  const siteLanguage=state?.preferredLanguages?.[0]||navigator.language;
  const timezone=state?.timezone||Intl.DateTimeFormat().resolvedOptions().timeZone;
  preferences.innerHTML = `
    <div class="setting-row">${icon('globe')}<span>Язык интерфейса</span><select id="interface-language" aria-label="Язык интерфейса">${interfaceLanguageOptions}</select></div>
    <div class="setting-row">${icon('search')}<span>Поисковик</span><select id="search-engine" aria-label="Поисковик"><option value="google">Google</option><option value="yandex">Яндекс</option><option value="bing">Bing</option><option value="duckduckgo">DuckDuckGo</option></select></div>
    <div class="setting-row">${icon('globe')}<span>Язык сайта</span>${useDeviceLanguage?
      `<small data-no-translate>${escape(siteLanguage)}</small>`:
      '<select id="site-language" aria-label="Язык сайта"><option value="ru-RU">Русский</option><option value="en-US">English</option></select>'}</div>
    <div class="setting-row">${icon('globe')}<span>Часовой пояс</span>${useDeviceTimezone?
      `<small data-no-translate>${escape(timezone.replaceAll('_',' '))}</small>`:
      '<select id="site-timezone" aria-label="Часовой пояс"><option value="Europe/Moscow">Москва</option><option value="UTC">UTC</option><option value="Europe/Berlin">Берлин</option><option value="America/New_York">Нью-Йорк</option><option value="Asia/Dubai">Дубай</option></select>'}</div>`;
  $('sheet-content').append(preferences);
  $('search-engine').value = searchEngine;
  bindInterfaceLanguage($('interface-language'));
  if(useDeviceLanguage||useDeviceTimezone){const note=document.createElement('p');note.className='sheet-note';note.textContent='Язык и часовой пояс сайтов определяет iOS.';$('sheet-content').append(note);}
  $('search-engine').addEventListener('change', async event => { searchEngine = event.target.value; localStorage.setItem('atma-preview-search', searchEngine); try { await action('preferences', { searchEngine }); } catch {} });
  if(!useDeviceLanguage){
    $('site-language').value = ['ru-RU','en-US'].includes(state?.locale)?state.locale:'ru-RU';
    $('site-language').addEventListener('change', async event => { try { await action('preferences', { locale: event.target.value }); } catch {} });
  }
  if(!useDeviceTimezone){
    $('site-timezone').value = state?.timezone || 'Europe/Moscow';
    $('site-timezone').addEventListener('change', async event => { try { await action('preferences', { timezone: event.target.value }); } catch {} });
  }
  settingsPickers(preferences);
  $('sheet-content').append(settingButton(window.webkit?.messageHandlers?.atma?'О браузере':'О предпросмотре', 'info', () => setPanel('about')));
}
function applyWallpaper() {
  const choice = wallpaperForTheme(wallpaper, document.body.dataset.theme);
  const image = wallpaper === 'custom' ? customWallpaperURL : choice?.image;
  document.body.dataset.wallpaper = wallpaper;
  document.body.dataset.wallpaperTone = choice?.tone ?? '';
  document.querySelector('.wallpaper').style.backgroundImage = image ? `url("${image}")` : 'none';
}
function useWallpaper(name) {
  localStorage.setItem(wallpaperKey, name);
  wallpaper = name;
  applyWallpaper();
  if (panel === 'wallpaper') renderWallpapers();
}
function renderWallpapers() {
  $('sheet-content').replaceChildren();
  const list = document.createElement('div'); list.className = 'wallpapers';
  for (const {id, label} of WALLPAPERS) {
    const preview = wallpaperForTheme(id, document.body.dataset.theme);
    const button = document.createElement('button');
    const title = document.createElement('span');
    title.textContent = label;
    button.className = 'wallpaper-choice';
    button.classList.toggle('selected', wallpaper === id);
    button.setAttribute('aria-pressed', String(wallpaper === id));
    button.dataset.wallpaper = id;
    button.dataset.tone = preview?.tone ?? '';
    button.style.backgroundImage = preview?.image ? `url("${preview.image}")` : 'none';
    button.append(title);
    button.addEventListener('click', () => useWallpaper(id));
    list.append(button);
  }
  $('sheet-content').append(appearanceBack('Оформление','appearance'),list, settingButton('Выбрать фото', 'image', () => $('wallpaper-file').click()));
}
function wallpaperDB() { return new Promise((resolve, reject) => { const request = indexedDB.open('atma-preview-ui', 1); request.onupgradeneeded = () => request.result.createObjectStore('preferences'); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); }); }
$('wallpaper-file').addEventListener('change', async event => {
  const file = event.target.files[0]; if (!file) return;
  if (!file.type.startsWith('image/')) return reportError('Выберите изображение');
  try {
    const db = await wallpaperDB(); const transaction = db.transaction('preferences', 'readwrite');
    transaction.objectStore('preferences').put(file, 'wallpaper');
    await new Promise((resolve, reject) => { transaction.oncomplete = resolve; transaction.onerror = () => reject(transaction.error); }); db.close();
    if (customWallpaperURL) URL.revokeObjectURL(customWallpaperURL);
    customWallpaperURL = URL.createObjectURL(file);
    useWallpaper('custom'); await setPanel(null);
  } catch { reportError('Не удалось сохранить обои'); }
});
function openAddShortcut() {
  editorScope=shortcutDestination();
  if(editorScope==='private'&&!vaultKey){
    pendingVaultAdd=true;
    return requestVault();
  }
  return setPanel('add');
}
function renderAppForm(app) {
  const editorPanel=panel,version=++appEditorVersion;
  const scope=editorScope,key=vaultKey;
  const submitLabel=app?'Сохранить':scope==='private'?'Добавить на приватный стол':'Добавить на рабочий стол';
  const selectedIcon=normalizeShortcutIconStyle(app?.iconStyle);
  const siteArtwork=/^data:image\/png;base64,/i.test(app?.iconUrl||'')?'<img src="'+escape(app.iconUrl)+'" alt="">':brand({...app,id:app?.id||'site-preview',name:app?.name||'Сайт',iconStyle:'site'});
  const iconChoices='<fieldset class="shortcut-icon-picker"><legend>Иконка ярлыка</legend><div class="shortcut-icon-options">'+SHORTCUT_ICON_CHOICES.map(choice=>'<label class="shortcut-icon-option"><input type="radio" name="iconStyle" value="'+choice.id+'" '+(selectedIcon===choice.id?'checked':'')+'><span class="shortcut-icon-art">'+(choice.id==='site'?siteArtwork:shortcutIconArtwork(choice.id))+'</span><span>'+choice.label+'</span></label>').join('')+'</div></fieldset>';
  const messageChoice=`<label class="message-choice" id="message-choice" hidden><input type="checkbox" name="messageNotifications" ${!app||messagesEnabled(app)?'checked':''}><span><strong>Счётчик сообщений</strong><small>Появится, пока ATMA открыт и сайт показывает число у сообщений. Текст переписки не передаётся.</small></span></label>`;
  $('sheet-content').innerHTML = `<form id="app-form"><label class="field">Название<input name="name" aria-label="Название приложения" maxlength="36" placeholder="Например, мой банк" value="${escape(app?.name || '')}" required></label><label class="field">Адрес сайта<input name="url" aria-label="Адрес приложения" placeholder="https://example.com" value="${escape(app?.url || '')}" required autocomplete="off"></label>${iconChoices}${messageChoice}<button class="primary-button" type="submit">${submitLabel}</button></form>`;
  const urlInput=$('app-form').elements.namedItem('url'),messageToggle=$('app-form').elements.namedItem('messageNotifications');
  const updateMessageChoice=()=>{const raw=urlInput.value.trim(),value=/^[a-z][\w+.-]*:/i.test(raw)?raw:`https://${raw}`;const supported=scope==='public'&&Boolean(messageProvider(value));$('message-choice').hidden=!supported;messageToggle.disabled=!supported;};
  urlInput.addEventListener('input',updateMessageChoice);updateMessageChoice();
  $('app-form').addEventListener('submit', async event => {
    event.preventDefault(); reportError(''); const form = new FormData(event.currentTarget); let url;
    try { const raw = String(form.get('url')).trim(); url = new URL(/^[a-z][\w+.-]*:/i.test(raw) ? raw : `https://${raw}`); if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error(); }
    catch { return reportError('Введите корректный адрес http или https'); }
    const name=String(form.get('name')).trim();if(!name)return reportError('Введите название приложения');
    const submit=event.currentTarget.querySelector?.('[type="submit"]');
    if(submit?.disabled)return;if(submit){submit.disabled=true;submit.textContent='Сохраняю…';}
    const iconStyle=normalizeShortcutIconStyle(form.get('iconStyle')),sameURL=app?.url===url.href;
    const iconUrl=iconStyle==='site'?await resolveShortcutIcon({url:url.href,iconUrl:sameURL?app.iconUrl:''}):sameURL?app.iconUrl||'':'';
    if(panel!==editorPanel||version!==appEditorVersion||scope==='private'&&(!vaultKey||vaultKey!==key))return;
    const entry = { ...app, iconUrl, iconStyle, id: app?.id || `custom-${crypto.randomUUID()}`, name, url: url.href, color: app?.color || '#337b96', custom: Boolean(app?.custom||!app||!sameURL), messageNotifications: scope==='public'&&Boolean(messageProvider(url.href)&&form.get('messageNotifications')) };
    delete entry.profileId;
    if (!entry.name) return;
    const pool=poolFor(scope);
    if (app) { const found=findEntry(pool,app.id); if(found) found.list.splice(found.index,1,{...entry,slots:app.slots}); } else pool.push(entry);
    try{await saveApps(scope,{layoutChanged:!app});if(panel===editorPanel&&version===appEditorVersion)await setPanel(null);}catch(error){reportError(error.message);}finally{if(submit){submit.disabled=false;submit.textContent=submitLabel;}}
  });
  if(app) $('sheet-content').append(settingButton(editorScope==='private'?'Вернуть на обычную страницу':'Перенести на закрытую страницу','lock',async()=>{
    if(editorScope==='private') {
      apps.push(detachFromLayout(app));await saveApps();vaultApps=removeEntry(vaultApps,app.id);await saveApps('private');await setPanel(null);showDesktopPage(0);
    } else {pendingVaultMove=app.id;if(vaultKey)await finishVaultUnlock();else requestVault();}
  }));
}
async function openAppEditor(app,scope='public') { editorScope=scope;await setPanel('edit');renderAppForm(app); }
async function requestVault() {
  if(panel==='pin'&&(pinBusy||pinSetup==='biometry'))return;
  if(vaultKey){
    try{await finishVaultUnlock();}catch(error){reportError(error.message);}
    return;
  }
  pinDigits='';firstPin=null;enableBiometryAfterPIN=false;
  const unavailable={available:false,kind:'none'};
  biometricStatus=unavailable;
  pinSetup=!vaultRecord?'choice':vaultRecord.biometric&&vaultRecord.vaultId?'biometry':'unlock';
  const epoch=++pinEpoch,openPanel=setPanel('pin');
  const status=await api('vault/biometry/status').catch(()=>unavailable);
  await openPanel;
  if(epoch!==pinEpoch||panel!=='pin')return;
  biometricStatus=status;
  if(pinSetup==='biometry'){
    if(status.available)return unlockWithBiometry();
    pinSetup='unlock';
  }
  renderPIN();
  if(vaultRecord?.auth==='biometric'&&!status.available)reportError('Не удалось войти по биометрии');
}
const biometricName=()=>biometricStatus.kind==='touchID'?'Touch ID':'Face ID';
function renderPIN() {
  $('sheet-title').textContent='Приватный стол';
  const creating=!vaultRecord,biometricOnly=vaultRecord?.auth==='biometric';
  const artwork=`<div class="pin-lock">${brand({id:'atma-private-desktop'})}</div>`;
  const biometricText=key=>escape(localization.t(key,{method:biometricName()}));
  if(pinSetup==='biometry'){
    $('sheet-content').innerHTML=`${artwork}<h2>Приватный стол</h2><p class="pin-subtitle" role="status">Ожидание биометрии…</p><div class="vault-choices"><button data-pin="cancel" ${pinBusy?'disabled':''}>Отмена</button></div>`;
    document.querySelector('[data-pin="cancel"]').addEventListener('click',()=>pinKey('cancel'));
    return;
  }
  if(creating&&pinSetup==='choice'){
    $('sheet-content').innerHTML=`${artwork}<h2>Приватный стол</h2><p class="pin-subtitle">Выберите способ входа</p><div class="vault-choices"><button data-vault-choice="pin" ${pinBusy?'disabled':''}>Код из 6 цифр</button>${biometricStatus.available?`<button data-vault-choice="biometric" ${pinBusy?'disabled':''}>${biometricName()}</button><button data-vault-choice="both" ${pinBusy?'disabled':''}>${biometricText('Код и {method}')}</button>`:''}<button data-vault-choice="cancel" ${pinBusy?'disabled':''}>Отмена</button></div><p class="pin-note">Замок скрывает ярлыки, но не историю и входы на сайты. При входе только по биометрии ключ нельзя перенести на другое устройство.</p>`;
    for(const button of document.querySelectorAll('[data-vault-choice]'))button.addEventListener('click',()=>{
      if(pinBusy)return;
      const choice=button.dataset.vaultChoice;
      if(choice==='cancel'){setPanel(null);return;}
      if(choice==='biometric'){createBiometricVault();return;}
      pinSetup=choice;renderPIN();
    });
    return;
  }
  if(biometricOnly){
    $('sheet-content').innerHTML=`${artwork}<h2>Приватный стол</h2><p class="pin-subtitle">${biometricText('Вход через {method}')}</p><div class="vault-choices"><button data-vault-biometry ${!biometricStatus.available||pinBusy?'disabled':''}>${biometricText('Открыть через {method}')}</button><button data-pin="cancel">Отмена</button></div><p class="pin-note">Если биометрия изменена или код устройства отключён, ключ на этом устройстве станет недоступен.</p>`;
  }else{
    const title=creating?(firstPin?'Повторите код':'Придумайте код'):'Введите код';
    $('sheet-content').innerHTML=`${artwork}<h2>${title}</h2><p class="pin-subtitle">6 цифр для приватного стола</p><div class="pin-dots" aria-label="Введено ${pinDigits.length} из 6 цифр">${Array.from({length:6},(_,i)=>`<i class="${i<pinDigits.length?'filled':''}"></i>`).join('')}</div><div class="pin-keypad">${['1','2','3','4','5','6','7','8','9','cancel','0','back'].map(digit=>`<button data-pin="${digit}" ${pinBusy?'disabled':''} class="${digit.length>1?'pin-small':''}">${digit==='cancel'?'Отмена':digit==='back'?'⌫':digit}</button>`).join('')}</div>${!creating&&vaultRecord?.biometric&&biometricStatus.available?`<button class="vault-biometry-link" data-vault-biometry>${biometricText('Открыть через {method}')}</button>`:''}${!creating&&!vaultRecord?.biometric&&biometricStatus.available?`<label class="vault-biometry-optin"><input type="checkbox" id="vault-enable-biometry" ${enableBiometryAfterPIN?'checked':''}> ${biometricText('Включить {method} после ввода кода')}</label>`:''}<p class="pin-note">${creating?'Код нельзя восстановить. ':''}Входы на сайты хранятся отдельно в браузере.</p>`;
  }
  for(const button of document.querySelectorAll('[data-pin]'))button.addEventListener('click',()=>pinKey(button.dataset.pin));
  document.querySelector('[data-vault-biometry]')?.addEventListener('click',unlockWithBiometry);
  document.getElementById('vault-enable-biometry')?.addEventListener('change',event=>{enableBiometryAfterPIN=event.target.checked;});
}
function pinKey(value) {
  if(pinBusy)return;
  if(value==='cancel'){setPanel(null);return;}
  if(pinSetup==='choice'||pinSetup==='biometry'||vaultRecord?.auth==='biometric')return;
  if(value==='back')pinDigits=pinDigits.slice(0,-1);
  else if(/^\d$/.test(value)&&pinDigits.length<6)pinDigits+=value;
  renderPIN();if(pinDigits.length===6)submitPIN();
}
async function submitPIN() {
  const epoch=pinEpoch,pin=pinDigits;pinBusy=true;renderPIN();
  try {
    let throttle;try{throttle=JSON.parse(localStorage.getItem('atma-preview-vault-throttle'))}catch{}
    if(throttle?.until>Date.now())throw new Error(`Повторите через ${Math.ceil((throttle.until-Date.now())/1000)} сек.`);
    if(!vaultRecord) {
      if(!firstPin){firstPin=pin;pinDigits='';pinBusy=false;renderPIN();return;}
      if(pin!==firstPin){firstPin=null;throw new Error('Коды не совпали. Придумайте код ещё раз');}
      const created=await createVault(pin,[]);if(epoch!==pinEpoch)return;
      if(pinSetup==='both'){
        const vaultId=crypto.randomUUID(),secret=await pinVaultSecret(pin,created.record);
        await api('vault/biometry/enroll',{vaultId,secret});if(epoch!==pinEpoch)return;
        created.record={...created.record,vaultId,biometric:true};
      }
      localStorage.setItem('atma-preview-vault',JSON.stringify(created.record));vaultRecord=created.record;vaultKey=created.key;vaultApps=[];
    } else {
      let opened;
      try{opened=await openVault(pin,vaultRecord);}catch {
        if(epoch!==pinEpoch)return;
        const attempts=(throttle?.attempts||0)+1;localStorage.setItem('atma-preview-vault-throttle',JSON.stringify({attempts:attempts>=3?0:attempts,until:attempts>=3?Date.now()+30000:0}));throw new Error(attempts>=3?(vaultRecord.biometric&&biometricStatus.available?'Неверный код. Попробуйте Face ID/Touch ID или подождите 30 сек.':'Слишком много попыток. Подождите 30 сек.'):'Неверный код');
      }
      if(epoch!==pinEpoch)return;vaultKey=opened.key;vaultApps=collapseSingletonFolders(opened.items);
      if(vaultApps.length!==opened.items.length)await saveApps('private',{render:false});
      if(enableBiometryAfterPIN&&biometricStatus.available&&!vaultRecord.biometric){
        const vaultId=crypto.randomUUID(),secret=await pinVaultSecret(pin,vaultRecord);
        try{await api('vault/biometry/enroll',{vaultId,secret});if(epoch!==pinEpoch)return;
          vaultRecord={...vaultRecord,vaultId,biometric:true};localStorage.setItem('atma-preview-vault',JSON.stringify(vaultRecord));
        }catch(error){reportError(error.message);}
      }
    }
    localStorage.removeItem('atma-preview-vault-throttle');pinDigits='';firstPin=null;await finishVaultUnlock();
  } catch(error){if(epoch===pinEpoch){pinDigits='';reportError(error.message);}}
  finally{if(epoch===pinEpoch){pinBusy=false;if(panel==='pin')renderPIN();}}
}
async function createBiometricVault(){
  if(pinBusy||vaultRecord||!biometricStatus.available)return;
  const epoch=pinEpoch;pinBusy=true;renderPIN();
  try{
    const vaultId=crypto.randomUUID(),secret=randomVaultSecret();
    await api('vault/biometry/enroll',{vaultId,secret});if(epoch!==pinEpoch)return;
    const created=await createVaultWithSecret(secret,[],vaultId);if(epoch!==pinEpoch)return;
    localStorage.setItem('atma-preview-vault',JSON.stringify(created.record));
    vaultRecord=created.record;vaultKey=created.key;vaultApps=[];await finishVaultUnlock();
  }catch(error){if(epoch===pinEpoch)reportError(error.message);}
  finally{if(epoch===pinEpoch){pinBusy=false;if(panel==='pin')renderPIN();}}
}
async function unlockWithBiometry(){
  if(pinBusy||!vaultRecord?.biometric||!vaultRecord.vaultId||!biometricStatus.available)return;
  const epoch=pinEpoch;pinSetup='biometry';pinBusy=true;renderPIN();
  try{
    const {secret}=await api('vault/biometry/unlock',{vaultId:vaultRecord.vaultId});if(epoch!==pinEpoch)return;
    await vaultWrite.catch(()=>{});if(epoch!==pinEpoch)return;
    const opened=await openVaultWithSecret(secret,vaultRecord);if(epoch!==pinEpoch)return;
    vaultKey=opened.key;vaultApps=collapseSingletonFolders(opened.items);pinDigits='';firstPin=null;
    if(vaultApps.length!==opened.items.length)await saveApps('private',{render:false});
    localStorage.removeItem('atma-preview-vault-throttle');await finishVaultUnlock();
  }catch{
    if(epoch!==pinEpoch)return;
    pinSetup='unlock';
    reportError('Не удалось войти по биометрии');
  }
  finally{if(epoch===pinEpoch){pinBusy=false;if(panel==='pin')renderPIN();}}
}
async function finishVaultUnlock() {
  const key=vaultKey,site=pendingVaultSite;
  clearTimeout(pageLockTimer);
  autoLockAfter=Date.now()+700;
  pendingVaultSite=null;
  if(site){
    await setPanel(null);
    if(vaultKey===key){resetVaultIdle();await saveCurrentSite(site);}
    return;
  }
  if(pendingVaultMove) {
    const found=findEntry(apps,pendingVaultMove);
    if(found){vaultApps.push(detachFromLayout(found.entry));await saveApps('private');apps=removeEntry(freezeSlots(apps,gridMetrics().columns),pendingVaultMove);await saveApps();}
    pendingVaultMove=null;
  }
  const showHome=document.body.dataset.surface!=='home';
  await setPanel(null,{keepVaultAction:true});
  if(showHome){await action('home');chooseDesktopSurface(state.activeTabId);$('address').value='';}
  if(vaultKey!==key)return;
  desktopPage=privatePageStart;renderApps();resetVaultIdle();
  if(pendingVaultAdd){pendingVaultAdd=false;editorScope='private';await setPanel('add');}
}
function detachFromLayout(app) {
  const entry=structuredClone(app);
  delete entry.dockSlot;
  entry.slots={};
  return entry;
}
function lockVault() {
  if(!vaultKey)return;
  vaultKey=null;vaultApps=[];clearTimeout(vaultIdleTimer);
  for(const page of $('apps').querySelectorAll('.private-page'))page.remove();
  if($('desktop-dock').dataset.scope==='private')renderDesktopDock('public');
  if($('desktop-focus-dock').dataset.scope==='private'){
    $('desktop-suggested-apps').replaceChildren();
    closeDesktopSearch();
    $('address').value='';
    $('address').dispatchEvent(new Event('input',{bubbles:true}));
  }
  if(gesture?.scope==='private'){clearTimeout(gesture.hold);clearTimeout(gesture.hoverTimer);clearTimeout(gesture.pageTimer);gesture.ghost?.remove();gesture=null;}
  if((panel==='folder'&&folderScope==='private')||(panel==='edit'&&editorScope==='private')||(panel==='add'&&editorScope==='private'))setPanel(null,{immediate:true});
  renderApps();
}
function resetVaultIdle(){clearTimeout(vaultIdleTimer);if(vaultKey)vaultIdleTimer=setTimeout(lockVault,60000);}
for(const name of ['pointerdown','keydown'])document.addEventListener(name,resetVaultIdle,{passive:true});
document.addEventListener('visibilitychange',()=>{if(document.hidden)lockVault();});
$('lock-private').addEventListener('click',lockVault);
window.addEventListener('storage',event=>{
  if(event.key===APPEARANCE_KEY){appearance=parseAppearance(event.newValue);applyAppearance();renderApps();if(panel==='folder')renderFolder();if(panel==='appearance')updateAppearanceControls();if(panel==='app-icon')renderAppIconPicker();}
  if(event.key==='atma-preview-apps'&&event.newValue&&!gesture){try{apps=JSON.parse(event.newValue);renderApps();updateQuickAdd();}catch{}}
  if(event.key==='atma-preview-vault'){try{vaultRecord=JSON.parse(event.newValue);}catch{}lockVault();pinEpoch++;firstPin=null;pinDigits='';pinBusy=false;if(panel==='pin')renderPIN();}
  if(event.key==='atma-preview-page-count'){publicPages=Math.max(2,Number(event.newValue)||2);renderApps();}
});
$('address-form').addEventListener('submit', event => {
  event.preventDefault(); const value = $('address').value.trim(); if (!value) return;
  const scope=currentScope(),matching=document.body.dataset.surface==='home'?flattenApps(poolFor(scope)).find(app=>[app.name,appLabel(app)].some(name=>name.toLocaleLowerCase()===value.toLocaleLowerCase())):null;
  if(matching)activate(matching,scope);else launch(value,scope);
});
function holdSubmitLayout(input,button,className){
  let timer,touchSubmitted=false;
  const release=()=>{clearTimeout(timer);touchSubmitted=false;document.body.classList.remove(className);};
  button.addEventListener('pointerdown',event=>{
    if(document.activeElement!==input)return;
    document.body.classList.add(className);
    clearTimeout(timer);timer=setTimeout(release,1500);
    // The native keyboard can start closing before click and move the whole WebKit viewport.
    // Submit on the touch start while the button is still in its original position.
    if(event.pointerType==='touch'){
      event.preventDefault();touchSubmitted=true;button.form.requestSubmit(button);
    }
  });
  button.addEventListener('mousedown',event=>{if(document.activeElement===input)event.preventDefault();});
  button.addEventListener('pointercancel',release);
  button.addEventListener('click',event=>{if(touchSubmitted)event.preventDefault();setTimeout(release,0);});
}
holdSubmitLayout($('address'),$('address-go'),'address-submit-hold');
holdSubmitLayout($('incognito-address'),$('incognito-form').querySelector('button[type=submit]'),'incognito-submit-hold');
selectAddressOnFirstTap($('address'), $('address-clear'));
selectAddressOnFirstTap($('incognito-address'), $('incognito-address-clear'));
for (const [inputId, listId] of [['address','address-suggestions'],['incognito-address','incognito-suggestions']]) {
  let editingTabID;
  const reset = installAddressSuggestions($(inputId), $(listId), {
    suggest: value => {
      const entries=document.body.dataset.surface==='home'?poolFor(currentScope()):apps;
      return addressSuggestions(value,state,flattenApps(entries).filter(app=>app.type!=='system'));
    },
    searchLabel: value => localization.t('Искать «{value}»',{value}),
    select: result => {
      const scope=state?.mode==='home'&&document.body.dataset.surface==='home'?currentScope():'public';
      if (result.kind === 'tab') selectBrowserTab(result.entry.id);
      else if (result.kind === 'shortcut') launchShortcut(result.entry,scope);
      else launch(result.query,scope);
    },
    editing: editing => {
      if (editing) editingTabID = state?.activeTabId;
      if (editingTabID && window.webkit?.messageHandlers?.atma) {
        api('address/editing', {tabID:editingTabID, editing}).catch(() => {});
      }
    },
  });
  document.addEventListener('atma-address-context-change', reset);
}
$('incognito-form').addEventListener('submit',event=>{event.preventDefault();const value=$('incognito-address').value.trim();if(!value)return;$('incognito-address').blur();$('incognito-address').value='';launch(value,'public',{webApp:false});});
$('end-incognito').addEventListener('click',async()=>{try{await action('tabs/private/close');chooseDesktopSurface(state.activeTabId);$('incognito-address').value='';}catch{}});
$('address').addEventListener('input', () => { if (document.body.hasAttribute('data-desktop-search')) renderDesktopQuickAccess(); });
$('settings').addEventListener('click', () => setPanel(document.body.dataset.surface==='home'?'desktop-menu':'settings'));
$('pin-site').addEventListener('click',()=>saveCurrentSite());
$('tabs-button').addEventListener('click',()=>{setEditing(false);lockVault();if(state?.tabs?.length)setPanel('tabs');else newBrowserTab();});
$('new-tab-button').addEventListener('click',newBrowserTab);
$('edit-apps').addEventListener('click', () => setEditing(!editing));
let emptyHomeTap=null,emptyHomeHold=null;
const emptyHomeTarget=target=>target instanceof Element&&target.closest('.home')&&!target.closest('.app-item,button,input,select,a,label');
const cancelEmptyHomeHold=()=>{clearTimeout(emptyHomeHold);emptyHomeHold=null;emptyHomeTap=null;};
document.querySelector('.home').addEventListener('pointerdown',event=>{
  cancelEmptyHomeHold();
  if(!event.isPrimary||event.button!==0||panel||gesture||!emptyHomeTarget(event.target))return;
  const press=emptyHomeTap={id:event.pointerId,x:event.clientX,y:event.clientY,wasEditing:editing,held:false};
  if(!editing)emptyHomeHold=setTimeout(()=>{
    if(emptyHomeTap!==press||panel||gesture)return;
    press.held=true;setEditing(true);suppressClickUntil=Date.now()+500;
  },DESKTOP_HOLD_MS);
});
document.addEventListener('pointermove',event=>{
  if(emptyHomeTap&&event.pointerId===emptyHomeTap.id&&Math.hypot(event.clientX-emptyHomeTap.x,event.clientY-emptyHomeTap.y)>7)cancelEmptyHomeHold();
});
document.addEventListener('pointerup',event=>{
  const tap=emptyHomeTap;cancelEmptyHomeHold();
  if(tap&&event.pointerId===tap.id&&tap.wasEditing&&!tap.held&&editing&&!panel&&!gesture&&emptyHomeTarget(event.target)&&Math.hypot(event.clientX-tap.x,event.clientY-tap.y)<=7)setEditing(false);
});
document.addEventListener('pointercancel',cancelEmptyHomeHold);
$('go-home').addEventListener('click', async () => { try {lockVault();desktopPage=0;await action('home');chooseDesktopSurface(state.activeTabId);$('address').value='';renderApps();showDesktopPage(0);} catch {} });
let privateDeviceTouchOpened=false;
const openPrivateDeviceChooser=()=>{$('incognito-address').blur();setPanel('private-device');};
$('incognito-device').addEventListener('pointerdown',event=>{
  if(event.pointerType!=='touch'||document.activeElement!==$('incognito-address'))return;
  // The keyboard moves this button before a touch click can reach it.
  event.preventDefault();privateDeviceTouchOpened=true;openPrivateDeviceChooser();
  setTimeout(()=>{privateDeviceTouchOpened=false;},500);
});
$('incognito-device').addEventListener('click',event=>{
  if(privateDeviceTouchOpened){event.preventDefault();privateDeviceTouchOpened=false;return;}
  openPrivateDeviceChooser();
});
$('go-back').addEventListener('click', () => action('back').catch(() => {}));
$('go-forward').addEventListener('click', () => action('forward').catch(() => {}));
$('share-page').addEventListener('click', async () => {
  const url=normalizedSiteUrl(state?.url);
  if (!url || state.mode!=='browse' || state.canGoForward) return;
  try {
    if (window.webkit?.messageHandlers?.atma) await api('share-page');
    else if (navigator.share) await navigator.share({url});
    else await navigator.clipboard.writeText(url);
  } catch (error) { if (error.name!=='AbortError') reportError('Не удалось поделиться ссылкой'); }
});
$('refresh').addEventListener('click', () => action('refresh').catch(() => {}));
$('show-original').addEventListener('click', () => action('translation/toggle').catch(() => reportError('Не удалось запустить перевод страницы')));
$('scrim').addEventListener('click', () => setPanel(null)); $('sheet-close').addEventListener('click', () => setPanel(null));
document.addEventListener('keydown', event => {
  if(panel==='pin'&&(/^\d$/.test(event.key)||event.key==='Backspace')){event.preventDefault();pinKey(event.key==='Backspace'?'back':event.key);return;}
  if(event.key==='Escape'){if(panel)setPanel(null);else if(editing)setEditing(false);}
});
window.addEventListener('message', event => { if (event.source === parent && event.data?.type === 'atma-state' && event.data.state.id === context) consume(event.data.state); });
window.addEventListener('atma-native-state',event=>{if(window.webkit?.messageHandlers?.atma)consume(event.detail);});
window.addEventListener('languagechange',()=>{
  if(localization.updateSystem(state?.preferredLanguages||navigator.languages)){
    renderApps();
    if(panel)renderPanel();
    syncPageTranslationLanguage();
  }
});

function syncPageTranslationLanguage() {
  if (state?.capabilities?.pageTranslation) {
    return api('translation/language', {language:localization.language}).catch(() => {});
  }
}

async function shellStylesReady() {
  const styles = [...document.querySelectorAll('link[rel="stylesheet"]')];
  const loaded = () => styles.length > 0 && styles.every(link => link.sheet?.cssRules.length > 0);
  if (!loaded() && document.readyState !== 'complete') {
    await new Promise(resolve => window.addEventListener('load', resolve, {once:true}));
  }
  return loaded();
}

async function start() {
  const attemptID = query.get('startup');
  applyAppearance();
  if (wallpaper === 'custom') {
    wallpaperDB().then(db => {
      const request = db.transaction('preferences').objectStore('preferences').get('wallpaper');
      request.onsuccess = () => {
        if (wallpaper === 'custom' && request.result && !customWallpaperURL) {
          customWallpaperURL = URL.createObjectURL(request.result);
          applyWallpaper();
        }
      };
      db.close();
    }).catch(() => {});
  }
  renderApps();
  try {
    const version = stateActionVersion;
    const next = await api('state');
    if (version === stateActionVersion) consume(next);
    if (attemptID && window.webkit?.messageHandlers?.atma && document.body.dataset.mode) {
      await api('ui/ready', {attemptID, stylesReady:await shellStylesReady()});
    }
    await api('preferences', {searchEngine});
    await syncPageTranslationLanguage();
  }
  catch (error) { reportError(error.message); }
  setInterval(async () => { const version=stateActionVersion;try { const next=await api('state');if(version===stateActionVersion)consume(next); } catch {} }, 1000);
  setInterval(pollMessageBadges,30000);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)scheduleMessageBadgePoll();});
}
start();
