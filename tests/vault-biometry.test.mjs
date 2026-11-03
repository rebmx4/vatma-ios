import test from 'node:test';
import assert from 'node:assert/strict';
import {createVault,createVaultWithSecret,openVault,openVaultWithSecret,pinVaultSecret,randomVaultSecret,sealVault} from '../BrowserUI/vault.js';

test('an existing PIN vault opens through its derived key and retains biometric metadata after saving',async()=>{
  const created=await createVault('123456',[{id:'site'}]);
  const id='80677047-a5fe-42c0-8590-f123bf27c6f9';
  const secret=await pinVaultSecret('123456',created.record);
  const upgraded={...created.record,vaultId:id,biometric:true};
  assert.deepEqual((await openVaultWithSecret(secret,upgraded)).items,[{id:'site'}]);
  const saved=await sealVault(created.key,[{id:'site'},{id:'new'}],upgraded);
  assert.equal(saved.vaultId,id);
  assert.equal(saved.biometric,true);
  assert.deepEqual((await openVault('123456',saved)).items,[{id:'site'},{id:'new'}]);
});

test('a biometric-only vault cannot be unlocked with a PIN',async()=>{
  const secret=randomVaultSecret(),id='285b4ee2-0300-4247-a7d4-931ce317156e';
  const created=await createVaultWithSecret(secret,[{id:'secret'}],id);
  assert.deepEqual((await openVaultWithSecret(secret,created.record)).items,[{id:'secret'}]);
  await assert.rejects(openVault('123456',created.record),/Face ID/);
});
