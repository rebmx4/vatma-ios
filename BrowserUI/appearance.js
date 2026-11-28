export const ICON_CHOICES=Object.freeze([
  {id:'default',label:'Основная'},
  ...Array.from({length:10},(_,index)=>({id:`a1-${String(index+1).padStart(2,'0')}`,label:String(index+1),x:12+(index%5)*304,y:164+Math.floor(index/5)*316,size:304})),
]);
export const APPEARANCE_KEY='atma-preview-appearance';
export const ACCENT_CHOICES=[
  ['Голубой','#68b7ff'],['Индиго','#444cc5'],['Сиреневый','#bba2cc'],['Розовый','#cc9ead'],
  ['Терракотовый','#cc9988'],['Персиковый','#c9aa86'],['Шалфейный','#9eaf95'],['Бирюзовый','#85b4ac'],
  ['Графитовый','#99a5b5'],['Красный ATMA','#e60218'],
];
export function accentColors(preference,theme) {
  const dark=theme==='dark';
  const base=preference==='auto'?(dark?'#444cc5':'#68b7ff'):preference;
  const rgb=base.slice(1).match(/../g).map(channel=>parseInt(channel,16));
  const luminance=rgb.reduce((sum,channel,i)=>{
    const s=channel/255;
    return sum+[.2126,.7152,.0722][i]*(s<=.04045?s/12.92:((s+.055)/1.055)**2.4);
  },0);
  const ink=rgb.map(channel=>Math.round(dark?channel*.48+255*.52:channel*.55).toString(16).padStart(2,'0')).join('');
  return {base,ink:'#'+ink,onBase:luminance>.179?'#111111':'#ffffff'};
}
export const WALLPAPERS = [
  {id:'auto', label:'Авто'},
  {id:'graphite', label:'Графит', image:'/assets/wallpapers/graphite.jpg', tone:'dark'},
  {id:'pearl', label:'Перламутр', image:'/assets/wallpapers/pearl.jpg', tone:'light'},
  {id:'slate-blue', label:'Синий сланец', image:'/assets/wallpapers/slate-blue.jpg', tone:'light'},
  {id:'indigo', label:'Индиго', image:'/assets/wallpapers/indigo.jpg', tone:'dark'},
  {id:'eucalyptus', label:'Эвкалипт', image:'/assets/wallpapers/eucalyptus.jpg', tone:'dark'},
  {id:'sandstone', label:'Песчаник', image:'/assets/wallpapers/sandstone.jpg', tone:'light'},
  {id:'solid', label:'Однотонный'},
  {id:'landscape', label:'Каньон', image:'/assets/landscape.svg'},
  {id:'north', label:'Север', image:'/assets/north.svg'},
  {id:'night', label:'Ночь', image:'/assets/night.svg'},
];
export function wallpaperForTheme(id, theme) {
  const resolved = id === 'auto' ? (theme === 'dark' ? 'graphite' : 'pearl') : id;
  return WALLPAPERS.find(wallpaper => wallpaper.id === resolved);
}
export function normalizeAppearance(value) {
  const source=value&&typeof value==='object'&&!Array.isArray(value)?value:{};
  const number=Number(source.textSize??100);
  return {
    showDock:source.showDock!==false,
    accent:typeof source.accent==='string'&&/^#[0-9a-f]{6}$/i.test(source.accent)?source.accent.toLowerCase():'auto',
    theme:['auto','light','dark'].includes(source.theme)?source.theme:'auto',
    textSize:Number.isFinite(number)?Math.min(130,Math.max(85,Math.round(number/5)*5)):100,
    icon:ICON_CHOICES.some(icon=>icon.id===source.icon)?source.icon:'default',
  };
}
export function parseAppearance(value) {
  try{return normalizeAppearance(JSON.parse(value));}catch{return normalizeAppearance();}
}
export function resolveTheme(mode,systemDark) {
  return mode==='light'?'light':mode==='dark'?'dark':systemDark?'dark':'light';
}
export function appIconArtwork(id,baseLogo) {
  const choice=ICON_CHOICES.find(icon=>icon.id===id)||ICON_CHOICES[0];
  if(choice.id==='default')return `<svg viewBox="0 0 62 62" data-atma-icon="default" aria-hidden="true"><rect width="62" height="62" rx="15" fill="white"/><image href="${baseLogo}" x="4" y="4" width="54" height="54" preserveAspectRatio="xMidYMid meet"/></svg>`;
  return `<svg viewBox="${choice.x} ${choice.y} ${choice.size} ${choice.size}" data-atma-icon="${choice.id}" aria-hidden="true"><image href="/assets/atma-icons-a1.png" width="1536" height="1024"/></svg>`;
}
