/* The Match Performance Engine — safe phase 1
 * Non-invasive media loading improvements. Does not query Supabase or alter auth/matching.
 */
(()=>{
 'use strict';
 if(window.__matchPerformanceEngineLoaded)return; window.__matchPerformanceEngineLoaded=true;
 const processed=new WeakSet();
 function tuneImage(img){if(!img||processed.has(img))return;processed.add(img);try{img.decoding='async';if(!img.hasAttribute('loading'))img.loading='lazy';}catch(_){} }
 function tune(root){if(!root)return;if(root.matches&&root.matches('img'))tuneImage(root);if(root.querySelectorAll)root.querySelectorAll('img').forEach(tuneImage);}
 function prioritizeFirstCard(){const list=document.getElementById('profileList');if(!list)return;const card=list.querySelector('.member-card,.discover-option3-card');if(!card)return;const img=card.querySelector('img');if(img){img.loading='eager';img.fetchPriority='high';tuneImage(img);} }
 function start(){tune(document);prioritizeFirstCard();const observer=new MutationObserver(records=>{for(const r of records)for(const node of r.addedNodes)if(node.nodeType===1)tune(node);prioritizeFirstCard();});observer.observe(document.documentElement,{childList:true,subtree:true});}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
 window.MatchPerformanceEngine={version:'1.0-phase1',status:'media-loading optimization active',refresh:()=>{tune(document);prioritizeFirstCard();}};
})();
