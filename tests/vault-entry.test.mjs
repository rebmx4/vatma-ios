import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(new URL('../BrowserUI/app.js',import.meta.url),'utf8');

function vaultEntry({record,available=true,authenticate=async()=>({secret:'keychain-key'})}={}) {
  const requests=[],screens=[],errors=[];
  let opened=0;
  const context={
    vaultRecord:record,vaultKey:null,vaultWrite:Promise.resolve(),panel:null,pinBusy:false,pinEpoch:0,pinDigits:'',firstPin:null,
    enableBiometryAfterPIN:false,biometricStatus:null,pinSetup:'choice',
    async setPanel(panel){context.panel=panel;screens.push(context.pinSetup);},
    renderPIN(){screens.push(context.pinSetup);},
    async api(method,body){requests.push([method,body]);return method.endsWith('/status')?{available,kind:'faceID'}:authenticate();},
    openVaultWithSecret:async secret=>{assert.equal(secret,'keychain-key');return{key:{},items:[]};},
    collapseSingletonFolders:items=>items,localStorage:{removeItem(){}},
    async finishVaultUnlock(){opened++;context.panel=null;context.pinEpoch++;},
    reportError:error=>errors.push(error)
  };
  vm.createContext(context);
  for(const [from,to] of [['async function requestVault()', 'const biometricName='],['async function unlockWithBiometry()', 'async function finishVaultUnlock()']]){
    vm.runInContext(source.slice(source.indexOf(from),source.indexOf(to)),context);
  }
  return {context,requests,screens,errors,get opened(){return opened;}};
}

test('opening an enrolled private desktop immediately authenticates without showing a PIN',async()=>{
  for(const auth of [undefined,'biometric']){
    const entry=vaultEntry({record:{biometric:true,vaultId:'vault',auth}});
    await entry.context.requestVault();
    assert.deepEqual(entry.requests.map(([method])=>method),['vault/biometry/status','vault/biometry/unlock']);
    assert.equal(entry.requests[1][1].vaultId,'vault');
    assert.equal(entry.opened,1);
    assert.ok(entry.screens.every(screen=>screen==='biometry'));
  }
});

test('a PIN remains available after biometric cancellation, and a PIN-only vault never requests biometric unlock',async()=>{
  const enrolled=vaultEntry({record:{biometric:true,vaultId:'vault'},authenticate:async()=>{throw new Error('cancelled');}});
  await enrolled.context.requestVault();
  assert.equal(enrolled.context.pinSetup,'unlock');
  assert.equal(enrolled.context.pinBusy,false);
  assert.equal(enrolled.opened,0);
  const pinOnly=vaultEntry({record:{}});
  await pinOnly.context.requestVault();
  assert.equal(pinOnly.context.pinSetup,'unlock');
  assert.deepEqual(pinOnly.requests.map(([method])=>method),['vault/biometry/status']);
});

test('a biometric result that arrives after the unlock panel closes is discarded',async()=>{
  let reply,started;
  const requested=new Promise(resolve=>{started=resolve;});
  const entry=vaultEntry({record:{biometric:true,vaultId:'vault'},authenticate:()=>new Promise(resolve=>{reply=resolve;started();})});
  const pending=entry.context.requestVault();
  await requested;
  entry.context.panel=null;
  entry.context.pinEpoch++;
  reply({secret:'keychain-key'});
  await pending;
  assert.equal(entry.opened,0);
  assert.equal(entry.context.vaultKey,null);
});

test('three wrong PINs throttle further PIN attempts and offer enrolled biometrics',async()=>{
  const start=source.indexOf('async function submitPIN()'),end=source.indexOf('async function createBiometricVault()',start);
  assert.ok(start>0&&end>start);
  const saved=new Map(),notices=[];let attempted=0;
  const context={pinEpoch:1,pinDigits:'123456',pinBusy:false,firstPin:null,
    vaultRecord:{biometric:true},biometricStatus:{available:true},renderPIN(){},
    localStorage:{getItem:key=>saved.get(key)||null,setItem:(key,value)=>saved.set(key,value),removeItem:key=>saved.delete(key)},
    openVault:async()=>{attempted++;throw new Error('bad key');},reportError:message=>notices.push(message),
    panel:'pin',Date,Math};
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  for(let i=0;i<4;i++){context.pinDigits='123456';await context.submitPIN();}
  assert.equal(attempted,3);
  assert.match(notices[2],/Face ID\/Touch ID/);
  assert.match(notices[3],/Повторите через/);
  assert.ok(JSON.parse(saved.get('atma-preview-vault-throttle')).until>Date.now());
});
