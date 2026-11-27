(() => {
  "use strict";
  const api = window.TheMatchAdvertisingPortal;
  if (!api?.callApi || !api.client) return;
  const $ = (id) => document.getElementById(id);
  const state = { payment: null };
  const esc = api.escapeHtml;
  const money = api.formatNaira;

  function showMessage(text, error = false) { api.message("globalMessage", text, error); }

  async function loadRequests() {
    const result = await api.callApi({ action: "list-design-requests" });
    const requests = result.requests || [];
    $("designRequestList").innerHTML = requests.length ? requests.map((request) => {
      const payment = Array.isArray(request.advertising_design_payments) ? request.advertising_design_payments[0] : null;
      return `<article class="campaign-item">
        <h3>${esc(request.service_type)} design · ${money(request.fee_ngn)}</h3>
        <div class="campaign-meta"><span class="status">${esc(request.status.replaceAll("_"," "))}</span><span class="status">Payment: ${esc(payment?.status || "pending")}</span></div>
        <p>Payment reference: ${esc(payment?.payment_reference || "—")}</p>
        <p>Delivery target: ${request.agreed_delivery_at ? esc(new Date(request.agreed_delivery_at).toLocaleString("en-NG",{timeZone:"Africa/Lagos"})) + " WAT" : "To be agreed before work starts"}</p>
        <p>Revisions used: ${request.revisions_used} / ${request.revisions_allowed}</p>
        <div class="campaign-actions">
          ${request.status === "first_draft_sent" && request.revisions_used < request.revisions_allowed ? `<button class="small-outline" data-design-revision="${esc(request.id)}">Request a revision</button>` : ""}
          ${request.status === "completed" ? `<button class="small-outline" data-design-download="${esc(request.id)}">Get finished artwork</button>` : ""}
        </div>
      </article>`;
    }).join("") : '<p class="muted">No design requests yet.</p>';

    $("designRequestList").querySelectorAll("[data-design-revision]").forEach((button) => button.addEventListener("click", async () => {
      if (!confirm("Use one of the included revision rounds for this request?")) return;
      try {
        await api.callApi({ action: "request-design-revision", request_id: button.dataset.designRevision });
        showMessage("Revision request sent to The Match design team.");
        await loadRequests();
      } catch (error) { showMessage(error.message, true); }
    }));
    $("designRequestList").querySelectorAll("[data-design-download]").forEach((button) => button.addEventListener("click", async () => {
      try {
        const result = await api.callApi({ action: "get-design-delivery", request_id: button.dataset.designDownload });
        window.open(result.download_url, "_blank", "noopener,noreferrer");
      } catch (error) { showMessage(error.message, true); }
    }));
  }

  async function loadAdminDesignQueue() {
    const panel = $("adminPanel");
    if (!panel || panel.classList.contains("hidden")) return;
    try {
      const result = await api.callApi({ action: "admin-list-design-requests" });
      const requests = result.requests || [];
      $("adminDesignRequests").innerHTML = requests.length ? requests.map((request) => {
        const payment = Array.isArray(request.advertising_design_payments) ? request.advertising_design_payments[0] : null;
        return `<article class="admin-row">
          <strong>${esc(request.service_type)} · ${money(request.fee_ngn)} · ${esc(request.status)}</strong>
          <p>${esc(request.advertiser_profiles?.display_name)} · ${esc(request.advertiser_profiles?.phone || "")}</p>
          <p>Payment: ${esc(payment?.status || "—")} · ${esc(payment?.bank_transfer_reference || payment?.payment_reference || "")}</p>
          <p>Revisions: ${request.revisions_used}/${request.revisions_allowed}</p>
          ${payment?.status === "submitted" ? `<button class="small-outline" data-design-confirm="${esc(payment.id)}">Confirm design payment</button>` : ""}
          ${request.status === "paid" ? `<button class="small-outline" data-design-accept="${esc(request.id)}">Accept and set delivery date</button>` : ""}
          ${["in_progress","revision"].includes(request.status) ? `<button class="small-outline" data-design-draft="${esc(request.id)}">Mark first draft sent</button>` : ""}
          ${["in_progress","first_draft_sent","revision"].includes(request.status) ? `<label class="small">Upload finished artwork<input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" data-design-file="${esc(request.id)}"></label>` : ""}
        </article>`;
      }).join("") : '<p class="muted">No design requests.</p>';

      $("adminDesignRequests").querySelectorAll("[data-design-confirm]").forEach((button) => button.addEventListener("click", async () => {
        if (!confirm("Confirm that the design service transfer has arrived in the business bank account?")) return;
        try { await api.callApi({ action: "admin-confirm-design-payment", payment_id: button.dataset.designConfirm }); await loadAdminDesignQueue(); await loadRequests(); }
        catch (error) { showMessage(error.message, true); }
      }));
      $("adminDesignRequests").querySelectorAll("[data-design-accept]").forEach((button) => button.addEventListener("click", async () => {
        const raw = prompt("Enter the confirmed delivery deadline in WAT (YYYY-MM-DDTHH:mm):");
        if (!raw) return;
        const date = new Date(raw + ":00+01:00");
        if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) return showMessage("Choose a future delivery deadline.", true);
        try { await api.callApi({ action: "admin-update-design-request", request_id: button.dataset.designAccept, status: "in_progress", delivery_at: date.toISOString(), admin_note: "Delivery deadline confirmed with advertiser." }); await loadAdminDesignQueue(); }
        catch (error) { showMessage(error.message, true); }
      }));
      $("adminDesignRequests").querySelectorAll("[data-design-draft]").forEach((button) => button.addEventListener("click", async () => {
        try { await api.callApi({ action: "admin-update-design-request", request_id: button.dataset.designDraft, status: "first_draft_sent" }); await loadAdminDesignQueue(); await loadRequests(); }
        catch (error) { showMessage(error.message, true); }
      }));
      $("adminDesignRequests").querySelectorAll("[data-design-file]").forEach((input) => input.addEventListener("change", async () => {
        const file = input.files?.[0];
        if (!file) return;
        try {
          const { data: { session } } = await api.client.auth.getSession();
          const form = new FormData();
          form.append("request_id", input.dataset.designFile);
          form.append("file", file, file.name);
          const response = await fetch(window.THE_MATCH_ADVERTISER_CONFIG.supabaseUrl.replace(/\/$/, "") + "/functions/v1/advertising-design-upload", {
            method: "POST",
            headers: { apikey: window.THE_MATCH_ADVERTISER_CONFIG.publishableKey, Authorization: "Bearer " + session.access_token },
            body: form,
          });
          const data = await response.json().catch(() => ({}));
          if (!response.ok || !data.success) throw new Error(data.error || "Artwork upload failed.");
          await api.callApi({ action: "admin-update-design-request", request_id: input.dataset.designFile, status: "completed", delivered_storage_key: data.delivered_storage_key, admin_note: "Finished artwork uploaded and delivered." });
          showMessage("Finished artwork uploaded and marked complete.");
          await loadAdminDesignQueue(); await loadRequests();
        } catch (error) { showMessage(error.message, true); }
      }));
    } catch (error) {
      if (!panel.classList.contains("hidden")) showMessage(error.message, true);
    }
  }

  $("designRequestForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = $("designRequestButton");
    button.disabled = true;
    try {
      const result = await api.callApi({
        action: "create-design-request",
        service_type: $("designServiceType").value,
        brief: $("designBrief").value,
      });
      state.payment = result.request;
      $("designBankName").textContent = result.bank_transfer.bank_name;
      $("designBankAccountName").textContent = result.bank_transfer.account_name;
      $("designBankAccountNumber").textContent = result.bank_transfer.account_number;
      $("designBankAmount").textContent = money(result.request.fee_ngn);
      $("designBankReference").textContent = result.request.payment_reference;
      $("designPaymentForm").dataset.paymentId = result.request.payment_id;
      $("designPaymentStep").classList.remove("hidden");
      showMessage("Design request created. Transfer the separate design fee to begin the process.");
      await loadRequests();
    } catch (error) { showMessage(error.message, true); }
    finally { button.disabled = false; }
  });

  $("designPaymentForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = event.submitter;
    button.disabled = true;
    try {
      await api.callApi({
        action: "submit-design-payment",
        payment_id: $("designPaymentForm").dataset.paymentId,
        bank_transfer_reference: $("designTransferReference").value.trim(),
      });
      $("designPaymentStep").classList.add("hidden");
      $("designRequestForm").reset();
      showMessage("Design payment details submitted. Work begins after the transfer is manually confirmed.");
      await loadRequests();
    } catch (error) { showMessage(error.message, true); }
    finally { button.disabled = false; }
  });

  const dashboard = $("dashboardView");
  if (dashboard) {
    const dashboardObserver = new MutationObserver(() => {
      if (!dashboard.classList.contains("hidden")) {
        loadRequests().catch((error) => showMessage(error.message, true));
        loadAdminDesignQueue();
      }
    });
    dashboardObserver.observe(dashboard, { attributes: true, attributeFilter: ["class"] });
  }
  const admin = $("adminPanel");
  if (admin) {
    const adminObserver = new MutationObserver(loadAdminDesignQueue);
    adminObserver.observe(admin, { attributes: true, attributeFilter: ["class"] });
  }
})();
