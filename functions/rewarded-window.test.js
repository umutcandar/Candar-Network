"use strict";

const assert = require("assert");
const {
  DEFAULT_WINDOW_SECONDS,
  getActiveRewardedAttemptTimes,
  getRewardedBoostState,
  getRewardedAttemptLimitState,
  resolveRewardedAttemptForApply,
} = require("./rewarded-window");

const base = 1_800_000_000;
const hour = 60 * 60;

const twoRecent = getActiveRewardedAttemptTimes({
  nowSec: base + 2 * hour,
  firstAt: base,
  secondAt: base + hour,
});
assert.deepStrictEqual(twoRecent, [base, base + hour]);
assert.deepStrictEqual(
  getRewardedAttemptLimitState({
    attemptTimes: twoRecent,
    nowSec: base + 2 * hour,
  }),
  {
    blocked: true,
    attemptCount: 2,
    remainingSeconds: 22 * hour,
  }
);

const firstExpired = getActiveRewardedAttemptTimes({
  nowSec: base + DEFAULT_WINDOW_SECONDS + 1,
  firstAt: base,
  secondAt: base + hour,
});
assert.deepStrictEqual(firstExpired, [base + hour]);
assert.strictEqual(
  getRewardedAttemptLimitState({
    attemptTimes: firstExpired,
    nowSec: base + DEFAULT_WINDOW_SECONDS + 1,
  }).blocked,
  false
);

const legacyMigrated = getActiveRewardedAttemptTimes({
  nowSec: base + 3 * hour,
  legacyAttemptCount: 2,
  legacyLastAttemptAt: base + 2 * hour,
});
assert.deepStrictEqual(legacyMigrated, [base + 2 * hour, base + 2 * hour]);

const fullyExpired = getActiveRewardedAttemptTimes({
  nowSec: base + 2 * DEFAULT_WINDOW_SECONDS,
  firstAt: base,
  secondAt: base + hour,
});
assert.deepStrictEqual(fullyExpired, []);

assert.deepStrictEqual(
  getRewardedBoostState({
    nowSec: base + 6 * hour,
    storedMultiplier: 2.785966,
    lastRewardAt: base,
  }),
  {
    active: true,
    multiplier: 2.785966,
    remainingSeconds: 0,
  }
);

assert.deepStrictEqual(
  getRewardedBoostState({
    nowSec: base + DEFAULT_WINDOW_SECONDS,
    storedMultiplier: 2.785966,
    lastRewardAt: base,
  }),
  {
    active: true,
    multiplier: 2.785966,
    remainingSeconds: 0,
  }
);

assert.deepStrictEqual(
  getRewardedBoostState({
    nowSec: base,
    storedMultiplier: 2.785966,
    lastRewardAt: 0,
  }),
  {
    active: true,
    multiplier: 2.785966,
    remainingSeconds: 0,
  }
);

assert.deepStrictEqual(
  getRewardedBoostState({
    nowSec: base,
    storedMultiplier: 99,
    lastRewardAt: 0,
  }),
  {
    active: true,
    multiplier: 10,
    remainingSeconds: 0,
  }
);

assert.deepStrictEqual(
  resolveRewardedAttemptForApply({
    attemptTimes: [base, base + hour],
    requestedAttemptAt: base + hour,
    lastAppliedAttemptAt: 0,
  }),
  {
    valid: true,
    idempotent: false,
    attemptAt: base + hour,
  }
);

assert.deepStrictEqual(
  resolveRewardedAttemptForApply({
    attemptTimes: [base, base + hour],
    requestedAttemptAt: base + hour,
    lastAppliedAttemptAt: base + hour,
  }),
  {
    valid: true,
    idempotent: true,
    attemptAt: base + hour,
  }
);

assert.deepStrictEqual(
  resolveRewardedAttemptForApply({
    attemptTimes: [base, base + hour],
    requestedAttemptAt: base + 2 * hour,
    lastAppliedAttemptAt: 0,
  }),
  {
    valid: false,
    idempotent: false,
    attemptAt: base + 2 * hour,
  }
);

console.log("Rewarded permanent multiplier and 24-hour attempt tests passed.");
