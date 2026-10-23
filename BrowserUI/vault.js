const ITERATIONS=600000;
const encode=bytes=>{let text='';for(let i=0;i<bytes.length;i+=4096)text+=String.fromCharCode(...bytes.subarray(i,i+4096));return btoa(text);};
const decode=value=>Uint8Array.from(atob(value),char=>char.charCodeAt(0));
async function derive(pin,salt) {
  if(!/^\d{6}$/.test(pin))throw new Error('Нужен код из 6 цифр');
  const material=await crypto.subtle.importKey('raw',new TextEncoder().encode(pin),'PBKDF2',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:ITERATIONS,hash:'SHA-256'},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export async function createVault(pin,items) {
  const salt=crypto.getRandomValues(new Uint8Array(16)),key=await derive(pin,salt);
  return{key,record:await sealVault(key,items,{version:1,iterations:ITERATIONS,salt:encode(salt)})};
}
export async function openVault(pin,record) {
  if(record?.version!==1||record.iterations!==ITERATIONS||typeof record.ciphertext!=='string'||record.ciphertext.length>2000000)throw new Error('Повреждённая закрытая страница');
  const salt=decode(record.salt),iv=decode(record.iv);
  if(salt.length!==16||iv.length!==12)throw new Error('Повреждённая закрытая страница');
  const key=await derive(pin,salt);
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,decode(record.ciphertext));
  const items=JSON.parse(new TextDecoder().decode(plain));
  if(!Array.isArray(items))throw new Error('Повреждённая закрытая страница');
  return{key,items};
}
export async function sealVault(key,items,record) {
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(items)));
  return{version:1,iterations:ITERATIONS,salt:record.salt,iv:encode(iv),ciphertext:encode(new Uint8Array(ciphertext))};
}
