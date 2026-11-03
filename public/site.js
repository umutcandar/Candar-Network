(function () {
  "use strict";
  var acquisition = window.CandarAcquisition;
  if (!acquisition) return;
  var downloadPage = document.body.getAttribute("data-page-type") === "download";
  if (!downloadPage) acquisition.event("site_page_view");

  Array.prototype.forEach.call(document.querySelectorAll("a[href]"), function (link) {
    var url = new URL(link.href, window.location.href);
    var store = link.getAttribute("data-store");
    var placement = link.getAttribute("data-track") || "link";
    if (store) {
      // Preserve an invitation via the explicit copy step before leaving for a store.
      if (acquisition.context.ref && !downloadPage) {
        var downloadPath = document.documentElement.lang === "en" ? "/en/download" : "/download";
        link.href = acquisition.withContext(downloadPath, placement).href;
      } else {
        link.href = acquisition.storeURL(store, placement);
        if (acquisition.platform === store) link.classList.add("recommended");
      }
    } else if (url.origin === window.location.origin && !link.getAttribute("href").startsWith("#") &&
      (/^\/(en\/)?(download(?:\.html)?\/?|$)/.test(url.pathname) || url.pathname.startsWith("/guides/"))) {
      link.href = acquisition.withContext(link.href, placement).href;
    }
    if (!link.hasAttribute("data-track") && !store) return;
    link.addEventListener("click", function () {
      var destination = new URL(link.href, window.location.href);
      acquisition.event("site_cta_click", { cta: placement, destination: destination.origin + destination.pathname });
      if (store && destination.origin !== window.location.origin) {
        var click = acquisition.event("store_click", { store: store, cta: placement });
        window.candarDownloadTracking = window.candarDownloadTracking || [];
        window.candarDownloadTracking.push(click);
      }
    });
  });
}());
