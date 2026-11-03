"use strict";

const assert = require("node:assert/strict");
const { calculateStreakProgress } = require("./retention");
const {
  getPointReward,
  extendExpiryMs,
  activePointBoost,
} = require("./ecosystem");

const today = 100;

assert.deepEqual(
  calculateStreakProgress({
    previousRewardDay: today - 1,
    today,
    currentStreak: 6,
    currentShieldCount: 0,
  }),
  {
    dailyStreak: 7,
    streakShieldCount: 1,
    streakShieldUsed: false,
    streakShieldEarned: true,
  }
);

assert.equal(getPointReward("ad_free_24h").cost, 25);
assert.equal(getPointReward("unknown"), null);
assert.equal(extendExpiryMs(2_000, 1_000, 1), 3_000);
assert.equal(extendExpiryMs(500, 1_000, 1), 2_000);
assert.equal(
  activePointBoost(
    {
      pointsBoostMultiplier: 1.25,
      pointsBoostUntil: new Date(Date.now() + 60_000),
    },
    new Date()
  ),
  1.25
);
assert.equal(
  activePointBoost(
    {
      pointsBoostMultiplier: 1.25,
      pointsBoostUntil: new Date(Date.now() - 60_000),
    },
    new Date()
  ),
  1
);

assert.deepEqual(
  calculateStreakProgress({
    previousRewardDay: today - 2,
    today,
    currentStreak: 7,
    currentShieldCount: 1,
  }),
  {
    dailyStreak: 8,
    streakShieldCount: 0,
    streakShieldUsed: true,
    streakShieldEarned: false,
  }
);

assert.deepEqual(
  calculateStreakProgress({
    previousRewardDay: today - 3,
    today,
    currentStreak: 20,
    currentShieldCount: 1,
  }),
  {
    dailyStreak: 1,
    streakShieldCount: 1,
    streakShieldUsed: false,
    streakShieldEarned: false,
  }
);

assert.deepEqual(
  calculateStreakProgress({
    previousRewardDay: today - 1,
    today,
    currentStreak: 13,
    currentShieldCount: 0,
  }),
  {
    dailyStreak: 14,
    streakShieldCount: 1,
    streakShieldUsed: false,
    streakShieldEarned: true,
  }
);

console.log("Retention tests passed.");
