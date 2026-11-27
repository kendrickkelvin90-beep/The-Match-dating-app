/* The Match — advertising discovery prompts.
 * Adds a dismissible, low-frequency invitation in Events and highlights the
 * existing signed-in Profile entry. Does not change member authentication,
 * event eligibility, campaign approval, payment, or Discover ad serving.
 */
(() => {
  "use strict";
  if (window.__matchAdvertisingPromptsLoaded) return;
  window.__matchAdvertisingPromptsLoaded = true;

  const PORTAL_URL = "/advertiser-portal.html";
  const DISMISS_DAYS = 14;
  const STORAGE_PREFIX = "match_advertising_prompt_dismissed_v1:";
  const $ = (selector, root = document) => root.querySelector(selector);

  function addStyles() {
    if ($("#matchAdvertisingPromptStyles")) return;
    const style = document.createElement("style");
    style.id = "matchAdvertisingPromptStyles";
    style.textContent = `
      #eventsPage .match-advertising-prompt {
        display:flex; align-items:center; justify-content:space-between; gap:16px;
        margin:18px 0 22px; padding:17px 18px; border-radius:18px;
        border:1px solid rgba(205,170,104,.34);
        background:linear-gradient(125deg,rgba(38,32,23,.96),rgba(17,18,17,.98));
        color:#f4eee2; box-shadow:0 8px 24px rgba(0,0,0,.12);
      }
      #eventsPage .match-advertising-prompt-copy { min-width:0; }
      #eventsPage .match-advertising-prompt-kicker {
        margin:0 0 5px; color:#d8bd85; font-size:10px; font-weight:800;
        letter-spacing:.13em; text-transform:uppercase;
      }
      #eventsPage .match-advertising-prompt h3 {
        margin:0 0 5px; color:#fff8eb; font-size:17px; line-height:1.25;
      }
      #eventsPage .match-advertising-prompt p:not(.match-advertising-prompt-kicker) {
        margin:0; color:#d8d0c2; font-size:13px; line-height:1.5;
      }
      #eventsPage .match-advertising-prompt-actions {
        display:flex; align-items:center; gap:10px; flex-shrink:0;
      }
      #eventsPage .match-advertising-prompt-link {
        display:inline-flex; align-items:center; justify-content:center;
        min-height:42px; padding:0 14px; border-radius:11px;
        background:#d8bd85; color:#21190c !important; text-decoration:none;
        font-size:12px; font-weight:800; white-space:nowrap;
      }
      #eventsPage .match-advertising-prompt-dismiss {
        border:0; background:transparent; color:#cfc6b6; font-size:20px;
        line-height:1; padding:7px; cursor:pointer;
      }
      body.light-theme #eventsPage .match-advertising-prompt {
        background:linear-gradient(125deg,#fffaf0,#f4f0e7);
        border-color:#e3d4b6; box-shadow:0 6px 18px rgba(45,35,18,.07);
      }
      body.light-theme #eventsPage .match-advertising-prompt h3 { color:#29251d !important; }
      body.light-theme #eventsPage .match-advertising-prompt p:not(.match-advertising-prompt-kicker) { color:#625b4e !important; }
      body.light-theme #eventsPage .match-advertising-prompt-dismiss { color:#625b4e; }
      #profileHomeDashboard a[href="/advertiser-portal.html"] {
        border:1px solid rgba(205,170,104,.38);
        background:linear-gradient(120deg,rgba(205,170,104,.10),rgba(205,170,104,.035));
      }
      @media(max-width:520px) {
        #eventsPage .match-advertising-prompt { align-items:flex-start; flex-direction:column; }
        #eventsPage .match-advertising-prompt-actions { width:100%; justify-content:space-between; }
        #eventsPage .match-advertising-prompt-link { flex:1; }
      }
    `;
    document.head.appendChild(style);
  }

  function currentUserKey() {
    const user = window.db?.auth?.getUser;
    return window.__MATCH_CURRENT_USER_ID || window.currentUser?.id ||
      window.matchCurrentUser?.id || "";
  }

  function shouldShow() {
    const userId = currentUserKey();
    if (!userId) return false;
    try {
      const lastDismissed = Number(localStorage.getItem(STORAGE_PREFIX + userId) || 0);
      return !lastDismissed || Date.now() - lastDismissed >= DISMISS_DAYS * 86400000;
    } catch (_) { return true; }
  }

  function mountEventsPrompt() {
    const page = $("#eventsPage");
    const heading = $("#eventsPage .events-heading");
    if (!page || !heading || $(".match-advertising-prompt", page) || !shouldShow()) return;
    const card = document.createElement("aside");
    card.className = "match-advertising-prompt";
    card.setAttribute("aria-label", "Advertising opportunities");
    card.innerHTML = `
      <div class="match-advertising-prompt-copy">
        <p class="match-advertising-prompt-kicker">A new opportunity on The Match</p>
        <h3>Have something worth sharing?</h3>
        <p>Promote your business, brand, service or event. Advertising opportunities are available to individuals and organisations.</p>
      </div>
      <div class="match-advertising-prompt-actions">
        <a class="match-advertising-prompt-link" href="${PORTAL_URL}">Explore Advertising</a>
        <button class="match-advertising-prompt-dismiss" type="button" aria-label="Dismiss advertising invitation">×</button>
      </div>`;
    $(".match-advertising-prompt-dismiss", card).addEventListener("click", () => {
      const userId = currentUserKey();
      if (userId) {
        try { localStorage.setItem(STORAGE_PREFIX + userId, String(Date.now())); } catch (_) {}
      }
      card.remove();
    });
    heading.insertAdjacentElement("afterend", card);
  }

  function refresh() {
    addStyles();
    mountEventsPrompt();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", refresh, { once: true });
  } else refresh();

  const observer = new MutationObserver(() => {
    if ($("#eventsPage") && !$(".match-advertising-prompt", $("#eventsPage"))) refresh();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.setTimeout(() => observer.disconnect(), 120000);
})();