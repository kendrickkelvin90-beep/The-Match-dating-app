(() => {
  "use strict";

  const STYLE_ID = "tm-discover-boost-experience-style";
  const PANEL_ID = "tm-discover-boost-status";
  let countdownTimer = null;
  let refreshTimer = null;
  let activeEndsAt = null;
  let statusLoaded = false;

  function addStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #discover #${PANEL_ID} {
        display:flex; align-items:center; justify-content:space-between; gap:14px;
        width:100%; box-sizing:border-box; margin:12px 0 14px; padding:14px 15px;
        border:1px solid rgba(213,179,109,.42); border-radius:16px;
        background:linear-gradient(125deg,rgba(213,179,109,.13),rgba(18,16,13,.96) 62%);
        color:#f7f0df;
      }
      #discover #${PANEL_ID}[hidden] { display:none!important; }
      #${PANEL_ID} .tm-boost-copy { min-width:0; }
      #${PANEL_ID} .tm-boost-eyebrow { display:block; margin-bottom:4px; color:#d8b76f; font-size:10px; font-weight:800; letter-spacing:1.35px; text-transform:uppercase; }
      #${PANEL_ID} .tm-boost-title { margin:0; color:#fff; font-size:14px; font-weight:800; }
      #${PANEL_ID} .tm-boost-description { margin:4px 0 0; color:#c7bdab; font-size:12px; line-height:1.45; }
      #${PANEL_ID} .tm-boost-time { flex:0 0 auto; color:#f0d493; font-size:15px; font-weight:900; font-variant-numeric:tabular-nums; text-align:right; }
      #${PANEL_ID} .tm-boost-action { flex:0 0 auto; min-height:38px; padding:8px 12px; border:1px solid #c6a15b; border-radius:11px; background:linear-gradient(135deg,#f0d493,#bd9148); color:#21180b; font-size:11px; font-weight:900; }
      body.light-theme #discover #${PANEL_ID} { background:linear-gradient(125deg,#fffaf0,#f5eddd); color:#292319; border-color:#d8c08e; }
      body.light-theme #${PANEL_ID} .tm-boost-title { color:#292319; }
      body.light-theme #${PANEL_ID} .tm-boost-description { color:#655b49; }
      body.light-theme #${PANEL_ID} .tm-boost-time { color:#8a682e; }
      @media(max-width:380px) { #${PANEL_ID} { gap:8px; padding:12px!important; } #${PANEL_ID} .tm-boost-time { font-size:13px; } }
    `;
    document.head.appendChild(style);
  }

  function ensurePanel() {
    const toolbar = document.querySelector("#discover .discover-premium-tools");
    if (!toolbar) return null;
    let panel = document.getElementById(PANEL_ID);
    if (panel) return panel;
    panel = document.createElement("section");
    panel.id = PANEL_ID;
    panel.setAttribute("aria-live", "polite");
    panel.hidden = true;
    panel.innerHTML = `
      <div class="tm-boost-copy">
        <span class="tm-boost-eyebrow">Profile visibility</span>
        <p class="tm-boost-title">Profile Boost</p>
        <p class="tm-boost-description">Get priority placement in Discover while your boost is active.</p>
      </div>
      <div class="tm-boost-time" data-boost-time></div>
      <button class="tm-boost-action" type="button" data-boost-action>Boost profile</button>
    `;
    toolbar.insertAdjacentElement("afterend", panel);
    panel.querySelector("[data-boost-action]").addEventListener("click", () => {
      document.getElementById("profileBoostBtn")?.click();
    });
    return panel;
  }

  function formatRemaining(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    return hours > 0
      ? hours + "h " + String(minutes).padStart(2, "0") + "m"
      : minutes + "m " + String(seconds).padStart(2, "0") + "s";
  }

  function renderCountdown() {
    const panel = ensurePanel();
    if (!panel || !statusLoaded) return;
    const title = panel.querySelector(".tm-boost-title");
    const description = panel.querySelector(".tm-boost-description");
    const time = panel.querySelector("[data-boost-time]");
    const action = panel.querySelector("[data-boost-action]");
    panel.hidden = false;

    if (!activeEndsAt) {
      title.textContent = "Give your profile a lift";
      description.textContent = "Activate a Profile Boost for priority placement in Discover. Duration depends on your Boost type.";
      time.textContent = "";
      action.textContent = "Boost profile";
      action.hidden = false;
      return;
    }

    const remaining = activeEndsAt - Date.now();
    if (remaining > 0) {
      title.textContent = "Your Profile Boost is active";
      description.textContent = "Your profile is receiving priority placement in Discover.";
      time.textContent = formatRemaining(remaining);
      action.hidden = true;
    } else {
      title.textContent = "Your Profile Boost has ended";
      description.textContent = "Your profile has returned to normal Discover placement.";
      time.textContent = "Expired";
      action.textContent = "Boost again";
      action.hidden = false;
    }
  }

  async function refreshBoostStatus() {
    const panel = ensurePanel();
    if (!panel || !window.db?.auth) return;
    try {
      const { data: authData, error: authError } = await window.db.auth.getUser();
      if (authError || !authData?.user) {
        activeEndsAt = null;
        statusLoaded = false;
        panel.hidden = true;
        return;
      }
      const { data, error } = await window.db.rpc("get_my_active_profile_boost");
      if (error) throw error;
      const activeBoost = Array.isArray(data) ? data[0] : data;
      activeEndsAt = activeBoost?.ends_at ? new Date(activeBoost.ends_at).getTime() : null;
      statusLoaded = true;
      renderCountdown();
    } catch (error) {
      // Keep the existing Discover flow working if boost status cannot be read.
      console.warn("Profile Boost status is temporarily unavailable:", error);
      statusLoaded = true;
      activeEndsAt = null;
      renderCountdown();
    }
  }

  function start() {
    addStyles();
    ensurePanel();
    refreshBoostStatus();
    if (countdownTimer) clearInterval(countdownTimer);
    // Update the visible clock locally; do not poll Supabase every second.
    countdownTimer = setInterval(renderCountdown, 1000);
    const boostButton = document.getElementById("profileBoostBtn");
    if (boostButton && !boostButton.dataset.boostStatusRefreshBound) {
      boostButton.dataset.boostStatusRefreshBound = "true";
      boostButton.addEventListener("click", () => {
        if (refreshTimer) clearTimeout(refreshTimer);
        refreshTimer = setTimeout(refreshBoostStatus, 1800);
        setTimeout(refreshBoostStatus, 3500);
      });
    }
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) refreshBoostStatus();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
