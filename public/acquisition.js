/* Shared, session-scoped campaign context. No identity or referral code is sent to analytics. */
(function () {
  "use strict";
  var params = new URLSearchParams(window.location.search);
  var storageKey = "candar_acquisition_v1";
  var keys = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"];
  var now = Date.now();
  var saved = {};
  function clean(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 64);
  }
  function referral(value) {
    var code = String(value || "").trim();
    return /^[a-z0-9_-]{4,32}$/i.test(code) ? code.toUpperCase() : "";
  }
  try {
    var stored = JSON.parse(sessionStorage.getItem(storageKey) || "null");
    if (stored && now - stored.at < 30 * 60 * 1000 && now >= stored.at) saved = stored;
  } catch (_) { /* Storage can be unavailable in private browsers. Links still work. */ }
  var incomingSource = clean(params.get("utm_source") || params.get("src"));
  var context = incomingSource ? {} : saved;
  keys.forEach(function (key) {
    context[key] = clean(params.get(key)) || clean(context[key]);
  });
  context.utm_source = incomingSource || context.utm_source || "direct";
  context.utm_medium = context.utm_medium || (context.utm_source === "direct" ? "none" : "referral");
  context.utm_campaign = context.utm_campaign || "download";
  // A new campaign does not silently inherit a previous friend's invitation.
  context.ref = referral(params.get("ref") || params.get("referral")) || referral(context.ref);
  context.at = now;
  try { sessionStorage.setItem(storageKey, JSON.stringify(context)); } catch (_) {}

  function withContext(href, placement) {
    var url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin) return url;
    keys.forEach(function (key) {
      if (context[key]) url.searchParams.set(key, context[key]);
    });
    url.searchParams.delete("src");
    url.searchParams.delete("referral");
    if (context.ref) url.searchParams.set("ref", context.ref);
    if (placement) url.searchParams.set("placement", clean(placement));
    return url;
  }
  function storeURL(store, placement) {
    if (store === "ios") {
      var ios = new URL("https://apps.apple.com/app/id6756212781");
      ios.searchParams.set("ct", (context.utm_source + "_" + context.utm_campaign).slice(0, 40));
      return ios.href;
    }
    var android = new URL("https://play.google.com/store/apps/details");
    android.searchParams.set("id", "com.candarnetwork.app");
    var referrer = new URLSearchParams();
    keys.forEach(function (key) { if (context[key]) referrer.set(key, context[key]); });
    if (placement) referrer.set("placement", clean(placement));
    if (context.ref) referrer.set("ref", context.ref);
    android.searchParams.set("referrer", referrer.toString());
    return android.href;
  }
  function event(name, extra) {
    var data = Object.assign({
      event: name,
      source: context.utm_source,
      medium: context.utm_medium,
      campaign: context.utm_campaign,
      content: context.utm_content || "download_page",
      referral_present: Boolean(context.ref),
      page_type: document.body.getAttribute("data-page-type") || "site",
      page_path: window.location.pathname,
      language: document.documentElement.lang
    }, extra || {});
    window.dataLayer = window.dataLayer || [];
    window.dataLayer.push(data);
    return data;
  }
  var agent = navigator.userAgent || "";
  var platform = /Android/i.test(agent) ? "android" :
    (/iPhone|iPad|iPod/i.test(agent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1) ? "ios" : "");
  window.CandarAcquisition = { context: context, withContext: withContext, storeURL: storeURL, event: event, platform: platform };
}());
