"use strict";

const crypto = require("node:crypto");

const IOS_REFUND_EVENTS = new Set(["REFUND", "REVOKE"]);
const ANDROID_PACKAGE = "com.candarnetwork.app";

function sha256(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex");
}

// The Apple notification body is merely a LOOKUP HINT. It is NOT authenticated
// by decoding it. Callers must retrieve transaction status from Apple's
// authenticated App Store Server API before changing an entitlement.
function decodeUntrustedJws(jws) {
  if (typeof jws !== "string" || jws.length < 20 || jws.length > 32768) return null;
  const parts = jws.split(".");
  if (parts.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(parts[1])) return null;
  try {
    const obj = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    return obj && typeof obj === "object" && !Array.isArray(obj) ? obj : null;
  } catch { return null; }
}

function readAppleRefundHint(signedPayload) {
  const notification = decodeUntrustedJws(signedPayload);
  if (!notification || !IOS_REFUND_EVENTS.has(notification.notificationType)) return null;
  const tx = decodeUntrustedJws(notification?.data?.signedTransactionInfo);
  const transactionId = String(tx?.transactionId || "");
  const bundleId = String(notification?.data?.bundleId || "");
  if (!/^\d{5,32}$/.test(transactionId) || bundleId !== ANDROID_PACKAGE) return null;
  return { transactionId, type: notification.notificationType };
}

function normalizeGoogleVoidedPurchase(value) {
  if (!value || typeof value !== "object") return null;
  const orderId = String(value.orderId || "").trim();
  const purchaseToken = String(value.purchaseToken || "").trim();
  const voidedAtMs = Number(value.voidedTimeMillis);
  if (!orderId || orderId.length > 180 || !purchaseToken ||
      purchaseToken.length > 4096 || !Number.isSafeInteger(voidedAtMs) ||
      voidedAtMs <= 0 || !/^[A-Za-z0-9_.-]+$/.test(orderId)) return null;
  // Quantity-based partial refunds need per-unit accounting, which this app
  // does not sell. Never revoke the entire entitlement for a partial refund.
  if (Number(value.voidedQuantity || 0) > 0) return null;
  return {
    orderId,
    tokenHash: sha256(purchaseToken),
    voidedAtMs,
    reason: Number(value.voidedReason || 0),
  };
}

function googleVoidedUrl({ startMs, pageToken = "", packageName = ANDROID_PACKAGE }) {
  if (packageName !== ANDROID_PACKAGE) throw new Error("Unexpected Google Play package");
  const url = new URL("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
    packageName + "/purchases/voidedpurchases");
  url.searchParams.set("type", "0"); // all products here are one-time purchases
  url.searchParams.set("pageSelection.maxResults", "500");
  if (pageToken) url.searchParams.set("pageSelection.token", pageToken);
  else url.searchParams.set("startTime", String(startMs));
  return url.toString();
}

function timestampMs(value) {
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value?._seconds === "number") return value._seconds * 1000;
  if (typeof value?.seconds === "number") return value.seconds * 1000;
  return 0;
}

function revokeUserFields({ user, eventId, event, nowMs = Date.now(), voidedTokenHash = "" }) {
  const premium = event?.isPremium === true;
  const pointerKey = premium ? "lastPremiumPurchaseEventId" : "lastBoostPurchaseEventId";
  const currentEventId = String(user?.[pointerKey] || "");
  if (currentEventId && currentEventId !== eventId) return null; // never cancel a newer purchase
  if (!currentEventId) {
    // Migration for purchases from before the entitlement pointers existed:
    // accept ONLY the most recently recorded purchase, identified by its
    // exact server timestamp or Google receipt hash (never by product alone).
    const samePurchase = user?.lastPurchasePlatform === event?.platform
      && user?.lastPurchaseProductId === event?.productId;
    const sameToken = Boolean(voidedTokenHash)
      && String(user?.lastPurchaseProofHash || "") === voidedTokenHash;
    const userAt = timestampMs(user?.lastPurchaseAt);
    const eventAt = timestampMs(event?.purchaseAt);
    const sameTime = userAt > 0 && eventAt > 0 && Math.abs(userAt - eventAt) <= 1000;
    if (!samePurchase || (!sameToken && !sameTime)) return null;
  }
  if (premium) {
    return {
      isPremium: false,
      premiumExpiresAt: new Date(nowMs),
      premium: { is_active: false, expires_at: new Date(nowMs) },
      [pointerKey]: "",
    };
  }
  return {
    currentMultiplier: 1,
    boostExpiresAt: new Date(nowMs),
    mining: {
      ...(user?.mining || {}),
      active_multiplier: 1,
      boost_expires_at: new Date(nowMs),
    },
    [pointerKey]: "",
  };
}

module.exports = {
  sha256,
  readAppleRefundHint,
  normalizeGoogleVoidedPurchase,
  googleVoidedUrl,
  revokeUserFields,
};
