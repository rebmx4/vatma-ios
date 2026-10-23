export const ICON_CHOICES=Object.freeze([
  {id:'default',label:'Основная'},
  ...Array.from({length:10},(_,index)=>({id:`a1-${String(index+1).padStart(2,'0')}`,label:String(index+1),x:12+(index%5)*304,y:164+Math.floor(index/5)*316,size:304})),
]);
export const APPEARANCE_KEY='atma-preview-appearance';
export function normalizeAppearance(value) {
  const source=value&&typeof value==='object'&&!Array.isArray(value)?value:{};
  const number=Number(source.textSize??100);
  return {
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
