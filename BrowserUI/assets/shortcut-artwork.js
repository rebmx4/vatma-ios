export const SHORTCUT_ICON_CHOICES = Object.freeze([
 {id:'site',label:'Иконка сайта'},
 {id:'globe',label:'Глобус',color:'#24788c',shape:'<circle cx="31" cy="31" r="17"/><path d="M14 31h34M31 14c-10 9-10 25 0 34m0-34c10 9 10 25 0 34"/>'},
 {id:'chat',label:'Чат',color:'#087fff',shape:'<path d="M15 16h32v25H28l-11 7v-7h-2Z"/><path d="M23 25h16m-16 8h11"/>'},
 {id:'shopping',label:'Покупки',color:'#db7333',shape:'<path d="M17 24h28l3 24H14Z"/><path d="M24 27v-7a7 7 0 0 1 14 0v7"/>'},
 {id:'work',label:'Работа',color:'#5968af',shape:'<rect x="13" y="23" width="36" height="25" rx="4"/><path d="M24 23v-7h14v7M13 32l18 7 18-7m-18 4v7"/>'},
 {id:'heart',label:'Сердце',color:'#cd4776',shape:'<path d="M31 47 16 33C3 20 22 10 31 23c9-13 28-3 15 10Z"/>'},
 {id:'star',label:'Звезда',color:'#8a58ae',shape:'<path d="m31 12 6 13 14 2-10 10 2 15-12-7-12 7 2-15-10-10 14-2Z"/>'},
]);
export function normalizeShortcutIconStyle(value){return SHORTCUT_ICON_CHOICES.some(choice=>choice.id===value)?value:'site';}
export function shortcutIconArtwork(value){
 const choice=SHORTCUT_ICON_CHOICES.find(choice=>choice.id===value);if(!choice?.shape)return '';
 return '<svg viewBox="0 0 62 62" aria-hidden="true"><rect width="62" height="62" rx="15" fill="'+choice.color+'"/><g fill="none" stroke="white" stroke-width="2.6" stroke-linejoin="round" stroke-linecap="round">'+choice.shape+'</g></svg>';
}
