(() => {
  "use strict";
  // The main app exposes Supabase as a top-level lexical `const db`, not window.client.
  // Classic scripts share the global lexical environment, so reuse that same client.
  if (typeof db === "undefined" || !db) {
    console.error("Coin wallet could not find the app Supabase client.");
    return;
  }
  const client = db;
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
    #coinWalletPage{color:#f5f2ed;padding:18px 0 110px;background:radial-gradient(ellipse at 12% 0%,rgba(70,150,143,.13),transparent 45%)}
    #coinWalletPage .cw-shell{max-width:760px;margin:auto;padding:0 14px}
    #coinWalletPage .cw-hero{position:relative;overflow:hidden;padding:24px;border:1px solid rgba(221,190,125,.48);border-radius:26px;background:radial-gradient(circle at 88% 18%,rgba(79,169,157,.27),transparent 32%),linear-gradient(135deg,#102a30 0%,#172b2b 42%,#191813 100%);box-shadow:0 16px 38px rgba(0,0,0,.28)}
    #coinWalletPage .cw-hero:after{content:"✦";position:absolute;right:22px;top:34px;font-size:68px;color:rgba(226,199,143,.22);text-shadow:0 0 26px rgba(111,211,194,.25);pointer-events:none}
    #coinWalletPage .cw-kicker{color:#d9bd83;font-size:10px;font-weight:850;letter-spacing:2.3px}
    #coinWalletPage h2{margin:8px 0;color:#fff0d0;font-size:27px}
    #coinWalletPage .cw-balance{font-size:42px;font-weight:900;letter-spacing:-1px;color:#e8ca8a;text-shadow:0 4px 18px rgba(232,202,138,.15)}
    #coinWalletPage .cw-tabs{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin:18px 0}
    #coinWalletPage .cw-tabs button,#coinWalletPage .cw-button{border:1px solid rgba(213,184,125,.42);border-radius:14px;padding:12px 10px;background:linear-gradient(145deg,#182e30,#151817);color:#e8d4a7;font-weight:750;transition:transform .18s,border-color .18s,filter .18s}
    #coinWalletPage .cw-tabs button{font-size:12px;min-height:54px}
    #coinWalletPage .cw-tabs button.active,#coinWalletPage .cw-button.primary{background:linear-gradient(120deg,#f0d89d,#c69a52);border-color:#f0d89d;color:#1c211d;box-shadow:0 7px 18px rgba(198,154,82,.2)}
    #coinWalletPage .cw-button:active{transform:scale(.98)}
    #coinWalletPage .cw-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
    #coinWalletPage .cw-card{position:relative;padding:17px;border:1px solid rgba(102,164,154,.28);border-radius:18px;background:linear-gradient(145deg,#172729,#151918 70%);box-shadow:0 8px 22px rgba(0,0,0,.16)}
    #coinWalletPage .cw-card h3{margin:0 0 7px;color:#f4e8d0}
    #coinWalletPage .cw-card .cw-button{margin-top:12px;width:100%}
    #coinWalletPage .cw-muted{color:#b9b9ae;font-size:12px;line-height:1.6}
    #coinWalletPage .cw-price{font-size:24px;font-weight:900;color:#e7c77f;margin:9px 0}
    #coinWalletPage .cw-panel>h3{color:#e8d3a3}
    #coinWalletPage label{display:block;margin:12px 0 5px;color:#d7c9aa;font-size:12px}
    #coinWalletPage input,#coinWalletPage select,#coinWalletPage textarea{width:100%;box-sizing:border-box;padding:12px;border:1px solid #52615a;border-radius:11px;background:#0c1718;color:#fff}
    #coinWalletPage .cw-panel{margin-top:16px}
    #coinWalletPage .cw-row{padding:12px 0;border-bottom:1px solid rgba(213,184,125,.18);display:flex;justify-content:space-between;gap:10px}
    #coinWalletPage .cw-status{min-height:24px;color:#e8ca8a;font-size:12px;padding:8px 2px}
    #coinWalletPage .cw-admin-card{padding:14px;margin:10px 0;border:1px solid #4b665d;border-radius:14px;background:#142323}
    #coinWalletPage .cw-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
    #coinWalletPage .cw-actions button{flex:1}
    #coinWalletPage .cw-account{padding:13px;border:1px dashed rgba(231,199,127,.5);border-radius:13px;background:rgba(8,20,21,.5);margin:12px 0}
    #coinWalletPage .cw-account strong{color:#f0d89d;letter-spacing:.4px}
    #coinWalletPage .cw-package-featured{border-color:#d7b66f;box-shadow:0 0 0 1px rgba(215,182,111,.15),0 10px 25px rgba(0,0,0,.2)}
    #coinWalletPage .cw-package-tag{display:inline-block;padding:4px 8px;border-radius:99px;background:rgba(101,190,173,.16);color:#8cdbcb;font-size:10px;font-weight:800;margin-bottom:8px}
    @media(max-width:480px){#coinWalletPage .cw-grid{grid-template-columns:1fr}#coinWalletPage .cw-balance{font-size:36px}#coinWalletPage .cw-hero{padding:21px}#coinWalletPage .cw-tabs{gap:5px}#coinWalletPage .cw-tabs button{font-size:11px;padding:9px 5px}}
    body.light-theme #coinWalletPage{color:#2e281e;background:#f7f5ef}
    body.light-theme #coinWalletPage .cw-hero{background:linear-gradient(130deg,#e3f0eb,#fff7e7);color:#2e281e}
    body.light-theme #coinWalletPage .cw-hero h2{color:#263c39}
    body.light-theme #coinWalletPage .cw-card{background:#fff;border-color:#d8d1bf}
    body.light-theme #coinWalletPage .cw-card h3{color:#30291f}
    body.light-theme #coinWalletPage .cw-muted{color:#68665f}
    body.light-theme #coinWalletPage input,body.light-theme #coinWalletPage select,body.light-theme #coinWalletPage textarea{background:#fff;color:#241f18}
    body.light-theme #coinWalletPage .cw-account{background:#f5f1e7}
  `;;
  document.head.appendChild(style);
  const page = document.createElement("section");
  page.id = "coinWalletPage"; page.className = "panel hidden";
  page.innerHTML = `
    <div class="cw-shell">
      <div class="cw-hero"><div class="cw-kicker">THE MATCH · COIN WALLET</div><h2>Your Match Coins</h2><div class="cw-balance" id="cwBalance">— coins</div><p class="cw-muted">Buy coins by bank transfer. Coins are added only after an administrator verifies your transfer.</p></div>
      <div class="cw-tabs"><button class="active" data-cw-tab="buy">Buy coins</button><button data-cw-tab="history">Wallet history</button><button data-cw-tab="plus">Match Plus</button><button data-cw-tab="store">Match Store</button></div>
      <div id="cwBuy" class="cw-panel"><h3>Choose a coin package</h3><div class="cw-grid" id="cwPackages"></div>
        <div class="cw-card cw-panel" id="cwTransfer" hidden><h3 id="cwSelectedPackage">Bank transfer</h3><p class="cw-muted">Transfer the exact amount shown below. Your coins are credited only after the administrator confirms receipt.</p>
          <div class="cw-account"><div class="cw-row"><span>Network</span><strong>MTN MoMo</strong></div><div class="cw-row"><span>Account name</span><strong>JUSTICE TRUST UGOALA</strong></div><div class="cw-row"><span>Account number</span><strong id="cwAccountNumber">0896939533</strong></div><button type="button" class="cw-button" id="cwCopyAccount">Copy account number</button></div><p class="cw-muted" id="cwPaymentAmount"></p>
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
  window.openCoinMemberships = async tier => {
    if(typeof window.show==="function")window.show("coinWalletPage");
    setTab("plus");
    try{await refresh();status("");}catch(error){status(error.message||"Wallet unavailable.");}
    if(tier){
      const button=page.querySelector('[data-cw-tier="'+tier+'"]');
      button?.scrollIntoView({behavior:"smooth",block:"center"});
    }
  };
  const getUser = async () => { const {data,error}=await client.auth.getUser();if(error)throw error;if(!data.user)throw new Error("Please sign in to use your coin wallet.");return data.user; };
  async function refresh(){
    const user=await getUser();
    const {data:wallet,error}=await client.from("coin_wallets").select("balance").eq("user_id",user.id).maybeSingle();
    if(error)throw error;
    document.getElementById("cwBalance").textContent=(wallet?.balance||0).toLocaleString("en-NG")+" coins";
    const [ledger,requests]=await Promise.all([
      client.from("coin_ledger").select("amount,entry_type,description,created_at,balance_after").eq("user_id",user.id).order("created_at",{ascending:false}).limit(40),
      client.from("coin_purchase_requests").select("id,coins,amount_ngn,status,admin_note,created_at").eq("user_id",user.id).order("created_at",{ascending:false}).limit(20)
    ]);
    if(ledger.error)throw ledger.error;if(requests.error)throw requests.error;
    document.getElementById("cwLedger").innerHTML=ledger.data?.length?ledger.data.map(x=>'<div class="cw-row"><span><strong>'+esc(x.description)+'</strong><br><small class="cw-muted">'+esc(new Date(x.created_at).toLocaleString())+'</small></span><strong style="color:'+(x.amount>0?'#62c78c':'#d58c8c')+'">'+(x.amount>0?'+':'')+x.amount+' coins</strong></div>').join(""):'No wallet transactions yet.';
    document.getElementById("cwRequests").innerHTML=requests.data?.length?requests.data.map(x=>'<div class="cw-row"><span>'+x.coins+' coins · '+money(x.amount_ngn)+'<br><small class="cw-muted">'+esc(x.admin_note||'Submitted '+new Date(x.created_at).toLocaleString())+'</small></span><strong>'+esc(x.status)+'</strong></div>').join(""):'No coin purchase requests yet.';
  }
  document.getElementById("cwPackages").innerHTML=PACKS.map((p,i)=>'<article class="cw-card '+(i===1?'cw-package-featured':'')+'">'+(i===1?'<span class="cw-package-tag">MOST POPULAR</span>':'')+'<h3>'+p[1]+'</h3><div class="cw-price">'+p[2]+'</div><strong>'+p[3]+'</strong><button class="cw-button primary" data-cw-package="'+p[0]+'">Choose package</button></article>').join("");
  document.getElementById("cwStoreItems").innerHTML=[
    ["Profile Boost · 30 minutes","40"],["3 Profile Boosts","100"],["1 Super Like","10"],["5 Super Likes","45"],["10 Extra Likes","30"],["30 Extra Likes","75"],["Priority Visibility · 7 days","100"],["Priority Visibility · 30 days","250"],["Special Profile Badge","100"],["Animated Profile Effect","150"]
  ].map(x=>'<article class="cw-card"><h3>'+x[0]+'</h3><div class="cw-price">'+x[1]+' coins</div><button class="cw-button" disabled>Coming after feature connection</button></article>').join("");
  page.addEventListener("click",async event=>{
    const packageButton=event.target.closest("[data-cw-package]");
    if(packageButton){selected=PACKS.find(p=>p[0]===packageButton.dataset.cwPackage);document.getElementById("cwSelectedPackage").textContent=selected[2]+" · "+selected[3];document.getElementById("cwPaymentAmount").textContent="Please transfer exactly "+selected[3]+" for "+selected[2]+".";document.getElementById("cwTransfer").hidden=false;status("Transfer the exact amount, then submit your sender name and reference.");document.getElementById("cwTransfer").scrollIntoView({behavior:"smooth",block:"center"});}
    const tierButton=event.target.closest("[data-cw-tier]");
    if(tierButton){
      const tier=tierButton.dataset.cwTier;
      const labels={plus:"Match Plus",quarterly:"Match Quarterly",annual:"Match Annual"};
      const costs={plus:300,quarterly:800,annual:2800};
      if(!(await window.matchConfirm("This will deduct "+costs[tier].toLocaleString("en-NG")+" coins from your wallet and activate "+labels[tier]+". Continue?","Activate "+labels[tier])))return;
      tierButton.disabled=true;status("Activating "+labels[tier]+"…");
      try{
        const {data,error}=await client.rpc("coin_buy_membership",{p_tier:tier,p_idempotency_key:"membership:"+tier+":"+crypto.randomUUID()});
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
    try{await getUser();const {data,error}=await client.rpc("coin_submit_purchase",{p_package_code:selected?.[0],p_sender_name:document.getElementById("cwSender").value.trim(),p_transfer_reference:document.getElementById("cwReference").value.trim()});if(error)throw error;document.getElementById("cwPurchaseForm").reset();document.getElementById("cwTransfer").hidden=true;selected=null;status("Your request has been submitted. Coins will appear after an administrator verifies your transfer.");await refresh();}
    catch(e){status(e.message||"Could not submit your request.");}finally{button.disabled=false;}
  });
  const adminSection=document.createElement("section");adminSection.className="admin-feature-section";adminSection.innerHTML='<div class="admin-section-heading admin-queue-heading"><div><p class="admin-eyebrow">COIN WALLET</p><h3>Pending coin transfers</h3></div><button type="button" id="cwAdminRefresh" class="admin-refresh-button">↻ Refresh</button></div><div id="cwAdminQueue" class="admin-queue-list">Open the admin dashboard to load requests.</div>';
  const adminShell=document.querySelector("#adminPanel .admin-shell");
  const adminWelcome=adminShell?.querySelector(".admin-welcome-strip");
  if(adminWelcome) adminWelcome.insertAdjacentElement("afterend",adminSection);
  else adminShell?.prepend(adminSection);
  async function loadAdminQueue(){
    const target=document.getElementById("cwAdminQueue");if(!target)return;target.textContent="Checking administrator access…";
    try{const {data:ok,error:authError}=await client.rpc("coin_is_admin");if(authError||ok!==true)throw new Error("Administrator access required.");
      const {data,error}=await client.from("coin_purchase_requests").select("id,user_id,package_code,coins,amount_ngn,sender_name,transfer_reference,created_at").eq("status","pending").order("created_at",{ascending:true});
      if(error)throw error;if(!data?.length){target.textContent="No pending coin transfers.";return;}
      target.replaceChildren();
      data.forEach(request=>{const card=document.createElement("article");card.className="cw-admin-card";const title=document.createElement("strong");title.textContent=request.coins+" coins · "+money(request.amount_ngn);const detail=document.createElement("p");detail.className="cw-muted";detail.textContent="Member: "+request.user_id+" · Sender: "+request.sender_name+" · Ref: "+request.transfer_reference+" · "+new Date(request.created_at).toLocaleString();const actions=document.createElement("div");actions.className="cw-actions";const approve=document.createElement("button");approve.className="cw-button primary";approve.textContent="Approve & credit";const reject=document.createElement("button");reject.className="cw-button";reject.textContent="Reject";approve.onclick=()=>review(request.id,"approved",null,approve);reject.onclick=()=>{const reason=window.prompt("Enter the reason for rejecting this transfer:");if(reason)review(request.id,"rejected",reason,reject);};actions.append(approve,reject);card.append(title,detail,actions);target.append(card);});
    }catch(e){target.textContent=e.message||"Could not load coin requests.";}
  }
  async function review(id,decision,reason,button){button.disabled=true;try{const {error}=await client.rpc("coin_admin_review_purchase",{p_request_id:id,p_decision:decision,p_reason:reason});if(error)throw error;await loadAdminQueue();}catch(e){alert(e.message||"Review failed.");button.disabled=false;}}
  document.getElementById("cwAdminRefresh")?.addEventListener("click",loadAdminQueue);
  document.getElementById("cwCopyAccount")?.addEventListener("click",async()=>{try{await navigator.clipboard.writeText("0896939533");status("Account number copied.");}catch(e){status("Please copy the account number manually.");}});
  document.addEventListener("click",async event=>{
    const navButton=event.target.closest('#bottomNavigation [data-page="coinWalletPage"]');if(!navButton)return;
    event.preventDefault();event.stopImmediatePropagation();
    if(typeof window.show==="function")window.show("coinWalletPage");
    try{await refresh();status("");}catch(e){status(e.message||"Wallet unavailable.");}
  },true);
  document.getElementById("cwBack").addEventListener("click",()=>{if(typeof window.show==="function")window.show("discover");});
  document.getElementById("openAdminDashboardBtn")?.addEventListener("click",()=>setTimeout(loadAdminQueue,500));
  document.getElementById("adminRefreshBtn")?.addEventListener("click",()=>setTimeout(loadAdminQueue,500));
  document.getElementById("adminOpenCoinWalletBtn")?.addEventListener("click",loadAdminQueue);

  document.getElementById("adminPanel")?.addEventListener("transitionend",loadAdminQueue);
  window.addEventListener("match:admin-opened",loadAdminQueue);
  page.querySelector('[data-cw-tab="plus"]')?.addEventListener("click",()=>setTab("plus"));
  page.querySelector('[data-cw-tab="store"]')?.addEventListener("click",()=>setTab("store"));
  document.getElementById("adminPanel")?.querySelector(".admin-shell")?.addEventListener("click",event=>{if(event.target.closest("#adminRefreshBtn"))loadAdminQueue();});
})();
