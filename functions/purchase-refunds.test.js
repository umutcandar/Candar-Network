"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
 sha256, readAppleRefundHint, normalizeGoogleVoidedPurchase,
 googleVoidedUrl, revokeUserFields
} = require("./purchase-refunds");

function fakeJws(json) {
  return "e30." + Buffer.from(JSON.stringify(json)).toString("base64url") + ".c2ln";
}
test("Apple refund events are only lookup hints, never arbitrary grants", () => {
  const valid = fakeJws({
    notificationType: "REFUND", data: {
      bundleId: "com.candarnetwork.app",
      signedTransactionInfo: fakeJws({ transactionId: "1234567890" }),
    }
  });
  assert.deepEqual(readAppleRefundHint(valid), { transactionId: "1234567890", type: "REFUND" });
  assert.equal(readAppleRefundHint(fakeJws({ notificationType: "DID_RENEW", data: {} })), null);
  assert.deepEqual(readAppleRefundHint(valid.replace("REFUND", "INVALID")), readAppleRefundHint(valid));
  assert.equal(readAppleRefundHint(fakeJws({
    notificationType: "REFUND",
    data: { bundleId: "other.bundle", signedTransactionInfo: fakeJws({transactionId: "1234567890"}) }
  })), null);
  assert.equal(readAppleRefundHint("bad"), null);
});
test("Google Play voided purchase validation and no accidental partial revocation", () => {
  const data = {
    orderId: "GPA.1234-5678-9999-55555",
    purchaseToken: "purchase-secret-token",
    voidedTimeMillis: "1783000000000", voidedReason: 7,
  };
  assert.deepEqual(normalizeGoogleVoidedPurchase(data), {
    orderId: data.orderId, tokenHash: sha256(data.purchaseToken),
    voidedAtMs: 1783000000000, reason: 7,
  });
  assert.equal(normalizeGoogleVoidedPurchase({...data, voidedQuantity: 1}), null);
  assert.equal(normalizeGoogleVoidedPurchase({...data, orderId: ""}).orderId, "");
  assert.equal(normalizeGoogleVoidedPurchase({...data, purchaseToken: ""}), null);
  assert.equal(normalizeGoogleVoidedPurchase({...data, voidedTimeMillis: "NaN"}), null);
});
test("Google API URL carries continuation tokens without exposing user secrets", () => {
  const first = new URL(googleVoidedUrl({ startMs: 1783000000000 }));
  assert.equal(first.searchParams.get("type"), "0");
  assert.equal(first.searchParams.get("startTime"), "1783000000000");
  const next = new URL(googleVoidedUrl({ startMs: 1783000000000, pageToken: "ABC/=" }));
  assert.equal(next.searchParams.get("pageSelection.token"), "ABC/=");
  assert.equal(next.searchParams.has("startTime"), false);
  assert.throws(() => googleVoidedUrl({ startMs: 10, packageName: "malicious" }));
});
test("Legacy purchases only revoke with exact proof or purchase timestamp", () => {
  const oldEvent = { platform: "android", productId: "candar.boost.pro.30d", isPremium: false, purchaseAt: new Date(1780000000000) };
  const last = { lastPurchasePlatform: "android", lastPurchaseProductId: oldEvent.productId, lastPurchaseProofHash: "token-hash",
    lastPurchaseAt: new Date(1780000000000) };
  assert.equal(revokeUserFields({ user: last, eventId: "old", event: oldEvent, voidedTokenHash: "token-hash" }).currentMultiplier, 1);
  assert.equal(revokeUserFields({ user: { ...last, lastPurchaseAt: new Date(1780000010000), lastPurchaseProofHash: "another" },
    eventId: "old", event: oldEvent, voidedTokenHash: "token-hash" }), null);
  assert.equal(revokeUserFields({ user: { ...last, lastPurchasePlatform: "ios" }, eventId: "old",
    event: oldEvent, voidedTokenHash: "token-hash" }), null);
});

test("Refund only disables its exact still-current entitlement", () => {
  assert.equal(revokeUserFields({
    user: { lastBoostPurchaseEventId: "newer" }, eventId: "older", event: { isPremium: false }
  }), null);
  const boost = revokeUserFields({
    user: {lastBoostPurchaseEventId: "event-a", mining: { other: 10 }},
    eventId: "event-a", event: { isPremium: false }, nowMs: 1780000000000,
  });
  assert.equal(boost.currentMultiplier, 1);
  assert.equal(boost.mining.other, 10);
  assert.equal(boost.lastBoostPurchaseEventId, "");
  const premium = revokeUserFields({
    user: { lastPremiumPurchaseEventId: "event-premium" },
    eventId: "event-premium", event: { isPremium: true }, nowMs: 1780000000000,
  });
  assert.equal(premium.isPremium, false);
  assert.equal(premium.premium.is_active, false);
  assert.equal(premium.lastPremiumPurchaseEventId, "");
});
