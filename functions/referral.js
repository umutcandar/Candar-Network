"use strict";

const DEFAULT_ATTRIBUTION_WINDOW_SECONDS = 7 * 24 * 60 * 60;
const REFERRAL_QUALIFICATION_STREAK = 3;
const REFERRAL_REWARD_POINTS = 10;

function sanitizeReferralCode(value) {
  return String(value || "")
    .trim()
    .replace(/[^A-Za-z0-9_-]/g, "")
    .slice(0, 32);
}

function getReferralAttributionDecision({
  referralCode,
  ownReferralCode = "",
  existingReferredBy = "",
  referralBonusApplied = false,
  accountCreatedAtMs = 0,
  nowMs = Date.now(),
  windowSeconds = DEFAULT_ATTRIBUTION_WINDOW_SECONDS,
}) {
  const code = sanitizeReferralCode(referralCode);
  if (!code) {
    return { canApply: false, resolved: false, reason: "missing_code" };
  }
  if (existingReferredBy || referralBonusApplied) {
    return { canApply: false, resolved: true, reason: "already_applied" };
  }
  if (ownReferralCode && ownReferralCode === code) {
    return { canApply: false, resolved: true, reason: "self_referral" };
  }

  const createdAt = Number(accountCreatedAtMs) || 0;
  const now = Number(nowMs) || 0;
  const ageMs = now - createdAt;
  if (createdAt <= 0 || ageMs < 0 || ageMs > windowSeconds * 1000) {
    return { canApply: false, resolved: true, reason: "attribution_window_expired" };
  }

  return { canApply: true, resolved: false, reason: "eligible" };
}

function getReferralQualificationDecision({
  dailyStreak = 0,
  referredByUid = "",
  rewardStatus = "",
}) {
  const normalizedStatus = String(rewardStatus || "").trim().toLowerCase();
  if (normalizedStatus !== "pending") {
    return { qualifies: false, reason: normalizedStatus || "not_pending" };
  }
  if (!String(referredByUid || "").trim()) {
    return { qualifies: false, reason: "missing_referrer" };
  }
  if (Math.max(0, Math.trunc(Number(dailyStreak) || 0)) < REFERRAL_QUALIFICATION_STREAK) {
    return { qualifies: false, reason: "streak_incomplete" };
  }
  return { qualifies: true, reason: "qualified" };
}

function resolveLegacyReferralState({
  selfUid = "",
  referredBy = "",
  referredByUid = "",
  rewardStatus = "",
  resolvedReferrerUid = "",
}) {
  const code = sanitizeReferralCode(referredBy);
  const existingUid = String(referredByUid || "").trim();
  const resolvedUid = String(resolvedReferrerUid || "").trim();
  const uid = existingUid || resolvedUid;
  const status = String(rewardStatus || "").trim().toLowerCase();

  if (!code) return { canBackfill: false, referrerUid: existingUid, rewardStatus: status, reason: "missing_code" };
  if (!uid) return { canBackfill: false, referrerUid: "", rewardStatus: status, reason: "referrer_not_found" };
  if (uid === String(selfUid || "").trim()) {
    return { canBackfill: false, referrerUid: "", rewardStatus: status, reason: "self_referral" };
  }
  if (status && status !== "pending") {
    return { canBackfill: false, referrerUid: uid, rewardStatus: status, reason: "already_resolved" };
  }
  return {
    canBackfill: !existingUid || !status,
    referrerUid: uid,
    rewardStatus: status || "pending",
    reason: existingUid && status ? "current" : "legacy_resolved",
  };
}

module.exports = {
  DEFAULT_ATTRIBUTION_WINDOW_SECONDS,
  REFERRAL_QUALIFICATION_STREAK,
  REFERRAL_REWARD_POINTS,
  getReferralAttributionDecision,
  getReferralQualificationDecision,
  resolveLegacyReferralState,
  sanitizeReferralCode,
};
