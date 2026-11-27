/* The Match Performance Engine — Discover first-card priority
 * Prioritizes the first visible Discover photo and warms its image origin.
 * This improves image delivery; server/network latency still determines the final load time.
 */
(()=>{
 'use strict';
 if(window.__matchPerformanceEngineLoaded)return;
 window.__matchPerformanceEngineLoaded=true;
 const processed=new WeakSet();
 const warmedOrigins=new Set();

 function warmImageOrigin(img){
   const raw=img.currentSrc||img.src;
   if(!raw)return;
   try{
     const url=new URL(raw,document.baseURI);
     if(!/^https?:$/.test(url.protocol)||warmedOrigins.has(url.origin))return;
     warmedOrigins.add(url.origin);
     const link=document.createElement('link');
     link.rel='preconnect';
     link.href=url.origin;
     document.head.appendChild(link);
   }catch(_){}
 }

 function tuneImage(img){
   if(!img)return;
   try{
     img.decoding='async';
     if(!img.hasAttribute('loading'))img.loading='lazy';
     if(!processed.has(img)){
       processed.add(img);
       img.addEventListener('load',()=>{img.dataset.matchImageLoaded='true';},{once:true});
     }
   }catch(_){}
 }

 function tune(root){
   if(!root)return;
   if(root.matches&&root.matches('img'))tuneImage(root);
   if(root.querySelectorAll)root.querySelectorAll('img').forEach(tuneImage);
 }

 function prioritizeFirstCard(){
   const list=document.getElementById('profileList');
   if(!list)return;
   const card=list.querySelector('.member-card,.discover-option3-card');
   if(!card)return;
   const img=card.querySelector('img');
   if(!img)return;
   try{
     img.loading='eager';
     img.fetchPriority='high';
     img.decoding='async';
     warmImageOrigin(img);
   }catch(_){}
   tuneImage(img);
 }

 function start(){
   tune(document);
   prioritizeFirstCard();
   const observer=new MutationObserver(records=>{
     for(const record of records){
       for(const node of record.addedNodes){
         if(node.nodeType===1)tune(node);
       }
     }
     prioritizeFirstCard();
   });
   observer.observe(document.documentElement,{childList:true,subtree:true});
 }

 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
 else start();

 window.MatchPerformanceEngine={
   version:'1.1-discover-priority',
   targetFirstCardMs:2000,
   status:'first Discover image prioritized; image origin preconnect enabled',
   refresh:()=>{tune(document);prioritizeFirstCard();}
 };
})();
