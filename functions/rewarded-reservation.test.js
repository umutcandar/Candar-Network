"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const rewardedWindow = require("./rewarded-window");

// Exercise the real transaction handler without Firebase credentials or writes.
const source = fs.readFileSync(require.resolve("./index.js"), "utf8");
const start = source.indexOf("async function reserveRewardedBoostAttemptForUser(");
const end = source.indexOf("\nfunction sanitizeAnalyticsParams(", start);
assert(start >= 0 && end > start, "reservation handler must be present");

let nowSec = 1_800_000_000;
let user = {};
let writes = 0;
class TestDate extends Date {
  static now() { return nowSec * 1000; }
}
const context = vm.createContext({
  ...rewardedWindow,
  Date: TestDate,
  HttpsError: Error,
  FieldValue: { serverTimestamp: () => "server-time" },
  REWARDED_BOOST_DAILY_LIMIT: 2,
  REWARDED_BOOST_MAX_MULTIPLIER: 10,
  REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS: 86400,
  REWARDED_BOOST_COOLDOWN_SECONDS: 0,
  rewardedBoostDayKey: (now) => Math.floor(now / 86400),
  numberField: (data, key, fallback) => Number(data[key] ?? fallback),
  intField: (data, key, fallback) => Math.trunc(Number(data[key] ?? fallback)),
  db: {
    collection: () => ({ doc: (uid) => ({ uid }) }),
    runTransaction: async (handler) => handler({
      get: async () => ({ exists: true, data: () => ({ ...user }) }),
      set: (_ref, update) => { user = { ...user, ...update }; writes += 1; },
    }),
  },
});
vm.runInContext(source.slice(start, end), context);
const reserve = () => context.reserveRewardedBoostAttemptForUser("test-user");

(async () => {
  const first = await reserve();
  assert.equal(first.ok, true);
  assert.equal(first.attempt_count, 1);
  assert.equal(first.attempts_remaining, 1);

  const retry = await reserve();
  assert.equal(retry.ok, true);
  assert.equal(retry.attempt_at, first.attempt_at);
  assert.equal(retry.attempt_count, 1, "same-second retry must not consume the other ad attempt");
  assert.equal(retry.attempts_remaining, 1);
  assert.equal(retry.idempotent, true);
  assert.equal(writes, 1, "retry must not mutate the reservation ledger");

  nowSec += 60;
  const second = await reserve();
  assert.equal(second.ok, true);
  assert.equal(second.attempt_count, 2);
  assert.equal(second.attempts_remaining, 0);
  assert.notEqual(second.attempt_at, first.attempt_at);
  const secondRetry = await reserve();
  assert.equal(secondRetry.ok, true, "retry of the second reservation must survive the limit check");
  assert.equal(secondRetry.idempotent, true);
  assert.equal(writes, 2);

  nowSec += 1;
  const blocked = await reserve();
  assert.equal(blocked.ok, false);
  assert.equal(blocked.error, "rewarded_boost_daily_attempt_limit");
  assert.equal(writes, 2);
  nowSec = first.attempt_at + 86400;
  const nextDay = await reserve();
  assert.equal(nextDay.ok, true);
  assert.equal(nextDay.attempt_count, 2, "expired slot must become available while the newer one stays active");

  user = {
    rewardedBoostAttemptDay: Math.floor(nowSec / 86400),
    rewardedBoostAttemptCount: 2,
    rewardedBoostAttemptLastAt: nowSec,
  };
  const legacy = await reserve();
  assert.equal(legacy.ok, false, "legacy counters must not be returned as reusable reservation IDs");
  assert.equal(legacy.error, "rewarded_boost_daily_attempt_limit");
  console.log("Rewarded reservation retries and rolling limit tests passed.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
