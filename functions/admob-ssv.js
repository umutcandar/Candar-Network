"use strict";
const crypto = require("node:crypto");

const KEY_ENDPOINT = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const CACHE_MS = 6 * 60 * 60 * 1000;
const MAX_AGE_MS = 30 * 60 * 1000;
const MAX_FUTURE_MS = 5 * 60 * 1000;
const ALLOWED_REWARDED_UNITS = new Set(["4038775406", "9932720942"]);
let cachedKeys = null;
let cachedUntil = 0;

class AdmobVerificationError extends Error {
  constructor(message) { super(message); this.name = "AdmobVerificationError"; }
}

async function fetchVerifyingKeys(fetchImpl = fetch, now = Date.now()) {
  if (cachedKeys && now < cachedUntil) return cachedKeys;
  const res = await fetchImpl(KEY_ENDPOINT, { signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error("Unable to refresh AdMob verifier keys");
  const body = await res.json();
  if (!Array.isArray(body.keys) || body.keys.length === 0) {
    throw new Error("AdMob verifier keys unavailable");
  }
  const keys = new Map();
  for (const entry of body.keys) {
    if (/^\d+$/.test(String(entry.keyId)) && typeof entry.pem === "string") {
      keys.set(String(entry.keyId), entry.pem);
    }
  }
  if (keys.size === 0) throw new Error("No trusted AdMob public keys");
  cachedKeys = keys;
  cachedUntil = now + CACHE_MS;
  return keys;
}

function verifyCallback(rawUrl, publicKeys, nowMs = Date.now()) {
  // Preserve the exact encoded callback payload: Google signs everything
  // preceding the last two fields (signature and key_id).
  const query = String(rawUrl || "").split("?")[1] || "";
  const match = query.match(/^(.+)&signature=([^&]+)&key_id=(\d+)$/);
  if (!match) throw new AdmobVerificationError("Invalid signed query layout");
  const key = publicKeys.get(match[3]);
  if (!key) throw new AdmobVerificationError("Unrecognized signature key");
  const signature = Buffer.from(decodeURIComponent(match[2]), "base64url");
  if (!signature.length || !crypto.verify(
    "sha256", Buffer.from(match[1], "utf8"), key, signature
  )) throw new AdmobVerificationError("Invalid AdMob signature");

  const params = new URLSearchParams(match[1]);
  const transactionId = String(params.get("transaction_id") || "");
  const uid = String(params.get("user_id") || "");
  const rawAttempt = String(params.get("custom_data") || "");
  const attemptAt = Number(rawAttempt);
  const unit = String(params.get("ad_unit") || "").split("/").pop();
  const rawTimestamp = Number(params.get("timestamp"));
  const timestampMs = rawTimestamp > 1e15 ? Math.floor(rawTimestamp / 1000) : rawTimestamp;

  if (!/^[A-Za-z0-9_-]{10,128}$/.test(transactionId) ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      !/^\d{9,12}$/.test(rawAttempt) ||
      !Number.isSafeInteger(attemptAt) ||
      !ALLOWED_REWARDED_UNITS.has(unit) ||
      !Number.isSafeInteger(timestampMs) ||
      nowMs - timestampMs > MAX_AGE_MS ||
      timestampMs - nowMs > MAX_FUTURE_MS) {
    throw new AdmobVerificationError("Invalid AdMob reward metadata");
  }
  return { uid, attemptAt, transactionId, adUnit: unit, timestampMs };
}

module.exports = { fetchVerifyingKeys, verifyCallback, AdmobVerificationError };
