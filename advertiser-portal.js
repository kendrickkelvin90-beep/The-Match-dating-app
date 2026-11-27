(() => {
  const config = window.THE_MATCH_ADVERTISER_CONFIG || {};
  const $ = (id) => document.getElementById(id);
  const state = { client: null, session: null, pendingCampaign: null, pendingBank: null, creativeFile: null, posterFile: null, handlingSession: false };
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
  const callMediaUpload = async (campaignId, creative, poster, changeRequestId = null) => {
    const form = new FormData();
    form.append("campaign_id", campaignId);
    if (changeRequestId) form.append("change_request_id", changeRequestId);
    form.append("creative", creative, creative.name);
    if (poster) form.append("poster", poster, poster.name);
    const { data: { session } } = await state.client.auth.getSession();
    if (!session?.access_token) throw new Error("Your advertiser session has expired. Sign in again before uploading.");
    const response = await fetch((config.supabaseUrl.endsWith("/") ? config.supabaseUrl.slice(0, -1) : config.supabaseUrl) + "/functions/v1/advertiser-register", {
      method: "POST",
      headers: {
        apikey: config.publishableKey,
        Authorization: "Bearer " + session.access_token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || !result.success) throw new Error(result.error || "Advertiser registration could not be completed.");
    const { data, error } = await state.client.auth.refreshSession();
    if (error || !data.session) throw new Error("Registration is saved. Please sign in again to finish activating your advertiser session.");
    return data.session;
  };
  const ensureAdvertiserProfile = async (session) => {
    let activeSession = session;
    if (!isAdvertiserSession(activeSession?.access_token)) {
      const metadata = activeSession?.user?.user_metadata || {};
      if (metadata.the_match_advertiser_registration !== "v1") {
        await state.client.auth.signOut({ scope: "local" });
        throw new Error("This is not an advertiser account. Create an advertiser account with a separate email, or use the Google identity linked to an existing advertiser account.");
      }
      activeSession = await enrollAdvertiserSession(activeSession);
      if (!isAdvertiserSession(activeSession?.access_token)) {
        throw new Error("Your advertiser account is registered, but secure advertiser access is not active yet. Please try again after setup is completed.");
      }
    }
    const metadata = activeSession.user?.user_metadata || {};
    await callApi({
      action: "complete-profile",
      advertiser_type: metadata.advertiser_type,
      display_name: metadata.display_name,
      contact_name: metadata.contact_name,
      phone: metadata.phone,
    });
    return activeSession;
  };
  const showDashboard = async (session) => {
    if (state.handlingSession) return;
    state.handlingSession = true;
    try {
      session = await ensureAdvertiserProfile(session);
    } catch (error) {
      $("dashboardView").classList.add("hidden");
      $("authView").classList.remove("hidden");
      message("authMessage", error.message, true);
      state.handlingSession = false;
      return;
    }
    state.handlingSession = false;
    state.session = session;
    $("authView").classList.add("hidden"); $("dashboardView").classList.remove("hidden");
    $("welcomeText").textContent = session.user?.email ? "Signed in as " + session.user.email : "Manage your sponsored advertising.";
    try { await refreshCampaigns(); await loadAdminPanel(); }
    catch (error) { message("globalMessage", error.message, true); }
  };

  if (!config.supabaseUrl || !config.publishableKey || !window.supabase?.createClient) {
    $("setupNotice").classList.remove("hidden");
    $("setupNotice").textContent = "Advertiser portal setup is pending: the shared Match Supabase project has not been connected yet. Advertiser sessions use a separate browser storage key and a dedicated database role.";
    $("authView").querySelectorAll("button,input,select").forEach((el) => el.disabled = true);
    return;
  }

  state.client = window.supabase.createClient(config.supabaseUrl, config.publishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: "the-match-advertiser-auth",
    },
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
      options: { data: {
        the_match_advertiser_registration: "v1",
        advertiser_type: type,
        display_name: displayName,
        contact_name: $("signupContact").value.trim(),
        phone: $("signupPhone").value.trim(),
      }, emailRedirectTo: window.location.href.split("#")[0] },
    });
    setBusy(button,false);
    if (error) return message("authMessage", error.message, true);
    if (data.session) {
      await showDashboard(data.session);
    } else message("authMessage", "Account created. Check your email to verify your advertiser account, then sign in.");
  });
  $("googleSignIn").addEventListener("click", async () => {
    const { error } = await state.client.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: window.location.href.split("#")[0] },
    });
    if (error) message("authMessage", error.message, true);
  });
  $("linkGoogle").addEventListener("click", async () => {
    try {
      const { data: { session } } = await state.client.auth.getSession();
      if (!isAdvertiserSession(session?.access_token)) {
        throw new Error("Sign in to your advertiser account before linking Google.");
      }
      const { error } = await state.client.auth.linkIdentity({
        provider: "google",
        options: { redirectTo: window.location.href.split("#")[0] },
      });
      if (error) throw error;
    } catch (error) {
      message("globalMessage", error.message || "Google linking is unavailable right now.", true);
    }
  });
  $("forgotPassword").addEventListener("click", async () => {
    const email = $("signinEmail").value.trim();
    if (!email) return message("authMessage", "Enter your email address first.");
    const { error } = await state.client.auth.resetPasswordForEmail(email, { redirectTo: window.location.href.split("#")[0] });
    message("authMessage", error ? error.message : "If an account exists for that email, a recovery link has been sent.", !!error);
  });
  $("signOut").addEventListener("click", async () => { await state.client.auth.signOut({ scope: "local" }); state.session = null; $("dashboardView").classList.add("hidden"); $("authView").classList.remove("hidden"); });
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
  window.TheMatchAdvertisingPortal = { callApi, callMediaUpload, createPoster, client: state.client, refreshCampaigns, message, escapeHtml, formatNaira };
  state.client.auth.onAuthStateChange((_event, session) => { if (session && $("dashboardView").classList.contains("hidden")) showDashboard(session); });
  state.client.auth.getSession().then(({ data }) => { if (data.session) showDashboard(data.session); });
})();
