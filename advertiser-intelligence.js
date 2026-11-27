/* The Match advertiser intelligence — local preflight and lightweight form guidance.
 * No member data collection, audience profiling, or additional network requests.
 */
(() => {
  "use strict";
  const start = () => {
    const form = document.getElementById("campaignForm");
    if (!form || window.__matchAdvertiserIntelligenceLoaded) return;
    window.__matchAdvertiserIntelligenceLoaded = true;
    const $ = (id) => document.getElementById(id);
    const headline = $("campaignHeadline");
    const description = $("campaignDescription");
    const url = $("campaignUrl");
    const creative = $("campaignCreative");
    if (!headline || !description || !url || !creative) return;

    const assist = document.createElement("section");
    assist.className = "advertiser-smart-assist";
    assist.setAttribute("aria-live", "polite");
    assist.innerHTML = '<div class="smart-assist-heading"><strong>Campaign readiness check</strong><span id="smartAssistCount">0 / 4</span></div><div class="smart-assist-track"><span id="smartAssistProgress"></span></div><p id="smartAssistMessage">Complete the campaign details and choose your artwork. We will check the creative before upload.</p>';
    form.insertBefore(assist, form.firstElementChild);
    const style = document.createElement("style");
    style.textContent = '.advertiser-smart-assist{margin:0 0 16px;padding:13px 14px;border:1px solid rgba(198,166,107,.3);border-radius:13px;background:rgba(198,166,107,.07)}.smart-assist-heading{display:flex;align-items:center;justify-content:space-between;gap:10px;color:var(--match-text,#f5f0e6);font-size:13px}.smart-assist-heading span{color:#c6a66b;font-variant-numeric:tabular-nums;font-weight:800}.smart-assist-track{height:5px;margin-top:10px;overflow:hidden;border-radius:9px;background:rgba(130,130,130,.2)}.smart-assist-track span{display:block;width:0;height:100%;border-radius:9px;background:#c6a66b;transition:width .18s ease}.advertiser-smart-assist p{margin:8px 0 0;color:var(--muted,#a6a39c);font-size:12px;line-height:1.45}.smart-field-count{display:block;margin-top:4px;text-align:right;color:#888;font-size:10px;font-variant-numeric:tabular-nums}';
    document.head.appendChild(style);

    const addCounter = (field, max) => {
      const label = field.closest("label");
      if (!label) return null;
      const counter = document.createElement("span");
      counter.className = "smart-field-count";
      counter.setAttribute("aria-hidden", "true");
      label.appendChild(counter);
      const update = () => { counter.textContent = field.value.length + " / " + max; };
      field.addEventListener("input", update, { passive: true });
      update();
      return counter;
    };
    addCounter(headline, 90);
    addCounter(description, 500);
    const message = $("smartAssistMessage");
    const count = $("smartAssistCount");
    const bar = $("smartAssistProgress");
    let creativeState = "missing";
    let videoCheckToken = 0;
    let scheduled = false;
    const urlIsSafe = () => {
      try { const parsed = new URL(url.value.trim()); return parsed.protocol === "https:" || parsed.protocol === "http:"; }
      catch { return false; }
    };
    const render = () => {
      scheduled = false;
      const checks = [
        headline.value.trim().length >= 3,
        description.value.trim().length >= 1,
        urlIsSafe(),
        creativeState === "valid"
      ];
      const complete = checks.filter(Boolean).length;
      count.textContent = complete + " / 4";
      bar.style.width = (complete / 4 * 100) + "%";
      if (creativeState === "invalid") message.textContent = "Please choose a supported image or MP4 video within the size and duration limits.";
      else if (complete === 4) message.textContent = "Your campaign details and creative passed the local preflight check. Submission still requires the campaign launch to be opened by The Match.";
      else message.textContent = "Complete the headline, description, secure destination URL and creative artwork to finish the preflight check.";
    };
    const scheduleRender = () => {
      if (scheduled) return;
      scheduled = true;
      if ("requestIdleCallback" in window) window.requestIdleCallback(render, { timeout: 250 });
      else window.setTimeout(render, 80);
    };
    [headline, description, url].forEach((field) => field.addEventListener("input", scheduleRender, { passive: true }));
    creative.addEventListener("change", () => {
      const file = creative.files && creative.files[0];
      const token = ++videoCheckToken;
      creativeState = "missing";
      if (!file) { scheduleRender(); return; }
      const isImage = ["image/jpeg", "image/png", "image/webp"].includes(file.type);
      const isVideo = file.type === "video/mp4";
      if ((isImage && file.size <= 10 * 1024 * 1024) || (isVideo && file.size <= 20 * 1024 * 1024)) {
        if (isImage) {
          creativeState = "valid";
          message.textContent = "Image selected. The creative will be checked again by the server before approval.";
          scheduleRender();
          return;
        }
        const probe = document.createElement("video");
        const objectUrl = URL.createObjectURL(file);
        probe.preload = "metadata";
        probe.onloadedmetadata = () => {
          URL.revokeObjectURL(objectUrl);
          if (token !== videoCheckToken) return;
          creativeState = Number.isFinite(probe.duration) && probe.duration > 0 && probe.duration <= 30 ? "valid" : "invalid";
          scheduleRender();
        };
        probe.onerror = () => {
          URL.revokeObjectURL(objectUrl);
          if (token !== videoCheckToken) return;
          creativeState = "invalid";
          scheduleRender();
        };
        probe.src = objectUrl;
      } else {
        creativeState = "invalid";
        scheduleRender();
      }
    });
    render();
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();
