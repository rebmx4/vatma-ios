import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

test('three wrong PINs throttle further PIN attempts and offer enrolled biometrics',async()=>{
  const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');
  const start=source.indexOf('async function submitPIN()'),end=source.indexOf('async function createBiometricVault()',start);
  assert.ok(start>0&&end>start);
  const saved=new Map(),notices=[];let attempted=0;
  const context={pinEpoch:1,pinDigits:'123456',pinBusy:false,firstPin:null,
    vaultRecord:{biometric:true},biometricStatus:{available:true},renderPIN(){},
    localStorage:{getItem:key=>saved.get(key)||null,setItem:(key,value)=>saved.set(key,value),removeItem:key=>saved.delete(key)},
    openVault:async()=>{attempted++;throw new Error('bad key');},notify:message=>notices.push(message),
    panel:'pin',Date,Math};
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  for(let i=0;i<4;i++){context.pinDigits='123456';await context.submitPIN();}
  assert.equal(attempted,3);
  assert.match(notices[2],/Face ID\/Touch ID/);
  assert.match(notices[3],/Повторите через/);
  assert.ok(JSON.parse(saved.get('atma-preview-vault-throttle')).until>Date.now());
});
