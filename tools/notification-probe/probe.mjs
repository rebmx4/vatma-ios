import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {readFile} from 'node:fs/promises';

const PROVIDER_HOSTS={
  vk:new Set(['vk.com','m.vk.com','vk.ru','m.vk.ru','web.vk.me']),
  avito:new Set(['avito.ru','www.avito.ru']),
};
const EVIDENCE=new Set([
  'official-schema','public-site-script','synthetic-local-test',
  'authenticated-subscription','encrypted-delivery','message-only-test',
  'read-sync-test','device-test',
]);

function knownOrigin(value,provider){
  try{
    const url=new URL(value);
    if(url.protocol!=='https:'||url.username||url.password||url.port||!PROVIDER_HOSTS[provider].has(url.hostname))return null;
    return url.origin;
  }catch{return null;}
}

const triState=value=>typeof value==='boolean'?value:null;

export function summarizeObservation(raw){
  if(!raw||typeof raw!=='object'||Array.isArray(raw)||!Object.hasOwn(PROVIDER_HOSTS,raw.provider)){
    throw new TypeError('Invalid provider observation');
  }
  const provider=raw.provider;
  const origins=[...new Set((Array.isArray(raw.origins)?raw.origins:[])
    .filter(value=>typeof value==='string').map(value=>knownOrigin(value,provider)).filter(Boolean))];
  const evidence=[...new Set((Array.isArray(raw.evidence)?raw.evidence:[])
    .filter(value=>typeof value==='string'&&EVIDENCE.has(value)))];
  const endpointAccepted=triState(raw.endpointAccepted);
  const verdict=endpointAccepted===false?'blocked':
    endpointAccepted===true&&evidence.includes('encrypted-delivery')?'prototype':'unknown';
  return {
    provider,
    origins,
    endpointAccepted,
    encoding:['aes128gcm','aesgcm'].includes(raw.encoding)?raw.encoding:null,
    messageOnly:triState(raw.messageOnly),
    eventID:triState(raw.eventID),
    unreadUnit:['messages','dialogs'].includes(raw.unreadUnit)?raw.unreadUnit:'unknown',
    authoritativeCount:triState(raw.authoritativeCount),
    revisionOrder:triState(raw.revisionOrder),
    remoteReadSync:triState(raw.remoteReadSync),
    logoutSignal:triState(raw.logoutSignal),
    revocation:triState(raw.revocation),
    evidence,
    verdict,
  };
}

async function main(){
  let input;
  if(process.argv.length===4&&process.argv[2]==='--fixture'&&['vk','avito'].includes(process.argv[3])){
    input=await readFile(new URL(`./fixtures/public-${process.argv[3]}.json`,import.meta.url));
  }else if(process.argv.length===2){
    const chunks=[];
    let size=0;
    for await(const chunk of process.stdin){
      size+=chunk.length;
      if(size>1024*1024)throw new Error('Observation too large');
      chunks.push(chunk);
    }
    input=Buffer.concat(chunks);
  }else{
    throw new Error('Invalid arguments');
  }
  if(input.length>1024*1024)throw new Error('Observation too large');
  const raw=JSON.parse(input.toString('utf8').replace(/^\uFEFF/,''));
  process.stdout.write(JSON.stringify(summarizeObservation(raw))+'\n');
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(()=>{process.stderr.write('Invalid observation.\n');process.exitCode=1;});
}
