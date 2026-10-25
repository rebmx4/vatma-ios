import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {summarizeObservation} from '../tools/notification-probe/probe.mjs';

const probePath=fileURLToPath(new URL('../tools/notification-probe/probe.mjs',import.meta.url));

test('provider report omits message content, cookies, credentials and full push endpoint',()=>{
  const raw={
    provider:'avito',origins:['https://www.avito.ru/profile?session=secret-query'],
    endpointAccepted:true,encoding:'aes128gcm',messageOnly:true,eventID:true,
    unreadUnit:'messages',authoritativeCount:true,revisionOrder:true,
    remoteReadSync:true,logoutSignal:true,revocation:true,
    evidence:['public-site-script','encrypted-delivery'],
    endpoint:'https://push.example/secret-endpoint',cookie:'secret-cookie',
    authorization:'secret-token',messageText:'secret-message',sender:'secret-sender',
  };
  const result=summarizeObservation(raw);
  assert.equal(result.provider,'avito');
  assert.deepEqual(result.origins,['https://www.avito.ru']);
  assert.equal(result.verdict,'prototype','a fixture cannot certify a production provider');
  assert.deepEqual(Object.keys(result),[
    'provider','origins','endpointAccepted','encoding','messageOnly','eventID','unreadUnit',
    'authoritativeCount','revisionOrder','remoteReadSync','logoutSignal','revocation',
    'evidence','verdict',
  ]);
  const serialized=JSON.stringify(result);
  for(const secret of ['secret-query','secret-endpoint','secret-cookie','secret-token','secret-message','secret-sender']){
    assert.equal(serialized.includes(secret),false,`leaked ${secret}`);
  }
});

test('unknown and unsupported signals never become a verified provider',()=>{
  const result=summarizeObservation({
    provider:'vk',origins:['https://m.vk.com/'],
    endpointAccepted:null,evidence:['official-schema','public-site-script'],
    unreadUnit:'dialogs',authoritativeCount:false,
  });
  assert.equal(result.verdict,'unknown');
  assert.equal(result.unreadUnit,'dialogs');
  assert.equal(result.authoritativeCount,false);
  assert.equal(result.messageOnly,null);
});

test('rejected endpoint blocks a provider even if a claimed count exists',()=>{
  const result=summarizeObservation({
    provider:'vk',origins:['https://vk.com/'],endpointAccepted:false,
    unreadUnit:'messages',authoritativeCount:true,evidence:['authenticated-subscription'],
  });
  assert.equal(result.verdict,'blocked');
});

test('probe CLI emits only the allowlisted JSON report',()=>{
  const input={provider:'avito',origins:['https://www.avito.ru/?private=secret-query'],
    endpointAccepted:true,evidence:['encrypted-delivery'],messageText:'secret-message'};
  const run=spawnSync(process.execPath,[probePath],{input:JSON.stringify(input),encoding:'utf8',env:process.env});
  assert.equal(run.status,0,run.stderr);
  assert.deepEqual(JSON.parse(run.stdout).origins,['https://www.avito.ru']);
  assert.equal((run.stdout+run.stderr).includes('secret-message'),false);
  assert.equal((run.stdout+run.stderr).includes('secret-query'),false);
});

test('probe CLI loads only its public fixtures without a shell pipe',()=>{
  for(const provider of ['vk','avito']){
    const run=spawnSync(process.execPath,[probePath,'--fixture',provider],{
      encoding:'utf8',env:process.env,
    });
    assert.equal(run.status,0,run.stderr);
    const report=JSON.parse(run.stdout);
    assert.equal(report.provider,provider);
    assert.equal(report.verdict,'unknown');
  }
  const rejected=spawnSync(process.execPath,[probePath,'--fixture','../private.json'],{
    encoding:'utf8',env:process.env,
  });
  assert.notEqual(rejected.status,0);
  assert.equal(rejected.stderr,'Invalid observation.\n');
});

test('unrelated or credentialed origins are excluded from a provider report',()=>{
  const result=summarizeObservation({provider:'avito',origins:[
    'https://user:password@www.avito.ru/path','https://evil.example/',
    'http://www.avito.ru/','https://www.avito.ru/inbox',
  ]});
  assert.deepEqual(result.origins,['https://www.avito.ru']);
});
