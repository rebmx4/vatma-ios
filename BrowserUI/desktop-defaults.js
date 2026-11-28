import {DESKTOP_MARKETS} from './assets/desktop-markets.js';

const RUSSIAN_DESKTOP = [
  {id:'vk', name:'ВКонтакте', url:'https://vk.com/', color:'#087fff'},
  {id:'dzen', name:'Дзен', url:'https://dzen.ru/', color:'#1c1c1c'},
  {id:'vtb', name:'ВТБ', url:'https://online.vtb.ru/', color:'#0b48b2'},
  {id:'tbank', name:'Т-Банк', url:'https://www.tbank.ru/', color:'#ffdf00'},
  {id:'rutube', name:'RUTUBE', url:'https://rutube.ru/', color:'#111729', dockSlot:0},
  {id:'avito', name:'Авито', url:'https://www.avito.ru/', color:'#fff', dockSlot:1},
  {id:'youtube', name:'YouTube', url:'https://www.youtube.com/', color:'#fff', dockSlot:2},
  {id:'mail', name:'Почта Mail', url:'https://e.mail.ru/', color:'#087cf1', dockSlot:3},
];

const bundledArtwork = new Map(RUSSIAN_DESKTOP.map(({id,url})=>[id,{url,path:`/assets/desktop-icons/${id}.png`}]));
const regionalDesktops = Object.fromEntries(Object.entries(DESKTOP_MARKETS).map(([country,rows])=>[
  country, rows.map(([name,url,file],index)=>{
    const site=new URL(url).hostname.replace(/^www\./,'');
    const id=`regional-${country.toLowerCase()}-${site}`;
    bundledArtwork.set(id,{url,path:`/assets/regional-desktop-icons/${file}`});
    const app={id,name,url,color:'#fff'};
    if(index>=4)app.dockSlot=index-4;
    return app;
  }),
]));

function regionFromLocale(locale) {
  if(!locale)return undefined;
  try{return new Intl.Locale(locale.replaceAll('_','-')).region;}catch{return undefined;}
}

export function createInitialDesktop(deviceRegion, previewLocale) {
  const region=(deviceRegion||regionFromLocale(previewLocale))?.toUpperCase();
  const preset=region==='RU'?RUSSIAN_DESKTOP:Object.hasOwn(regionalDesktops,region)?regionalDesktops[region]:regionalDesktops.US;
  return preset.map(app=>({...app}));
}

const siteHost=url=>new URL(url).hostname.replace(/^www\./,'');
const artworkByHost=new Map(Array.from(bundledArtwork.values(),({url,path})=>[siteHost(url),path]));
for(const [mobile,desktop] of [['m.vk.com','vk.com'],['m.vk.ru','vk.com'],['vk.ru','vk.com'],['m.youtube.com','youtube.com']]){
  artworkByHost.set(mobile,artworkByHost.get(desktop));
}
export function bundledSiteArtwork(url) {
  try{return artworkByHost.get(siteHost(url))||'';}catch{return '';}
}

export function bundledShortcutArtwork(app) {
  const stock=bundledArtwork.get(app.artworkId||app.id);
  return !app.custom&&stock&&stock.url===app.url?stock.path:null;
}

export function hasTranslatedDesktopLabel(app) {
  return !app.custom&&RUSSIAN_DESKTOP.some(stock=>stock.id===(app.artworkId||app.id)&&stock.name===app.name&&stock.url===app.url);
}
