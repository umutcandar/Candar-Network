"use strict";

const assert = require("assert");
const {
  getMiningReminderDecision,
  notificationDeliveryKey,
  normalizeLanguage,
} = require("./notifications");

const day = 24 * 60 * 60;
const now = 2_000_000_000;

assert.strictEqual(normalizeLanguage("tr_TR"), "tr");
assert.strictEqual(normalizeLanguage("pt-BR"), "pt");
assert.strictEqual(normalizeLanguage("it-IT"), "en");
assert.strictEqual(
  notificationDeliveryKey({
    type: "daily",
    lastMining: now - day,
    nowSeconds: now,
    readyAfterSeconds: day,
  }),
  `daily:${now - day}:1`
);
assert.strictEqual(
  notificationDeliveryKey({
    type: "first",
    createdAt: now - (30 * 60 * 60),
    nowSeconds: now,
    readyAfterSeconds: day,
  }),
  "first-mining:1"
);
assert.strictEqual(
  notificationDeliveryKey({ force: true, campaignKey: "manual-1" }),
  "campaign:manual-1"
);

assert.deepStrictEqual(
  getMiningReminderDecision({
    nowSeconds: now,
    createdAt: now - (5 * 60 * 60),
    readyAfterSeconds: day,
    firstReminderDelaySeconds: 6 * 60 * 60,
  }),
  { eligible: false, type: "first", reason: "grace_period" }
);

assert.deepStrictEqual(
  getMiningReminderDecision({
    nowSeconds: now,
    createdAt: now - (7 * 60 * 60),
    readyAfterSeconds: day,
    firstReminderDelaySeconds: 6 * 60 * 60,
  }),
  { eligible: true, type: "first", reason: "never_mined" }
);

assert.deepStrictEqual(
  getMiningReminderDecision({
    nowSeconds: now,
    createdAt: now - day,
    neverMinedNotifiedAt: now - 60,
    readyAfterSeconds: day,
    firstReminderDelaySeconds: 6 * 60 * 60,
  }),
  { eligible: false, type: "first", reason: "cooldown" }
);

assert.deepStrictEqual(
  getMiningReminderDecision({
    nowSeconds: now,
    lastMining: now - day,
    scheduledNotifiedFor: now - day,
    lastReminderAt: now - 60,
    readyAfterSeconds: day,
    firstReminderDelaySeconds: 6 * 60 * 60,
  }),
  { eligible: false, type: "daily", reason: "cooldown" }
);

assert.deepStrictEqual(
  getMiningReminderDecision({
    nowSeconds: now,
    lastMining: now - (3 * day),
    scheduledNotifiedFor: now - (3 * day),
    lastReminderAt: now - day,
    readyAfterSeconds: day,
    firstReminderDelaySeconds: 6 * 60 * 60,
  }),
  { eligible: true, type: "daily", reason: "ready" }
);

assert.notStrictEqual(
  notificationDeliveryKey({
    type: "daily",
    lastMining: now - (3 * day),
    nowSeconds: now - day,
    readyAfterSeconds: day,
  }),
  notificationDeliveryKey({
    type: "daily",
    lastMining: now - (3 * day),
    nowSeconds: now,
    readyAfterSeconds: day,
  })
);

console.log("Notification targeting and locale tests passed.");
