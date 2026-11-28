/* The Match — sponsored Discover feed data helpers.
 * Ads are requested as feed entries by index.html and rendered in the existing portrait slot.
 * This file deliberately does not insert DOM nodes or create a second card outside the portrait.
 */
(() => {
  "use strict";
  if (window.__matchSponsoredFeedHelpersLoaded) return;
  const config = window.MATCH_SPONSORED_AD_CONFIG || {};
  const endpoint = String(config.advertiserSupabaseUrl || "").replace(/\/$/, "") + "/functions/v1/member-ad-serving";
  async function memberRequest(action, payload = {}) {
    const db = window.db;
    if (config.enabled !== true || !config.publishableKey || !endpoint || !db?.auth) return null;
    const { data, error } = await db.auth.getSession();
    if (error || !data?.session?.access_token) return null;
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": config.publishableKey,
        "Authorization": "Bearer " + data.session.access_token
      },
      body: JSON.stringify({ action, ...payload }),
      cache: "no-store"
    });
    if (!response.ok) return null;
    return response.json().catch(() => null);
  }
  window.matchGetSponsoredAd = async (slotIndex) => {
    const result = await memberRequest("get-ad", { slot_index: Number(slotIndex) || 1 });
    const ad = result?.ad;
    if (!ad?.campaign_id || !ad?.creative_url || !ad?.destination_url) return null;
    return ad;
  };
  window.matchRecordSponsoredEvent = (campaignId, eventType) => {
    if (!campaignId || !["impression", "click"].includes(eventType)) return Promise.resolve(null);
    return memberRequest("record-event", { campaign_id: campaignId, event_type: eventType }).catch(() => null);
  };
  window.__matchSponsoredFeedHelpersLoaded = true;
})();
