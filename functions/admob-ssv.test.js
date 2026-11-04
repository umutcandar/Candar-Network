"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { verifyCallback, AdmobVerificationError } = require("./admob-ssv");

const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const keys = new Map([["1234", publicKey.export({ type: "spki", format: "pem" })]]);
const now = 1762250000000;
function signedUrl(data) {
  const sig = crypto.sign("sha256", Buffer.from(data), privateKey).toString("base64url");
  return "/admob_ssv?" + data + "&signature=" + sig + "&key_id=1234";
}
const data = [
  "ad_unit=4038775406",
  "custom_data=1762249000",
  "reward_amount=1",
  "reward_item=boost",
  "timestamp=" + now,
  "transaction_id=0123456789abcdef0123",
  "user_id=abc_USER-123",
].join("&");

test("valid Google-style ECDSA callback and metadata", () => {
  const value = verifyCallback(signedUrl(data), keys, now);
  assert.equal(value.uid, "abc_USER-123");
  assert.equal(value.attemptAt, 1762249000);
  assert.equal(value.adUnit, "4038775406");
});
test("rejects changes after signing", () => {
  assert.throws(() => verifyCallback(signedUrl(data).replace("boost", "coins"), keys, now), AdmobVerificationError);
});
test("rejects unexpected ad units even with a valid signature", () => {
  assert.throws(() => verifyCallback(signedUrl(data.replace("4038775406", "9999")), keys, now), AdmobVerificationError);
});
test("rejects expired callbacks and unsigned requests", () => {
  assert.throws(() => verifyCallback(signedUrl(data), keys, now + 31 * 60 * 1000), AdmobVerificationError);
  assert.throws(() => verifyCallback("/admob_ssv?" + data, keys, now), AdmobVerificationError);
});
