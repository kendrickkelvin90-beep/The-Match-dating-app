/* The Match Performance Engine — Discover HD card + first-card priority
 * Scopes media tuning to Discover only. It does not change profile data or auth.
 * Image sharpness is limited by the original uploaded file; this presents it without
 * artificial pixelation or stretching and gives the first card network priority.
 */
(()=>{
 'use strict';
 if(window.__matchPerformanceEngineLoaded)return;
 window.__matchPerformanceEngineLoaded=true;

 const processed=new WeakSet();
 const warmedOrigins=new Set();
 let discoverList=null;
 let listObserver=null;
 let waitingObserver=null;

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

 function addCardPresentation(card){
   if(!card)return;
   card.classList.add('match-discover-hd-card');
   const img=card.querySelector('img');
   if(!img)return;
   img.classList.add('match-discover-hd-photo');
   tuneImage(img);
 }

 function installPresentation(){
   if(document.getElementById('match-discover-hd-styles'))return;
   const style=document.createElement('style');
   style.id='match-discover-hd-styles';
   style.textContent=
     '#profileList .match-discover-hd-card{width:100%;max-width:100%;overflow:hidden;}'+
     '#profileList .match-discover-hd-photo{display:block;width:100%;height:clamp(440px,72svh,780px);max-height:780px;object-fit:cover;object-position:center center;image-rendering:auto;}'+
     '@media(max-width:600px){#profileList .match-discover-hd-photo{height:clamp(460px,69svh,740px);max-height:740px;}}'+
     '@media(min-width:900px){#profileList .match-discover-hd-card{margin-inline:auto;}}';
   (document.head||document.documentElement).appendChild(style);
 }

 function tuneDiscover(){
   if(!discoverList)return;
   installPresentation();
   const cards=discoverList.querySelectorAll('.member-card,.discover-option3-card');
   cards.forEach(addCardPresentation);
   prioritizeFirstCard();
 }

 function prioritizeFirstCard(){
   if(!discoverList)return;
   const card=discoverList.querySelector('.member-card,.discover-option3-card');
   if(!card)return;
   addCardPresentation(card);
   const img=card.querySelector('img');
   if(!img)return;
   try{
     img.loading='eager';
     img.fetchPriority='high';
     img.decoding='async';
     warmImageOrigin(img);
   }catch(_){}
 }

 function attachDiscoverList(){
   const list=document.getElementById('profileList');
   if(!list||list===discoverList)return;
   if(listObserver)listObserver.disconnect();
   discoverList=list;
   tuneDiscover();
   listObserver=new MutationObserver(()=>tuneDiscover());
   listObserver.observe(discoverList,{childList:true,subtree:true});
   if(waitingObserver){waitingObserver.disconnect();waitingObserver=null;}
 }

 function start(){
   attachDiscoverList();
   if(!discoverList){
     waitingObserver=new MutationObserver(()=>attachDiscoverList());
     waitingObserver.observe(document.documentElement,{childList:true,subtree:true});
   }
 }

 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
 else start();

 window.MatchPerformanceEngine={
   version:'1.2-discover-hd-priority',
   targetFirstCardMs:2000,
   status:'Discover-only lazy loading; first photo prioritized; large HD presentation enabled',
   refresh:()=>{attachDiscoverList();tuneDiscover();}
 };
})();
