"use strict";

function normalizeLanguage(lang) {
  const code = String(lang || "en").toLowerCase().split(/[-_]/)[0];
  return ["tr", "de", "fr", "es", "pt", "ru", "zh", "ja", "ko", "ar", "hi"].includes(code)
    ? code
    : "en";
}

function getMiningReminderDecision({
  nowSeconds,
  lastMining = 0,
  createdAt = 0,
  readyAfterSeconds,
  firstReminderDelaySeconds,
  scheduledNotifiedFor = 0,
  lastReminderAt = 0,
  neverMinedNotifiedAt = 0,
}) {
  const now = Math.trunc(Number(nowSeconds) || 0);
  const last = Math.trunc(Number(lastMining) || 0);
  const created = Math.trunc(Number(createdAt) || 0);
  const readyAfter = Math.max(1, Math.trunc(Number(readyAfterSeconds) || 0));

  if (last > 0) {
    if (now - last < readyAfter) return { eligible: false, type: "daily", reason: "not_ready" };
    const sentAt = Math.trunc(Number(lastReminderAt) || 0);
    // Eski kayıtlarda yalnızca hangi kazım için bildirim gönderildiği tutuluyordu.
    // Bu kayıtları ilk 48 saat dolmadan yeniden dürtmemek için ilk uygun zamanı
    // lastMining + 24 saat olarak kabul et; sonraki bildirimler gerçek gönderim
    // zamanından itibaren 24 saatlik aralıkla devam eder.
    const legacySentAt = Math.trunc(Number(scheduledNotifiedFor) || 0) === last
      ? last + readyAfter
      : 0;
    const effectiveSentAt = sentAt > 0 ? sentAt : legacySentAt;
    if (effectiveSentAt > 0 && now - effectiveSentAt < readyAfter) {
      return { eligible: false, type: "daily", reason: "cooldown" };
    }
    return { eligible: true, type: "daily", reason: "ready" };
  }

  if (created <= 0 || now - created < Math.max(0, Number(firstReminderDelaySeconds) || 0)) {
    return { eligible: false, type: "first", reason: "grace_period" };
  }
  const notifiedAt = Math.trunc(Number(neverMinedNotifiedAt) || 0);
  if (notifiedAt > 0 && now - notifiedAt < readyAfter) {
    return { eligible: false, type: "first", reason: "cooldown" };
  }
  return { eligible: true, type: "first", reason: "never_mined" };
}

function notificationDeliveryKey({
  force = false,
  campaignKey = "",
  type = "daily",
  lastMining = 0,
  createdAt = 0,
  nowSeconds = 0,
  readyAfterSeconds = 24 * 60 * 60,
}) {
  if (force) return `campaign:${String(campaignKey || "manual").slice(0, 64)}`;
  const interval = Math.max(1, Math.trunc(Number(readyAfterSeconds) || 0));
  const now = Math.max(0, Math.trunc(Number(nowSeconds) || 0));
  if (type === "first") {
    const created = Math.max(0, Math.trunc(Number(createdAt) || 0));
    const slot = Math.max(0, Math.floor((now - created) / interval));
    return `first-mining:${slot}`;
  }
  const last = Math.max(0, Math.trunc(Number(lastMining) || 0));
  const slot = Math.max(1, Math.floor((now - last) / interval));
  return `daily:${last}:${slot}`;
}

module.exports = {
  getMiningReminderDecision,
  notificationDeliveryKey,
  normalizeLanguage,
};
