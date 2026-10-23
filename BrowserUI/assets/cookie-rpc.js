export function previewCookieRequest(action,body){
 return new Promise((resolve,reject)=>{
  const id=crypto.randomUUID(),parentWindow=window.parent;
  const timer=setTimeout(()=>finish(new Error('Хранилище cookie не отвечает')),12000);
  function finish(error,result){clearTimeout(timer);window.removeEventListener('message',receive);error?reject(error):resolve(result);}
  function receive(event){if(event.source!==parentWindow||event.data?.type!=='atma-cookie-response'||event.data.id!==id)return;finish(event.data.error?new Error(event.data.error):null,event.data.result);}
  window.addEventListener('message',receive);
  parentWindow.postMessage({type:'atma-cookie-request',id,action,body},'*');
 });
}
