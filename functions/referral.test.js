"use strict";

const assert = require("assert");
const {
  DEFAULT_ATTRIBUTION_WINDOW_SECONDS,
  REFERRAL_QUALIFICATION_STREAK,
  REFERRAL_REWARD_POINTS,
  getReferralAttributionDecision,
  getReferralQualificationDecision,
  resolveLegacyReferralState,
  sanitizeReferralCode,
} = require("./referral");

const now = 1_800_000_000_000;

assert.strictEqual(sanitizeReferralCode("  AB-12_34!!  "), "AB-12_34");
assert.strictEqual(sanitizeReferralCode("x".repeat(40)).length, 32);

assert.deepStrictEqual(
  getReferralAttributionDecision({
    referralCode: "INVITE42",
    accountCreatedAtMs: now - 60_000,
    nowMs: now,
  }),
  { canApply: true, resolved: false, reason: "eligible" }
);

assert.deepStrictEqual(
  resolveLegacyReferralState({
    selfUid: "invitee",
    referredBy: "123456",
    resolvedReferrerUid: "inviter",
  }),
  {
    canBackfill: true,
    referrerUid: "inviter",
    rewardStatus: "pending",
    reason: "legacy_resolved",
  }
);

assert.deepStrictEqual(
  resolveLegacyReferralState({
    selfUid: "same-user",
    referredBy: "123456",
    resolvedReferrerUid: "same-user",
  }),
  {
    canBackfill: false,
    referrerUid: "",
    rewardStatus: "",
    reason: "self_referral",
  }
);

// Yeni hesap dışındaki attribution kararı çağrı katmanında engellenir;
// mevcut kullanıcıların sonradan kod bağlamaması temel ürün kuralıdır.
assert.strictEqual(DEFAULT_ATTRIBUTION_WINDOW_SECONDS, 7 * 24 * 60 * 60);

assert.deepStrictEqual(
  getReferralAttributionDecision({
    referralCode: "SELF42",
    ownReferralCode: "SELF42",
    accountCreatedAtMs: now - 60_000,
    nowMs: now,
  }),
  { canApply: false, resolved: true, reason: "self_referral" }
);

assert.deepStrictEqual(
  getReferralAttributionDecision({
    referralCode: "INVITE42",
    existingReferredBy: "OTHER42",
    accountCreatedAtMs: now - 60_000,
    nowMs: now,
  }),
  { canApply: false, resolved: true, reason: "already_applied" }
);

assert.deepStrictEqual(
  getReferralAttributionDecision({
    referralCode: "INVITE42",
    accountCreatedAtMs: now - (DEFAULT_ATTRIBUTION_WINDOW_SECONDS * 1000) - 1,
    nowMs: now,
  }),
  { canApply: false, resolved: true, reason: "attribution_window_expired" }
);

assert.strictEqual(REFERRAL_QUALIFICATION_STREAK, 3);
assert.strictEqual(REFERRAL_REWARD_POINTS, 10);

assert.deepStrictEqual(
  getReferralQualificationDecision({
    dailyStreak: 2,
    referredByUid: "referrer-1",
    rewardStatus: "pending",
  }),
  { qualifies: false, reason: "streak_incomplete" }
);

assert.deepStrictEqual(
  getReferralQualificationDecision({
    dailyStreak: 3,
    referredByUid: "referrer-1",
    rewardStatus: "pending",
  }),
  { qualifies: true, reason: "qualified" }
);

assert.deepStrictEqual(
  getReferralQualificationDecision({
    dailyStreak: 8,
    referredByUid: "referrer-1",
    rewardStatus: "qualified",
  }),
  { qualifies: false, reason: "qualified" }
);

console.log("Referral attribution tests passed.");
