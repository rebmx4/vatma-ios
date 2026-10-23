export function previewMediaRequest(action,body={}){
 return new Promise((resolve,reject)=>{
  const id=crypto.randomUUID(),parentWindow=window.parent;
  const timer=setTimeout(()=>finish(new Error('Медиаплеер не отвечает')),12000);
  function finish(error,result){clearTimeout(timer);window.removeEventListener('message',receive);error?reject(error):resolve(result);}
  function receive(event){
   if(event.source!==parentWindow||!['file://','null'].includes(event.origin)||event.data?.type!=='atma-media-response'||event.data.id!==id)return;
   finish(event.data.error?new Error(event.data.error):null,event.data.result);
  }
  window.addEventListener('message',receive);
  parentWindow.postMessage({type:'atma-media-request',id,action,body},'*');
 });
}
