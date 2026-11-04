"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const crypto = require("node:crypto");
const fs = require("node:fs");
const vm = require("node:vm");
const { createRequire } = require("node:module");
const path = require("node:path");

const absolute = path.join(__dirname, "index.js");
const nativeRequire = createRequire(absolute);
const sha = (value) => crypto.createHash("sha256").update(value).digest("hex");
const deleted = Symbol("deleted");
const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const privatePem = privateKey.export({ type: "pkcs8", format: "pem" });

class Timestamp {
  constructor(ms) { this.ms = ms; }
  static fromMillis(ms) { return new Timestamp(ms); }
  static fromDate(date) { return new Timestamp(date.getTime()); }
  toDate() { return new Date(this.ms); }
  toMillis() { return this.ms; }
}

class Ref {
  constructor(db, collection, id) {
    this.db = db;
    this.collectionId = collection;
    this.id = id;
    this.path = collection + "/" + id;
  }
  async get() {
    const data = this.db.rows.get(this.path);
    return { exists: data !== undefined, id: this.id, ref: this,
      data: () => data };
  }
  async set(patch, options) {
    this.db.put(this, patch, options);
  }
}

class Query {
  constructor(db, collection) {
    this.db = db;
    this.collectionId = collection;
    this.filters = [];
    this.cap = Infinity;
  }
  where(field, comparator, value) {
    assert.equal(comparator, "==");
    this.filters.push([field, value]);
    return this;
  }
  limit(count) { this.cap = count; return this; }
  async get() {
    const refs = [...this.db.rows.entries()]
      .filter(([name, row]) => name.startsWith(this.collectionId + "/")
        && this.filters.every(([key, value]) => row[key] === value))
      .slice(0, this.cap)
      .map(([name]) => new Ref(this.db, this.collectionId, name.split("/").at(-1)));
    return { docs: await Promise.all(refs.map(ref => ref.get())), empty: refs.length === 0 };
  }
}

class MemoryFirestore {
  constructor() { this.rows = new Map(); }
  collection(name) {
    return {
      doc: (id) => new Ref(this, name, id),
      where: (field, op, value) => new Query(this, name).where(field, op, value),
    };
  }
  put(ref, patch, options = {}) {
    const old = this.rows.get(ref.path) || {};
    const next = options.merge ? { ...old, ...patch } : { ...patch };
    for (const [key, value] of Object.entries(next)) {
      if (value === deleted) delete next[key];
    }
    this.rows.set(ref.path, next);
  }
  async runTransaction(callback) {
    let writesStarted = false;
    const writes = [];
    const tx = {
      get: async (ref) => {
        if (writesStarted) throw new Error("Firestore read after write");
        return ref.get();
      },
      set: (ref, patch, options = {}) => {
        writesStarted = true;
        writes.push(() => this.put(ref, patch, options));
      },
      update: (ref, patch) => {
        writesStarted = true;
        writes.push(() => this.put(ref, patch, { merge: true }));
      },
      create: (ref, patch) => {
        writesStarted = true;
        writes.push(() => {
          if (this.rows.has(ref.path)) throw new Error("Duplicate create");
          this.put(ref, patch);
        });
      },
      delete: (ref) => {
        writesStarted = true;
        writes.push(() => this.rows.delete(ref.path));
      },
    };
    const result = await callback(tx);
    for (const write of writes) write();
    return result;
  }
}

function fakeJws(value) {
  return "e30." + Buffer.from(JSON.stringify(value)).toString("base64url") + ".c2ln";
}

function makeHarness() {
  const db = new MemoryFirestore();
  const tokenOrders = new Map();
  let voided = [];
  let appleRevoked = false;
  const storeRequest = async ({url}) => {
    if (url.includes("/purchases/products/")) {
      const token = decodeURIComponent(url.split("/tokens/")[1]);
      const orderId = tokenOrders.get(token);
      return {data: {purchaseState: 0, purchaseTimeMillis: String(Date.now()-60000), orderId}};
    }
    if (url.includes("/purchases/voidedpurchases")) {
      return {data: {voidedPurchases: voided}};
    }
    throw new Error("Unexpected Google request");
  };
  const secrets = {
    APPLE_ISSUER_ID: "test",
    APPLE_KEY_ID: "testkey",
    APPLE_PRIVATE_KEY: privatePem,
    APPLE_BUNDLE_ID: "com.candarnetwork.app",
  };
  const firebaseFields = {
    serverTimestamp: () => Timestamp.fromMillis(Date.now()),
    delete: () => deleted,
    increment: (x) => ({increment: x}),
  };
  const shim = (name) => {
    if (name === "firebase-functions/v2/https") {
      return {
        onCall: (_options, callback) => callback,
        onRequest: (_options, callback) => callback,
        HttpsError: class HttpsError extends Error {
          constructor(code, message) { super(message); this.code = code; }
        },
      };
    }
    if (name === "firebase-functions/v2/scheduler") {
      return { onSchedule: (_options, callback) => callback };
    }
    if (name === "firebase-functions/params") {
      return { defineSecret: (id) => ({value: () => secrets[id] || "test"}) };
    }
    if (name === "firebase-admin/app") return {initializeApp: () => undefined};
    if (name === "firebase-admin/auth") return {getAuth: () => ({})};
    if (name === "firebase-admin/firestore") {
      return {getFirestore: () => db, FieldValue: firebaseFields, FieldPath: {}, Timestamp};
    }
    if (name === "firebase-admin/messaging") return {getMessaging: () => ({})};
    if (name === "google-auth-library") {
      return {GoogleAuth: class GoogleAuth {
        getClient() { return Promise.resolve({request: storeRequest}); }
      }};
    }
    return nativeRequire(name);
  };
  const mod = {exports: {}};
  const source = fs.readFileSync(absolute, "utf8") + `
module.exports.__refundTests = {
  applyPurchaseToUser, applyGoogleVoidedPurchase, revokePurchaseEvent,
  scanGoogleVoidedPurchases
};`;
  vm.runInNewContext(source, {
    require: shim, module: mod, exports: mod.exports, console,
    Buffer, URL, URLSearchParams, AbortSignal, fetch: async (url) => {
      if (!String(url).includes("api.storekit.apple.com")
        && !String(url).includes("api.storekit-sandbox.apple.com")) {
        throw new Error("Unexpected Apple API URL");
      }
      return {
        status: 200, ok: true,
        json: async () => ({
          signedTransactionInfo: fakeJws({
            transactionId: "123456789012",
            bundleId: "com.candarnetwork.app",
            productId: "candar.ios.premium.30d",
            revocationDate: appleRevoked ? Date.now()-10000 : null,
          }),
        }),
      };
    },
  }, {filename: absolute});

  const doc = (collection, id) => db.collection(collection).doc(id);
  const row = (collection, id) => db.rows.get(collection+"/"+id);
  return {
    db, doc, row, exported: mod.exports, internal: mod.exports.__refundTests,
    setOrder: (token, orderId) => tokenOrders.set(token, orderId),
    setVoided: (items) => {voided = items;},
    setAppleRevoked: (value) => {appleRevoked = value;},
  };
}

test("Google Play: refund is atomic, removes active boost, cannot be replay-granted", async () => {
  const h = makeHarness();
  h.db.put(h.doc("users", "u1"), {points: 0, lastMiningStart: 0, isPremium: false});
  const orderId = "GPA.1234-5678-9999-55555";
  const token = "google-token-for-order-123";
  h.setOrder(token, orderId);
  const grant = await h.internal.applyPurchaseToUser("u1", {
    platform: "android", productId: "candar.boost.pro.30d", receipt: token,
  }, false);
  assert.equal(grant.ok, true);
  assert.equal(h.row("users", "u1").currentMultiplier, 3);
  const eventId = sha("android|candar.boost.pro.30d|"+orderId);
  assert.equal(h.row("users", "u1").lastBoostPurchaseEventId, eventId);
  const voided = {
    orderId, purchaseToken: token,
    voidedTimeMillis: String(Date.now()-1000),
    voidedReason: 7,
  };
  assert.equal((await h.internal.applyGoogleVoidedPurchase(voided)).status, "revoked_current");
  assert.equal(h.row("users", "u1").currentMultiplier, 1);
  assert.equal(h.row("users", "u1").lastBoostPurchaseEventId, "");
  assert.equal(h.row("purchase_events", eventId).revoked, true);
  assert.equal((await h.internal.applyGoogleVoidedPurchase(voided)).status, "already_revoked");
  await assert.rejects(() => h.internal.applyPurchaseToUser("u1", {
    platform: "android", productId: "candar.boost.pro.30d", receipt: token,
  }, false), (error) => error.code === "failed-precondition");
});

test("Google Play: later product survives older refund; pending tombstone blocks late grant", async () => {
  const h = makeHarness();
  h.db.put(h.doc("users", "u2"), {points: 0, lastMiningStart: 0});
  h.setOrder("token-old", "GPA.older-1234");
  h.setOrder("token-new", "GPA.newer-1234");
  await h.internal.applyPurchaseToUser("u2", {platform: "android",
    productId: "candar.boost.basic.30d", receipt: "token-old"}, false);
  await h.internal.applyPurchaseToUser("u2", {platform: "android",
    productId: "candar.boost.ultra.30d", receipt: "token-new"}, false);
  const newer = h.row("users", "u2").lastBoostPurchaseEventId;
  const oldVoid = {orderId: "GPA.older-1234", purchaseToken: "token-old",
    voidedTimeMillis: String(Date.now()-1000)};
  assert.equal((await h.internal.applyGoogleVoidedPurchase(oldVoid)).status, "revoked_historical");
  assert.equal(h.row("users", "u2").currentMultiplier, 7);
  assert.equal(h.row("users", "u2").lastBoostPurchaseEventId, newer);

  // A cancellation without orderId must still leave a token tombstone.
  assert.equal((await h.internal.applyGoogleVoidedPurchase({
    orderId: "", purchaseToken: "unknown-cancelled-token",
    voidedTimeMillis: String(Date.now()-1000),
  })).status, "tombstoned_unmatched");
  h.setOrder("token-later", "GPA.refund-before-grant");
  const before = {orderId:"GPA.refund-before-grant",purchaseToken:"token-later",
    voidedTimeMillis: String(Date.now()-1000)};
  assert.equal((await h.internal.applyGoogleVoidedPurchase(before)).status, "tombstoned_unmatched");
  await assert.rejects(() => h.internal.applyPurchaseToUser("u2", {platform: "android",
    productId: "candar.boost.basic.30d", receipt:"token-later"}, false),
  (error) => error.code === "failed-precondition");
});

test("Apple: fake notification cannot revoke unless Apple API confirms refund", async () => {
  const h = makeHarness();
  const eventId = sha("ios|candar.premium.30d|123456789012");
  h.db.put(h.doc("purchase_events", eventId), {
    uid: "apple-user", platform: "ios", productId: "candar.premium.30d",
    storeTransactionId: "123456789012", isPremium: true, revoked: false,
  });
  h.db.put(h.doc("users","apple-user"), {
    isPremium: true, lastPremiumPurchaseEventId: eventId,
    premium: {is_active: true},
  });
  const signedPayload = fakeJws({notificationType: "REFUND", data: {
    bundleId: "com.candarnetwork.app",
    signedTransactionInfo: fakeJws({transactionId:"123456789012"}),
  }});
  const req = {method: "POST", body: {signedPayload}};
  const reply = () => ({
    statusCode: 200, status(value) {this.statusCode=value;return this;},
    send(value) {this.body=value;return this;},
  });
  h.setAppleRevoked(false);
  const unverified = reply();
  await h.exported.apple_store_refund_notification(req, unverified);
  assert.equal(unverified.statusCode, 503);
  assert.equal(h.row("users","apple-user").isPremium, true);
  h.setAppleRevoked(true);
  const valid = reply();
  await h.exported.apple_store_refund_notification(req, valid);
  assert.equal(valid.statusCode, 200);
  assert.equal(h.row("users","apple-user").isPremium, false);
  assert.equal(h.row("purchase_events",eventId).revoked, true);
  const duplicate = reply();
  await h.exported.apple_store_refund_notification(req, duplicate);
  assert.equal(duplicate.statusCode, 200);
});

test("Google hourly sweep stores its completion cursor and handles zero results", async () => {
  const h = makeHarness();
  h.setVoided([]);
  const done = await h.internal.scanGoogleVoidedPurchases();
  assert.equal(done.completed, true);
  assert.equal(done.inspected, 0);
  assert.ok(h.row("purchase_refund_scan_state", "google_play").completedAtMs);
});
