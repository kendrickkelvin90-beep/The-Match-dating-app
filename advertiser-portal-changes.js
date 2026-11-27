(() => {
  "use strict";
  const portal = window.TheMatchAdvertisingPortal;
  const config = window.THE_MATCH_ADVERTISER_CONFIG || {};
  if (!portal || !portal.callApi) return;
  const $ = (id) => document.getElementById(id);
  const escape = portal.escapeHtml;

  function addCampaignButtons() {
    const list = $("campaignList");
    if (!list) return;
    list.querySelectorAll(".campaign-item[data-campaign-id]").forEach((card) => {
      if (!["active","paused","scheduled"].includes(card.dataset.campaignStatus)) return;
      if (card.querySelector("[data-campaign-change]")) return;
      if ((card.dataset.hasPendingChange || "") === "true") {
        if (card.dataset.pendingChangeRequest && card.dataset.pendingChangeCreative !== "true" &&
            !card.querySelector("[data-attach-change]")) {
          const attach = document.createElement("button");
          attach.type = "button";
          attach.className = "small-outline";
          attach.dataset.attachChange = card.dataset.pendingChangeRequest;
          attach.dataset.campaignId = card.dataset.campaignId;
          attach.textContent = "Attach replacement creative";
          card.querySelector(".campaign-actions")?.append(attach);
        }
        return;
      }
      const button = document.createElement("button");
      button.type = "button";
      button.className = "small-outline";
      button.dataset.campaignChange = card.dataset.campaignId;
      button.textContent = "Request changes";
      card.querySelector(".campaign-actions")?.append(button);
    });
  }

  function openReplacementPicker(button,campaignId,changeRequestId) {
    const picker = document.createElement("input");
    picker.type = "file";
    picker.accept = "image/jpeg,image/png,image/webp,video/mp4";
    picker.onchange = async () => {
      const file = picker.files && picker.files[0];
      if (!file) return;
      button.disabled = true;
      try {
        const poster = file.type === "video/mp4" ? await portal.createPoster(file) : null;
        await portal.callMediaUpload(campaignId,file,poster,changeRequestId);
        portal.message("globalMessage","Replacement creative uploaded privately for admin review.");
        await portal.refreshCampaigns();
      } catch (error) {
        portal.message("globalMessage",error.message,true);
        await portal.refreshCampaigns().catch(() => undefined);
      } finally { button.disabled = false; }
    };
    picker.click();
  }

  async function requestChange(button) {
    const campaignId = button.dataset.campaignChange;
    let listing;
    try {
      listing = await portal.callApi({action:"list-campaigns"});
    } catch (error) {
      portal.message("globalMessage",error.message,true);
      return;
    }
    const campaign = (listing.campaigns || []).find((item) => item.id === campaignId);
    if (!campaign) {
      portal.message("globalMessage","This campaign is no longer available. Refresh your campaign list and try again.",true);
      return;
    }
    const card = button.closest(".campaign-item");
    const currentHeadline = campaign.headline || card?.querySelector("h3")?.textContent || "";
    const headline = prompt("New headline (leave unchanged to keep current):", currentHeadline);
    if (headline === null) return;
    const description = prompt("New description (leave blank to keep current):");
    if (description === null) return;
    const destination = prompt("New HTTPS destination URL (leave blank to keep current):",campaign.destination_url || "");
    if (destination === null) return;
    const cta = prompt("Call to action: learn_more, visit_website, contact_us or whatsapp",campaign.cta || "learn_more");
    if (cta === null) return;
    let scheduledStart = "";
    if (campaign.status === "scheduled" && !campaign.go_live_at) {
      const localStart = campaign.scheduled_start_at ? new Date(campaign.scheduled_start_at).toLocaleString("sv-SE",{timeZone:"Africa/Lagos"}).replace(" ","T").slice(0,16) : "";
      scheduledStart = prompt("New scheduled start (YYYY-MM-DDTHH:mm local time; leave blank to keep current):",localStart);
      if (scheduledStart === null) return;
    }
    const reason = prompt("Why are you requesting these changes?");
    if (!reason || reason.trim().length < 3) return;
    const payload = { action:"request-campaign-change", campaign_id:campaignId, reason:reason.trim() };
    if (headline.trim() && headline.trim() !== currentHeadline) payload.headline = headline.trim();
    if (description.trim()) payload.description = description.trim();
    if (destination.trim() && destination.trim() !== campaign.destination_url) payload.destination_url = destination.trim();
    if (cta.trim() && cta.trim() !== campaign.cta) payload.cta = cta.trim();
    if (scheduledStart.trim()) {
      const parsedStart = new Date(scheduledStart + ":00+01:00");
      if (Number.isNaN(parsedStart.getTime()) || parsedStart.getTime() <= Date.now()) {
        portal.message("globalMessage","Choose a valid future scheduled start time.",true);
        return;
      }
      payload.start_mode = "scheduled";
      payload.scheduled_start_at = parsedStart.toISOString();
    }
    button.disabled = true;
    try {
      const result = await portal.callApi(payload);
      portal.message("globalMessage","Change request submitted. Your live advert remains unchanged until admin approval.");
      await portal.refreshCampaigns();
      if (confirm("Attach a replacement image or video to this change request now?")) {
        const attachButton = Array.from(document.querySelectorAll("[data-attach-change]"))
          .find((item) => item.dataset.attachChange === result.change_request_id);
        if (attachButton) openReplacementPicker(attachButton,campaignId,result.change_request_id);
      }
    } catch (error) {
      portal.message("globalMessage",error.message,true);
    } finally { button.disabled = false; }
  }

  function ensureAdminQueue() {
    const panel = $("adminPanel");
    if (!panel || panel.classList.contains("hidden") || $("adminCampaignChanges")) return;
    const section = document.createElement("div");
    section.className = "admin-change-queue";
    section.innerHTML = "<h3>Campaign change requests</h3><div id=\"adminCampaignChanges\">Loading…</div>";
    panel.querySelector(".admin-columns")?.prepend(section);
    loadAdminQueue();
  }

  async function loadAdminQueue() {
    const target = $("adminCampaignChanges");
    if (!target) return;
    try {
      const result = await portal.callApi({action:"admin-list-campaign-changes"});
      const requests = (result.requests || []).filter((item) => item.status === "pending");
      target.innerHTML = requests.map((item) =>
        '<article class="admin-row"><strong>' + escape(item.advertising_campaigns?.headline || "Campaign") + '</strong>' +
        '<p>' + escape(item.advertiser_profiles?.display_name || "Advertiser") + '</p>' +
        '<p>Headline: ' + escape(item.proposed_headline || "No change") + '</p>' +
        '<p>Description: ' + escape(item.proposed_description || "No change") + '</p>' +
        '<p>Destination: ' + escape(item.proposed_destination_url || "No change") + '</p>' +
        '<p>Reason: ' + escape(item.advertiser_reason) + '</p>' +
        (item.proposed_creative_id ? '<button class="small-outline" data-preview-change="' + item.id + '">Preview creative</button> ' : '') +
        '<button class="small-outline" data-approve-change="' + item.id + '">Approve</button> ' +
        '<button class="small-outline" data-reject-change="' + item.id + '">Reject</button></article>'
      ).join("") || '<p class="muted">No pending campaign changes.</p>';
      target.querySelectorAll("[data-preview-change]").forEach((b) => b.addEventListener("click", async () => {
        b.disabled = true;
        try {
          const result = await portal.callApi({action:"admin-preview-change-creative",change_request_id:b.dataset.previewChange});
          const dialog = document.createElement("dialog");
          dialog.className = "advertising-creative-preview";
          dialog.style.cssText = "max-width:min(92vw,760px);max-height:90vh;border:0;border-radius:16px;padding:16px;background:#171717;color:#fff";
          const media = result.creative_type === "video"
            ? '<video controls playsinline preload="metadata" src="' + escape(result.preview_url) + '" poster="' + escape(result.poster_url || "") + '" style="display:block;max-width:100%;max-height:72vh;margin:auto"></video>'
            : '<img src="' + escape(result.preview_url) + '" alt="Proposed replacement creative" style="display:block;max-width:100%;max-height:72vh;object-fit:contain;margin:auto">';
          dialog.innerHTML = media + '<div style="display:flex;justify-content:flex-end;margin-top:12px"><button type="button" class="small-outline" data-close-preview>Close preview</button></div>';
          dialog.querySelector("[data-close-preview]").addEventListener("click", () => dialog.close());
          dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
          dialog.addEventListener("close", () => dialog.remove(), {once:true});
          document.body.append(dialog);
          dialog.showModal();
        } catch(error) { portal.message("globalMessage",error.message,true); }
        finally { b.disabled = false; }
      }));
      target.querySelectorAll("[data-approve-change]").forEach((b) => b.addEventListener("click", () => reviewChange(b.dataset.approveChange,true)));
      target.querySelectorAll("[data-reject-change]").forEach((b) => b.addEventListener("click", () => reviewChange(b.dataset.rejectChange,false)));
    } catch (error) {
      target.textContent = error.message;
    }
  }

  async function reviewChange(id, approve) {
    const reason = approve ? "" : prompt("Reason for rejecting these changes:");
    if (!approve && (!reason || reason.trim().length < 3)) return;
    try {
      await portal.callApi({action:"admin-review-campaign-change",change_request_id:id,approve,reason});
      portal.message("globalMessage",approve ? "Campaign changes approved." : "Campaign changes rejected.");
      await loadAdminQueue();
      await portal.refreshCampaigns();
    } catch (error) { portal.message("globalMessage",error.message,true); }
  }

  $("campaignList")?.addEventListener("click", (event) => {
    const attach = event.target.closest("[data-attach-change]");
    if (attach) { openReplacementPicker(attach,attach.dataset.campaignId,attach.dataset.attachChange); return; }
    const button = event.target.closest("[data-campaign-change]");
    if (button) requestChange(button);
  });
  const campaignList = $("campaignList");
  if (campaignList) new MutationObserver(addCampaignButtons).observe(campaignList,{childList:true,subtree:true});
  const adminPanel = $("adminPanel");
  if (adminPanel) new MutationObserver(ensureAdminQueue).observe(adminPanel,{attributes:true,childList:true,subtree:true});
  addCampaignButtons();
  ensureAdminQueue();
})();
