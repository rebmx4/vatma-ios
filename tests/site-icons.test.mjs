import test from 'node:test';
import assert from 'node:assert/strict';
import {readSiteMetadata,resolveWebsiteIcon} from '../BrowserUI/assets/site-icons.js';
function documentFixture(links,{base,siteName='Fixture'}={}){return{title:'Fixture title',querySelector:selector=>selector==='base[href]'&&base?{getAttribute:()=>base}:selector.startsWith('meta[')?{content:siteName}:null,querySelectorAll:()=>links.map(attributes=>({getAttribute:name=>attributes[name]||null}))};}
test('page icons use declared touch and favicon URLs relative to the actual document base',()=>{
 const metadata=readSiteMetadata(documentFixture([{rel:'ICON',href:'small.ico',sizes:'16x16'},{rel:'apple-touch-icon',href:'touch.png',sizes:'180x180'},{rel:'manifest',href:'app.webmanifest'}],{base:'/brand/'}),'https://site.example/login');
 assert.deepEqual(metadata.iconCandidates,['https://site.example/brand/touch.png']);assert.deepEqual(metadata.faviconCandidates,['https://site.example/brand/small.ico']);assert.equal(metadata.manifestUrl,'https://site.example/brand/app.webmanifest');
});
test('a missing touch image falls back to a manifest icon resolved against the manifest URL',async()=>{
 const requests=[];const request=async(kind,url)=>{requests.push([kind,url]);if(kind==='manifest')return{url:'https://cdn.example/pwa/manifest.json',text:JSON.stringify({icons:[{src:'icons/logo.png',sizes:'192x192'}]})};if(url==='https://cdn.example/pwa/icons/logo.png')return{dataUrl:'real-image'};throw Error('404');};
 const found=await resolveWebsiteIcon({url:'https://site.example/account',iconCandidates:['https://site.example/broken.png'],manifestUrl:'https://site.example/app.json'},request,{normalize:async value=>'png:'+value});
 assert.equal(found,'png:real-image');assert.ok(requests.some(([kind,url])=>kind==='image'&&url==='https://cdn.example/pwa/icons/logo.png'));
});
test('manual creation discovers metadata at the redirected URL and retains a working fallback',async()=>{
 const urls=[];const icon=await resolveWebsiteIcon({url:'https://old.example/'},async(kind,url)=>{urls.push([kind,url]);if(kind==='document')return{url:'https://new.example/path/',text:'HTML'};if(url==='https://new.example/path/logo.png')return{dataUrl:'logo'};throw Error('not found');},{parseHTML:()=>documentFixture([{rel:'icon',href:'logo.png'}]),normalize:async value=>'png:'+value});
 assert.equal(icon,'png:logo');assert.ok(urls.some(([,url])=>url==='https://new.example/path/logo.png'));assert.ok(!urls.some(([,url])=>url.includes('undefined')));
});
test('an already stored PNG works offline without any request',async()=>{
 assert.equal(await resolveWebsiteIcon({url:'https://site.example/',iconUrl:'data:image/png;base64,saved'},()=>{throw Error('offline');}),'data:image/png;base64,saved');
});
test('unavailable and unsafe icons do not break shortcut creation or fetch other URL schemes',async()=>{
 const urls=[];assert.equal(await resolveWebsiteIcon({url:'https://site.example/',iconCandidates:['file:///private/icon','javascript:alert(1)','https://user:pass@site.example/icon']},async(kind,url)=>{urls.push(url);throw Error('offline');}), '');
 assert.deepEqual(urls,['https://site.example/apple-touch-icon.png','https://site.example/favicon.ico']);
});
