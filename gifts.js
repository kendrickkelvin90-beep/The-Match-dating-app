(() => {
"use strict";
if (typeof db === "undefined" || !db) return;
const giftStyle=document.createElement("style");
giftStyle.textContent=`/* Romantic Premium chat and gifting palette */
#chatPage{background:#fff5ef!important;color:#4b1724!important;padding:82px 12px calc(12px + env(safe-area-inset-bottom))!important}
#chatPage :is(h2,h3,p){color:#4b1724}
#chatPage #chatHeader{background:linear-gradient(115deg,#65162d,#8f2944)!important;border:0!important;box-shadow:0 5px 20px rgba(91,19,41,.16)}
#chatPage #chatHeader :is(button,span,strong){color:#fff!important}
#chatPage #chatPartnerAvatar{border:2px solid #f2c7b9!important}
#chatPage #chatPageTitle{color:#fff!important;font-weight:750!important}
#chatPage #chatPartnerLocation{color:#f7dce0!important}
#chatPage #chatMessages{background:linear-gradient(180deg,#fff8f3,#f9e9e1)!important;border:1px solid #f0d6cb!important;border-radius:22px!important;scrollbar-color:#c58b91 transparent}
#chatPage #chatMessages .chat-bubble{border:1px solid #efd8cf!important;border-radius:18px!important;box-shadow:0 3px 10px rgba(105,45,54,.055)!important;color:#40232a!important}
#chatPage #chatMessages .chat-bubble.received{background:#fffdfb!important;color:#40232a!important;border-color:#eadbd3!important}
#chatPage #chatMessages .chat-bubble.sent{background:#f8d9d5!important;color:#581b2b!important;border-color:#edc0bd!important}
#chatPage #chatMessages .chat-bubble small{color:#916c70!important}
#chatPage #chatMessages .chat-bubble small span{color:#8b2944!important}
#chatPage #chatComposer{background:rgba(255,251,247,.97)!important;border:1px solid #e9cfc4!important;border-radius:30px!important;box-shadow:0 8px 24px rgba(100,40,53,.09)!important}
#chatPage #chatComposer #chatMessageInput{color:#48232d!important}
#chatPage #chatMessageInput::placeholder{color:#9b7c7d!important}
#chatPage #chatEmojiToggle{color:#9a2947!important}
#chatPage #chatMediaButton,#chatPage #openChatGifts{background:#fff0e9!important;color:#9b2444!important;border:1px solid #e8bdb3!important}
#chatPage #chatComposer #sendChatMessage{background:linear-gradient(145deg,#b83253,#79182f)!important;color:#fff!important;box-shadow:0 4px 12px rgba(121,24,47,.2)!important}
#chatPage #chatViewOnce{accent-color:#982844}
#chatPage #chatComposer label[for=chatViewOnce]{color:#6b3b45!important}
#chatPage #chatPageStatus{color:#8d6b6d!important}
#matchGiftPanel{background:rgba(75,20,37,.35)!important;backdrop-filter:blur(12px);color:#4b1724!important;padding:calc(18px + env(safe-area-inset-top)) 14px 28px!important}
#matchGiftPanel .mg-shell{max-width:640px;margin:12px auto;background:linear-gradient(145deg,#fffdf9,#fff0e8);border:1px solid #edcfc3;border-radius:26px;padding:22px;box-shadow:0 24px 70px rgba(75,20,37,.2)}
#matchGiftPanel h2{color:#741d35!important;font-size:27px;letter-spacing:-.6px}
#matchGiftPanel h3{color:#542331!important;margin-top:24px}
#matchGiftPanel .mg-muted{color:#8c6b70!important}
#matchGiftPanel .mg-grid{gap:12px}
#matchGiftPanel .mg-card{background:#fffaf6!important;border:1px solid #efd8ce!important;border-radius:19px!important;padding:16px;box-shadow:0 5px 16px rgba(100,40,53,.05)}
#matchGiftPanel .mg-card .emoji{font-size:36px;margin-bottom:7px}
#matchGiftPanel .mg-card strong{color:#572433}
#matchGiftPanel button{background:#8f2340!important;color:#fff!important;border:0!important;border-radius:13px!important;font-weight:700;padding:11px 15px}
#matchGiftPanel #mgClose{background:#f7e5dc!important;color:#79243b!important;border:1px solid #e8c9bd!important}
#matchGiftPanel .mg-row{border-color:#efd8ce!important;color:#542331}
#matchGiftMessageDialog{position:fixed;inset:0;z-index:14000;display:none;align-items:center;justify-content:center;padding:18px;background:rgba(64,18,34,.58);backdrop-filter:blur(8px)}
#matchGiftMessageDialog.open{display:flex}
#matchGiftMessageDialog .gmd-card{position:relative;width:min(100%,470px);padding:25px 22px 22px;border:1px solid #e7bfb1;border-radius:28px;background:linear-gradient(145deg,#fffdf9,#ffede5);box-shadow:0 25px 80px rgba(55,13,27,.3);text-align:center;color:#4d1d2a}
#matchGiftMessageDialog .gmd-brand{display:flex;align-items:center;justify-content:center;gap:9px;color:#641a30}
#matchGiftMessageDialog .gmd-brand strong{display:block;font-size:20px}
#matchGiftMessageDialog .gmd-brand small{display:block;font-size:9px;letter-spacing:1px;font-weight:800}
#matchGiftMessageDialog .gmd-heart{font-size:38px;color:#b72d50}
#matchGiftMessageDialog .gmd-close{position:absolute;right:0;top:0;width:36px;height:36px;border:1px solid #e8c9bd;border-radius:50%;background:#fff6f0;color:#6e2538;font-size:24px}
#matchGiftMessageDialog .gmd-art{font-size:62px;margin:18px 0 8px;filter:drop-shadow(0 8px 10px rgba(125,35,54,.13))}
#matchGiftMessageDialog h2{margin:0;color:#761d37;font-size:23px;letter-spacing:-.5px}
#matchGiftMessageDialog p{margin:9px 0 18px;color:#86656b;line-height:1.5;font-size:14px}
#matchGiftMessageDialog textarea{display:block;width:100%;min-height:104px;box-sizing:border-box;resize:vertical;padding:14px;border:1px solid #e6c5b9;border-radius:17px;background:#fffaf7;color:#4d2730;font:inherit;outline:none}
#matchGiftMessageDialog textarea:focus{border-color:#b65b70;box-shadow:0 0 0 3px rgba(182,91,112,.12)}
#matchGiftMessageDialog textarea::placeholder{color:#a78b8c}
#matchGiftMessageDialog .gmd-count{text-align:right;color:#98777b;font-size:11px;margin:6px 3px 16px}
#matchGiftMessageDialog .gmd-actions{display:flex;gap:10px}
#matchGiftMessageDialog .gmd-actions button{flex:1;min-height:48px;border-radius:15px;font-weight:750}
#matchGiftMessageDialog .gmd-cancel{background:#fff8f3;border:1px solid #dcb5a7;color:#68243a}
#matchGiftMessageDialog .gmd-send{border:0;background:linear-gradient(110deg,#b52d50,#77172f);color:#fff;box-shadow:0 6px 15px rgba(119,23,47,.18)}
#matchGiftAdmin{background:rgba(76,19,37,.4)!important;backdrop-filter:blur(9px);color:#542331!important}
#matchGiftAdmin .mga-shell{background:linear-gradient(145deg,#fffdf9,#fff1e9)!important;border:1px solid #edcfc3!important;border-radius:25px!important;color:#542331!important}
#matchGiftAdmin .mga-eyebrow{color:#a24a5e!important}
#matchGiftAdmin h2,#matchGiftAdmin h3,#matchGiftAdmin .mga-item strong{color:#642238!important}
#matchGiftAdmin .mga-muted{color:#927176!important}
#matchGiftAdmin .mga-top{border-color:#f0d9cf!important}
#matchGiftAdmin .mga-item{background:#fffaf7!important;border-color:#efd9d0!important;box-shadow:0 4px 14px rgba(100,40,53,.05)!important}
#matchGiftAdmin button{background:#f7e5dc!important;color:#78263d!important}
#matchGiftAdmin .mga-primary{background:linear-gradient(110deg,#b52d50,#77172f)!important;color:#fff!important}
#matchGiftAdmin #mgaClose{background:#f5e7e0!important;color:#74283e!important}
#matchGiftAdmin input{background:#fffaf7!important;border-color:#e7cfc5!important;color:#4d2730!important}
#matchGiftAdmin .mga-status{background:#f8e8e4!important;color:#78263d!important}
@media(max-width:380px){#chatPage #chatComposer{gap:5px;padding:7px}#chatPage #chatComposer label[for=chatViewOnce]{font-size:10px!important}#matchGiftMessageDialog .gmd-card{padding:22px 16px 17px}#matchGiftMessageDialog h2{font-size:20px}}
 
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
const giftMessageDialog=document.createElement("div");
giftMessageDialog.id="matchGiftMessageDialog";
giftMessageDialog.innerHTML=`<div class="gmd-card" role="dialog" aria-modal="true" aria-labelledby="gmdTitle"><div class="gmd-brand"><span class="gmd-heart">♡</span><span><strong>The Match</strong><small>BY BEYOND THE BINARY MEDIA</small></span><button type="button" class="gmd-close" aria-label="Close">×</button></div><div class="gmd-art" aria-hidden="true">🎁</div><h2 id="gmdTitle">Add a Message to Your Gift</h2><p>Send a short and sweet message with your gift (optional).</p><textarea maxlength="160" placeholder="Type your message here…"></textarea><div class="gmd-count">0 / 160</div><div class="gmd-actions"><button type="button" class="gmd-cancel">Cancel</button><button type="button" class="gmd-send">🎁 &nbsp; Send Gift</button></div></div>`;
document.body.appendChild(giftMessageDialog);
function askGiftMessage(){
 return new Promise(resolve=>{
  const input=giftMessageDialog.querySelector("textarea"),count=giftMessageDialog.querySelector(".gmd-count");
  const finish=value=>{giftMessageDialog.classList.remove("open");input.value="";count.textContent="0 / 160";resolve(value);};
  input.oninput=()=>count.textContent=input.value.length+" / 160";
  giftMessageDialog.querySelector(".gmd-cancel").onclick=()=>finish(false);
  giftMessageDialog.querySelector(".gmd-close").onclick=()=>finish(false);
  giftMessageDialog.querySelector(".gmd-send").onclick=()=>finish(input.value.trim()||null);
  giftMessageDialog.onclick=e=>{if(e.target===giftMessageDialog)finish(false);};
  giftMessageDialog.classList.add("open");
  setTimeout(()=>input.focus(),60);
 });
}
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
  const msg=await askGiftMessage();
  if(msg===false)return;
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
