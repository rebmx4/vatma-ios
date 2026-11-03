const ITERATIONS=600000;
const encode=bytes=>{let text='';for(let i=0;i<bytes.length;i+=4096)text+=String.fromCharCode(...bytes.subarray(i,i+4096));return btoa(text);};
const decode=value=>Uint8Array.from(atob(value),char=>char.charCodeAt(0));
async function deriveBytes(pin,salt) {
  if(!/^\d{6}$/.test(pin))throw new Error('Нужен код из 6 цифр');
  const material=await crypto.subtle.importKey('raw',new TextEncoder().encode(pin),'PBKDF2',false,['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',salt,iterations:ITERATIONS,hash:'SHA-256'},material,256));
}
const importSecret=secret=>crypto.subtle.importKey('raw',secret,{name:'AES-GCM'},false,['encrypt','decrypt']);
const derive=async(pin,salt)=>importSecret(await deriveBytes(pin,salt));
function validateRecord(record) {
  if(record?.version!==1||record.iterations!==ITERATIONS||typeof record.ciphertext!=='string'||record.ciphertext.length>2000000)throw new Error('Повреждённая закрытая страница');
  const salt=decode(record.salt),iv=decode(record.iv);
  if(salt.length!==16||iv.length!==12)throw new Error('Повреждённая закрытая страница');
  return{salt,iv};
}
export function randomVaultSecret(){return encode(crypto.getRandomValues(new Uint8Array(32)));}
export async function pinVaultSecret(pin,record){return encode(await deriveBytes(pin,validateRecord(record).salt));}
export async function createVault(pin,items) {
  const salt=crypto.getRandomValues(new Uint8Array(16)),key=await derive(pin,salt);
  return{key,record:await sealVault(key,items,{version:1,iterations:ITERATIONS,salt:encode(salt)})};
}
export async function openVault(pin,record) {
  if(record?.auth==='biometric')throw new Error('Для этого стола нужен Face ID');
  const {salt,iv}=validateRecord(record);
  const key=await derive(pin,salt);
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,decode(record.ciphertext));
  const items=JSON.parse(new TextDecoder().decode(plain));
  if(!Array.isArray(items))throw new Error('Повреждённая закрытая страница');
  return{key,items};
}
export async function createVaultWithSecret(encodedSecret,items,vaultId) {
  const secret=decode(encodedSecret);
  if(secret.length!==32)throw new Error('Неверный ключ приватного стола');
  const key=await importSecret(secret);
  const salt=crypto.getRandomValues(new Uint8Array(16));
  return{key,record:await sealVault(key,items,{version:1,iterations:ITERATIONS,salt:encode(salt),auth:'biometric',biometric:true,vaultId})};
}
export async function openVaultWithSecret(encodedSecret,record) {
  const {iv}=validateRecord(record),secret=decode(encodedSecret);
  if(secret.length!==32)throw new Error('Неверный ключ приватного стола');
  const key=await importSecret(secret);
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,decode(record.ciphertext));
  const items=JSON.parse(new TextDecoder().decode(plain));
  if(!Array.isArray(items))throw new Error('Повреждённая закрытая страница');
  return{key,items};
}
export async function sealVault(key,items,record) {
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify(items)));
  return{version:1,iterations:ITERATIONS,salt:record.salt,iv:encode(iv),ciphertext:encode(new Uint8Array(ciphertext)),...(record.vaultId?{vaultId:record.vaultId}:{}),...(record.biometric?{biometric:true}:{}),...(record.auth==='biometric'?{auth:'biometric'}:{})};
}
