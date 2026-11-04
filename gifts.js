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
 const {data:userData,error:userError}=await db.auth.getUser();
 if(userError)throw userError;
 const myId=userData?.user?.id;
 if(!myId)throw new Error("Please sign in to view your gifts.");
 const [cat,gifts]=await Promise.all([
 db.from("gift_catalog").select("code,name,emoji,send_cost,redeem_coins").eq("active",true).order("sort_order"),
 db.from("member_gifts").select("id,sender_id,recipient_id,gift_code,send_cost,redeem_coins,message,created_at,redeemed_at,gift_catalog(name,emoji)").eq("recipient_id",myId).order("created_at",{ascending:false}).limit(60)
 ]);
 if(cat.error)throw cat.error;if(gifts.error)throw gifts.error;
 panel.querySelector("#mgCatalog").innerHTML=(cat.data||[]).map(g=>`<article class="mg-card"><div class="emoji">${esc(g.emoji)}</div><strong>${esc(g.name)}</strong><p class="mg-muted">${g.send_cost} coins · recipient gets ${g.redeem_coins}</p><button data-gift="${esc(g.code)}">Send gift</button></article>`).join("")||"No gifts available.";
 panel.querySelector("#mgCollection").innerHTML=(gifts.data||[]).filter(g=>g.gift_catalog).map(g=>`<div class="mg-row"><strong>${esc(g.gift_catalog.emoji)} ${esc(g.gift_catalog.name)}</strong><div class="mg-muted">${new Date(g.created_at).toLocaleString()} · ${g.redeemed_at?"Redeemed":g.redeem_coins+" coins available"}</div>${g.message?`<div>${esc(g.message)}</div>`:""}${!g.redeemed_at&&g.redeem_coins>0?`<button data-redeem="${g.id}">Redeem ${g.redeem_coins} coins</button>`:""}</div>`).join("")||"Your gift collection is empty.";
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
  const {data:userData,error:userError}=await db.auth.getUser();
  if(userError)throw userError;
  const senderId=userData?.user?.id;
  if(!senderId)throw new Error("Please sign in to send a gift.");
  const giftCode=send.dataset.gift;
  const storageKey="theMatch.pendingGiftRequest."+senderId+"."+recipient+"."+giftCode;
  let requestId;
  try{
   requestId=window.localStorage.getItem(storageKey);
   if(!requestId){requestId=window.crypto.randomUUID();window.localStorage.setItem(storageKey,requestId);}
  }catch(storageError){
   requestId=send.dataset.requestId||(send.dataset.requestId=window.crypto.randomUUID());
  }
  const {error}=await db.rpc("send_member_gift",{p_recipient_id:recipient,p_gift_code:giftCode,p_message:msg,p_request_id:requestId});
  if(error)throw error;
  status("Gift sent successfully.");
  await load();
  try{window.localStorage.removeItem(storageKey);}catch(storageError){}
  delete send.dataset.requestId;
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

/* Floating, admin-verified Gift Manager. All catalogue writes are server-authorized. */
const adminStyle=document.createElement("style");
adminStyle.textContent=`
#matchGiftAdmin{position:fixed;inset:0;z-index:13000;background:rgba(20,27,43,.34);backdrop-filter:blur(7px);display:none;align-items:center;justify-content:center;padding:14px;box-sizing:border-box;color:#202b3c;font-family:inherit}
#matchGiftAdmin.open{display:flex}
#matchGiftAdmin .mga-shell{width:min(820px,100%);max-height:91dvh;overflow:auto;background:#f7f8fc;border:0;border-radius:24px;padding:clamp(17px,3vw,28px);box-shadow:0 28px 90px rgba(19,32,56,.28)}
#matchGiftAdmin .mga-top{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;padding-bottom:20px;border-bottom:1px solid #e7eaf1}
#matchGiftAdmin .mga-eyebrow{margin:0 0 6px;color:#6474a5;font-size:10px;font-weight:800;letter-spacing:.16em}
#matchGiftAdmin h2{margin:0;color:#1d2940;font-size:clamp(23px,4vw,29px);letter-spacing:-.04em}
#matchGiftAdmin h3{margin:22px 0 12px;color:#27344c;font-size:15px}
#matchGiftAdmin .mga-muted{color:#758096;font-size:12px;line-height:1.5}
#matchGiftAdmin .mga-top .mga-muted{margin:6px 0 0}
#matchGiftAdmin button{border:0;border-radius:11px;padding:10px 14px;background:#e9edfb;color:#344879;font-weight:700;cursor:pointer;transition:transform .15s,background .15s}
#matchGiftAdmin button:active{transform:scale(.98)}
#matchGiftAdmin button:hover{background:#dce4fb}
#matchGiftAdmin #mgaClose{background:#eef0f5;color:#58647a}
#matchGiftAdmin .mga-primary{background:#5268ad;color:#fff}
#matchGiftAdmin .mga-primary:hover{background:#405796}
#matchGiftAdmin input{min-width:0;width:100%;box-sizing:border-box;border:1px solid #e0e5ef;border-radius:11px;padding:12px;background:#fff;color:#26334a;font:inherit;font-size:13px;outline:none}
#matchGiftAdmin input:focus{border-color:#8295d2;box-shadow:0 0 0 3px rgba(100,125,195,.13)}
#matchGiftAdmin .mga-form{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin:14px 0 8px}
#matchGiftAdmin .mga-form button{grid-column:1/-1}
#matchGiftAdmin .mga-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
#matchGiftAdmin .mga-item{min-width:0;display:flex;justify-content:space-between;align-items:center;gap:10px;padding:14px;background:#fff;border:1px solid #e9edf4;border-radius:15px;box-shadow:0 3px 12px rgba(31,48,78,.035)}
#matchGiftAdmin .mga-item strong{color:#26344d;font-size:13px}
#matchGiftAdmin .mga-actions{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}
#matchGiftAdmin .mga-actions button{padding:8px 10px;font-size:11px}
#matchGiftAdmin .mga-status{margin-top:12px;padding:10px 12px;background:#edf2ff;border-radius:11px;color:#405796}
@media(max-width:560px){#matchGiftAdmin{padding:8px}#matchGiftAdmin .mga-shell{max-height:94dvh;border-radius:19px;padding:15px}#matchGiftAdmin .mga-form{grid-template-columns:repeat(2,minmax(0,1fr))}#matchGiftAdmin .mga-list{grid-template-columns:1fr}#matchGiftAdmin .mga-item{align-items:flex-start}}
`;
document.head.appendChild(adminStyle);
const adminPanel=document.createElement("section");
adminPanel.id="matchGiftAdmin";
adminPanel.innerHTML=`<div class="mga-shell"><div class="mga-top"><div><p class="mga-eyebrow">THE MATCH · ADMIN TOOLS</p><h2>Gift Manager</h2><p class="mga-muted">Manage the catalogue and review recent gift activity.</p></div><button type="button" id="mgaClose">Close ✕</button></div><h3>Gift catalogue</h3><form id="mgaForm" class="mga-form"><input name="code" placeholder="Gift code (e.g. rose)" required maxlength="32"><input name="name" placeholder="Gift name" required maxlength="60"><input name="emoji" placeholder="Emoji" required maxlength="12"><input name="cost" type="number" min="1" placeholder="Send cost" required><input name="redeem" type="number" min="0" placeholder="Redeem coins" required><input name="sort" type="number" min="0" placeholder="Display order" value="0"><button class="mga-primary" type="submit">Save gift</button></form><p class="mga-muted">Redemption must not exceed the sending price. Existing gifts already sent retain their original values.</p><div id="mgaCatalog" class="mga-list">Loading catalogue…</div><h3>Recent gift activity</h3><div id="mgaActivity" class="mga-muted">Loading activity…</div><p id="mgaStatus" role="status" class="mga-status"></p></div>`;
document.body.appendChild(adminPanel);
const mgaStatus=m=>adminPanel.querySelector("#mgaStatus").textContent=m||"";
async function loadGiftAdmin(){
 const {data:ok,error:authError}=await db.rpc("is_match_admin");
 if(authError||ok!==true)throw new Error("Admin access denied.");
 const [c,a]=await Promise.all([
  db.from("gift_catalog").select("code,name,emoji,send_cost,redeem_coins,active,sort_order").order("sort_order"),
  db.rpc("admin_gift_activity",{p_limit:100})
 ]);
 if(c.error)throw c.error;if(a.error)throw a.error;
 adminPanel.querySelector("#mgaCatalog").innerHTML=(c.data||[]).map(g=>`<div class="mga-item"><div><strong>${esc(g.emoji)} ${esc(g.name)}</strong><div class="mga-muted">${g.send_cost} send · ${g.redeem_coins} redeem · ${g.code}</div></div><div class="mga-actions"><button type="button" data-editgift="${esc(g.code)}">Edit</button><button type="button" data-togglegift="${esc(g.code)}" data-active="${g.active}">${g.active?"Deactivate":"Activate"}</button></div></div>`).join("")||"No gifts configured.";
 adminPanel.querySelector("#mgaActivity").innerHTML=(a.data||[]).map(g=>`<div class="mga-item"><div><strong>${esc(g.gift_code)}</strong><div class="mga-muted">From ${esc(g.sender_id)} → ${esc(g.recipient_id)} · ${g.send_cost} coins · ${g.redeemed_at?"Redeemed ("+g.redeem_coins+")":"Not redeemed"}</div></div><span class="mga-muted">${new Date(g.created_at).toLocaleDateString()}</span></div>`).join("")||"No gift activity yet.";
}
adminPanel.querySelector("#mgaClose").onclick=()=>adminPanel.classList.remove("open");
adminPanel.querySelector("#mgaForm").addEventListener("submit",async ev=>{
 ev.preventDefault();const f=new FormData(ev.currentTarget);
 const args={p_code:String(f.get("code")).trim().toLowerCase(),p_name:String(f.get("name")).trim(),p_emoji:String(f.get("emoji")).trim(),p_send_cost:Number(f.get("cost")),p_redeem_coins:Number(f.get("redeem")),p_sort_order:Number(f.get("sort")||0)};
 try{const {error}=await db.rpc("admin_save_gift",args);if(error)throw error;mgaStatus("Gift saved.");ev.currentTarget.reset();ev.currentTarget.elements.code.readOnly=false;await loadGiftAdmin();}catch(e){mgaStatus(e.message||"Could not save gift.");}
});
adminPanel.addEventListener("click",async ev=>{
 const edit=ev.target.closest("[data-editgift]"),toggle=ev.target.closest("[data-togglegift]");
 try{
 if(edit){const {data,error}=await db.from("gift_catalog").select("*").eq("code",edit.dataset.editgift).single();if(error)throw error;const form=adminPanel.querySelector("#mgaForm");for(const [n,v] of Object.entries({code:data.code,name:data.name,emoji:data.emoji,cost:data.send_cost,redeem:data.redeem_coins,sort:data.sort_order}))form.elements[n].value=v;form.elements.code.readOnly=true;form.scrollIntoView({behavior:"smooth",block:"center"});}
 if(toggle){const {error}=await db.rpc("admin_set_gift_active",{p_code:toggle.dataset.togglegift,p_active:toggle.dataset.active!=="true"});if(error)throw error;mgaStatus("Gift availability updated.");await loadGiftAdmin();}
 }catch(e){mgaStatus(e.message||"Admin action failed.");}
});
function addGiftAdminButton(){
 const head=document.querySelector("#adminPanel .admin-top-actions");
 if(!head||head.querySelector("#openGiftAdmin"))return;
 const b=document.createElement("button");b.type="button";b.id="openGiftAdmin";b.className="admin-refresh-button";b.textContent="🎁 Gift Manager";
 b.onclick=async()=>{adminPanel.classList.add("open");mgaStatus("Verifying administrator access…");try{await loadGiftAdmin();mgaStatus("Gift Manager ready.");}catch(e){mgaStatus(e.message||"Admin access denied or Gift Manager unavailable.");}};
 head.insertBefore(b,head.firstChild);
}
document.addEventListener("match:admin-opened",addGiftAdminButton);
addGiftAdminButton();

})();
