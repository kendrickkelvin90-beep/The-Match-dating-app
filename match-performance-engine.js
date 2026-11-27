/* The Match Performance Engine — Discover HD card + stable first-card layout
 * Scopes media tuning to Discover only. It does not change profile data or auth.
 * The first card's measured height is frozen after its initial viewport fit so
 * Android browser-chrome/visualViewport changes during scrolling cannot resize it.
 */
(()=>{
 'use strict';
 if(window.__matchPerformanceEngineLoaded)return;
 window.__matchPerformanceEngineLoaded=true;

 const processed=new WeakSet();
 const warmedOrigins=new Set();
 const stabilizedCards=new WeakSet();
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

 // The Discover renderer initially fits the card to the visible space. Its
 // visualViewport resize callback can run when Android's browser chrome hides
 // during a scroll, recalculating the card from a different cardRect.top.
 // Capture the first completed fit and prevent scroll-related height changes.
 function stabilizeCardHeight(card){
   if(!card||stabilizedCards.has(card))return;
   stabilizedCards.add(card);
   requestAnimationFrame(()=>requestAnimationFrame(()=>{
     if(!card.isConnected)return;
     const stableHeight=card.style.getPropertyValue('height');
     if(!stableHeight||stableHeight==='auto')return;
     let restoring=false;
     const observer=new MutationObserver(()=>{
       if(!card.isConnected){observer.disconnect();return;}
       if(restoring)return;
       const currentHeight=card.style.getPropertyValue('height');
       if(currentHeight!==stableHeight){
         restoring=true;
         card.style.setProperty('height',stableHeight,'important');
         restoring=false;
       }
     });
     observer.observe(card,{attributes:true,attributeFilter:['style']});
   }));
 }

 function addCardPresentation(card){
   if(!card)return;
   card.classList.add('match-discover-hd-card');
   stabilizeCardHeight(card);
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
     '#profileList .match-discover-hd-card{width:100%;max-width:100%;}'+
     '#profileList .match-discover-hd-photo{display:block;width:100%;height:clamp(440px,72svh,780px);max-height:780px;object-fit:cover;object-position:center center;image-rendering:auto;}'+
     '#discover #profileList > .discover-option3-card .discover-option3-overlay{box-sizing:border-box!important;padding:clamp(78px,12vh,108px) 16px max(18px,env(safe-area-inset-bottom))!important;gap:5px!important;}'+
     '#discover #profileList > .discover-option3-card .discover-option3-overlay h2{max-width:100%!important;margin:0 0 7px!important;line-height:1.12!important;overflow-wrap:anywhere!important;}'+
     '#discover #profileList > .discover-option3-card .discover-option3-overlay .distance{display:inline-flex!important;align-self:flex-start!important;max-width:100%!important;box-sizing:border-box!important;margin:0 0 10px!important;padding:6px 10px!important;border:1px solid rgba(239,211,148,.38)!important;border-radius:999px!important;background:rgba(0,0,0,.76)!important;color:#ffe5ad!important;font-size:13px!important;line-height:1.35!important;text-shadow:0 1px 8px rgba(0,0,0,.95)!important;}'+
     '#discover #profileList > .discover-option3-card .discover-floating-actions{display:flex!important;flex:0 0 auto!important;align-items:center!important;justify-content:center!important;gap:clamp(10px,3.5vw,18px)!important;width:100%!important;margin:13px 0 4px!important;padding:4px 0 max(4px,env(safe-area-inset-bottom))!important;box-sizing:border-box!important;}'+
     '#discover #profileList > .discover-option3-card .discover-floating-actions > button{flex:0 0 clamp(58px,18vw,72px)!important;width:clamp(58px,18vw,72px)!important;min-width:clamp(58px,18vw,72px)!important;max-width:clamp(58px,18vw,72px)!important;height:clamp(58px,18vw,72px)!important;min-height:clamp(58px,18vw,72px)!important;max-height:clamp(58px,18vw,72px)!important;padding:0!important;}'+
     '@media(max-height:700px){#discover #profileList > .discover-option3-card .discover-option3-overlay{padding-top:68px!important;padding-left:13px!important;padding-right:13px!important;}#discover #profileList > .discover-option3-card .discover-floating-actions{margin-top:8px!important;}}'+
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
   listObserver.observe(discoverList,{childList:true,subtree:true,attributes:true,attributeFilter:['src','srcset']});
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
   version:'1.4-discover-stable-card-layout',
   targetFirstCardMs:2000,
   status:'Discover first photo prioritized; card height held steady during scroll; distance and action spacing refined',
   refresh:()=>{attachDiscoverList();tuneDiscover();}
 };
})();
