/* The Match admin dashboard navigation.
 * Organises existing admin controls into short, named pages without changing their data/actions.
 */
(() => {
  "use strict";
  const init = () => {
    const panel = document.getElementById("adminPanel");
    const shell = panel?.querySelector(".admin-shell");
    const topbar = shell?.querySelector(".admin-topbar");
    if (!panel || !shell || !topbar || shell.querySelector("[data-admin-page-nav]")) return;
    const groups = { overview: [], requests: [], members: [], premium: [], media: [], activity: [] };
    const add = (group, element) => { if (element && !groups[group].includes(element)) groups[group].push(element); };
    const direct = Array.from(shell.children);
    let metricGrid = 0;
    direct.forEach((element) => {
      const text = (element.textContent || "").trim().toLowerCase();
      if (element.matches(".admin-welcome-strip")) add("overview", element);
      else if (element.matches(".admin-section-heading")) {
        if (/key metrics|member activation|overview/.test(text)) add("overview", element);
        else if (/action centre|events/.test(text)) add("requests", element);
        else if (/community/.test(text)) add("members", element);
        else if (/premium/.test(text)) add("premium", element);
        else if (/backblaze|media/.test(text)) add("media", element);
        else if (/activity|analytics/.test(text)) add("activity", element);
      } else if (element.matches(".admin-metrics-grid")) {
        add(metricGrid++ < 2 ? "overview" : "activity", element);
      } else if (element.matches(".admin-queues-grid,.admin-events-control")) add("requests", element);
      else if (element.matches('[aria-labelledby="adminMembersHeading"]')) add("members", element);
      else if (element.matches('[aria-labelledby="adminPremiumHeading"]')) add("premium", element);
      else if (element.matches('[aria-labelledby="adminB2Heading"]')) add("media", element);
      else if (element.matches('[aria-labelledby="adminAnalyticsHeading"],#adminActivityDetail')) add("activity", element);
      else if (element.matches(".admin-data-note")) add("overview", element);
    });
    add("activity", document.getElementById("adminActivityDetail"));
    const labels = [
      ["overview", "Overview"], ["requests", "Requests & events"], ["members", "Members"],
      ["premium", "Premium"], ["media", "Media"], ["activity", "Activity"]
    ];
    const nav = document.createElement("nav");
    nav.dataset.adminPageNav = "true";
    nav.setAttribute("aria-label", "Admin dashboard pages");
    nav.innerHTML = labels.map(([key, label], i) => '<button type="button" data-admin-page="' + key + '" aria-pressed="' + (i === 0 ? "true" : "false") + '">' + label + '</button>').join("")
      + '<a href="/advertiser-admin.html">Advertising</a>';
    const style = document.createElement("style");
    style.textContent = '#adminPanel [data-admin-page-nav]{position:sticky;top:0;z-index:20;display:flex;gap:7px;overflow-x:auto;padding:10px 0 13px;margin:12px 0 18px;background:#090a0d;scrollbar-width:thin}#adminPanel [data-admin-page-nav] button,#adminPanel [data-admin-page-nav] a{flex:0 0 auto;min-height:40px;padding:9px 13px;border:1px solid #39362e;border-radius:11px;background:#151515;color:#d7d0c2;font:inherit;font-size:12px;font-weight:700;text-decoration:none;white-space:nowrap}#adminPanel [data-admin-page-nav] button[aria-pressed="true"]{background:#d8b56b;border-color:#d8b56b;color:#17120a}#adminPanel [data-admin-page-nav] a{border-color:#8b713d;color:#e7c77f}#adminPanel [data-admin-group-hidden="true"]{display:none!important}body.light-theme #adminPanel [data-admin-page-nav]{background:#fff}body.light-theme #adminPanel [data-admin-page-nav] button{background:#fff;color:#254c46;border-color:#c9d5cf}body.light-theme #adminPanel [data-admin-page-nav] button[aria-pressed="true"]{background:#254c46;color:#fff;border-color:#254c46}';
    document.head.appendChild(style);
    topbar.insertAdjacentElement("afterend", nav);
    const show = (key) => {
      Object.entries(groups).forEach(([group, elements]) => elements.forEach((element) => {
        element.dataset.adminGroupHidden = String(group !== key);
      }));
      nav.querySelectorAll("button[data-admin-page]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.adminPage === key)));
      nav.dataset.activePage = key;
    };
    nav.querySelectorAll("button[data-admin-page]").forEach((button) => button.addEventListener("click", () => show(button.dataset.adminPage)));
    show("overview");
    panel.addEventListener("click", (event) => {
      const detail = event.target.closest("[data-admin-detail]");
      if (detail) show("activity");
      const jump = event.target.closest("[data-admin-jump]");
      if (jump) show("requests");
    });
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
  const observer = new MutationObserver(() => init());
  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
