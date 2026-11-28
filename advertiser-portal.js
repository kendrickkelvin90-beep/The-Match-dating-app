(() => {
  const config = window.THE_MATCH_ADVERTISER_CONFIG || {};
  const $ = (id) => document.getElementById(id);
  const state = { client: null, session: null, pendingCampaign: null, pendingBank: null, creativeFile: null, posterFile: null, handlingSession: false, passwordRecovery: false, pendingEnrollmentSession: null, previewObjectUrl: null };
  // Return to the exact Match page that opened this portal (normally the signed-in Profile).
  // Do not send members to "/" directly: that can restart the app at its public welcome screen.
  const returnLink = document.querySelector(".return-to-match");
  if (returnLink) {
    returnLink.addEventListener("click", (event) => {
      const referrer = document.referrer;
      let sameOriginReferrer = false;
      try { sameOriginReferrer = !!referrer && new URL(referrer).origin === window.location.origin; } catch {}
      if (sameOriginReferrer && window.history.length > 1) {
        event.preventDefault();
        window.history.back();
      }
    });
  }
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
    $("advertiserEnrollmentForm").classList.add("hidden");
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
      if (Number.isFinite(video.duration) && video.duration > 30) throw new Error("Advert videos must be 30 seconds or shorter.");
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
    const campaigns = (result.campaigns || []).filter((campaign) => campaign.status !== "deleted");
    $("campaignList").innerHTML = campaigns.length ? campaigns.map((campaign) => `
      <article class="campaign-item" data-campaign-id="${escapeHtml(campaign.id)}" data-campaign-status="${escapeHtml(campaign.status)}" data-has-pending-change="${(campaign.advertising_campaign_change_requests || []).some((request) => request.status === "pending") ? "true" : "false"}" data-pending-change-request="${escapeHtml((campaign.advertising_campaign_change_requests || []).find((request) => request.status === "pending")?.id || "")}" data-pending-change-creative="${(campaign.advertising_campaign_change_requests || []).find((request) => request.status === "pending")?.proposed_creative_id ? "true" : "false"}" data-has-creative="${(campaign.advertising_creatives || []).some((creative) => creative.is_current) ? "true" : "false"}" data-payment-ids="${escapeHtml((campaign.advertising_payments || []).filter((p) => p.status === "duplicate" || (campaign.status === "rejected" && p.status === "confirmed")).map((p) => p.id).join(","))}">
        <h3>${escapeHtml(campaign.headline)}</h3>
        <div class="campaign-meta"><span class="status ${campaign.status === "active" ? "active" : ""}">${escapeHtml(campaign.status.replaceAll("_"," "))}</span><span class="status">${campaign.package_days} days</span><span class="status">${formatNaira(campaign.package_price_ngn)}</span></div>
        <p>Payment: ${escapeHtml(campaign.payment_status.replaceAll("_"," "))}</p>
        <p>Reference: <strong>${escapeHtml(campaign.payment_reference)}</strong></p>
        <p>Live: ${formatDate(campaign.go_live_at)} · Ends: ${formatDate(campaign.ends_at)}</p>
        ${(campaign.advertising_campaign_change_requests || []).slice().sort((a,b) => new Date(b.created_at) - new Date(a.created_at)).slice(0,1).map((request) => "<p class=\"fineprint\">Latest change request: <strong>" + escapeHtml(request.status.replaceAll("_"," ")) + "</strong>" + (request.admin_reason ? " · Admin note: " + escapeHtml(request.admin_reason) : "") + "</p>").join("")}
        <div class="campaign-actions"><button class="small-outline" data-metrics="${escapeHtml(campaign.id)}">View performance</button>${campaign.status === "awaiting_payment" && campaign.payment_status === "awaiting_payment" ? `${(campaign.advertising_creatives || []).some((creative) => creative.is_current) ? `<button class="small-outline" data-resume-payment="${escapeHtml(campaign.id)}">Resume payment</button>` : `<button class="small-outline" data-finish-creative="${escapeHtml(campaign.id)}">Finish creative</button>`}<button class="small-outline" data-cancel-campaign="${escapeHtml(campaign.id)}">Cancel reservation</button>` : ""}${campaign.status !== "deleted" ? `<button class="small-outline" data-delete-campaign="${escapeHtml(campaign.id)}">Delete advert</button>` : ""}</div>
        <div class="fineprint" id="metrics-${escapeHtml(campaign.id)}"></div>
      </article>`).join("") : '<p class="muted">You have no campaigns yet. Create your first sponsored advert to get started.</p>';
    $("campaignList").querySelectorAll("[data-finish-creative]").forEach((button) => button.addEventListener("click", () => {
      const campaign = campaigns.find((item) => item.id === button.dataset.finishCreative);
      if (!campaign) return;
      state.pendingCampaign = {
        campaign_id: campaign.id,
        amount_ngn: campaign.package_price_ngn,
        payment_reference: campaign.payment_reference,
      };
      $("campaignHeadline").value = campaign.headline || "";
      $("campaignDescription").value = campaign.description || "";
      $("campaignCta").value = campaign.cta || "learn_more";
      $("campaignUrl").value = campaign.destination_url || "";
      $("campaignPackage").value = String(campaign.package_days || 7);
      $("packagePrice").textContent = formatNaira(campaign.package_price_ngn);
      $("campaignCreative").click();
      $("campaignForm").scrollIntoView({ behavior: "smooth", block: "start" });
      message("globalMessage", "Choose the creative for this existing unpaid campaign. It will not create a second reservation.");
    }));
    $("campaignList").querySelectorAll("[data-cancel-campaign]").forEach((button) => button.addEventListener("click", async () => {
      if (!confirm("Cancel this unpaid campaign reservation?")) return;
      button.disabled = true;
      try { await callApi({ action: "cancel-campaign", campaign_id: button.dataset.cancelCampaign }); message("globalMessage", "Unpaid campaign reservation cancelled."); await refreshCampaigns(); }
      catch (error) { message("globalMessage", error.message, true); button.disabled = false; }
    }));
    $("campaignList").querySelectorAll("[data-delete-campaign]").forEach((button) => button.addEventListener("click", async () => {
      if (!confirm("Delete this advert? It will immediately stop appearing in Discover and disappear from your campaign list. Payment and campaign records will be retained for accounting. This action cannot be undone.")) return;
      button.disabled = true;
      try {
        await callApi({ action: "delete-campaign", campaign_id: button.dataset.deleteCampaign });
        message("globalMessage", "Advert deleted. It will no longer appear in Discover.");
        await refreshCampaigns();
      } catch (error) { message("globalMessage", error.message || "The advert could not be deleted.", true); button.disabled = false; }
    }));
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

  const ensureAdminPreviewDialog = () => {
    let dialog = $("adminCreativePreview");
    if (dialog) return dialog;
    dialog = document.createElement("dialog");
    dialog.id = "adminCreativePreview";
    dialog.className = "admin-preview-dialog";
    dialog.innerHTML = '<div class="admin-preview-head"><div><p class="eyebrow">PRIVATE CREATIVE REVIEW</p><h3 id="adminPreviewTitle">Advert creative</h3></div><button type="button" class="small-outline" id="closeAdminPreview" aria-label="Close preview">Close</button></div><div id="adminPreviewMedia" class="admin-preview-media"></div><div id="adminPreviewMeta" class="admin-preview-meta"></div>';
    document.body.append(dialog);
    $("closeAdminPreview").addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
    return dialog;
  };
  const showAdminCreativePreview = async (action, id, title, meta = {}) => {
    const dialog = ensureAdminPreviewDialog();
    const media = $("adminPreviewMedia");
    const details = $("adminPreviewMeta");
    $("adminPreviewTitle").textContent = title || "Advert creative";
    media.textContent = "Loading secure preview…";
    details.replaceChildren();
    dialog.showModal();
    try {
      const payload = action === "admin-preview-change-creative" ? { action, change_request_id: id } : { action, campaign_id: id };
      const result = await callApi(payload);
      media.replaceChildren();
      if (result.creative_type === "video") {
        const video = document.createElement("video");
        video.controls = true; video.playsInline = true; video.preload = "metadata";
        if (result.poster_url) video.poster = result.poster_url;
        video.src = result.preview_url;
        media.append(video);
      } else {
        const image = document.createElement("img");
        image.src = result.preview_url; image.alt = "Private advert creative preview"; image.loading = "eager";
        media.append(image);
      }
      const rows = [
        ["Creative type", result.creative_type || "—"], ["Advertiser", meta.advertiser || "—"],
        ["Campaign", meta.headline || title || "—"], ["Campaign status", meta.status || "—"],
        ["Payment", meta.payment || "—"], ["Package", meta.package || "—"], ["CTA", meta.cta || "—"],
      ];
      details.innerHTML = rows.map(([label,value]) => '<div><span>' + escapeHtml(label) + '</span><strong>' + escapeHtml(value) + '</strong></div>').join("");
      if (meta.destination) {
        const link = document.createElement("a");
        link.href = meta.destination; link.target = "_blank"; link.rel = "noopener noreferrer";
        link.textContent = "Open full destination link: " + meta.destination; link.className = "admin-destination-link";
        details.append(link);
      }
      const note = document.createElement("p");
      note.className = "fineprint";
      note.textContent = "This private preview link expires in about " + (result.expires_in || 120) + " seconds. Reopen Preview to refresh it.";
      details.append(note);
    } catch (error) { media.textContent = error.message || "The private creative preview could not be loaded."; }
  };

  const loadAdminPanel = async () => {
    try {
      const overview = await callApi({ action: "admin-overview" });
      $("adminPanel").classList.remove("hidden");
      $("adminOverview").innerHTML = `
        <div class="admin-stat"><strong>${overview.campaigns_total}</strong><span>Campaigns</span></div>
        <div class="admin-stat"><strong>${overview.confirmed_campaign_payments}</strong><span>Campaign transfers</span></div>
        <div class="admin-stat"><strong>${overview.confirmed_design_payments}</strong><span>Design transfers</span></div>
        <div class="admin-stat"><strong>${formatNaira(overview.design_service_revenue_ngn)}</strong><span>Design service revenue</span></div>
        <div class="admin-stat"><strong>${formatNaira(overview.confirmed_revenue_ngn)}</strong><span>Total confirmed revenue</span></div>`;
      const [campaignData, paymentData, changeData] = await Promise.all([
        callApi({ action: "admin-list-campaigns" }),
        callApi({ action: "admin-list-payments" }),
        callApi({ action: "admin-list-campaign-changes" }),
      ]);
      $("adminCampaigns").innerHTML = (campaignData.campaigns || []).map((c) => {
        const creative = (c.advertising_creatives || []).find((item) => item.is_current === true);
        const paid = c.payment_status === "confirmed";
        const ready = !!creative && paid && c.status === "awaiting_approval";
        const destination = /^https:\/\//i.test(c.destination_url || "") ? c.destination_url : "";
        return `
        <article class="admin-row admin-campaign-card">
          <div class="admin-campaign-title"><strong>${escapeHtml(c.headline)}</strong><span class="status">${escapeHtml(String(c.status || "unknown").replaceAll("_"," "))}</span></div>
          <p><strong>Advertiser:</strong> ${escapeHtml(c.advertiser_profiles?.display_name || "—")} · ${escapeHtml(c.advertiser_profiles?.advertiser_type || "—")} · ${escapeHtml(c.advertiser_profiles?.phone || "No phone supplied")}</p>
          <p><strong>Campaign ID:</strong> <code>${escapeHtml(c.id)}</code></p>
          <p><strong>Description:</strong> ${escapeHtml(c.description || "—")}</p>
          <p><strong>Package:</strong> ${escapeHtml(c.package_days)} days · ${formatNaira(c.package_price_ngn)} · <strong>Payment:</strong> ${escapeHtml(String(c.payment_status || "unknown").replaceAll("_"," "))}</p>
          <p><strong>Payment reference:</strong> ${escapeHtml(c.payment_reference || "—")} · <strong>Start:</strong> ${escapeHtml(c.start_mode || "—")} ${c.scheduled_start_at ? "· " + formatDate(c.scheduled_start_at) : ""}</p>
          <p><strong>CTA:</strong> ${escapeHtml(c.cta || "—")} · <strong>Creative:</strong> ${creative ? escapeHtml(creative.creative_type) : "Missing current creative"}</p>
          <p><strong>Destination:</strong> ${destination ? `<a href="${escapeHtml(destination)}" target="_blank" rel="noopener noreferrer">${escapeHtml(destination)}</a>` : "No valid HTTPS destination"}</p>
          <p><strong>Created:</strong> ${formatDate(c.created_at)} · <strong>Scheduled:</strong> ${formatDate(c.scheduled_start_at)} · <strong>Ends:</strong> ${formatDate(c.ends_at)}</p>
          <div class="campaign-actions">
            <button class="primary admin-approve-button" data-approve="${escapeHtml(c.id)}" ${ready ? "" : "disabled"} title="${ready ? "Approve campaign" : "Approval requires confirmed payment, awaiting approval status and a current creative"}>Approve advert</button>
            <button class="small-outline" data-preview="${escapeHtml(c.id)}" ${creative ? "" : "disabled"}>Preview image / video</button>
            <button class="small-outline" data-reject="${escapeHtml(c.id)}">Reject</button>
            <button class="small-outline" data-pause="${escapeHtml(c.id)}">${c.status === "paused" ? "Resume" : "Pause"}</button>
          </div>
        </article>`;
      }).join("") || '<p class="muted">No campaigns.</p>';
      $("adminCampaignChanges").innerHTML = (changeData.requests || []).filter((r) => r.status === "pending").map((r) => {
        const destination = /^https:\/\//i.test(r.proposed_destination_url || "") ? r.proposed_destination_url : "";
        return `
          <article class="admin-row">
            <div class="admin-campaign-title"><strong>Replacement / campaign change</strong><span class="status">Pending review</span></div>
            <p><strong>Campaign:</strong> ${escapeHtml(r.advertising_campaigns?.headline || r.campaign_id)} · <strong>Advertiser:</strong> ${escapeHtml(r.advertiser_profiles?.display_name || "—")}</p>
            <p><strong>Requested headline:</strong> ${escapeHtml(r.proposed_headline || "No change")} · <strong>Reason:</strong> ${escapeHtml(r.advertiser_reason || "—")}</p>
            <p><strong>Description:</strong> ${escapeHtml(r.proposed_description || "No change")}</p>
            <p><strong>Destination:</strong> ${destination ? `<a href="${escapeHtml(destination)}" target="_blank" rel="noopener noreferrer">${escapeHtml(destination)}</a>` : "No destination change"}</p>
            <p><strong>Replacement creative:</strong> ${r.proposed_creative_id ? "Attached" : "Not attached"}</p>
            <div class="campaign-actions">
              <button class="small-outline" data-preview-change="${escapeHtml(r.id)}" ${r.proposed_creative_id ? "" : "disabled"}>Preview replacement</button>
              <button class="small-outline" data-approve-change="${escapeHtml(r.id)}">Approve change</button>
              <button class="small-outline" data-reject-change="${escapeHtml(r.id)}">Reject change</button>
            </div>
          </article>`;
      }).join("") || '<p class="muted">No pending campaign changes.</p>';
      $("adminPayments").innerHTML = (paymentData.payments || []).map((p) => `
        <div class="admin-row" data-payment-status="${escapeHtml(p.status)}" data-payment-campaign="${escapeHtml(p.campaign_id)}" data-payment-advertiser="${escapeHtml(p.advertiser_id)}" data-payment-amount="${escapeHtml(p.amount_ngn)}"><strong>${formatNaira(p.amount_ngn)} · ${escapeHtml(p.status)}</strong><p>${escapeHtml(p.advertising_campaigns?.headline)} · ${escapeHtml(p.advertiser_profiles?.display_name)}</p><p>Transfer ref: ${escapeHtml(p.bank_transfer_reference)}</p>
        ${p.status === "submitted" ? `<button class="small-outline" data-confirm-payment="${p.id}">Confirm bank transfer</button>` : ""}</div>`).join("") || '<p class="muted">No submitted transfers.</p>';
      $("adminCampaigns").querySelectorAll("[data-preview]").forEach((b) => b.addEventListener("click", async () => {
        const campaign = (campaignData.campaigns || []).find((item) => item.id === b.dataset.preview);
        if (!campaign) return;
        await showAdminCreativePreview("admin-preview-creative", campaign.id, campaign.headline, {
          advertiser: campaign.advertiser_profiles?.display_name, headline: campaign.headline, status: campaign.status,
          payment: campaign.payment_status, package: campaign.package_days + " days · " + formatNaira(campaign.package_price_ngn),
          cta: campaign.cta, destination: campaign.destination_url,
        });
      }));
      $("adminCampaignChanges").querySelectorAll("[data-preview-change]").forEach((b) => b.addEventListener("click", async () => {
        const request = (changeData.requests || []).find((item) => item.id === b.dataset.previewChange);
        await showAdminCreativePreview("admin-preview-change-creative", b.dataset.previewChange, request?.proposed_headline || request?.advertising_campaigns?.headline || "Replacement creative", {
          advertiser: request?.advertiser_profiles?.display_name, headline: request?.proposed_headline || request?.advertising_campaigns?.headline,
          status: request?.advertising_campaigns?.status, destination: request?.proposed_destination_url,
        });
      }));
      $("adminCampaignChanges").querySelectorAll("[data-approve-change]").forEach((b) => b.addEventListener("click", async () => {
        if (!confirm("Approve this campaign change and activate its proposed creative/details?")) return;
        try { await callApi({ action: "admin-review-campaign-change", change_request_id: b.dataset.approveChange, approve: true }); await loadAdminPanel(); }
        catch (error) { message("globalMessage", error.message, true); }
      }));
      $("adminCampaignChanges").querySelectorAll("[data-reject-change]").forEach((b) => b.addEventListener("click", async () => {
        const reason = prompt("Enter the reason for rejecting this campaign change:");
        if (!reason || reason.trim().length < 3) return;
        try { await callApi({ action: "admin-review-campaign-change", change_request_id: b.dataset.rejectChange, approve: false, reason }); await loadAdminPanel(); }
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
  const isAdvertiserSession = (token) => {
    try {
      const segment = token?.split(".")[1];
      if (!segment) return false;
      const normalized = segment.replace(/-/g, "+").replace(/_/g, "/");
      const payload = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
      return ["anon", "authenticated"].includes(payload.role) && payload.user_role === "advertiser";
    } catch { return false; }
  };
  const enrollAdvertiserSession = async (session, details) => {
    if (!session?.user?.email_confirmed_at) throw new Error("Please verify your Match email first, then return here and sign in.");
    const baseUrl = config.supabaseUrl.endsWith("/") ? config.supabaseUrl.slice(0, -1) : config.supabaseUrl;
    const response = await fetch(baseUrl + "/functions/v1/advertiser-register", {
      method: "POST",
      headers: { apikey: config.publishableKey, Authorization: "Bearer " + session.access_token, "Content-Type": "application/json" },
      body: JSON.stringify(details),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || !result.success) throw new Error(result.error || "Advertiser registration could not be completed.");
    const { data, error } = await state.client.auth.refreshSession();
    if (error || !data.session) throw new Error("Your advertiser enrolment was saved. Please sign in again to activate it.");
    return data.session;
  };
  const completeAdvertiserProfile = async (session, details = {}) => {
    const metadata = session.user?.user_metadata || {};
    await callApi({ action: "complete-profile", advertiser_type: details.advertiser_type || metadata.advertiser_type, display_name: details.display_name || metadata.display_name, contact_name: details.contact_name ?? metadata.contact_name, phone: details.phone ?? metadata.phone });
  };
  const ensureAdvertiserProfile = async (session) => {
    let activeSession = session;
    if (!isAdvertiserSession(activeSession?.access_token)) {
      const metadata = activeSession?.user?.user_metadata || {};
      if (metadata.the_match_advertiser_registration === "v1") {
        activeSession = await enrollAdvertiserSession(activeSession, { advertiser_type: metadata.advertiser_type, display_name: metadata.display_name, contact_name: metadata.contact_name || "", phone: metadata.phone || "" });
        if (!isAdvertiserSession(activeSession?.access_token)) throw new Error("Your advertiser enrolment was saved, but access is not active yet. Please sign in again.");
        await completeAdvertiserProfile(activeSession);
        return activeSession;
      }
      state.pendingEnrollmentSession = activeSession;
      $("dashboardView").classList.add("hidden");
      $("authView").classList.remove("hidden");
      $("signinForm").classList.add("hidden");
      $("signupForm").classList.add("hidden");
      $("resetPasswordForm").classList.add("hidden");
      $("advertiserEnrollmentForm").classList.remove("hidden");
      $("enrollName").value = activeSession.user?.user_metadata?.full_name || activeSession.user?.email?.split("@")[0] || "";
      message("authMessage", "Your verified Match account can use the advertising portal too. Complete your advertiser details below.");
      return null;
    }
    await completeAdvertiserProfile(activeSession);
    return activeSession;
  };
  const showDashboard = async (session) => {
    if (state.handlingSession) return;
    state.handlingSession = true;
    try {
      session = await ensureAdvertiserProfile(session);
      if (!session) { state.handlingSession = false; return; }
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
    if (config.campaignsEnabled !== true) {
      // Keep the advertiser workspace usable: members can enter details and select
      // creative files. The server remains authoritative and rejects submissions
      // until the campaign launch flag is enabled.
      message("globalMessage", "You can prepare your advert details here. Campaign submission and payment are not open yet.");
    }
    const adminRoute = new URLSearchParams(window.location.search).get("admin") === "1";
    if (adminRoute) {
      document.querySelector(".dashboard-head")?.classList.add("hidden");
      document.querySelector(".dashboard-grid")?.classList.add("hidden");
      document.querySelector(".workspace-tabs")?.classList.add("hidden");
      $("adminPanel").classList.add("hidden");
      $("adminAccessDenied")?.classList.add("hidden");
      await loadAdminPanel();
      if ($("adminPanel").classList.contains("hidden")) $("adminAccessDenied")?.classList.remove("hidden");
    } else {
      $("adminPanel").classList.add("hidden");
      $("adminAccessDenied")?.classList.add("hidden");
      document.querySelector(".dashboard-head")?.classList.remove("hidden");
      document.querySelector(".dashboard-grid")?.classList.remove("hidden");
      document.querySelector(".workspace-tabs")?.classList.remove("hidden");
      // Campaign history loads only when its tab is opened, keeping first paint fast.
    }
    try { /* Session and page visibility are established above. */ }
    catch (error) { message("globalMessage", error.message, true); }
  };

  if (config.enabled !== true) {
    $("setupNotice").classList.remove("hidden");
    $("setupNotice").textContent = "The Match advertising portal is not open yet. Account registration and campaign submissions will be enabled after the security and launch checks are complete.";
    $("authView").querySelectorAll("button,input,select").forEach((el) => el.disabled = true);
    return;
  }

  if (!config.supabaseUrl || !config.publishableKey || !window.supabase?.createClient) {
    $("setupNotice").classList.remove("hidden");
    $("setupNotice").textContent = "Advertiser portal setup is pending: the shared Match Supabase project has not been connected yet. The portal keeps its browser session separate while preserving the same verified Match identity.";
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
  document.querySelectorAll("[data-workspace-tab]").forEach((button) => button.addEventListener("click", async () => {
    const target = button.dataset.workspaceTab;
    document.querySelectorAll("[data-workspace-tab]").forEach((tab) => tab.classList.toggle("active", tab === button));
    document.querySelectorAll("[data-workspace-panel]").forEach((panel) => panel.classList.toggle("hidden", panel.dataset.workspacePanel !== target));
    if (target === "campaigns") {
      try { await refreshCampaigns(); }
      catch (error) { message("globalMessage", error.message || "Campaign history could not be loaded.", true); }
    }
  }));
  document.querySelectorAll("[data-password-toggle]").forEach((button) => button.addEventListener("click", () => {
    const input = $(button.dataset.passwordToggle);
    if (!input) return;
    const show = input.type === "password";
    input.type = show ? "text" : "password";
    button.setAttribute("aria-pressed", String(show));
    button.setAttribute("aria-label", show ? "Hide password" : "Show password");
    button.innerHTML = show
      ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 3l18 18M10.6 10.6a2 2 0 002.8 2.8M9.9 5.2A10.8 10.8 0 0112 5c6.4 0 10 7 10 7a17 17 0 01-3.1 3.8M6.2 6.2C3.5 8 2 12 2 12s3.6 7 10 7c1.3 0 2.5-.3 3.6-.8"/></svg>'
      : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>';
  }));
  $("signupType").addEventListener("change", () => { $("signupNameLabel").firstChild.textContent = $("signupType").value === "business" ? "Business / organisation name" : "Your name"; });
  $("enrollType").addEventListener("change", () => { $("enrollNameLabel").firstChild.textContent = $("enrollType").value === "business" ? "Business / organisation name" : "Your name"; });
  $("advertiserEnrollmentForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = event.submitter;
    const session = state.pendingEnrollmentSession;
    if (!session) return message("authMessage", "Please sign in to your Match account again.", true);
    const details = { advertiser_type: $("enrollType").value, display_name: $("enrollName").value.trim(), contact_name: $("enrollContact").value.trim(), phone: $("enrollPhone").value.trim() };
    if (details.display_name.length < 2) return message("authMessage", "Enter a name with at least two characters.", true);
    setBusy(button, true, "Activating advertiser access…");
    try {
      const activeSession = await enrollAdvertiserSession(session, details);
      if (!isAdvertiserSession(activeSession?.access_token)) throw new Error("Advertiser access could not be activated. Please sign in again.");
      await completeAdvertiserProfile(activeSession, details);
      state.pendingEnrollmentSession = null;
      await showDashboard(activeSession);
    } catch (error) { message("authMessage", error.message || "Advertiser enrolment could not be completed.", true); }
    finally { setBusy(button, false); }
  });
  $("cancelEnrollment").addEventListener("click", async () => {
    state.pendingEnrollmentSession = null;
    await state.client.auth.signOut({ scope: "local" });
    $("advertiserEnrollmentForm").classList.add("hidden");
    $("signinForm").classList.remove("hidden");
    message("authMessage", "You can sign in again whenever you are ready.");
  });
  $("signinForm").addEventListener("submit", async (event) => {
    event.preventDefault(); const button = event.submitter; setBusy(button,true);
    const { data, error } = await state.client.auth.signInWithPassword({ email: $("signinEmail").value.trim(), password: $("signinPassword").value });
    setBusy(button,false);
    if (error) return message("authMessage", error.message, true);
    await showDashboard(data.session);
  });
  $("signupForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = event.submitter;
    if ($("signupPassword").value.length < 8) return message("authMessage", "Password must be at least 8 characters.", true);
    if ($("signupPassword").value !== $("signupConfirmPassword").value) return message("authMessage", "The passwords do not match. Please check and try again.", true);
    setBusy(button,true);
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
    } else if (data.user?.identities?.length === 0) {
      showAuthTab("signin");
      $("signinEmail").value = $("signupEmail").value.trim();
      message("authMessage", "This email already has a Match account. Sign in with the same email and password you use for The Match, then complete advertiser setup.");
    } else {
      message("authMessage", "Account created. Check your email to verify your account, then sign in.");
    }
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
    if (!email) return message("authMessage", "Enter the email address you use to sign in to The Match.");
    const button = $("forgotPassword");
    setBusy(button, true, "Sending recovery email…");
    try {
      const { error } = await state.client.auth.resetPasswordForEmail(email, { redirectTo: window.location.href.split("#")[0] });
      if (error) {
        const rateLimited = /rate limit|too many requests|seconds|60/i.test(error.message || "");
        message("authMessage", rateLimited
          ? "Please wait 60 seconds before requesting another reset email. Resend sends the email; the security cooldown is enforced by account protection."
          : error.message || "We could not send the recovery email. Please try again.", true);
      } else {
        message("authMessage", "If an advertiser account exists for that exact email, a password-reset link has been sent through The Match email service. Check Inbox and Spam, then open the link on this same device.");
      }
    } catch (error) {
      message("authMessage", error.message || "We could not send the recovery email. Please try again.", true);
    } finally { setBusy(button, false); }
  });
  $("resetPasswordForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = $("saveNewPassword");
    const password = $("resetPassword").value;
    if (password.length < 8) return message("authMessage", "Your new password must be at least 8 characters.", true);
    if (password !== $("resetConfirmPassword").value) return message("authMessage", "The two new passwords do not match.", true);
    setBusy(button, true, "Saving password…");
    try {
      const { error } = await state.client.auth.updateUser({ password });
      if (error) throw error;
      state.passwordRecovery = false;
      $("resetPasswordForm").classList.add("hidden");
      $("signinForm").classList.remove("hidden");
      $("resetPasswordForm").reset();
      message("authMessage", "Your password has been updated. Signing you into your advertiser workspace…");
      const { data } = await state.client.auth.getSession();
      if (data.session) await showDashboard(data.session);
    } catch (error) {
      message("authMessage", error.message || "Your password could not be updated. Please reopen the latest recovery email link.", true);
    } finally { setBusy(button, false); }
  });
  $("cancelPasswordReset").addEventListener("click", async () => {
    state.passwordRecovery = false;
    $("resetPasswordForm").classList.add("hidden");
    $("signinForm").classList.remove("hidden");
    $("resetPasswordForm").reset();
    message("authMessage", "You can sign in with your existing password.");
    await state.client.auth.signOut({ scope: "local" });
  });
  $("signOut").addEventListener("click", async () => { await state.client.auth.signOut({ scope: "local" }); state.session = null; $("dashboardView").classList.add("hidden"); $("authView").classList.remove("hidden"); });
  $("campaignPackage").addEventListener("change", () => { $("packagePrice").textContent = formatNaira(({7:12000,14:22000,30:40000})[$("campaignPackage").value]); });
  $("campaignStartMode").addEventListener("change", () => $("scheduleField").classList.toggle("hidden", $("campaignStartMode").value !== "scheduled"));
  $("campaignCreative").addEventListener("change", async () => {
    const file = $("campaignCreative").files?.[0]; state.creativeFile = file || null; state.posterFile = null;
    const preview = $("creativePreview"); preview.replaceChildren();
    if (state.previewObjectUrl) URL.revokeObjectURL(state.previewObjectUrl);
    state.previewObjectUrl = null;
    if (!file) { preview.textContent = "Your creative preview appears here"; return; }
    const isImage = ["image/jpeg", "image/png", "image/webp"].includes(file.type);
    const isVideo = file.type === "video/mp4";
    if ((!isImage && !isVideo) || (isImage && file.size > 10 * 1024 * 1024) || (isVideo && file.size > 20 * 1024 * 1024)) {
      state.creativeFile = null; $("campaignCreative").value = "";
      preview.textContent = "Choose JPG, PNG or WebP up to 10 MB, or MP4 up to 20 MB.";
      return message("globalMessage", "That file type or size is outside the advert upload limits.", true);
    }
    state.previewObjectUrl = URL.createObjectURL(file);
    if (isImage) {
      const img = document.createElement("img"); img.decoding = "async"; img.loading = "lazy";
      img.src = state.previewObjectUrl; preview.append(img);
    } else {
      const video = document.createElement("video"); video.src = state.previewObjectUrl;
      video.controls = true; video.muted = true; video.playsInline = true; video.preload = "metadata";
      preview.append(video);
      try { state.posterFile = await createPoster(file); }
      catch (error) { state.creativeFile = null; message("globalMessage", error.message || "Video preview could not be prepared.", true); }
    }
  });
  window.addEventListener("pagehide", () => {
    if (state.previewObjectUrl) URL.revokeObjectURL(state.previewObjectUrl);
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
  $("refreshCampaigns").addEventListener("click", async () => { try { await refreshCampaigns(); } catch (error) { message("globalMessage",error.message,true); } });
  $("copyAccount").addEventListener("click", () => navigator.clipboard?.writeText($("bankAccountNumber").textContent));
  $("copyReference").addEventListener("click", () => navigator.clipboard?.writeText($("bankReference").textContent));
  window.TheMatchAdvertisingPortal = { callApi, callMediaUpload, createPoster, client: state.client, refreshCampaigns, message, escapeHtml, formatNaira };
  state.client.auth.onAuthStateChange((event, session) => {
    if (event === "PASSWORD_RECOVERY") {
      state.passwordRecovery = true;
      $("dashboardView").classList.add("hidden");
      $("authView").classList.remove("hidden");
      $("signinForm").classList.add("hidden");
      $("signupForm").classList.add("hidden");
      $("resetPasswordForm").classList.remove("hidden");
      message("authMessage", "Recovery link verified. Set a new password below.");
      return;
    }
    if (session && !state.passwordRecovery && $("dashboardView").classList.contains("hidden")) showDashboard(session);
  });
  state.client.auth.getSession().then(({ data }) => { if (data.session && !state.passwordRecovery) showDashboard(data.session); });
})();
