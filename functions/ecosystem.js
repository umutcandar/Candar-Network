"use strict";

const POINT_REWARDS = Object.freeze({
  ad_free_24h: Object.freeze({
    id: "ad_free_24h",
    cost: 25,
    type: "timed",
    durationSeconds: 24 * 60 * 60,
  }),
  boost_24h: Object.freeze({
    id: "boost_24h",
    cost: 40,
    type: "timed",
    durationSeconds: 24 * 60 * 60,
    multiplier: 1.25,
  }),
  profile_gold: Object.freeze({
    id: "profile_gold",
    cost: 75,
    type: "permanent",
  }),
  ai_5: Object.freeze({
    id: "ai_5",
    cost: 30,
    type: "consumable",
    amount: 5,
  }),
});

function getPointReward(rewardId) {
  return POINT_REWARDS[String(rewardId || "")] || null;
}

function extendExpiryMs(currentExpiryMs, nowMs, durationSeconds) {
  const safeNow = Math.max(0, Number(nowMs) || 0);
  const parsedCurrent = Number(currentExpiryMs);
  const base =
    Number.isFinite(parsedCurrent) && parsedCurrent > safeNow
      ? parsedCurrent
      : safeNow;
  return base + Math.max(0, Number(durationSeconds) || 0) * 1000;
}

function activePointBoost(data, now = new Date()) {
  const multiplier = Number(data?.pointsBoostMultiplier || 1);
  const rawExpiry = data?.pointsBoostUntil;
  let expiry = null;
  if (rawExpiry instanceof Date) expiry = rawExpiry;
  else if (rawExpiry && typeof rawExpiry.toDate === "function") expiry = rawExpiry.toDate();
  else if (typeof rawExpiry === "string") expiry = new Date(rawExpiry);
  else if (rawExpiry && typeof rawExpiry._seconds === "number") {
    expiry = new Date(rawExpiry._seconds * 1000);
  }
  if (!expiry || Number.isNaN(expiry.getTime()) || expiry <= now) return 1;
  return Number.isFinite(multiplier) ? Math.max(1, multiplier) : 1;
}

module.exports = {
  POINT_REWARDS,
  getPointReward,
  extendExpiryMs,
  activePointBoost,
};
