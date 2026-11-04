(() => {
"use strict";
if (typeof db === "undefined" || !db) return;
const giftStyle=document.createElement("style");
giftStyle.textContent=`
#matchGiftPanel{position:fixed;inset:0;z-index:12000;background:#050505f5;display:none;overflow:auto;padding:calc(22px + env(safe-area-inset-top)) 16px 30px;color:#fff}
#matchGiftPanel.open{display:block}
#matchGiftPanel .mg-shell{max-width:620px;margin:auto}
#matchGiftPanel h2{color:#e7c77f}
#matchGiftPanel .mg-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
#matchGiftPanel .mg-card{padding:14px;border:1px solid #665333;border-radius:15px;background:#171511}
#matchGiftPanel button{border:1px solid #8e7444;border-radius:11px;padding:10px;background:#272116;color:#f5d995}
#matchGiftPanel .mg-card .emoji{font-size:30px}
#matchGiftPanel .mg-muted{color:#c3b99f;font-size:12px}
#matchGiftPanel .mg-row{padding:12px 0;border-bottom:1px solid #443a27}
`;
document.head.appendChild(giftStyle);
const panel=document.createElement("section");panel.id="matchGiftPanel";panel.innerHTML=`<div class="mg-shell"><button id="mgClose">← Back</button><h2>Virtual Gifts</h2><p class="mg-muted">Send a gift using your coins. Keep gifts in your collection or redeem them for 80% of their sending value.</p><h3>Choose a gift</h3><div class="mg-grid" id="mgCatalog">Loading gifts…</div><h3>Your gift collection</h3><div id="mgCollection">Loading collection…</div><p id="mgStatus" role="status"></p></div>`;document.body.appendChild(panel);
let recipient=null;
const status=m=>panel.querySelector("#mgStatus").textContent=m||"";
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
async function load(){
 const [cat,gifts]=await Promise.all([
 db.from("gift_catalog").select("code,name,emoji,send_cost,redeem_coins").eq("active",true).order("sort_order"),
 db.from("member_gifts").select("id,sender_id,recipient_id,gift_code,send_cost,redeem_coins,message,created_at,redeemed_at,gift_catalog(name,emoji)").order("created_at",{ascending:false}).limit(60)
 ]);
 if(cat.error)throw cat.error;if(gifts.error)throw gifts.error;
 panel.querySelector("#mgCatalog").innerHTML=(cat.data||[]).map(g=>`<article class="mg-card"><div class="emoji">${esc(g.emoji)}</div><strong>${esc(g.name)}</strong><p class="mg-muted">${g.send_cost} coins · recipient gets ${g.redeem_coins}</p><button data-gift="${esc(g.code)}">Send gift</button></article>`).join("")||"No gifts available.";
 const myId=window.currentUser?.id;
 panel.querySelector("#mgCollection").innerHTML=(gifts.data||[]).filter(g=>g.gift_catalog&&g.recipient_id===myId).map(g=>`<div class="mg-row"><strong>${esc(g.gift_catalog.emoji)} ${esc(g.gift_catalog.name)}</strong><div class="mg-muted">${new Date(g.created_at).toLocaleString()} · ${g.redeemed_at?"Redeemed":g.redeem_coins+" coins available"}</div>${g.message?`<div>${esc(g.message)}</div>`:""}${!g.redeemed_at&&g.redeem_coins>0?`<button data-redeem="${g.id}">Redeem ${g.redeem_coins} coins</button>`:""}</div>`).join("")||"Your gift collection is empty.";
}
window.openMatchGifts=async userId=>{recipient=userId||null;panel.classList.add("open");status("");try{await load();}catch(e){status(e.message||"Could not load gifts.");}};
panel.querySelector("#mgClose").onclick=()=>panel.classList.remove("open");
panel.addEventListener("click",async e=>{
 const send=e.target.closest("[data-gift]");
 const redeem=e.target.closest("[data-redeem]");
 try{
 if(send){
  if(!recipient){status("Open a chat first to send a gift.");return;}
  const msg=prompt("Add a short message with your gift (optional):")||null;
  send.disabled=true;
  const {error}=await db.rpc("send_member_gift",{p_recipient_id:recipient,p_gift_code:send.dataset.gift,p_message:msg});
  if(error)throw error;
  status("Gift sent successfully.");await load();
 }else if(redeem){
  redeem.disabled=true;
  const {error}=await db.rpc("redeem_member_gift",{p_gift_id:redeem.dataset.redeem});
  if(error)throw error;
  status("Gift redeemed. Your coin wallet has been credited.");await load();
 }
 }catch(err){status(err.message||"Gift action failed.");if(send)send.disabled=false;if(redeem)redeem.disabled=false;}
});
function addChatGiftButton(){
 const composer=document.querySelector("#chatComposer");
 if(!composer||composer.querySelector("#openChatGifts"))return;
 const b=document.createElement("button");b.type="button";b.id="openChatGifts";b.title="Send a virtual gift";b.setAttribute("aria-label","Send a virtual gift");b.textContent="🎁";
 b.style.cssText="flex:0 0 40px;width:40px;height:40px;border:1px solid #8e7444;border-radius:50%;background:#242025;color:#f5d995;font-size:20px";
 b.onclick=()=>window.openMatchGifts(window.activeChatUserId||null);
 composer.insertBefore(b,composer.querySelector("#sendChatMessage"));
}
addChatGiftButton();
new MutationObserver(addChatGiftButton).observe(document.body,{childList:true,subtree:true});
document.addEventListener("DOMContentLoaded",addChatGiftButton);
})();