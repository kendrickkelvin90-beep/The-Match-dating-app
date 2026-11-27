/* The Match — Discover sponsored-card integration.
 * Runs only when the separate advertiser project is configured and enabled.
 * It never adds advertisers to member profile data or changes member actions.
 */
(() => {
  "use strict";
  if (window.__matchSponsoredDiscoverLoaded) return;
  window.__matchSponsoredDiscoverLoaded = true;

  const config = window.MATCH_SPONSORED_AD_CONFIG || {};
  if (config.enabled !== true || !config.advertiserSupabaseUrl || !config.publishableKey) return;

  const list = document.getElementById("profileList");
  const discover = document.getElementById("discover");
  const db = window.db;
  if (!list || !discover || !db?.auth) return;

  const endpoint = config.advertiserSupabaseUrl.replace(/\/$/, "") + "/functions/v1/member-ad-serving";
  const organicSelector = ".member-card,.discover-option3-card";
  const processed = new WeakSet();
  const requested = new WeakSet();
  const cardsByAnchor = new Map();
  let observer = null;
  let sequence = 0;
  let feedGeneration = 0;
  let previousOrganicCount = 0;

  const safeText = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[char]));

  async function memberRequest(action, payload = {}) {
    const { data } = await db.auth.getSession();
    const token = data?.session?.access_token;
    if (!token) return null;
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": config.publishableKey,
        "Authorization": "Bearer " + token
      },
      body: JSON.stringify({ action, ...payload }),
      cache: "no-store"
    });
    if (!response.ok) return null;
    return await response.json().catch(() => null);
  }

  function ctaLabel(cta) {
    return ({
      learn_more: "Learn More",
      visit_website: "Visit Website",
      contact_us: "Contact Us",
      whatsapp: "WhatsApp"
    })[cta] || "Learn More";
  }

  function createCard(ad) {
    const card = document.createElement("article");
    card.className = "match-sponsored-ad-card";
    card.dataset.campaignId = ad.campaign_id;
    card.setAttribute("aria-label", "Sponsored advert");

    const media = document.createElement("div");
    media.className = "match-sponsored-ad-media";
    if (ad.creative_type === "video") {
      const video = document.createElement("video");
      video.className = "match-sponsored-ad-video";
      video.muted = true;
      video.loop = true;
      video.playsInline = true;
      video.preload = "none";
      video.poster = ad.poster_url || "";
      video.dataset.src = ad.creative_url;
      media.appendChild(video);

      const sound = document.createElement("button");
      sound.type = "button";
      sound.className = "match-sponsored-ad-sound";
      sound.textContent = "Tap for sound";
      sound.addEventListener("click", () => {
        video.muted = !video.muted;
        sound.textContent = video.muted ? "Tap for sound" : "Sound on";
        if (!video.paused) video.play().catch(() => {});
      });
      media.appendChild(sound);
    } else {
      const image = document.createElement("img");
      image.className = "match-sponsored-ad-image";
      image.src = ad.creative_url;
      image.alt = "Sponsored advert";
      image.loading = "lazy";
      image.decoding = "async";
      media.appendChild(image);
    }

    const body = document.createElement("div");
    body.className = "match-sponsored-ad-body";
    const label = document.createElement("span");
    label.className = "match-sponsored-ad-label";
    label.textContent = "Sponsored";
    const headline = document.createElement("h3");
    headline.textContent = ad.headline || "";
    const description = document.createElement("p");
    description.textContent = ad.description || "";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "match-sponsored-ad-cta";
    button.textContent = ctaLabel(ad.cta);
    button.addEventListener("click", () => {
      // Open synchronously so mobile browsers do not block the destination.
      const destination = window.open(ad.destination_url, "_blank", "noopener,noreferrer");
      if (destination) destination.opener = null;
      memberRequest("record-event", { campaign_id: ad.campaign_id, event_type: "click" }).catch(() => {});
    });
    body.append(label, headline, description, button);
    card.append(media, body);
    return card;
  }

  function installStyles() {
    if (document.getElementById("match-sponsored-ad-styles")) return;
    const style = document.createElement("style");
    style.id = "match-sponsored-ad-styles";
    style.textContent = [
      "#discover #profileList>.match-sponsored-ad-card{display:block;width:100%;max-width:100%;margin:18px 0 22px;overflow:hidden;border:1px solid rgba(214,180,110,.38);border-radius:22px;background:#15130f;color:#f6f0e5;box-sizing:border-box;}",
      "#discover .match-sponsored-ad-media{position:relative;width:100%;aspect-ratio:4/5;max-height:720px;overflow:hidden;background:#0d0d0d;}",
      "#discover .match-sponsored-ad-image,#discover .match-sponsored-ad-video{display:block;width:100%;height:100%;object-fit:cover;object-position:center center;}",
      "#discover .match-sponsored-ad-body{display:flex;flex-direction:column;gap:8px;padding:16px;background:linear-gradient(155deg,#1b1915,#100f0d);}",
      "#discover .match-sponsored-ad-label{align-self:flex-start;border:1px solid rgba(214,180,110,.42);border-radius:999px;padding:4px 9px;color:#e7cc91;font-size:10px;font-weight:800;letter-spacing:.13em;text-transform:uppercase;}",
      "#discover .match-sponsored-ad-body h3{margin:0;color:#f8f3e8;font-size:22px;line-height:1.2;}",
      "#discover .match-sponsored-ad-body p{margin:0;color:#d3cbbb;font-size:14px;line-height:1.45;}",
      "#discover .match-sponsored-ad-cta{align-self:stretch;min-height:48px;margin-top:4px;border:1px solid #d2aa62;border-radius:13px;background:linear-gradient(135deg,#f4dfad,#c99b4b);color:#33230b;font-size:14px;font-weight:800;}",
      "#discover .match-sponsored-ad-sound{position:absolute;right:12px;bottom:12px;border:1px solid #ffffff55;border-radius:999px;padding:8px 12px;background:#0009;color:#fff;font-size:11px;}",
      "body.light-theme #discover #profileList>.match-sponsored-ad-card{background:#fffdf8;color:#211f1b;border-color:rgba(177,137,62,.32);}",
      "body.light-theme #discover .match-sponsored-ad-body{background:#fffdf8;}",
      "body.light-theme #discover .match-sponsored-ad-body h3{color:#211f1b;}",
      "body.light-theme #discover .match-sponsored-ad-body p{color:#625a4c;}",
      "@media(min-width:900px){#discover #profileList>.match-sponsored-ad-card{max-width:620px;margin-left:auto;margin-right:auto;}}"
    ].join("");
    document.head.appendChild(style);
  }

  async function loadAd(anchor, slotIndex) {
    if (requested.has(anchor)) return;
    requested.add(anchor);
    const response = await memberRequest("get-ad", { slot_index: slotIndex });
    const ad = response?.ad;
    if (!ad || !ad.campaign_id || !ad.creative_url) return;
    const card = createCard(ad);
    card.dataset.anchorId = anchor.dataset.matchSponsoredAnchorId;
    cardsByAnchor.set(anchor, card);
    anchor.insertAdjacentElement("afterend", card);
    observeCard(card);
  }

  function observeCard(card) {
    if (!observer) {
      observer = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          const target = entry.target;
          const video = target.querySelector("video");
          if (entry.isIntersecting && entry.intersectionRatio >= 0.5) {
            if (video && !video.src && video.dataset.src) {
              video.src = video.dataset.src;
              video.load();
            }
            if (video) video.play().catch(() => {});
            if (!target.dataset.impressionTimer && target.dataset.impressionRecorded !== "true") {
              target.dataset.impressionTimer = "pending";
              window.setTimeout(() => {
                delete target.dataset.impressionTimer;
                if (!target.isConnected || !target.dataset.campaignId) return;
                const rect = target.getBoundingClientRect();
                const visible = Math.max(0, Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0));
                if (visible / Math.max(rect.height, 1) < 0.5) return;
                target.dataset.impressionRecorded = "true";
                memberRequest("record-event", { campaign_id: target.dataset.campaignId, event_type: "impression" }).catch(() => {});
              }, 1000);
            }
          } else if (video) {
            video.pause();
          }
        }
      }, { threshold: [0, 0.5, 1] });
    }
    observer.observe(card);
  }

  function scan() {
    if (!list.isConnected || !discover.isConnected) return;
    const organic = Array.from(list.children).filter((node) => node.matches?.(organicSelector));
    if (!organic.length && previousOrganicCount > 0) {
      feedGeneration++;
      sequence = 0;
      processed.clear?.();
      requested.clear?.();
      cardsByAnchor.clear();
      list.querySelectorAll(".match-sponsored-ad-card").forEach((card) => card.remove());
    }
    previousOrganicCount = organic.length;
    organic.forEach((anchor, index) => {
      if (!anchor.dataset.matchSponsoredAnchorId) anchor.dataset.matchSponsoredAnchorId = "sponsored-anchor-" + (++sequence);
      if (processed.has(anchor)) return;
      processed.add(anchor);
      const ordinal = index + 1;
      if (ordinal % 12 === 0) {
        const slotIndex = Math.floor(ordinal / 12);
        loadAd(anchor, slotIndex + feedGeneration * 1000).catch(() => {});
      }
    });
  }

  installStyles();
  scan();
  const listObserver = new MutationObserver(() => scan());
  listObserver.observe(list, { childList: true });
  const pageObserver = new MutationObserver(() => {
    if (!discover.isConnected) {
      listObserver.disconnect();
      pageObserver.disconnect();
      observer?.disconnect();
    }
  });
  pageObserver.observe(document.documentElement, { childList: true, subtree: true });

  db.auth.onAuthStateChange((event) => {
    if (event === "SIGNED_OUT") {
      list.querySelectorAll(".match-sponsored-ad-card").forEach((card) => card.remove());
      observer?.disconnect();
    }
  });
})();
