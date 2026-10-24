// Resolve icons from the website itself; saved PNGs do not depend on later network access.
function webURL(value,base){if(typeof value!=='string'||!value.trim())return '';try{const url=new URL(value,base);return /^https?:$/.test(url.protocol)&&!url.username&&!url.password?url.href:'';}catch{return '';}}
export function readSiteMetadata(doc,url){
 const base=webURL(doc.querySelector('base[href]')?.getAttribute('href'),url)||url;
 const links=[...doc.querySelectorAll('link[rel][href]')].map(link=>({rel:(link.getAttribute('rel')||'').toLowerCase().split(/\s+/),url:webURL(link.getAttribute('href'),base),size:Math.max(0,...(link.getAttribute('sizes')||'').split(/\s+/).map(size=>Number.parseInt(size)||0))}));
 const touch=links.filter(link=>link.rel.some(rel=>rel==='apple-touch-icon'||rel==='apple-touch-icon-precomposed')).sort((a,b)=>b.size-a.size);
 const icons=links.filter(link=>link.rel.includes('icon')).sort((a,b)=>b.size-a.size);
 return {url,title:doc.title||'',siteName:doc.querySelector('meta[property="og:site_name"]')?.content||'',iconCandidates:touch.map(link=>link.url).filter(Boolean),faviconCandidates:icons.map(link=>link.url).filter(Boolean),manifestUrl:links.find(link=>link.rel.includes('manifest'))?.url||''};
}
async function normalizedImage(source){
 return new Promise(resolve=>{
  const image=new Image();let timer=setTimeout(()=>resolve(''),4000);
  image.onload=()=>{clearTimeout(timer);try{if(!image.naturalWidth||!image.naturalHeight)return resolve('');const canvas=document.createElement('canvas');canvas.width=192;canvas.height=192;const ctx=canvas.getContext('2d'),scale=Math.min(192/image.naturalWidth,192/image.naturalHeight),width=image.naturalWidth*scale,height=image.naturalHeight*scale;ctx.drawImage(image,(192-width)/2,(192-height)/2,width,height);resolve(canvas.toDataURL('image/png'));}catch{resolve('');}};
  image.onerror=()=>{clearTimeout(timer);resolve('');};image.src=source;
 });
}
export async function resolveWebsiteIcon(site,request,{parseHTML=text=>new DOMParser().parseFromString(text,'text/html'),normalize=normalizedImage}={}){
 if(/^data:image\/png;base64,/i.test(site.iconUrl||''))return site.iconUrl;
 const original=webURL(site.url);if(!original)return '';
 let metadata=site;
 if(!Array.isArray(site.iconCandidates)){
  try{const page=await request('document',original);metadata=readSiteMetadata(parseHTML(page.text),webURL(page.url)||original);}catch{}
 }
 const pageURL=webURL(metadata.url)||original,candidates=[...(metadata.iconCandidates||[])];
 if(metadata.manifestUrl){try{const response=await request('manifest',metadata.manifestUrl),manifest=JSON.parse(response.text);const base=webURL(response.url)||metadata.manifestUrl;candidates.push(...(Array.isArray(manifest.icons)?manifest.icons:[]).filter(icon=>icon&&typeof icon.src==='string').sort((a,b)=>(Number.parseInt(b.sizes)||0)-(Number.parseInt(a.sizes)||0)).map(icon=>webURL(icon.src,base)));}catch{}}
 candidates.push(...(metadata.faviconCandidates||[]),site.iconUrl,new URL('/apple-touch-icon.png',pageURL).href,new URL('/favicon.ico',pageURL).href);
 const urls=[...new Set(candidates.map(url=>webURL(url,pageURL)).filter(Boolean))].slice(0,8);
 for(let start=0;start<urls.length;start+=3){
  const results=await Promise.all(urls.slice(start,start+3).map(async url=>{try{const image=await request('image',url);return await normalize(image.dataUrl);}catch{return '';}}));
  const found=results.find(Boolean);if(found)return found;
 }
 return '';
}
