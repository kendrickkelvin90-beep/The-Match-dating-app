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
 const editorialCards=new WeakSet();
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
     const stableHeight='auto';
     card.style.setProperty('height',stableHeight,'important');
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


 function transformEditorialCard(card){
   if(!card||editorialCards.has(card))return;
   // The renderer/card-stack can wrap or move descendants during assembly.
   // Use resilient descendant selectors and retry on later observer passes.
   const photoBox=card.querySelector('.discover-option3-photo');
   const overlay=card.querySelector('.discover-option3-overlay');
   if(!photoBox||!overlay){card.dataset.matchEditorialStatus='waiting-for-card-parts';return;}
   editorialCards.add(card);
   card.dataset.matchEditorialStatus='applied';
   card.classList.add('match-discover-editorial-card');
   photoBox.classList.add('match-discover-editorial-media');
   overlay.classList.add('match-discover-editorial-body');
   const set=(el,prop,value)=>el&&el.style.setProperty(prop,value,'important');
   [['display','flex'],['flex-direction','column'],['height','auto'],['min-height','0'],['max-height','none'],['overflow','hidden'],['width','100%'],['max-width','100%'],['margin','0'],['border-radius','24px'],['border','1px solid rgba(214,180,110,.38)'],['background','#10100e'],['box-shadow','0 16px 38px rgba(0,0,0,.28)'],['touch-action','pan-y']].forEach(([p,v])=>set(card,p,v));
   [['position','relative'],['inset','auto'],['display','block'],['flex','0 0 auto'],['width','100%'],['height','clamp(360px,52svh,520px)'],['min-height','360px'],['max-height','520px'],['border-radius','0'],['overflow','hidden']].forEach(([p,v])=>set(photoBox,p,v));
   const photo=photoBox.querySelector('.discover-option3-image');
   [['position','absolute'],['inset','0'],['width','100%'],['height','100%'],['object-fit','cover'],['object-position','center 24%'],['border-radius','0']].forEach(([p,v])=>set(photo,p,v));
   // Move the existing information panel below the photo without recreating
   // its buttons; all existing click handlers and entitlement checks remain.
   [['position','relative'],['inset','auto'],['left','auto'],['right','auto'],['bottom','auto'],['z-index','2'],['display','flex'],['flex-direction','column'],['gap','8px'],['padding','18px 16px'],['background','#fffdf8'],['color','#211f1b'],['pointer-events','auto'],['box-sizing','border-box'],['width','100%'],['text-shadow','none']].forEach(([p,v])=>set(overlay,p,v));
   card.appendChild(overlay);
   const applyEditorialTheme=()=>{
     const dark=!document.body.classList.contains('light-theme');
     set(overlay,'background',dark?'linear-gradient(155deg,#1c1a15,#11100d)':'#fffdf8');
     set(overlay,'color',dark?'#f5f0e6':'#211f1b');
     set(overlay.querySelector('h2'),'color',dark?'#f8f3e8':'#211f1b');
     set(overlay.querySelector('.distance'),'color',dark?'#d8c39a':'#75684f');
     set(toggle,'background',dark?'#242016':'#f7f1e5');
     set(toggle,'color',dark?'#e7cc91':'#6e501d');
     set(details,'background',dark?'#242016':'#f7f3eb');
     set(details,'color',dark?'#f1e8d7':'#302b22');
     actions?.querySelectorAll('button').forEach((button,index)=>{
       if(index===0){set(button,'background',dark?'#292824':'#efede8');set(button,'color',dark?'#f2eee5':'#4c4942');}
     });
   };
   const heading=overlay.querySelector('h2');
   [['color','#211f1b'],['font-size','clamp(25px,6vw,31px)'],['line-height','1.12'],['letter-spacing','-.55px'],['text-shadow','none'],['margin','0']].forEach(([p,v])=>set(heading,p,v));
   const distance=overlay.querySelector('.distance');
   [['color','#75684f'],['font-size','14px'],['font-weight','650'],['text-shadow','none'],['margin','0 0 3px']].forEach(([p,v])=>set(distance,p,v));
   overlay.querySelectorAll('.discover-compatibility-badge,.discover-lifestyle-match-badge,.discover-interest-match-badge').forEach((el,i)=>{
     [['align-self','flex-start'],['max-width','100%'],['white-space','normal'],['background',i===0?'#f5ead2':'#f7f2e8'],['color','#79591f'],['border','1px solid rgba(180,140,65,.24)'],['box-shadow','none'],['text-shadow','none'],['margin','0 0 3px']].forEach(([p,v])=>set(el,p,v));
   });
   const explain=overlay.querySelector('.discover-compatibility-explain');
   [['align-self','flex-start'],['color','#76571f'],['background','#f8f2e7'],['margin','0 0 4px']].forEach(([p,v])=>set(explain,p,v));
   const toggle=overlay.querySelector('button[aria-expanded]');
   [['min-height','44px'],['margin','3px 0 0'],['border','1px solid rgba(177,137,62,.34)'],['border-radius','13px'],['background','#f7f1e5'],['color','#6e501d'],['box-shadow','none'],['backdrop-filter','none']].forEach(([p,v])=>set(toggle,p,v));
   const details=toggle?.nextElementSibling;
   [['max-height','38svh'],['background','#f7f3eb'],['color','#302b22'],['backdrop-filter','none']].forEach(([p,v])=>set(details,p,v));
   const actions=overlay.querySelector('.discover-floating-actions');
   if(actions){
     [['display','grid'],['grid-template-columns','1fr 1fr 1fr'],['gap','9px'],['width','100%'],['margin','7px 0 0'],['padding','0']].forEach(([p,v])=>set(actions,p,v));
     actions.querySelectorAll('button').forEach((button,index)=>{
       button.textContent=index===0?'✕ Pass':index===1?'✦ Super Like':'♥ Like';
       [['width','100%'],['min-width','0'],['max-width','none'],['height','54px'],['min-height','54px'],['max-height','54px'],['flex','1 1 0'],['border-radius','14px'],['font-size','13px'],['box-shadow','none'],['padding','0 5px']].forEach(([p,v])=>set(button,p,v));
       if(index===0){
         [['background','#efede8'],['border','1px solid #e2ded5'],['color','#4c4942']].forEach(([p,v])=>set(button,p,v));
       }else{
         [['background','linear-gradient(135deg,#f4dfad,#c99b4b)'],['border','1px solid #d2aa62'],['color','#33230b']].forEach(([p,v])=>set(button,p,v));
       }
     });
   }
   applyEditorialTheme();
 }

 function addCardPresentation(card){
   if(!card)return;
   card.classList.add('match-discover-hd-card');
   transformEditorialCard(card);
   stabilizeCardHeight(card);
   const img=card.querySelector('img');
   if(!img)return;
   img.classList.add('match-discover-hd-photo');
   tuneImage(img);
 }


 function installEditorialPresentation(){
   if(document.getElementById('match-discover-editorial-styles'))return;
   const style=document.createElement('style');
   style.id='match-discover-editorial-styles';
   style.textContent=[
     '#discover .discover-page-heading{margin-bottom:10px!important;}',
     '#discover #storiesSection{margin-bottom:10px!important;}',
     '#match-discover-events-banner{display:flex;align-items:center;gap:12px;width:100%;box-sizing:border-box;margin:10px 0 14px;padding:12px 13px;border:1px solid rgba(214,180,110,.35);border-radius:17px;background:linear-gradient(120deg,rgba(198,161,91,.13),rgba(20,18,14,.96));color:#f7f1e5;}',
     '#match-discover-events-banner .match-discover-events-mark{display:grid;place-items:center;flex:0 0 42px;width:42px;height:42px;border-radius:13px;background:linear-gradient(145deg,#f4dfad,#bc8d3d);color:#241807;font-size:23px;}',
     '#match-discover-events-banner .match-discover-events-copy{display:flex;flex:1 1 auto;min-width:0;flex-direction:column;gap:3px;}',
     '#match-discover-events-banner .match-discover-events-copy strong{font-size:14px;line-height:1.25;color:#e4c47e;}',
     '#match-discover-events-banner .match-discover-events-copy span{font-size:11px;line-height:1.35;color:#c9c1b2;}',
     '#match-discover-events-banner .match-discover-events-button{flex:0 0 auto!important;min-width:0!important;width:auto!important;min-height:40px!important;margin:0!important;padding:8px 11px!important;border:1px solid #d8b66d!important;border-radius:999px!important;background:linear-gradient(135deg,#f4dfad,#c99b4b)!important;color:#241807!important;font-size:12px!important;font-weight:800!important;white-space:nowrap!important;}',
     '#match-discover-events-banner .events-notification-badge{margin-left:3px;}',
     '#discover #profileList>.match-discover-editorial-card{height:auto!important;min-height:0!important;max-height:none!important;overflow:hidden!important;}',
     '#discover .match-discover-editorial-media{height:clamp(360px,52svh,520px)!important;min-height:360px!important;max-height:520px!important;}',
     '#discover .match-discover-editorial-body{background:#fffdf8!important;color:#211f1b!important;}',
     '#discover .match-discover-editorial-body h2{color:#211f1b!important;}',
     '#discover .match-discover-editorial-body .distance{color:#75684f!important;}',
     '#discover .match-discover-editorial-body .discover-photo-count{top:14px!important;right:14px!important;}',
     '#discover .match-discover-editorial-body .discover-floating-actions button{font-size:24px!important;}',
     '#discover .discover-profile-card-stack{padding-bottom:12px!important;margin-bottom:8px!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-card{background:#171612!important;border-color:rgba(214,180,110,.36)!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body{background:linear-gradient(155deg,#1c1a15,#11100d)!important;color:#f5f0e6!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body h2{color:#f8f3e8!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body .distance{color:#d8c39a!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body .discover-compatibility-badge,body:not(.light-theme) #discover .match-discover-editorial-body .discover-lifestyle-match-badge,body:not(.light-theme) #discover .match-discover-editorial-body .discover-interest-match-badge{background:#2a2418!important;color:#f0d79e!important;border-color:rgba(214,180,110,.3)!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body button[aria-expanded],body:not(.light-theme) #discover .match-discover-editorial-body .discover-compatibility-explain{background:#242016!important;color:#e7cc91!important;border-color:rgba(214,180,110,.34)!important;}',
     'body:not(.light-theme) #discover .match-discover-editorial-body .discover-floating-actions button:first-child{background:#292824!important;color:#f2eee5!important;border-color:#4a463d!important;}',
     '@media(max-width:380px){#match-discover-events-banner{gap:8px;padding:10px;}#match-discover-events-banner .match-discover-events-mark{flex-basis:36px;width:36px;height:36px;}#match-discover-events-banner .match-discover-events-copy span{font-size:10px;}#match-discover-events-banner .match-discover-events-button{padding:7px 9px!important;font-size:11px!important;}}'
   ].join('');
   (document.head||document.documentElement).appendChild(style);
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


 function installDiscoverEventsBanner(){
   const discover=document.getElementById('discover');
   const stories=document.getElementById('storiesSection');
   const eventsButton=document.getElementById('openEventsFromDiscover');
   if(!discover||!stories||!eventsButton)return;
   let banner=document.getElementById('match-discover-events-banner');
   if(!banner){
     banner=document.createElement('section');
     banner.id='match-discover-events-banner';
     banner.className='match-discover-events-banner';
     banner.setAttribute('aria-label','Discover community events');
     const copy=document.createElement('div');
     copy.className='match-discover-events-copy';
     const title=document.createElement('strong');
     title.textContent='Discover LGBTQ+ Events';
     const subtitle=document.createElement('span');
     subtitle.textContent='Find verified community events and meet people.';
     copy.append(title,subtitle);
     const mark=document.createElement('span');
     mark.className='match-discover-events-mark';
     mark.setAttribute('aria-hidden','true');
     mark.textContent='✦';
     banner.append(mark,copy,eventsButton);
     stories.insertAdjacentElement('afterend',banner);
   }else if(eventsButton.parentElement!==banner){
     banner.appendChild(eventsButton);
   }
   eventsButton.classList.add('match-discover-events-button');
   eventsButton.setAttribute('aria-label','Explore LGBTQ+ events');
   const textNode=Array.from(eventsButton.childNodes).find(node=>node.nodeType===3);
   if(textNode)textNode.nodeValue='Explore Events ';
   const headingActions=discover.querySelector('.discover-header-actions');
   if(headingActions){
     headingActions.style.setProperty('display','flex','important');
     headingActions.style.setProperty('align-items','center','important');
     headingActions.style.setProperty('gap','8px','important');
   }
 }

 function tuneDiscover(){
   if(!discoverList)return;
   installPresentation();
   installEditorialPresentation();
   installDiscoverEventsBanner();
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
   const themeObserver=new MutationObserver(()=>{
     discoverList?.querySelectorAll('.match-discover-editorial-card').forEach(card=>{
       const panel=card.querySelector('.match-discover-editorial-body');
       if(!panel)return;
       const dark=!document.body.classList.contains('light-theme');
       panel.style.setProperty('background',dark?'linear-gradient(155deg,#1c1a15,#11100d)':'#fffdf8','important');
       panel.style.setProperty('color',dark?'#f5f0e6':'#211f1b','important');
       const h=panel.querySelector('h2');if(h)h.style.setProperty('color',dark?'#f8f3e8':'#211f1b','important');
       const d=panel.querySelector('.distance');if(d)d.style.setProperty('color',dark?'#d8c39a':'#75684f','important');
     });
   });
   themeObserver.observe(document.body,{attributes:true,attributeFilter:['class']});
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
