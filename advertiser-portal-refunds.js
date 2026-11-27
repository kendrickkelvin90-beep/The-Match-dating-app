(() => {
  "use strict";
  const api = window.TheMatchAdvertisingPortal;
  if (!api?.callApi) return;
  const list = document.getElementById("campaignList");
  const adminPanel = document.getElementById("adminPanel");
  const adminRefunds = document.getElementById("adminRefunds");
  if (!list || !adminPanel || !adminRefunds) return;

  const esc = api.escapeHtml;
  const money = api.formatNaira;
  let loading = false;

  async function loadRefundQueue() {
    if (loading || adminPanel.classList.contains("hidden")) return;
    loading = true;
    try {
      const result = await api.callApi({ action: "admin-list-refunds" });
      const refunds = result.refunds || [];
      adminRefunds.innerHTML = refunds.length ? refunds.map((refund) => `
        <article class="admin-row">
          <strong>${money(refund.amount_ngn)} · ${esc(refund.status)}</strong>
          <p>${esc(refund.advertising_campaigns?.headline)} · ${esc(refund.advertising_profiles?.display_name)}</p>
          <p>${esc(refund.reason)}</p>
          ${refund.admin_note ? `<p>Admin note: ${esc(refund.admin_note)}</p>` : ""}
          ${refund.status === "requested" ? `<button class="small-outline" data-refund-approve="${esc(refund.id)}">Approve refund</button><button class="small-outline" data-refund-reject="${esc(refund.id)}">Reject</button>` : ""}
          ${refund.status === "approved" ? `<button class="small-outline" data-refund-paid="${esc(refund.id)}">Record refund paid</button>` : ""}
        </article>`).join("") : '<p class="muted">No refund requests.</p>';

      adminRefunds.querySelectorAll("[data-refund-approve]").forEach((button) => button.addEventListener("click", async () => {
        try {
          await api.callApi({ action: "admin-review-refund", refund_id: button.dataset.refundApprove, approve: true });
          await loadRefundQueue();
        } catch (error) { api.message("globalMessage", error.message, true); }
      }));
      adminRefunds.querySelectorAll("[data-refund-reject]").forEach((button) => button.addEventListener("click", async () => {
        const reason = prompt("Reason for rejecting this refund:");
        if (!reason || reason.trim().length < 3) return;
        try {
          await api.callApi({ action: "admin-review-refund", refund_id: button.dataset.refundReject, approve: false, reason });
          await loadRefundQueue();
        } catch (error) { api.message("globalMessage", error.message, true); }
      }));
      adminRefunds.querySelectorAll("[data-refund-paid]").forEach((button) => button.addEventListener("click", async () => {
        const reference = prompt("Enter the outgoing bank transfer reference after refund has actually been paid:");
        if (!reference) return;
        try {
          await api.callApi({ action: "admin-mark-refund-paid", refund_id: button.dataset.refundPaid, bank_transfer_reference: reference });
          await loadRefundQueue();
        } catch (error) { api.message("globalMessage", error.message, true); }
      }));
    } catch (error) {
      if (!adminPanel.classList.contains("hidden")) api.message("globalMessage", error.message, true);
    } finally {
      loading = false;
    }
  }

  function addAdvertiserRefundButtons() {
    list.querySelectorAll(".campaign-item[data-payment-ids]").forEach((card) => {
      if (card.querySelector("[data-advertiser-refund]")) return;
      const paymentIds = (card.dataset.paymentIds || "").split(",").filter(Boolean);
      if (!paymentIds.length) return;
      const actions = card.querySelector(".campaign-actions");
      if (!actions) return;
      for (const paymentId of paymentIds) {
        const button = document.createElement("button");
        button.className = "small-outline";
        button.type = "button";
        button.textContent = "Request refund";
        button.dataset.advertiserRefund = paymentId;
        button.addEventListener("click", async () => {
          const reason = prompt("Please tell us why you are requesting a refund:");
          if (!reason || reason.trim().length < 3) return;
          button.disabled = true;
          try {
            await api.callApi({ action: "request-refund", payment_id: paymentId, reason });
            button.textContent = "Refund requested";
            button.disabled = true;
            api.message("globalMessage", "Refund request submitted for admin review.");
          } catch (error) {
            api.message("globalMessage", error.message, true);
            button.disabled = false;
          }
        });
        actions.appendChild(button);
      }
    });
  }


  function addDuplicatePaymentButtons() {
    const payments = document.getElementById("adminPayments");
    if (!payments || adminPanel.classList.contains("hidden")) return;
    payments.querySelectorAll('.admin-row[data-payment-status="confirmed"]').forEach((row) => {
      if (row.querySelector("[data-record-duplicate]")) return;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "small-outline";
      button.dataset.recordDuplicate = "true";
      button.textContent = "Log additional transfer";
      button.addEventListener("click", async () => {
        const reference = prompt("Enter the bank reference for the additional transfer after verifying it in the business bank account:");
        if (!reference || reference.trim().length < 4) return;
        const amount = Number(prompt("Enter the exact additional amount received (NGN):", row.dataset.paymentAmount));
        if (!Number.isInteger(amount) || amount <= 0) return;
        button.disabled = true;
        try {
          await api.callApi({
            action: "admin-record-duplicate-payment",
            campaign_id: row.dataset.paymentCampaign,
            advertiser_id: row.dataset.paymentAdvertiser,
            amount_ngn: amount,
            bank_transfer_reference: reference,
            admin_note: "Additional transfer manually verified by admin."
          });
          button.textContent = "Additional transfer recorded";
          api.message("globalMessage", "Additional transfer recorded. It can now enter the refund workflow.");
        } catch (error) {
          api.message("globalMessage", error.message, true);
          button.disabled = false;
        }
      });
      row.appendChild(button);
    });
  }

  const listObserver = new MutationObserver(addAdvertiserRefundButtons);
  listObserver.observe(list, { childList: true, subtree: true });
  const adminObserver = new MutationObserver(loadRefundQueue);
  adminObserver.observe(adminPanel, { attributes: true, attributeFilter: ["class"] });
  const paymentsList = document.getElementById("adminPayments");
  if (paymentsList) new MutationObserver(addDuplicatePaymentButtons).observe(paymentsList, { childList: true, subtree: true });
  addAdvertiserRefundButtons();
  loadRefundQueue();
  addDuplicatePaymentButtons();
})();
