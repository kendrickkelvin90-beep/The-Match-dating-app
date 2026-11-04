(() => {
  "use strict";
  const db = window.db;
  if (!db) { console.error("Coin wallet could not find the Supabase client."); return; }
  const PACKS = [
    ["starter_50","Starter","50 coins","₦1,000"],
    ["popular_120","Popular","120 coins","₦2,000"],
    ["value_260","Value","260 coins","₦4,000"],
    ["bundle_700","Premium Bundle","700 coins","₦10,000"],
    ["ultimate_1500","Ultimate Bundle","1,500 coins","₦20,000"]
  ];
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const money = value => "₦" + Number(value || 0).toLocaleString("en-NG");
  const style = document.createElement("style");
  style.textContent = `
    #coinWalletPage{color:#f7f2e7;padding:18px 0 110px}
    #coinWalletPage .cw-shell{max-width:760px;margin:auto}
    #coinWalletPage .cw-hero{padding:22px;border:1px solid #68532d;border-radius:22px;background:linear-gradient(130deg,#282013,#101010)}
    #coinWalletPage .cw-kicker{color:#d9b76d;font-size:10px;font-weight:800;letter-spacing:2px}
    #coinWalletPage h2{margin:6px 0;color:#f7e6bf}
    #coinWalletPage .cw-balance{font-size:38px;font-weight:850;color:#e7c77f}
    #coinWalletPage .cw-tabs{display:flex;gap:8px;overflow:auto;margin:16px 0}
    #coinWalletPage .cw-tabs button,#coinWalletPage .cw-button{border:1px solid #6a542c;border-radius:12px;padding:11px 14px;background:#17140e;color:#e7c77f;font-weight:700}
    #coinWalletPage .cw-tabs button.active,#coinWalletPage .cw-button.primary{background:linear-gradient(120deg,#e5c47b,#b58a42);color:#17120a}
    #coinWalletPage .cw-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
    #coinWalletPage .cw-card{padding:15px;border:1px solid #34302a;border-radius:15px;background:#111214}
    #coinWalletPage .cw-card h3{margin:0 0 7px;color:#f4e5c5}
    #coinWalletPage .cw-muted{color:#aaa49a;font-size:12px;line-height:1.5}
    #coinWalletPage .cw-price{font-size:21px;font-weight:800;color:#e7c77f;margin:8px 0}
    #coinWalletPage label{display:block;margin:12px 0 5px;color:#d7c9aa;font-size:12px}
    #coinWalletPage input,#coinWalletPage select,#coinWalletPage textarea{width:100%;box-sizing:border-box;padding:12px;border:1px solid #49402e;border-radius:10px;background:#090909;color:#fff}
    #coinWalletPage .cw-panel{margin-top:16px}
    #coinWalletPage .cw-row{padding:12px 0;border-bottom:1px solid #302b22;display:flex;justify-content:space-between;gap:10px}
    #coinWalletPage .cw-status{min-height:22px;color:#e7c77f;font-size:12px}
    #coinWalletPage .cw-admin-card{padding:14px;margin:10px 0;border:1px solid #4b402a;border-radius:14px;background:#111}
    #coinWalletPage .cw-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
    #coinWalletPage .cw-actions button{flex:1}
    @media(max-width:480px){#coinWalletPage .cw-grid{grid-template-columns:1fr}#coinWalletPage .cw-balance{font-size:32px}}
    body.light-theme #coinWalletPage{color:#2e281e}
    body.light-theme #coinWalletPage .cw-card{background:#fff;border-color:#ded5c4}
    body.light-theme #coinWalletPage .cw-card h3{color:#30291f}
    body.light-theme #coinWalletPage input,body.light-theme #coinWalletPage select,body.light-theme #coinWalletPage textarea{background:#fff;color:#241f18}
  `;
  document.head.appendChild(style);
  const page = document.createElement("section");
  page.id = "coinWalletPage"; page.className = "panel hidden";
  page.innerHTML = `
    <div class="cw-shell">
      <div class="cw-hero"><div class="cw-kicker">THE MATCH · COIN WALLET</div><h2>Your Match Coins</h2><div class="cw-balance" id="cwBalance">— coins</div><p class="cw-muted">Buy coins by bank transfer. Coins are added only after an administrator verifies your transfer.</p></div>
      <div class="cw-tabs"><button class="active" data-cw-tab="buy">Buy coins</button><button data-cw-tab="history">Wallet history</button><button data-cw-tab="plus">Match Plus</button><button data-cw-tab="store">Match Store</button></div>
      <div id="cwBuy" class="cw-panel"><h3>Choose a coin package</h3><div class="cw-grid" id="cwPackages"></div>
        <div class="cw-card cw-panel" id="cwTransfer" hidden><h3 id="cwSelectedPackage">Bank transfer</h3><p class="cw-muted">Transfer the exact amount to the existing Match payment account.</p>
          <div class="cw-row"><span>Network</span><strong>MTN MoMo</strong></div><div class="cw-row"><span>Account name</span><strong>JUSTICE TRUST UGOALA</strong></div><div class="cw-row"><span>Account number</span><strong>0896939533</strong></div>
          <form id="cwPurchaseForm"><label for="cwSender">Sender name</label><input id="cwSender" maxlength="120" required autocomplete="name"><label for="cwReference">Transfer reference</label><input id="cwReference" maxlength="160" required><button class="cw-button primary" style="width:100%;margin-top:14px">Submit transfer for review</button></form>
        </div>
      </div>
      <div id="cwHistory" class="cw-panel" hidden><h3>Wallet activity</h3><div id="cwLedger" class="cw-card">Loading wallet history…</div><h3 style="margin-top:20px">Coin transfer requests</h3><div id="cwRequests" class="cw-card">Loading requests…</div></div>
      <div id="cwPlus" class="cw-panel" hidden><h3>Match Plus memberships</h3><p class="cw-muted">Spend coins from your wallet. Membership benefits activate only through the Match Plus entitlement system.</p><div class="cw-grid">
        <article class="cw-card"><h3>Match Plus</h3><div class="cw-price">300 coins</div><p class="cw-muted">30 days · Access Premium Nearby, up to 3 Rewinds per day and up to 3 Stories per Lagos calendar day.</p><button class="cw-button primary" data-cw-tier="plus">Activate with 300 coins</button></article>
        <article class="cw-card"><h3>Match Quarterly</h3><div class="cw-price">800 coins</div><p class="cw-muted">90 days · Match Plus benefits, unlimited Likes, up to 10 Rewinds per day, unlimited Stories and one Profile Boost every 7 days.</p><button class="cw-button primary" data-cw-tier="quarterly">Activate with 800 coins</button></article>
        <article class="cw-card"><h3>Match Annual</h3><div class="cw-price">2,800 coins</div><p class="cw-muted">365 days · Quarterly benefits, unlimited Rewinds and one Profile Boost every 24 hours. Includes a 50-coin reward every 30 days while active, granted by an administrator.</p><button class="cw-button primary" data-cw-tier="annual">Activate with 2,800 coins</button></article>
      </div></div>
      <div id="cwStore" class="cw-panel" hidden><h3>Individual Match Store</h3><div class="cw-grid" id="cwStoreItems"></div><p class="cw-muted">Store purchases remain unavailable until each benefit is connected to its real feature gate. This prevents coins being deducted for an item that has not yet been delivered.</p></div>
      <p id="cwStatus" class="cw-status" role="status" aria-live="polite"></p><button id="cwBack" class="cw-button">← Back</button>
    </div>`;
  document.body.appendChild(page);
  const nav = document.querySelector('#bottomNavigation');
  if (nav && !nav.querySelector('[data-page="coinWalletPage"]')) {
    const button = document.createElement("button"); button.type="button";button.dataset.page="coinWalletPage";button.setAttribute("aria-label","Coin Wallet");button.innerHTML='<span class="nav-icon" aria-hidden="true">◈</span><span>Coins</span>';nav.insertBefore(button,nav.lastElementChild);
  }
  let selected = null;
  const status = message => { document.getElementById("cwStatus").textContent = message || ""; };
  const setTab = name => {
    ["buy","history","plus","store"].forEach(k=>{document.getElementById("cw"+k[0].toUpperCase()+k.slice(1)).hidden=k!==name;});
    page.querySelectorAll("[data-cw-tab]").forEach(b=>b.classList.toggle("active",b.dataset.cwTab===name));
  };
  const getUser = async () => { const {data,error}=await db.auth.getUser();if(error)throw error;if(!data.user)throw new Error("Please sign in to use your coin wallet.");return data.user; };
  async function refresh(){
    const user=await getUser();
    const {data:wallet,error}=await db.from("coin_wallets").select("balance").eq("user_id",user.id).maybeSingle();
    if(error)throw error;
    document.getElementById("cwBalance").textContent=(wallet?.balance||0).toLocaleString("en-NG")+" coins";
    const [ledger,requests]=await Promise.all([
      db.from("coin_ledger").select("amount,entry_type,description,created_at,balance_after").eq("user_id",user.id).order("created_at",{ascending:false}).limit(40),
      db.from("coin_purchase_requests").select("id,coins,amount_ngn,status,admin_note,created_at").eq("user_id",user.id).order("created_at",{ascending:false}).limit(20)
    ]);
    if(ledger.error)throw ledger.error;if(requests.error)throw requests.error;
    document.getElementById("cwLedger").innerHTML=ledger.data?.length?ledger.data.map(x=>'<div class="cw-row"><span><strong>'+esc(x.description)+'</strong><br><small class="cw-muted">'+esc(new Date(x.created_at).toLocaleString())+'</small></span><strong style="color:'+(x.amount>0?'#62c78c':'#d58c8c')+'">'+(x.amount>0?'+':'')+x.amount+' coins</strong></div>').join(""):'No wallet transactions yet.';
    document.getElementById("cwRequests").innerHTML=requests.data?.length?requests.data.map(x=>'<div class="cw-row"><span>'+x.coins+' coins · '+money(x.amount_ngn)+'<br><small class="cw-muted">'+esc(x.admin_note||'Submitted '+new Date(x.created_at).toLocaleString())+'</small></span><strong>'+esc(x.status)+'</strong></div>').join(""):'No coin purchase requests yet.';
  }
  document.getElementById("cwPackages").innerHTML=PACKS.map(p=>'<article class="cw-card"><h3>'+p[1]+'</h3><div class="cw-price">'+p[2]+'</div><strong>'+p[3]+'</strong><button class="cw-button primary" style="width:100%;margin-top:12px" data-cw-package="'+p[0]+'">Select package</button></article>').join("");
  document.getElementById("cwStoreItems").innerHTML=[
    ["Profile Boost · 30 minutes","40"],["3 Profile Boosts","100"],["1 Super Like","10"],["5 Super Likes","45"],["10 Extra Likes","30"],["30 Extra Likes","75"],["Priority Visibility · 7 days","100"],["Priority Visibility · 30 days","250"],["Special Profile Badge","100"],["Animated Profile Effect","150"]
  ].map(x=>'<article class="cw-card"><h3>'+x[0]+'</h3><div class="cw-price">'+x[1]+' coins</div><button class="cw-button" disabled>Coming after feature connection</button></article>').join("");
  page.addEventListener("click",async event=>{
    const packageButton=event.target.closest("[data-cw-package]");
    if(packageButton){selected=PACKS.find(p=>p[0]===packageButton.dataset.cwPackage);document.getElementById("cwSelectedPackage").textContent=selected[2]+" · "+selected[3];document.getElementById("cwTransfer").hidden=false;status("Transfer the exact amount, then submit your sender name and reference.");}
    const tierButton=event.target.closest("[data-cw-tier]");
    if(tierButton){
      const tier=tierButton.dataset.cwTier;
      const labels={plus:"Match Plus",quarterly:"Match Quarterly",annual:"Match Annual"};
      if(!window.confirm("Use coins from your wallet to activate "+labels[tier]+"?"))return;
      tierButton.disabled=true;status("Activating "+labels[tier]+"…");
      try{
        const {data,error}=await db.rpc("coin_buy_membership",{p_tier:tier,p_idempotency_key:"membership:"+tier+":"+crypto.randomUUID()});
        if(error)throw error;
        await refresh();
        status(labels[tier]+" activated successfully. Your wallet balance is "+Number(data||0).toLocaleString("en-NG")+" coins.");
      }catch(e){status(e.message||"Could not activate membership.");}
      finally{tierButton.disabled=false;}
    }
    const tab=event.target.closest("[data-cw-tab]");if(tab){setTab(tab.dataset.cwTab);if(tab.dataset.cwTab==="history")refresh().catch(e=>status(e.message));}
  });
  document.getElementById("cwPurchaseForm").addEventListener("submit",async event=>{
    event.preventDefault();const button=event.submitter;button.disabled=true;status("Submitting your transfer for admin review…");
    try{await getUser();const {data,error}=await db.rpc("coin_submit_purchase",{p_package_code:selected?.[0],p_sender_name:document.getElementById("cwSender").value.trim(),p_transfer_reference:document.getElementById("cwReference").value.trim()});if(error)throw error;document.getElementById("cwPurchaseForm").reset();document.getElementById("cwTransfer").hidden=true;selected=null;status("Your request has been submitted. Coins will appear after an administrator verifies your transfer.");await refresh();}
    catch(e){status(e.message||"Could not submit your request.");}finally{button.disabled=false;}
  });
  const adminSection=document.createElement("section");adminSection.className="admin-feature-section";adminSection.innerHTML='<div class="admin-section-heading admin-queue-heading"><div><p class="admin-eyebrow">COIN WALLET</p><h3>Pending coin transfers</h3></div><button type="button" id="cwAdminRefresh" class="admin-refresh-button">↻ Refresh</button></div><div id="cwAdminQueue" class="admin-queue-list">Open the admin dashboard to load requests.</div>';
  document.querySelector("#adminPanel .admin-shell")?.appendChild(adminSection);
  async function loadAdminQueue(){
    const target=document.getElementById("cwAdminQueue");if(!target)return;target.textContent="Checking administrator access…";
    try{const {data:ok,error:authError}=await db.rpc("is_match_admin");if(authError||ok!==true)throw new Error("Administrator access required.");
      const {data,error}=await db.from("coin_purchase_requests").select("id,user_id,package_code,coins,amount_ngn,sender_name,transfer_reference,created_at").eq("status","pending").order("created_at",{ascending:true});
      if(error)throw error;if(!data?.length){target.textContent="No pending coin transfers.";return;}
      target.replaceChildren();
      data.forEach(request=>{const card=document.createElement("article");card.className="cw-admin-card";const title=document.createElement("strong");title.textContent=request.coins+" coins · "+money(request.amount_ngn);const detail=document.createElement("p");detail.className="cw-muted";detail.textContent="Member: "+request.user_id+" · Sender: "+request.sender_name+" · Ref: "+request.transfer_reference+" · "+new Date(request.created_at).toLocaleString();const actions=document.createElement("div");actions.className="cw-actions";const approve=document.createElement("button");approve.className="cw-button primary";approve.textContent="Approve & credit";const reject=document.createElement("button");reject.className="cw-button";reject.textContent="Reject";approve.onclick=()=>review(request.id,"approved",null,approve);reject.onclick=()=>{const reason=window.prompt("Enter the reason for rejecting this transfer:");if(reason)review(request.id,"rejected",reason,reject);};actions.append(approve,reject);card.append(title,detail,actions);target.append(card);});
    }catch(e){target.textContent=e.message||"Could not load coin requests.";}
  }
  async function review(id,decision,reason,button){button.disabled=true;try{const {error}=await db.rpc("coin_admin_review_purchase",{p_request_id:id,p_decision:decision,p_reason:reason});if(error)throw error;await loadAdminQueue();}catch(e){alert(e.message||"Review failed.");button.disabled=false;}}
  document.getElementById("cwAdminRefresh")?.addEventListener("click",loadAdminQueue);
  const originalShow=window.show;
  document.addEventListener("click",async event=>{
    const navButton=event.target.closest('#bottomNavigation [data-page="coinWalletPage"]');if(!navButton)return;
    event.preventDefault();event.stopImmediatePropagation();
    document.querySelectorAll("section.panel").forEach(el=>el.classList.add("hidden"));page.classList.remove("hidden");
    document.querySelectorAll("#bottomNavigation button").forEach(b=>b.classList.toggle("active",b===navButton));
    document.querySelector(".hero")?.classList.add("hidden");
    try{await refresh();status("");}catch(e){status(e.message||"Wallet unavailable.");}
    window.scrollTo(0,0);
  },true);
  document.getElementById("cwBack").addEventListener("click",()=>{page.classList.add("hidden");if(originalShow)originalShow("discover");});
  document.getElementById("openAdminDashboardBtn")?.addEventListener("click",()=>setTimeout(loadAdminQueue,500));
  document.getElementById("adminRefreshBtn")?.addEventListener("click",()=>setTimeout(loadAdminQueue,500));
  document.getElementById("adminOpenCoinWalletBtn")?.addEventListener("click",loadAdminQueue);

  document.getElementById("adminPanel")?.addEventListener("transitionend",loadAdminQueue);
  page.querySelector('[data-cw-tab="plus"]')?.addEventListener("click",()=>setTab("plus"));
  page.querySelector('[data-cw-tab="store"]')?.addEventListener("click",()=>setTab("store"));
  document.getElementById("adminPanel")?.querySelector(".admin-shell")?.addEventListener("click",event=>{if(event.target.closest("#adminRefreshBtn"))loadAdminQueue();});
})();
