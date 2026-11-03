(function () {
  "use strict";
  var acquisition = window.CandarAcquisition;
  if (!acquisition) return;
  var code = acquisition.context.ref;
  var card = document.getElementById("inviteCodeCard");
  var value = document.getElementById("inviteCodeValue");
  var copy = document.getElementById("copyInviteCode");
  var status = document.getElementById("copyInviteStatus");
  if (code && card && value) {
    card.hidden = false;
    value.textContent = code;
  }
  if (copy) {
    copy.addEventListener("click", function () {
      function failed() {
        if (status) status.textContent = copy.getAttribute("data-failure");
        acquisition.event("invite_copy", { result: "failed" });
      }
      if (!code || !navigator.clipboard || !navigator.clipboard.writeText) { failed(); return; }
      navigator.clipboard.writeText("candar_ref=" + code).then(function () {
        if (status) status.textContent = copy.getAttribute("data-success");
        acquisition.event("invite_copy", { result: "success" });
      }).catch(failed);
    });
  }
  if (acquisition.platform) {
    var label = document.createElement("p");
    label.className = "store-recommendation";
    label.textContent = document.body.getAttribute("data-recommended-label") + ": " +
      (acquisition.platform === "ios" ? "App Store" : "Google Play");
    var actions = document.querySelector(".store-actions");
    if (actions) actions.insertAdjacentElement("afterend", label);
  }
  window.candarDownloadTracking = window.candarDownloadTracking || [];
  window.candarDownloadTracking.push(acquisition.event("download_page_view"));
}());
