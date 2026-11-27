(() => {
  const config = window.THE_MATCH_ADVERTISER_CONFIG || {};
  const $ = (id) => document.getElementById(id);
  const state = { client: null, session: null, pendingCampaign: null, pendingBank: null, creativeFile: null, posterFile: null };
  const formatNaira = (amount) => new Intl.NumberFormat("en-NG", { style: "currency", currency: "NGN", maximumFractionDigits: 0 }).format(Number(amount || 0));
  const formatDate = (value) => value ? new Date(value).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short", timeZone: "Africa/Lagos" }) + " WAT" : "—";
  const message = (target, text, error = false) => { const el = $(target); if (!el) return; el.textContent = text || ""; el.classList.toggle("error", !!error); };
  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[char]));
  const callApi = async (body) => {
    const { data, error } = await state.client.functions.invoke("advertising-api", { body });
    if (error) throw new Error(error.message || "Advertising request failed.");
    if (data?.error) throw new Error(data.error);
    return data;
  };
  const showAuthTab = (tab) => {
    document.querySelectorAll("[data-auth-tab]").forEach((button) => button.classList.toggle("active", button.dataset.authTab === tab));
    $("signinForm").classList.toggle("hidden", tab !== "signin");
    $("signupForm").classList.toggle("hidden", tab !== "signup");
    message("authMessage", "");
  };
  const setBusy = (button, busy, label) => { button.disabled = busy; if (busy) { button.dataset.oldLabel = button.textContent; button.textContent = label || "Please wait…"; } else if (button.dataset.oldLabel) { button.textContent = button.dataset.oldLabel; delete button.dataset.oldLabel; } };
  const callMediaUpload = async (campaignId, creative, poster) => {
    const form = new FormData();
    form.append("campaign_id", campaignId);
    form.append("creative", creative, creative.name);
    if (poster) form.append("poster", poster, poster.name);
    const { data: { session } } = await state.client.auth.getSession();
    const response = await fetch(config.supabaseUrl.replace(/\/$/, "") + "/functions/v1/advertising-media-upload", {
      method: "POST",
      headers: { apikey: config.publishableKey, Authorization: "Bearer " + session.access_token },
      body: form,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.success) throw new Error(data.error || "Creative upload failed.");
    return data;
  };
  const createPoster = async (file) => {
    const objectUrl = URL.createObjectURL(file);
    try {
      const video = document.createElement("video");
      video.muted = true; video.playsInline = true; video.preload = "metadata"; video.src = objectUrl;
      await new Promise((resolve, reject) => { video.onloadeddata = resolve; video.onerror = reject; });
      video.currentTime = Math.min(0.5, Math.max(0, video.duration / 4));
      await new Promise((resolve) => { video.onseeked = resolve; });
      const canvas = document.createElement("canvas");
      const ratio = 4 / 5;
      const sourceRatio = video.videoWidth / video.videoHeight;
      let sx = 0, sy = 0, sw = video.videoWidth, sh = video.videoHeight;
      if (sourceRatio > ratio) { sw = video.videoHeight * ratio; sx = (video.videoWidth - sw) / 2; }
      else { sh = video.videoWidth / ratio; sy = (video.videoHeight - sh) / 2; }
      canvas.width = 720; canvas.height = 900;
      canvas.getContext("2d").drawImage(video, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.86));
      if (!blob) throw new Error("Could not create a video poster.");
      return new File([blob], "advert-poster.jpg", { type: "image/jpeg" });
    } finally { URL.revokeObjectURL(objectUrl); }
  };
  const refreshCampaigns = async () => {
    const result = await callApi({ action: "list-campaigns" });
    const campaigns = result.campaigns || [];
    $("campaignList").innerHTML = campaigns.length ? campaigns.map((campaign) => `
      <article class="campaign-item" data-campaign-id="${escapeHtml(campaign.id)}" data-campaign-status="${escapeHtml(campaign.status)}" data-payment-ids="${escapeHtml((campaign.advertising_payments || []).filter((p) => p.status === "confirmed").map((p) => p.id).join(","))}">
        <h3>${escapeHtml(campaign.headline)}</h3>
        <div class="campaign-meta"><span class="status ${campaign.status === "active" ? "active" : ""}">${escapeHtml(campaign.status.replaceAll("_"," "))}</span><span class="status">${campaign.package_days} days</span><span class="status">${formatNaira(campaign.package_price_ngn)}</span></div>
        <p>Payment: ${escapeHtml(campaign.payment_status.replaceAll("_"," "))}</p>
        <p>Reference: <strong>${escapeHtml(campaign.payment_reference)}</strong></p>
        <p>Live: ${formatDate(campaign.go_live_at)} · Ends: ${formatDate(campaign.ends_at)}</p>
        <div class="campaign-actions"><button class="small-outline" data-metrics="${escapeHtml(campaign.id)}">View performance</button>${campaign.status === "awaiting_payment" && campaign.payment_status === "awaiting_payment" ? `<button class="small-outline" data-resume-payment="${escapeHtml(campaign.id)}">Resume payment</button>` : ""}</div>
        <div class="fineprint" id="metrics-${escapeHtml(campaign.id)}"></div>
      </article>`).join("") : '<p class="muted">You have no campaigns yet. Create your first sponsored advert to get started.</p>';
    $("campaignList").querySelectorAll("[data-resume-payment]").forEach((button) => button.addEventListener("click", async () => {
      button.disabled = true;
      try {
        const result = await callApi({ action: "get-payment-details", campaign_id: button.dataset.resumePayment });
        $("bankName").textContent = result.bank_transfer.bank_name;
        $("bankAccountName").textContent = result.bank_transfer.account_name;
        $("bankAccountNumber").textContent = result.bank_transfer.account_number;
        $("bankAmount").textContent = formatNaira(result.campaign.amount_ngn);
        $("bankReference").textContent = result.campaign.payment_reference;
        $("bankDeadline").textContent = formatDate(result.payment_deadline_at);
        $("paymentForm").dataset.campaignId = result.campaign.campaign_id;
        $("paymentForm").dataset.amount = result.campaign.amount_ngn;
        $("paymentStep").classList.remove("hidden");
        $("paymentStep").scrollIntoView({ behavior:"smooth", block:"start" });
      } catch (error) { message("globalMessage", error.message, true); }
      finally { button.disabled = false; }
    }));
    $("campaignList").querySelectorAll("[data-metrics]").forEach((button) => button.addEventListener("click", async () => {
      button.disabled = true;
      try {
        const result = await callApi({ action: "get-metrics", campaign_id: button.dataset.metrics });
        const m = result.metrics;
        $("metrics-" + button.dataset.metrics).textContent = m ? `Impressions: ${m.impressions} · Clicks: ${m.clicks} · CTR: ${m.ctr}%` : "No performance data yet.";
      } catch (error) { message("globalMessage", error.message, true); }
      finally { button.disabled = false; }
    }));
  };
  const loadAdminPanel = async () => {
    try {
      const overview = await callApi({ action: "admin-overview" });
      $("adminPanel").classList.remove("hidden");
      $("adminOverview").innerHTML = `
        <div class="admin-stat"><strong>${overview.campaigns_total}</strong><span>Campaigns</span></div>
        <div class="admin-stat"><strong>${overview.confirmed_payments}</strong><span>Confirmed transfers</span></div>
        <div class="admin-stat"><strong>${formatNaira(overview.confirmed_revenue_ngn)}</strong><span>Confirmed revenue</span></div>`;
      const [campaignData, paymentData] = await Promise.all([
        callApi({ action: "admin-list-campaigns" }), callApi({ action: "admin-list-payments" }),
      ]);
      $("adminCampaigns").innerHTML = (campaignData.campaigns || []).map((c) => `
        <div class="admin-row"><strong>${escapeHtml(c.headline)}</strong><p>${escapeHtml(c.advertiser_profiles?.display_name)} · ${escapeHtml(c.status)} · ${formatNaira(c.package_price_ngn)}</p>
        <div class="campaign-actions"><button class="small-outline" data-preview="${c.id}">Preview creative</button><button class="small-outline" data-approve="${c.id}">Approve</button><button class="small-outline" data-reject="${c.id}">Reject</button><button class="small-outline" data-pause="${c.id}">${c.status === "paused" ? "Resume" : "Pause"}</button></div></div>`).join("") || '<p class="muted">No campaigns.</p>';
      $("adminPayments").innerHTML = (paymentData.payments || []).map((p) => `
        <div class="admin-row"><strong>${formatNaira(p.amount_ngn)} · ${escapeHtml(p.status)}</strong><p>${escapeHtml(p.advertising_campaigns?.headline)} · ${escapeHtml(p.advertiser_profiles?.display_name)}</p><p>Transfer ref: ${escapeHtml(p.bank_transfer_reference)}</p>
        ${p.status === "submitted" ? `<button class="small-outline" data-confirm-payment="${p.id}">Confirm bank transfer</button>` : ""}</div>`).join("") || '<p class="muted">No submitted transfers.</p>';
      $("adminCampaigns").querySelectorAll("[data-preview]").forEach((b) => b.addEventListener("click", async () => {
        try { const result = await callApi({ action: "admin-preview-creative", campaign_id: b.dataset.preview }); window.open(result.preview_url, "_blank", "noopener"); }
        catch (error) { message("globalMessage", error.message, true); }
      }));
      $("adminCampaigns").querySelectorAll("[data-approve]").forEach((b) => b.addEventListener("click", () => adminReview(b.dataset.approve, true)));
      $("adminCampaigns").querySelectorAll("[data-reject]").forEach((b) => b.addEventListener("click", () => adminReview(b.dataset.reject, false)));
      $("adminCampaigns").querySelectorAll("[data-pause]").forEach((b) => b.addEventListener("click", async () => {
        const action = b.textContent === "Resume" ? "resume" : "pause";
        try { await callApi({ action: "admin-set-campaign-state", campaign_id: b.dataset.pause, state_action: action }); await loadAdminPanel(); }
        catch (error) { message("globalMessage", error.message, true); }
      }));
      $("adminPayments").querySelectorAll("[data-confirm-payment]").forEach((b) => b.addEventListener("click", async () => {
        if (!confirm("Confirm that the actual incoming bank transaction has been verified?")) return;
        try { await callApi({ action: "admin-confirm-payment", payment_id: b.dataset.confirmPayment }); await loadAdminPanel(); await refreshCampaigns(); }
        catch (error) { message("globalMessage", error.message, true); }
      }));
    } catch { $("adminPanel").classList.add("hidden"); }
  };
  const adminReview = async (campaignId, approve) => {
    const reason = approve ? "" : prompt("Enter the reason for rejecting this advert:");
    if (!approve && (!reason || reason.trim().length < 3)) return;
    try { await callApi({ action: "admin-review-campaign", campaign_id: campaignId, approve, reason }); await loadAdminPanel(); await refreshCampaigns(); }
    catch (error) { message("globalMessage", error.message, true); }
  };
  const showDashboard = async (session) => {
    state.session = session;
    $("authView").classList.add("hidden"); $("dashboardView").classList.remove("hidden");
    $("welcomeText").textContent = session.user?.email ? "Signed in as " + session.user.email : "Manage your sponsored advertising.";
    try { await refreshCampaigns(); await loadAdminPanel(); }
    catch (error) { message("globalMessage", error.message, true); }
  };

  if (!config.supabaseUrl || !config.publishableKey || !window.supabase?.createClient) {
    $("setupNotice").classList.remove("hidden");
    $("setupNotice").textContent = "Advertiser portal setup is pending: the separate advertiser Supabase project has not been connected yet. This portal is intentionally not connected to Match member login.";
    $("authView").querySelectorAll("button,input,select").forEach((el) => el.disabled = true);
    return;
  }

  state.client = window.supabase.createClient(config.supabaseUrl, config.publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  document.querySelectorAll("[data-auth-tab]").forEach((button) => button.addEventListener("click", () => showAuthTab(button.dataset.authTab)));
  $("signupType").addEventListener("change", () => { $("signupNameLabel").firstChild.textContent = $("signupType").value === "business" ? "Business / organisation name" : "Your name"; });
  $("signinForm").addEventListener("submit", async (event) => {
    event.preventDefault(); const button = event.submitter; setBusy(button,true);
    const { data, error } = await state.client.auth.signInWithPassword({ email: $("signinEmail").value.trim(), password: $("signinPassword").value });
    setBusy(button,false);
    if (error) return message("authMessage", error.message, true);
    await showDashboard(data.session);
  });
  $("signupForm").addEventListener("submit", async (event) => {
    event.preventDefault(); const button = event.submitter; setBusy(button,true);
    const type = $("signupType").value, displayName = $("signupName").value.trim();
    const { data, error } = await state.client.auth.signUp({
      email: $("signupEmail").value.trim(), password: $("signupPassword").value,
      options: { data: { advertiser_type: type, display_name: displayName }, emailRedirectTo: window.location.href.split("#")[0] },
    });
    setBusy(button,false);
    if (error) return message("authMessage", error.message, true);
    if (data.session) {
      await state.client.from("advertiser_profiles").update({ contact_name: $("signupContact").value.trim() || null, phone: $("signupPhone").value.trim() || null }).eq("user_id", data.user.id);
      await showDashboard(data.session);
    } else message("authMessage", "Account created. Check your email to verify your advertiser account, then sign in.");
  });
  $("googleSignIn").addEventListener("click", async () => {
    const { error } = await state.client.auth.signInWithOAuth({ provider: "google", options: { redirectTo: window.location.href.split("#")[0] } });
    if (error) message("authMessage", error.message, true);
  });
  $("forgotPassword").addEventListener("click", async () => {
    const email = $("signinEmail").value.trim();
    if (!email) return message("authMessage", "Enter your email address first.");
    const { error } = await state.client.auth.resetPasswordForEmail(email, { redirectTo: window.location.href.split("#")[0] });
    message("authMessage", error ? error.message : "If an account exists for that email, a recovery link has been sent.", !!error);
  });
  $("signOut").addEventListener("click", async () => { await state.client.auth.signOut(); state.session = null; $("dashboardView").classList.add("hidden"); $("authView").classList.remove("hidden"); });
  $("campaignPackage").addEventListener("change", () => { $("packagePrice").textContent = formatNaira(({7:12000,14:22000,30:40000})[$("campaignPackage").value]); });
  $("campaignStartMode").addEventListener("change", () => $("scheduleField").classList.toggle("hidden", $("campaignStartMode").value !== "scheduled"));
  $("campaignCreative").addEventListener("change", async () => {
    const file = $("campaignCreative").files?.[0]; state.creativeFile = file || null; state.posterFile = null;
    const preview = $("creativePreview"); preview.innerHTML = "";
    if (!file) { preview.textContent = "Your creative preview appears here"; return; }
    if (file.type.startsWith("image/")) {
      const img = document.createElement("img"); img.src = URL.createObjectURL(file); img.onload = () => URL.revokeObjectURL(img.src); preview.append(img);
    } else if (file.type === "video/mp4") {
      const video = document.createElement("video"); video.src = URL.createObjectURL(file); video.controls = true; video.muted = true; preview.append(video);
      try { state.posterFile = await createPoster(file); } catch (error) { message("globalMessage", error.message, true); }
    } else { preview.textContent = "Choose a JPG, PNG, WebP or MP4 file."; }
  });
  $("campaignForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = $("createCampaignButton");
    setBusy(button, true, "Preparing campaign…");
    try {
      if (!state.creativeFile) throw new Error("Choose an image or video creative first.");
      let campaign = state.pendingCampaign;
      let created = null;
      if (!campaign) {
        const startMode = $("campaignStartMode").value;
        let scheduled = null;
        if (startMode === "scheduled") {
          const raw = $("campaignSchedule").value;
          if (!raw) throw new Error("Choose a scheduled start time in WAT.");
          scheduled = new Date(raw + ":00+01:00");
          if (Number.isNaN(scheduled.getTime()) || scheduled.getTime() <= Date.now()) throw new Error("Scheduled start must be in the future.");
        }
        created = await callApi({
          action: "create-campaign",
          headline: $("campaignHeadline").value,
          description: $("campaignDescription").value,
          cta: $("campaignCta").value,
          destination_url: $("campaignUrl").value,
          package_days: Number($("campaignPackage").value),
          start_mode: startMode,
          scheduled_start_at: scheduled?.toISOString() ?? null,
        });
        campaign = created.campaign;
        state.pendingCampaign = campaign;
        state.pendingBank = created.bank_transfer;
      }
      setBusy(button, true, "Uploading creative…");
      await callMediaUpload(campaign.campaign_id, state.creativeFile, state.posterFile);
      if (!created) created = await callApi({ action: "get-payment-details", campaign_id: campaign.campaign_id });
      if (!created.bank_transfer) created.bank_transfer = state.pendingBank;
      $("bankName").textContent = created.bank_transfer.bank_name;
      $("bankAccountName").textContent = created.bank_transfer.account_name;
      $("bankAccountNumber").textContent = created.bank_transfer.account_number;
      $("bankAmount").textContent = formatNaira(campaign.amount_ngn ?? created.campaign.amount_ngn);
      $("bankReference").textContent = campaign.payment_reference ?? created.campaign.payment_reference;
      $("bankDeadline").textContent = formatDate(created.payment_deadline_at);
      $("paymentStep").classList.remove("hidden");
      $("paymentForm").dataset.campaignId = campaign.campaign_id ?? created.campaign.campaign_id;
      $("paymentForm").dataset.amount = campaign.amount_ngn ?? created.campaign.amount_ngn;
      message("globalMessage", "Campaign created and creative uploaded. Complete the transfer within 24 hours.");
      await refreshCampaigns();
      $("paymentStep").scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (error) {
      message("globalMessage", error.message, true);
    } finally {
      setBusy(button, false);
    }
  });
  $("paymentForm").addEventListener("submit", async (event) => {
    event.preventDefault(); const button = event.submitter; setBusy(button,true);
    try {
      await callApi({
        action: "submit-payment",
        campaign_id: $("paymentForm").dataset.campaignId,
        amount_ngn: Number($("paymentForm").dataset.amount),
        bank_transfer_reference: $("transferReference").value.trim(),
      });
      message("globalMessage","Transfer details submitted. Your advert is awaiting manual bank confirmation and campaign approval.");
      $("paymentStep").classList.add("hidden"); $("campaignForm").reset(); $("creativePreview").textContent = "Your creative preview appears here"; state.creativeFile = null; state.posterFile = null; state.pendingCampaign = null; state.pendingBank = null;
      await refreshCampaigns();
    } catch (error) { message("globalMessage",error.message,true); }
    finally { setBusy(button,false); }
  });
  $("refreshCampaigns").addEventListener("click", async () => { try { await refreshCampaigns(); await loadAdminPanel(); } catch (error) { message("globalMessage",error.message,true); } });
  $("copyAccount").addEventListener("click", () => navigator.clipboard?.writeText($("bankAccountNumber").textContent));
  $("copyReference").addEventListener("click", () => navigator.clipboard?.writeText($("bankReference").textContent));
  window.TheMatchAdvertisingPortal = { callApi, refreshCampaigns, message, escapeHtml, formatNaira };
  state.client.auth.onAuthStateChange((_event, session) => { if (session && $("dashboardView").classList.contains("hidden")) showDashboard(session); });
  state.client.auth.getSession().then(({ data }) => { if (data.session) showDashboard(data.session); });
})();
