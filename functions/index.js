const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, FieldPath, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { GoogleAuth } = require("google-auth-library");
const crypto = require("crypto");
const { calculateStreakProgress } = require("./retention");
const {
  POINT_REWARDS,
  getPointReward,
  extendExpiryMs,
  activePointBoost,
} = require("./ecosystem");
const {
  getActiveRewardedAttemptTimes,
  getRewardedBoostState,
  getRewardedAttemptLimitState,
  resolveRewardedAttemptForApply,
} = require("./rewarded-window");
const {
  REFERRAL_REWARD_POINTS,
  getReferralAttributionDecision,
  getReferralQualificationDecision,
  resolveLegacyReferralState,
  sanitizeReferralCode,
} = require("./referral");
const {
  getMiningReminderDecision,
  notificationDeliveryKey,
  normalizeLanguage: normalizeLang,
} = require("./notifications");

initializeApp();

const db = getFirestore();
const candarAiConfig = defineSecret("CANDAR_AI_CONFIG");
const { generateAnswer } = require("./candar-ai");
const { normalizeMiningRate } = require("./admin-config");
const { fetchVerifyingKeys, verifyCallback, AdmobVerificationError } = require("./admob-ssv");
const { TEAM_CAPACITY, normalizeTeamName, normalizeTeamCode, addMember, removeMember } = require("./team-domain");
const appleIssuerId = defineSecret("APPLE_ISSUER_ID");
const appleKeyId = defineSecret("APPLE_KEY_ID");
const applePrivateKey = defineSecret("APPLE_PRIVATE_KEY");
const appleBundleId = defineSecret("APPLE_BUNDLE_ID");
const ga4ApiSecret = defineSecret("GA4_API_SECRET");

const FREE_DAILY_LIMIT = 5;
const PREMIUM_DAILY_LIMIT = 100;
const DAILY_REWARD_SECONDS = 24 * 60 * 60;
const NEVER_MINED_REMINDER_DELAY_SECONDS = 6 * 60 * 60;
const MAX_NOTIFICATION_BATCH = 400;
const PURCHASE_DURATION_DAYS = 30;
const REWARDED_BOOST_PERCENTAGE = 0.05;
const REWARDED_BOOST_DAILY_LIMIT = 2;
const REWARDED_BOOST_COOLDOWN_SECONDS = 0;
const REWARDED_BOOST_MAX_MULTIPLIER = 10.0;
const REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS = 24 * 60 * 60;
const ACHIEVEMENT_DEFINITIONS = [
  { id: "first_mining", name: "ach_first_mining", xp: 10, test: (data) => intField(data, "lastMiningStart", 0) > 0 },
  { id: "100_points", name: "ach_100_points", xp: 20, test: (data) => numberField(data, "points", 0) >= 100 },
  { id: "1000_points", name: "ach_1000_points", xp: 50, test: (data) => numberField(data, "points", 0) >= 1000 },
  { id: "10000_points", name: "ach_10000_points", xp: 100, test: (data) => numberField(data, "points", 0) >= 10000 },
  { id: "first_referral", name: "ach_first_referral", xp: 30, test: (data) => intField(data, "referralCount", 0) >= 1 },
  { id: "10_referrals", name: "ach_10_referrals", xp: 100, test: (data) => intField(data, "referralCount", 0) >= 10 },
  { id: "7_day_streak", name: "ach_7_day_streak", xp: 50, test: (data) => intField(data, "dailyStreak", 0) >= 7 },
  { id: "30_day_streak", name: "ach_30_day_streak", xp: 200, test: (data) => intField(data, "dailyStreak", 0) >= 30 },
  { id: "premium_member", name: "ach_premium_member", xp: 150, test: (data) => isPremiumUser(data) },
];
const OWNER_EMAIL_HASHES = new Set([
  "2d01b5f016fddbb0ec5131fc8771d6b81f425f1d1dc8805020d4c5d59e791751",
  "34d4392ae7769c7f9fda45f9ac816dbc0f31de9cd42fcfa6837a04f897403b19",
]);
const BOOST_PRODUCT_MULTIPLIERS = {
  "candar.boost.basic.30d": 2,
  "candar.boost.pro.30d": 3,
  "candar.boost.ultra.30d": 7,
  "candar.ios.boost.basic.30d": 2,
  "candar.ios.boost.pro.30d": 3,
  "candar.ios.boost.ultra.30d": 7,
};
const STORE_PRODUCT_ALIASES = {
  "candar.ios.boost.basic.30d": "candar.boost.basic.30d",
  "candar.ios.boost.pro.30d": "candar.boost.pro.30d",
  "candar.ios.boost.ultra.30d": "candar.boost.ultra.30d",
  "candar.ios.premium.30d": "candar.premium.30d",
  "candar.boost.basic.v2.30d": "candar.boost.basic.30d",
  "candar.boost.pro.v2.30d": "candar.boost.pro.30d",
  "candar.boost.ultra.v2.30d": "candar.boost.ultra.30d",
  "candar.premium.v2.30d": "candar.premium.30d",
};
const PREMIUM_PRODUCTS = new Set(["candar.premium.30d", "candar.ios.premium.30d"]);
const APP_BUNDLE_ID = "com.candarnetwork.app";
const GA4_MEASUREMENT_ID = "G-RE5P7SX0TL";
const APPLE_VERIFY_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_VERIFY_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";
const ANALYTICS_EVENT_NAMES = new Set([
  "first_open",
  "app_first_open",
  "signup_start",
  "signup_complete",
  "signup_error",
  "login_google_tap",
  "login_apple_tap",
  "login_complete",
  "app_screen_view",
  "daily_reward_tap",
  "earn_virtual_currency",
  "daily_reward_ad_result",
  "ad_sdk_init_requested",
  "ad_load_requested",
  "ad_load_succeeded",
  "ad_load_failed",
  "ad_show_failed",
  "ad_impression_confirmed",
  "daily_reward_error",
  "begin_checkout",
  "purchase_flow_ok",
  "purchase_flow_error",
  "chat_send",
  "chat_answer",
  "chat_error",
  "chat_back",
  "share_referral_tap",
  "referral_code_copied",
  "referral_share_opened",
  "referral_link_copied",
  "open_leaderboard",
  "open_chat",
  "open_market",
  "open_profile",
  "open_referrals",
  "profile_back",
  "market_back",
  "growth_first_session_modal",
  "activation_goal_selected",
  "activation_first_task_complete",
  "referral_reward_qualified",
  "rewarded_boost_tap",
  "rewarded_boost_applied",
  "rewarded_boost_apply_failed",
  "rewarded_boost_ad_not_completed",
  "rewarded_boost_ad_not_ready",
  "rewarded_boost_blocked_before_ad",
  "app_engagement_sync",
  "day_1_return",
  "day_7_return",
  "store_review_prompt_request",
  "streak_shield_used",
  "streak_shield_earned",
  "achievements_open",
  "ecosystem_open",
  "daily_mission_complete",
  "point_center_open",
  "point_reward_redeemed",
  "community_roles_open",
  "roadmap_open",
]);
const googlePlayAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});

function parseExpiry(value) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "object" && typeof value._seconds === "number") {
    return new Date(value._seconds * 1000);
  }
  return null;
}

function isPremiumUser(data) {
  if (!data || typeof data !== "object") return false;

  if (data.isPremium === true) {
    const expires = parseExpiry(data.premiumExpiresAt);
    return !expires || expires > new Date();
  }

  const premium = data.premium;
  if (premium && typeof premium === "object" && premium.is_active === true) {
    const expires = parseExpiry(premium.expires_at || data.premiumExpiresAt);
    return !expires || expires > new Date();
  }

  return false;
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function rewardedBoostDayKey(nowSec = Math.floor(Date.now() / 1000)) {
  return Math.floor(nowSec / 86400);
}

function numberField(data, key, fallback = 0) {
  const value = data?.[key];
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "" && Number.isFinite(Number(value))) {
    return Number(value);
  }
  return fallback;
}

function intField(data, key, fallback = 0) {
  const value = data?.[key];
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string" && value.trim() !== "" && Number.isFinite(Number(value))) {
    return Math.trunc(Number(value));
  }
  if (value instanceof Timestamp) return Math.trunc(value.toMillis() / 1000);
  return fallback;
}

function nestedNumber(data, path, fallback = 0) {
  let cursor = data;
  for (const part of path) {
    if (!cursor || typeof cursor !== "object") return fallback;
    cursor = cursor[part];
  }
  return typeof cursor === "number" && Number.isFinite(cursor) ? cursor : fallback;
}

function isBoostActive(data, now) {
  const expires = parseExpiry(data?.boostExpiresAt || data?.mining?.boost_expires_at);
  return !expires || expires.getTime() > now.getTime();
}

function normalizeProductId(productId) {
  const id = String(productId || "").trim();
  return STORE_PRODUCT_ALIASES[id] || id;
}

function calculateMiningRateComponents(data, nowSec = Math.floor(Date.now() / 1000)) {
  const baseRate =
    numberField(data, "base_rate", 0) ||
    nestedNumber(data, ["mining", "base_rate"], 0) ||
    1.0;

  const accountBoost = Math.max(1.0, numberField(data, "currentMultiplier", 1.0));
  const miningBoost = Math.max(1.0, nestedNumber(data, ["mining", "active_multiplier"], 1.0));
  let boostMultiplier = Math.max(accountBoost, miningBoost);
  if (!isBoostActive(data, new Date())) boostMultiplier = 1.0;
  const pointsBoostMultiplier = activePointBoost(data);

  const refCount = Math.max(0, intField(data, "referralCount", intField(data, "refCount", 0)));
  const refMultiplier = 1.0 + refCount * 0.05;
  const rewardedBoostState = getRewardedBoostState({
    nowSec,
    storedMultiplier: numberField(data, "rewardedBoostMultiplier", 1.0),
    lastRewardAt: intField(
      data,
      "rewardedBoostLastAt",
      intField(data, "lastRewardedBoostAt", 0)
    ),
    windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
    maxMultiplier: REWARDED_BOOST_MAX_MULTIPLIER,
  });
  const rewardedMultiplier = rewardedBoostState.multiplier;
  const streakMultiplier = Math.max(1.0, numberField(data, "streakBonus", 1.0));
  const totalRate = Math.max(
    1.0,
    Number(
      (
        baseRate *
        boostMultiplier *
        pointsBoostMultiplier *
        refMultiplier *
        rewardedMultiplier *
        streakMultiplier
      ).toFixed(2)
    )
  );

  return {
    baseRate,
    boostMultiplier,
    pointsBoostMultiplier,
    refCount,
    refMultiplier: Number(refMultiplier.toFixed(2)),
    rewardedMultiplier,
    streakMultiplier,
    totalRate,
  };
}

function calculateMiningRate(data) {
  return calculateMiningRateComponents(data).totalRate;
}

function streakBonusFor(streak) {
  if (streak >= 100) return 3.0;
  if (streak >= 30) return 2.0;
  if (streak >= 7) return 1.5;
  return 1.0;
}

function levelForXp(xp) {
  let level = 1;
  let remaining = Math.max(0, Math.trunc(xp));
  while (level < 1000) {
    const needed = Math.trunc(100 * Math.pow(1.5, level - 1));
    if (remaining < needed) return level;
    remaining -= needed;
    level += 1;
  }
  return level;
}

function purchaseExpiryDate(startDate = new Date()) {
  return new Date(
    startDate.getTime() + PURCHASE_DURATION_DAYS * 24 * 60 * 60 * 1000
  );
}

function purchaseEventId(platform, productId, transactionId) {
  return crypto
    .createHash("sha256")
    .update([platform, productId, transactionId].join("|"))
    .digest("hex");
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex");
}

function base64urlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function createAppleServerApiToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlJson({
    alg: "ES256",
    kid: appleKeyId.value(),
    typ: "JWT",
  });
  const payload = base64urlJson({
    iss: appleIssuerId.value(),
    iat: now,
    exp: now + 5 * 60,
    aud: "appstoreconnect-v1",
    bid: appleBundleId.value() || APP_BUNDLE_ID,
  });
  const unsignedToken = `${header}.${payload}`;
  const privateKey = applePrivateKey.value().replace(/\\n/g, "\n");
  const signature = crypto.sign("sha256", Buffer.from(unsignedToken), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${unsignedToken}.${signature.toString("base64url")}`;
}

function decodeAppleJwsPayload(jws) {
  const parts = String(jws || "").split(".");
  if (parts.length !== 3) {
    throw new HttpsError("failed-precondition", "Apple işlem imzası geçersiz.");
  }
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    throw new HttpsError("failed-precondition", "Apple işlem bilgisi okunamadı.");
  }
}

async function requestAppleTransaction(baseUrl, transactionId, bearerToken) {
  const response = await fetch(
    `${baseUrl}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${bearerToken}`,
        Accept: "application/json",
      },
    }
  );
  const body = await response.json().catch(() => ({}));
  return { response, body };
}

async function verifyAppleServerTransaction(transactionId, rawProductId, productId) {
  const bearerToken = createAppleServerApiToken();
  let lookup = await requestAppleTransaction(
    "https://api.storekit.apple.com",
    transactionId,
    bearerToken
  );
  let environment = "store";

  if (lookup.response.status === 404) {
    lookup = await requestAppleTransaction(
      "https://api.storekit-sandbox.apple.com",
      transactionId,
      bearerToken
    );
    environment = "sandbox";
  }

  if (!lookup.response.ok) {
    console.error("Apple transaction lookup failed", {
      status: lookup.response.status,
      errorCode: lookup.body?.errorCode,
    });
    throw new HttpsError(
      "failed-precondition",
      "Apple satın alımı sunucuda doğrulanamadı."
    );
  }

  const transaction = decodeAppleJwsPayload(lookup.body?.signedTransactionInfo);
  const verifiedBundleId = String(transaction?.bundleId || "");
  const verifiedProductId = String(transaction?.productId || "");
  const verifiedTransactionId = String(transaction?.transactionId || "");
  const originalTransactionId = String(transaction?.originalTransactionId || "");

  if (verifiedBundleId !== APP_BUNDLE_ID) {
    throw new HttpsError("permission-denied", "Apple işlemi bu uygulamaya ait değil.");
  }
  if (
    verifiedProductId !== rawProductId &&
    normalizeProductId(verifiedProductId) !== productId
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Apple işlemindeki ürün satın alınan paketle eşleşmiyor."
    );
  }
  if (
    verifiedTransactionId !== transactionId &&
    originalTransactionId !== transactionId
  ) {
    throw new HttpsError("failed-precondition", "Apple işlem kimliği eşleşmiyor.");
  }
  if (Number(transaction?.revocationDate || 0) > 0) {
    throw new HttpsError("failed-precondition", "Apple satın alımı iptal edilmiş.");
  }

  const purchaseDate = new Date(Number(transaction?.purchaseDate || Date.now()));
  if (Number.isNaN(purchaseDate.getTime())) {
    throw new HttpsError("failed-precondition", "Apple işlem tarihi geçersiz.");
  }
  const appleExpiryMs = Number(transaction?.expiresDate || 0);
  const expiresAt =
    appleExpiryMs > 0 ? new Date(appleExpiryMs) : purchaseExpiryDate(purchaseDate);
  if (expiresAt.getTime() <= Date.now()) {
    throw new HttpsError("failed-precondition", "Apple satın alımının süresi dolmuş.");
  }

  return {
    transactionId: verifiedTransactionId,
    orderId: verifiedTransactionId,
    purchaseDate,
    expiresAt,
    environment:
      String(transaction?.environment || "").toLowerCase() === "sandbox"
        ? "sandbox"
        : environment,
  };
}

function maskEmail(value) {
  const email = String(value || "").trim();
  const at = email.indexOf("@");
  if (at <= 1) return email ? "***" : "";
  return `${email.slice(0, 2)}***${email.slice(at)}`;
}

async function postAppleReceipt(url, receipt) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      "receipt-data": receipt,
      "exclude-old-transactions": false,
    }),
  });
  if (!response.ok) {
    throw new HttpsError("unavailable", "Apple doğrulama servisine ulaşılamadı.");
  }
  return response.json();
}

async function verifyApplePurchase(receipt, rawProductId, productId) {
  if (receipt.length < 128) {
    throw new HttpsError(
      "invalid-argument",
      "Apple App Store makbuzu eksik veya geçersiz."
    );
  }

  let result = await postAppleReceipt(APPLE_VERIFY_PRODUCTION_URL, receipt);
  if (Number(result?.status) === 21007) {
    result = await postAppleReceipt(APPLE_VERIFY_SANDBOX_URL, receipt);
  }
  if (Number(result?.status) !== 0) {
    console.warn("Apple receipt rejected", { status: result?.status });
    throw new HttpsError("failed-precondition", "Apple satın alımı doğrulanamadı.");
  }
  if (String(result?.receipt?.bundle_id || "") !== APP_BUNDLE_ID) {
    throw new HttpsError("permission-denied", "Apple makbuzu bu uygulamaya ait değil.");
  }

  const allItems = [
    ...(Array.isArray(result?.receipt?.in_app) ? result.receipt.in_app : []),
    ...(Array.isArray(result?.latest_receipt_info) ? result.latest_receipt_info : []),
  ];
  const matching = allItems
    .filter(
      (item) =>
        !item?.cancellation_date_ms &&
        (String(item?.product_id || "") === rawProductId ||
          normalizeProductId(item?.product_id) === productId)
    )
    .sort(
      (a, b) =>
        Number(b?.purchase_date_ms || b?.original_purchase_date_ms || 0) -
        Number(a?.purchase_date_ms || a?.original_purchase_date_ms || 0)
    );
  const item = matching[0];
  if (!item) {
    throw new HttpsError(
      "failed-precondition",
      "Apple makbuzunda satın alınan ürün bulunamadı."
    );
  }

  const purchaseMs = Number(
    item.purchase_date_ms || item.original_purchase_date_ms || Date.now()
  );
  const purchaseDate = new Date(purchaseMs);
  const appleExpiryMs = Number(item.expires_date_ms || 0);
  const expiresAt =
    appleExpiryMs > 0 ? new Date(appleExpiryMs) : purchaseExpiryDate(purchaseDate);
  const transactionId = String(
    item.transaction_id || item.original_transaction_id || ""
  );

  if (!transactionId || Number.isNaN(purchaseDate.getTime())) {
    throw new HttpsError("failed-precondition", "Apple işlem bilgisi eksik.");
  }
  if (expiresAt.getTime() <= Date.now()) {
    throw new HttpsError("failed-precondition", "Apple satın alımının süresi dolmuş.");
  }

  return {
    transactionId,
    orderId: transactionId,
    purchaseDate,
    expiresAt,
    environment: result?.environment === "Sandbox" ? "sandbox" : "store",
  };
}

async function verifyGooglePlayPurchase(receipt, rawProductId) {
  const client = await googlePlayAuth.getClient();
  const encodedProduct = encodeURIComponent(rawProductId);
  const encodedToken = encodeURIComponent(receipt);
  let response;
  try {
    response = await client.request({
      url:
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
        `${APP_BUNDLE_ID}/purchases/products/${encodedProduct}/tokens/${encodedToken}`,
      method: "GET",
    });
  } catch (error) {
    // Google API errors can include the purchase token in request URLs.
    console.error("Google Play verification failed", {
      status: error?.response?.status,
      code: error?.code,
    });
    throw new HttpsError(
      "failed-precondition",
      "Google Play satın alımı doğrulanamadı."
    );
  }

  const purchase = response?.data || {};
  if (Number(purchase.purchaseState) !== 0) {
    throw new HttpsError("failed-precondition", "Google Play satın alımı tamamlanmamış.");
  }
  const purchaseDate = new Date(Number(purchase.purchaseTimeMillis || Date.now()));
  const transactionId = String(purchase.orderId || sha256(receipt));
  return {
    transactionId,
    orderId: String(purchase.orderId || ""),
    purchaseDate,
    expiresAt: purchaseExpiryDate(purchaseDate),
    environment: Number(purchase.purchaseType) === 0 ? "test" : "store",
  };
}

async function verifyStorePurchase(
  platform,
  receipt,
  rawProductId,
  productId,
  transactionId
) {
  if (platform === "ios") {
    if (transactionId) {
      return verifyAppleServerTransaction(transactionId, rawProductId, productId);
    }
    return verifyApplePurchase(receipt, rawProductId, productId);
  }
  if (platform === "android") {
    return verifyGooglePlayPurchase(receipt, rawProductId);
  }
  throw new HttpsError("invalid-argument", "Desteklenmeyen mağaza platformu.");
}

async function applyPurchaseToUser(uid, data, isPremium) {
  const rawProductId = String(data?.productId || "").trim();
  const productId = normalizeProductId(rawProductId);
  const platform = String(data?.platform || "").trim().toLowerCase();
  const receipt = String(data?.receipt || "").trim();
  const transactionId = String(data?.transactionId || "").trim();

  if (!receipt) {
    throw new HttpsError("invalid-argument", "Satın alma doğrulama bilgisi eksik.");
  }

  if (
    (isPremium && !PREMIUM_PRODUCTS.has(productId)) ||
    (!isPremium && !BOOST_PRODUCT_MULTIPLIERS[productId])
  ) {
    throw new HttpsError("invalid-argument", "Geçersiz mağaza ürünü.");
  }

  // External store verification happens first. All internal changes are then
  // committed in a single transaction, so concurrent retries cannot grant
  // the same purchase twice or leave an orphaned ledger record.
  const verification = await verifyStorePurchase(
    platform,
    receipt,
    rawProductId,
    productId,
    transactionId
  );
  const eventId = purchaseEventId(platform, productId, verification.transactionId);
  const eventRef = db.collection("purchase_events").doc(eventId);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const [existingEvent, userSnap] = await Promise.all([
      tx.get(eventRef),
      tx.get(userRef),
    ]);
    if (existingEvent.exists) {
      const eventData = existingEvent.data() || {};
      if (String(eventData.uid || "") !== uid) {
        throw new HttpsError("already-exists", "Bu mağaza işlemi başka bir hesapta kullanılmış.");
      }
      return {
        ok: true,
        alreadyApplied: true,
        productId,
        rawProductId,
        platform,
        isPremium,
        expiresAt: eventData.expiresAt?.toDate?.()?.toISOString?.() || "",
      };
    }
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Satın alma için kullanıcı profili bulunamadı.");
    }

    const existingUserData = userSnap.data() || {};
    const expiresAt = verification.expiresAt;
    const update = {
      lastPurchasePlatform: platform,
      lastPurchaseProductId: productId,
      lastPurchaseStoreProductId: rawProductId,
      lastPurchaseProofHash: sha256(receipt),
      lastPurchaseAt: FieldValue.serverTimestamp(),
      purchaseExpiresAt: Timestamp.fromDate(expiresAt),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (isPremium) {
      update.isPremium = true;
      update.premiumExpiresAt = Timestamp.fromDate(expiresAt);
      update.premium = {
        is_active: true,
        expires_at: Timestamp.fromDate(expiresAt),
      };
    } else {
      const multiplier = BOOST_PRODUCT_MULTIPLIERS[productId];
      update.currentMultiplier = multiplier;
      update.boostExpiresAt = Timestamp.fromDate(expiresAt);
      update.mining = {
        active_multiplier: multiplier,
        boost_expires_at: Timestamp.fromDate(expiresAt),
      };
    }

    const nextData = {
      ...existingUserData,
      ...update,
      mining: {
        ...(existingUserData.mining || {}),
        ...(update.mining || {}),
      },
    };
    const rateComponents = isPremium ? null : calculateMiningRateComponents(nextData);
    let boostCatchup = null;

    if (!isPremium && rateComponents) {
      const nowSeconds = Math.trunc(Date.now() / 1000);
      const lastMiningStart = intField(existingUserData, "lastMiningStart", 0);
      const previousReward = numberField(
        existingUserData,
        "lastMiningReward",
        numberField(existingUserData, "lastKnownMiningRate", 0)
      );
      const alreadyCaughtUp =
        String(existingUserData.lastBoostCatchupPurchaseEventId || "") === eventId;
      if (
        lastMiningStart > 0 &&
        nowSeconds - lastMiningStart >= 0 &&
        nowSeconds - lastMiningStart < DAILY_REWARD_SECONDS &&
        previousReward > 0 &&
        !alreadyCaughtUp
      ) {
        const catchupDelta = Number((rateComponents.totalRate - previousReward).toFixed(2));
        if (catchupDelta > 0) {
          const currentPoints = numberField(existingUserData, "points", 0);
          const nextPoints = Number((currentPoints + catchupDelta).toFixed(2));
          boostCatchup = {
            delta: catchupDelta,
            previousReward,
            adjustedReward: Number((previousReward + catchupDelta).toFixed(2)),
            points: nextPoints,
          };
          update.points = nextPoints;
          update.lastMiningReward = boostCatchup.adjustedReward;
          update.lastKnownMiningRate = rateComponents.totalRate;
          update.lastBoostCatchupDelta = catchupDelta;
          update.lastBoostCatchupPurchaseEventId = eventId;
          update.lastBoostCatchupAt = FieldValue.serverTimestamp();
        }
      }
    }

    tx.set(userRef, update, { merge: true });
    tx.create(eventRef, {
      uid,
      productId,
      rawProductId,
      platform,
      storeTransactionId: verification.transactionId,
      storeOrderId: verification.orderId,
      storeEnvironment: verification.environment,
      storePurchaseAt: Timestamp.fromDate(verification.purchaseDate),
      isPremium,
      multiplier: isPremium ? null : BOOST_PRODUCT_MULTIPLIERS[productId],
      boostCatchup,
      purchaseAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(expiresAt),
      source: "iap_callable",
      verifiedByStoreServer: true,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      productId,
      rawProductId,
      platform,
      isPremium,
      multiplier: isPremium ? null : BOOST_PRODUCT_MULTIPLIERS[productId],
      rateComponents,
      boostCatchup,
      expiresAt: expiresAt.toISOString(),
    };
  });
}

async function applyRewardedBoostToUser(uid, requestData = {}) {
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
    }

    const data = snap.data() || {};
    const nowSec = Math.floor(Date.now() / 1000);
    const today = rewardedBoostDayKey(nowSec);
    const rewardedBoostState = getRewardedBoostState({
      nowSec,
      storedMultiplier: numberField(data, "rewardedBoostMultiplier", 1.0),
      lastRewardAt: intField(
        data,
        "rewardedBoostLastAt",
        intField(data, "lastRewardedBoostAt", 0)
      ),
      windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      maxMultiplier: REWARDED_BOOST_MAX_MULTIPLIER,
    });
    const currentMultiplier = rewardedBoostState.multiplier;
    const storedDay = intField(data, "rewardedBoostDay", -1);
    const dailyCount =
      storedDay === today ? Math.max(0, intField(data, "rewardedBoostDailyCount", 0)) : 0;
    const lastAt = Math.max(
      0,
      intField(data, "rewardedBoostLastAt", intField(data, "lastRewardedBoostAt", 0))
    );
    const attemptTimes = getActiveRewardedAttemptTimes({
      nowSec,
      firstAt: intField(data, "rewardedBoostAttemptFirstAt", 0),
      secondAt: intField(data, "rewardedBoostAttemptSecondAt", 0),
      windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      limit: REWARDED_BOOST_DAILY_LIMIT,
    });
    const attemptResolution = resolveRewardedAttemptForApply({
      attemptTimes,
      requestedAttemptAt: requestData?.attempt_at,
      lastAppliedAttemptAt: intField(data, "rewardedBoostLastAppliedAttemptAt", 0),
    });

    if (!attemptResolution.valid) {
      return {
        ok: false,
        error: "rewarded_boost_attempt_invalid",
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
      };
    }

    if (attemptResolution.idempotent) {
      return {
        ok: true,
        idempotent: true,
        attempt_at: attemptResolution.attemptAt,
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        total_rate: calculateMiningRate(data, nowSec),
        daily_count: dailyCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
        max_multiplier: REWARDED_BOOST_MAX_MULTIPLIER,
      };
    }

    if (dailyCount >= REWARDED_BOOST_DAILY_LIMIT) {
      return {
        ok: false,
        error: "rewarded_boost_daily_limit",
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        daily_count: dailyCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    if (currentMultiplier >= REWARDED_BOOST_MAX_MULTIPLIER) {
      return {
        ok: false,
        error: "rewarded_boost_max_reached",
        remaining_seconds: rewardedBoostState.remainingSeconds,
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        daily_count: dailyCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
        max_multiplier: REWARDED_BOOST_MAX_MULTIPLIER,
      };
    }

    const elapsed = lastAt > 0 ? nowSec - lastAt : REWARDED_BOOST_COOLDOWN_SECONDS;
    if (elapsed < REWARDED_BOOST_COOLDOWN_SECONDS) {
      return {
        ok: false,
        error: "rewarded_boost_cooldown",
        remaining_seconds: REWARDED_BOOST_COOLDOWN_SECONDS - elapsed,
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        daily_count: dailyCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    const nextMultiplier = Number(
      Math.min(
        REWARDED_BOOST_MAX_MULTIPLIER,
        currentMultiplier * (1.0 + REWARDED_BOOST_PERCENTAGE)
      ).toFixed(6)
    );
    const nextData = {
      ...data,
      rewardedBoostMultiplier: nextMultiplier,
      rewardedBoostLastAt: nowSec,
    };
    const totalRate = calculateMiningRate(nextData, nowSec);

    tx.set(
      userRef,
      {
        rewardedBoostMultiplier: nextMultiplier,
        rewardedBoostDay: today,
        rewardedBoostDailyCount: dailyCount + 1,
        rewardedBoostLastAt: nowSec,
        rewardedBoostLastAppliedAttemptAt: attemptResolution.attemptAt,
        lastRewardedBoostAt: FieldValue.serverTimestamp(),
        lastKnownMiningRate: totalRate,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      ok: true,
      rewarded_multiplier: nextMultiplier,
      total_rate: totalRate,
      daily_count: dailyCount + 1,
      daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      max_multiplier: REWARDED_BOOST_MAX_MULTIPLIER,
      attempt_at: attemptResolution.attemptAt,
    };
  });
}

async function reserveRewardedBoostAttemptForUser(uid) {
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
    }

    const data = snap.data() || {};
    const nowSec = Math.floor(Date.now() / 1000);
    const today = rewardedBoostDayKey(nowSec);
    const rewardedBoostState = getRewardedBoostState({
      nowSec,
      storedMultiplier: numberField(data, "rewardedBoostMultiplier", 1.0),
      lastRewardAt: intField(
        data,
        "rewardedBoostLastAt",
        intField(data, "lastRewardedBoostAt", 0)
      ),
      windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      maxMultiplier: REWARDED_BOOST_MAX_MULTIPLIER,
    });
    const currentMultiplier = rewardedBoostState.multiplier;
    const boostDay = intField(data, "rewardedBoostDay", -1);
    const dailyCount =
      boostDay === today ? Math.max(0, intField(data, "rewardedBoostDailyCount", 0)) : 0;
    const lastAt = Math.max(
      0,
      intField(data, "rewardedBoostLastAt", intField(data, "lastRewardedBoostAt", 0))
    );
    // Önceki sürümün günlük sayacından kayan 24 saatlik pencereye güvenli geçiş.
    const legacyAttemptDay = intField(data, "rewardedBoostAttemptDay", -1);
    const legacyAttemptCount =
      legacyAttemptDay === today
        ? Math.max(0, intField(data, "rewardedBoostAttemptCount", 0))
        : 0;
    const legacyLastAttemptAt = Math.max(0, intField(data, "rewardedBoostAttemptLastAt", 0));
    const attemptTimes = getActiveRewardedAttemptTimes({
      nowSec,
      firstAt: intField(data, "rewardedBoostAttemptFirstAt", 0),
      secondAt: intField(data, "rewardedBoostAttemptSecondAt", 0),
      legacyAttemptCount,
      legacyLastAttemptAt,
      successfulAttemptCount: dailyCount,
      lastRewardAt: lastAt,
      windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      limit: REWARDED_BOOST_DAILY_LIMIT,
    });
    const attemptState = getRewardedAttemptLimitState({
      attemptTimes,
      nowSec,
      windowSeconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      limit: REWARDED_BOOST_DAILY_LIMIT,
    });
    const attemptCount = attemptState.attemptCount;

    // attempt_at is the reservation identity. A same-second retry cannot create
    // a second distinct reward, so return its existing slot before limit checks.
    if (
      intField(data, "rewardedBoostAttemptFirstAt", 0) === nowSec ||
      intField(data, "rewardedBoostAttemptSecondAt", 0) === nowSec
    ) {
      return {
        ok: true,
        idempotent: true,
        attempt_at: nowSec,
        attempt_count: attemptCount,
        attempts_remaining: Math.max(0, REWARDED_BOOST_DAILY_LIMIT - attemptCount),
        window_seconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    if (attemptState.blocked) {
      return {
        ok: false,
        error: "rewarded_boost_daily_attempt_limit",
        attempt_count: attemptCount,
        remaining_seconds: attemptState.remainingSeconds,
        window_seconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    if (dailyCount >= REWARDED_BOOST_DAILY_LIMIT) {
      return {
        ok: false,
        error: "rewarded_boost_daily_limit",
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        daily_count: dailyCount,
        attempt_count: attemptCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    if (currentMultiplier >= REWARDED_BOOST_MAX_MULTIPLIER) {
      return {
        ok: false,
        error: "rewarded_boost_max_reached",
        remaining_seconds: rewardedBoostState.remainingSeconds,
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        attempt_count: attemptCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
        max_multiplier: REWARDED_BOOST_MAX_MULTIPLIER,
      };
    }

    const elapsed = lastAt > 0 ? nowSec - lastAt : REWARDED_BOOST_COOLDOWN_SECONDS;
    if (elapsed < REWARDED_BOOST_COOLDOWN_SECONDS) {
      return {
        ok: false,
        error: "rewarded_boost_cooldown",
        remaining_seconds: REWARDED_BOOST_COOLDOWN_SECONDS - elapsed,
        rewarded_multiplier: Number(currentMultiplier.toFixed(6)),
        attempt_count: attemptCount,
        daily_limit: REWARDED_BOOST_DAILY_LIMIT,
      };
    }

    const nextAttemptTimes = [...attemptTimes, nowSec]
      .sort((a, b) => a - b)
      .slice(-REWARDED_BOOST_DAILY_LIMIT);
    const nextAttemptCount = nextAttemptTimes.length;
    tx.set(
      userRef,
      {
        rewardedBoostAttemptFirstAt: nextAttemptTimes[0] || 0,
        rewardedBoostAttemptSecondAt: nextAttemptTimes[1] || 0,
        rewardedBoostAttemptCount: nextAttemptCount,
        rewardedBoostAttemptLastAt: nowSec,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      ok: true,
      attempt_at: nowSec,
      attempt_count: nextAttemptCount,
      attempts_remaining: Math.max(0, REWARDED_BOOST_DAILY_LIMIT - nextAttemptCount),
      window_seconds: REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
      daily_limit: REWARDED_BOOST_DAILY_LIMIT,
    };
  });
}

function sanitizeAnalyticsParams(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const output = {};
  for (const [rawKey, rawValue] of Object.entries(value).slice(0, 12)) {
    const key = String(rawKey)
      .replace(/[^A-Za-z0-9_]/g, "_")
      .slice(0, 40);
    if (!key) continue;
    if (typeof rawValue === "number" && Number.isFinite(rawValue)) {
      output[key] = rawValue;
    } else if (typeof rawValue === "boolean") {
      output[key] = rawValue;
    } else if (typeof rawValue === "string") {
      output[key] = rawValue.slice(0, 120);
    }
  }
  return output;
}

async function forwardEventToGa4(eventName, clientId, uid, params) {
  const apiSecret = ga4ApiSecret.value();
  if (!apiSecret) return;

  const response = await fetch(
    `https://www.google-analytics.com/mp/collect?measurement_id=${encodeURIComponent(
      GA4_MEASUREMENT_ID
    )}&api_secret=${encodeURIComponent(apiSecret)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: clientId,
        ...(uid ? { user_id: uid } : {}),
        events: [
          {
            name: eventName,
            params: {
              ...params,
              engagement_time_msec: 1,
            },
          },
        ],
      }),
    }
  );
  if (!response.ok) {
    throw new Error(`GA4 Measurement Protocol returned ${response.status}`);
  }
}

exports.track_event = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
    secrets: [ga4ApiSecret],
  },
  async (request) => {
    const eventName = String(request.data?.eventName || "").trim();
    if (!ANALYTICS_EVENT_NAMES.has(eventName)) {
      throw new HttpsError("invalid-argument", "Geçersiz ölçüm olayı.");
    }

    const clientId = String(request.data?.clientId || "").trim().slice(0, 128);
    if (clientId.length < 12) {
      throw new HttpsError("invalid-argument", "Ölçüm istemci kimliği eksik.");
    }

    const params = sanitizeAnalyticsParams(request.data?.params);
    const unauthenticatedEvents = new Set([
      "first_open",
      "app_first_open",
      "signup_start",
      "signup_error",
      "login_google_tap",
      "login_apple_tap",
    ]);
    const isPublicOnboardingView =
      eventName === "app_screen_view" &&
      String(params.screen || "") === "onboarding";
    if (
      !request.auth &&
      !unauthenticatedEvents.has(eventName) &&
      !isPublicOnboardingView
    ) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const uid = request.auth?.uid || "";
    const clientIdHash = sha256(clientId);
    const now = new Date();
    const dedupeBucket =
      eventName === "app_first_open" || eventName === "first_open"
        ? "install"
        : Math.floor(now.getTime() / (60 * 1000));
    const documentId = sha256(
      [clientIdHash, uid, eventName, dedupeBucket].join("|")
    );

    await db.collection("analytics_events").doc(documentId).set(
      {
        eventName,
        uid: uid || null,
        clientIdHash,
        platform: String(params.platform || "").slice(0, 24),
        params,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    try {
      await forwardEventToGa4(eventName, clientId, uid, params);
    } catch (error) {
      console.warn("GA4 event forwarding failed", {
        eventName,
        message: error?.message || String(error),
      });
    }

    return { ok: true };
  }
);

async function applyReferralAttributionToUser(uid, rawReferralCode) {
  const referralCode = sanitizeReferralCode(rawReferralCode);
  if (!referralCode) {
    return {
      applied: false,
      resolved: false,
      status: "missing_code",
    };
  }

  const [authUser, userSnap] = await Promise.all([
    getAuth().getUser(uid),
    db.collection("users").doc(uid).get(),
  ]);
  if (!userSnap.exists) {
    return {
      applied: false,
      resolved: false,
      status: "profile_not_found",
    };
  }

  const accountCreatedAtMs = Date.parse(authUser.metadata.creationTime || "");
  const initialDecision = getReferralAttributionDecision({
    referralCode,
    ownReferralCode: String(userSnap.data()?.referralCode || ""),
    existingReferredBy: String(userSnap.data()?.referredBy || ""),
    referralBonusApplied: Boolean(userSnap.data()?.referralBonusApplied),
    accountCreatedAtMs,
  });
  if (!initialDecision.canApply) {
    return {
      applied: false,
      resolved: initialDecision.resolved,
      status: initialDecision.reason,
    };
  }

  const referrerSnap = await db
    .collection("users")
    .where("referralCode", "==", referralCode)
    .limit(1)
    .get();
  if (referrerSnap.empty || referrerSnap.docs[0].id === uid) {
    return {
      applied: false,
      resolved: !referrerSnap.empty,
      status: referrerSnap.empty ? "referrer_not_found" : "self_referral",
    };
  }

  const userRef = db.collection("users").doc(uid);
  const referrerRef = referrerSnap.docs[0].ref;
  return db.runTransaction(async (tx) => {
    const [latestUser, latestReferrer] = await Promise.all([
      tx.get(userRef),
      tx.get(referrerRef),
    ]);
    if (!latestUser.exists || !latestReferrer.exists) {
      return {
        applied: false,
        resolved: false,
        status: "profile_not_found",
      };
    }

    const latestData = latestUser.data() || {};
    const latestDecision = getReferralAttributionDecision({
      referralCode,
      ownReferralCode: String(latestData.referralCode || ""),
      existingReferredBy: String(latestData.referredBy || ""),
      referralBonusApplied: Boolean(latestData.referralBonusApplied),
      accountCreatedAtMs,
    });
    if (!latestDecision.canApply) {
      return {
        applied: false,
        resolved: latestDecision.resolved,
        status: latestDecision.reason,
      };
    }

    tx.set(
      userRef,
      {
        referredBy: referralCode,
        referredByUid: referrerRef.id,
        referralBonusApplied: false,
        referralRewardStatus: "pending",
        referralPendingAt: FieldValue.serverTimestamp(),
        referralAppliedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      applied: true,
      resolved: true,
      status: "pending",
    };
  });
}

exports.ensure_user_profile = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const uid = request.auth.uid;
    const email = String(request.auth.token?.email || "").trim();
    const referralCode = sanitizeReferralCode(request.data?.referralCode);
    const userRef = db.collection("users").doc(uid);
    const snap = await userRef.get();
    const loginData = {
      email,
      lastLoginAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    let created = false;
    if (snap.exists) {
      await userRef.set(loginData, { merge: true });
    } else {
      const configSnap = await db.collection("config").doc("general").get();
      const initialRate = normalizeMiningRate(configSnap.data()?.mining_rate, 1.0);
      const newReferralCode = `C${crypto.randomBytes(8).toString("hex").toUpperCase()}`;
      const newReferralRef = db.collection("referral_codes").doc(newReferralCode);
      created = await db.runTransaction(async (tx) => {
        const latestUser = await tx.get(userRef);
        if (latestUser.exists) {
          tx.set(userRef, loginData, { merge: true });
          return false;
        }

        const codeSnap = await tx.get(newReferralRef);
        if (codeSnap.exists) {
          throw new HttpsError("aborted", "Davet kodu çakıştı. Lütfen tekrar deneyin.");
        }
        tx.create(newReferralRef, { uid, createdAt: FieldValue.serverTimestamp() });
        tx.set(
          userRef,
          {
            ...loginData,
            referralCode: newReferralCode,
            base_rate: initialRate,
            referredBy: "",
            referralBonusApplied: false,
            points: 0,
            referralCount: 0,
            lastMiningStart: 0,
            dailyStreak: 0,
            streakBonus: 1,
            streakShieldCount: 0,
            tutorialSeen: false,
            createdAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return true;
      });
    }

    // Referans yalnızca bu çağrıda gerçekten oluşturulan profile bağlanır.
    // Var olan bir hesap davet linkine sonradan tıklayarak başka kullanıcıya
    // yazılamaz. Yeni hesap daveti beklemeye alınır; iki taraf da davet edilen
    // kullanıcı 3 günlük seriyi tamamladığında atomik olarak ödüllendirilir.
    const referralResult = referralCode && created
      ? await applyReferralAttributionToUser(uid, referralCode)
      : {
          applied: false,
          resolved: Boolean(referralCode),
          status: referralCode ? "existing_account" : "missing_code",
        };

    return {
      ok: true,
      created,
      referralApplied: referralResult.applied,
      referralResolved: referralResult.resolved,
      referralStatus: referralResult.status,
    };
  }
);

exports.apply_referral = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    const result = await applyReferralAttributionToUser(
      request.auth.uid,
      request.data?.referralCode
    );
    return {
      ok: result.applied || result.resolved,
      referralApplied: result.applied,
      referralResolved: result.resolved,
      referralStatus: result.status,
    };
  }
);

exports.get_referrals = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const userSnap = await db.collection("users").doc(request.auth.uid).get();
    const referralCode = String(userSnap.data()?.referralCode || "");
    if (!referralCode) return { users: [], count: 0 };

    const referralsSnap = await db
      .collection("users")
      .where("referredBy", "==", referralCode)
      .limit(100)
      .get();
    const users = referralsSnap.docs
      .filter((doc) => {
        const status = String(doc.data()?.referralRewardStatus || "");
        return status === "qualified" || status === "";
      })
      .map((doc) => ({
        fields: {
          email: { stringValue: maskEmail(doc.data()?.email) },
        },
      }));
    return { users, count: users.length };
  }
);

exports.get_point_rewards = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    const snap = await db.collection("users").doc(request.auth.uid).get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
    }
    const data = snap.data() || {};
    return {
      ok: true,
      points: numberField(data, "points", 0),
      aiBonusCredits: Math.max(0, intField(data, "aiBonusCredits", 0)),
      profilePrivilege: String(data.profilePrivilege || ""),
      pointsAdFreeUntil: parseExpiry(data.pointsAdFreeUntil)?.toISOString() || "",
      pointsBoostUntil: parseExpiry(data.pointsBoostUntil)?.toISOString() || "",
      rewards: Object.values(POINT_REWARDS),
    };
  }
);

exports.redeem_point_reward = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const reward = getPointReward(request.data?.rewardId);
    if (!reward) {
      throw new HttpsError("invalid-argument", "Geçersiz puan avantajı.");
    }

    const userRef = db.collection("users").doc(request.auth.uid);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
      }
      const data = snap.data() || {};
      const currentPoints = numberField(data, "points", 0);
      if (currentPoints < reward.cost) {
        throw new HttpsError("failed-precondition", "Bu avantaj için yeterli Candar puanın yok.");
      }
      if (reward.id === "profile_gold" && data.profilePrivilege === "gold") {
        throw new HttpsError("already-exists", "Altın profil ayrıcalığı zaten açık.");
      }

      const now = new Date();
      const update = {
        points: Number((currentPoints - reward.cost).toFixed(2)),
        lastPointRewardId: reward.id,
        lastPointRewardAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (reward.id === "ad_free_24h") {
        const current = parseExpiry(data.pointsAdFreeUntil)?.getTime() || 0;
        update.pointsAdFreeUntil = Timestamp.fromMillis(
          extendExpiryMs(current, now.getTime(), reward.durationSeconds)
        );
      } else if (reward.id === "boost_24h") {
        const current = parseExpiry(data.pointsBoostUntil)?.getTime() || 0;
        update.pointsBoostUntil = Timestamp.fromMillis(
          extendExpiryMs(current, now.getTime(), reward.durationSeconds)
        );
        update.pointsBoostMultiplier = reward.multiplier;
      } else if (reward.id === "profile_gold") {
        update.profilePrivilege = "gold";
        update.profilePrivilegeUnlockedAt = FieldValue.serverTimestamp();
      } else if (reward.id === "ai_5") {
        update.aiBonusCredits = FieldValue.increment(reward.amount);
      }

      tx.set(userRef, update, { merge: true });
      const projectedCredits =
        reward.id === "ai_5"
          ? Math.max(0, intField(data, "aiBonusCredits", 0)) + reward.amount
          : Math.max(0, intField(data, "aiBonusCredits", 0));
      return {
        ok: true,
        rewardId: reward.id,
        spent: reward.cost,
        points: update.points,
        aiBonusCredits: projectedCredits,
        profilePrivilege:
          reward.id === "profile_gold" ? "gold" : String(data.profilePrivilege || ""),
        pointsAdFreeUntil:
          update.pointsAdFreeUntil?.toDate().toISOString() ||
          parseExpiry(data.pointsAdFreeUntil)?.toISOString() ||
          "",
        pointsBoostUntil:
          update.pointsBoostUntil?.toDate().toISOString() ||
          parseExpiry(data.pointsBoostUntil)?.toISOString() ||
          "",
      };
    });
  }
);

exports.get_leaderboard = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const requestedLimit = Math.max(1, Math.min(80, Number(request.data?.limit || 25)));
    // Query an indexed, globally ordered leaderboard rather than sorting an
    // arbitrary first 500 users in memory.
    const usersSnap = await db.collection("users")
      .orderBy("referralCount", "desc")
      .orderBy("points", "desc")
      .limit(requestedLimit)
      .get();

    const rows = usersSnap.docs.map((doc) => {
      const data = doc.data() || {};
      return {
        fields: {
          email: {
            stringValue: doc.id === request.auth.uid
              ? String(data.email || "")
              : maskEmail(data.email),
          },
          points: { doubleValue: numberField(data, "points", 0) },
          referralCount: { integerValue: Math.max(0, intField(data, "referralCount", 0)) },
        },
      };
    });

    return { users: rows, count: rows.length };
  }
);

// Team membership lives on /users/{uid}.teamCode and
// /teams/{code}.members. Both documents change in a Firestore transaction;
// clients cannot write either field using firestore.rules.
function requireSignedIn(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  }
  return request.auth.uid;
}

function teamSummary(code, data, uid = "") {
  const members = Array.isArray(data?.members) ? data.members : [];
  return {
    code,
    name: String(data?.name || ""),
    memberCount: members.length,
    maxMembers: TEAM_CAPACITY,
    isOwner: String(data?.ownerUid || "") === uid,
    isMember: members.includes(uid),
  };
}

async function leaveTeamForUser(uid) {
  const userRef = db.collection("users").doc(uid);
  // A retry is safe. The caller may delete the account after this completes.
  const profile = await userRef.get();
  const code = normalizeTeamCode(profile.data()?.teamCode);
  if (!code) return { ok: true, left: false };

  const teamRef = db.collection("teams").doc(code);
  return db.runTransaction(async (tx) => {
    const [userSnap, teamSnap] = await Promise.all([
      tx.get(userRef), tx.get(teamRef),
    ]);
    if (!userSnap.exists) return { ok: true, left: false };
    if (normalizeTeamCode(userSnap.data()?.teamCode) !== code) {
      return { ok: true, left: false };
    }
    if (!teamSnap.exists) {
      tx.update(userRef, { teamCode: FieldValue.delete() });
      return { ok: true, left: true, missingTeam: true };
    }

    const change = removeMember(teamSnap.data(), uid);
    if (change.disbanded) {
      tx.delete(teamRef);
    } else if (change.wasMember) {
      tx.update(teamRef, {
        members: change.members,
        memberCount: change.members.length,
        ownerUid: change.ownerUid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(userRef, { teamCode: FieldValue.delete() });
    return { ok: true, left: true, disbanded: Boolean(change.disbanded) };
  });
}

exports.team_create = onCall(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const uid = requireSignedIn(request);
    const name = normalizeTeamName(request.data?.name);
    if (!name) throw new HttpsError("invalid-argument", "Takım adı 3–40 karakter olmalı.");
    const code = "T" + crypto.randomBytes(6).toString("hex").toUpperCase();
    const userRef = db.collection("users").doc(uid);
    const teamRef = db.collection("teams").doc(code);
    return db.runTransaction(async (tx) => {
      const [user, team] = await Promise.all([tx.get(userRef), tx.get(teamRef)]);
      if (!user.exists) throw new HttpsError("not-found", "Kullanıcı profili bulunamadı.");
      if (normalizeTeamCode(user.data()?.teamCode)) {
        throw new HttpsError("failed-precondition", "Zaten bir takımdasın.");
      }
      if (team.exists) throw new HttpsError("aborted", "Takım kodu çakıştı. Tekrar deneyin.");
      tx.create(teamRef, {
        name, code, members: [uid], ownerUid: uid, memberCount: 1,
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(userRef, { teamCode: code });
      return { ok: true, team: { code, name, memberCount: 1, maxMembers: TEAM_CAPACITY, isOwner: true } };
    });
  }
);

exports.team_join = onCall(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    const uid = requireSignedIn(request);
    const code = normalizeTeamCode(request.data?.code);
    if (!code) throw new HttpsError("invalid-argument", "Takım kodu geçersiz.");
    const userRef = db.collection("users").doc(uid);
    const teamRef = db.collection("teams").doc(code);
    return db.runTransaction(async (tx) => {
      const [user, teamSnap] = await Promise.all([tx.get(userRef), tx.get(teamRef)]);
      if (!user.exists) throw new HttpsError("not-found", "Kullanıcı profili bulunamadı.");
      if (!teamSnap.exists) throw new HttpsError("not-found", "Takım bulunamadı.");
      const currentCode = normalizeTeamCode(user.data()?.teamCode);
      const teamData = teamSnap.data() || {};
      if (currentCode) {
        if (currentCode === code && Array.isArray(teamData.members) && teamData.members.includes(uid)) {
          return { ok: true, alreadyJoined: true, team: teamSummary(code, teamData, uid) };
        }
        throw new HttpsError("failed-precondition", "Önce mevcut takımından ayrılmalısın.");
      }
      const joined = addMember(teamData, uid);
      if (joined.full) throw new HttpsError("resource-exhausted", "Takım dolu (30 kişi).");
      if (joined.alreadyMember) throw new HttpsError("failed-precondition", "Takım kayıtları uyuşmuyor.");
      tx.update(teamRef, {
        members: joined.members, memberCount: joined.members.length,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(userRef, { teamCode: code });
      return { ok: true, team: { ...teamSummary(code, teamData, uid), memberCount: joined.members.length, isMember: true } };
    });
  }
);

exports.team_leave = onCall(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => leaveTeamForUser(requireSignedIn(request))
);

exports.team_info = onCall(
  { region: "europe-west1", timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    const uid = requireSignedIn(request);
    const profile = await db.collection("users").doc(uid).get();
    if (!profile.exists) throw new HttpsError("not-found", "Profil bulunamadı.");
    const code = normalizeTeamCode(profile.data()?.teamCode);
    if (!code) return { ok: true, inTeam: false };
    const snap = await db.collection("teams").doc(code).get();
    if (!snap.exists || !Array.isArray(snap.data()?.members) ||
        !snap.data().members.includes(uid)) {
      // Recover orphaned membership without racing a concurrent team join.
      const profileRef = db.collection("users").doc(uid);
      await db.runTransaction(async (tx) => {
        const latest = await tx.get(profileRef);
        if (latest.exists && normalizeTeamCode(latest.data()?.teamCode) === code) {
          tx.update(profileRef, { teamCode: FieldValue.delete() });
        }
      });
      return { ok: true, inTeam: false, repairedOrphan: true };
    }
    return { ok: true, inTeam: true, team: teamSummary(code, snap.data(), uid) };
  }
);

exports.team_leaderboard = onCall(
  { region: "europe-west1", timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    requireSignedIn(request);
    const limit = Math.min(50, Math.max(1, Number(request.data?.limit || 10)));
    const snap = await db.collection("teams").orderBy("memberCount", "desc").limit(limit).get();
    return {
      ok: true,
      teams: snap.docs.map((doc) => teamSummary(doc.id, doc.data())),
    };
  }
);

// Delete account-associated records held outside /users/{uid} as well as
// the user document and its nested collections. Purchase ledger rows keep
// their transaction identity for anti-replay while removing the account UID.
async function removeUserRelatedRows(collectionName, uid, anonymize = false) {
  let removed = 0;
  while (true) {
    const snap = await db.collection(collectionName)
      .where("uid", "==", uid)
      .limit(200)
      .get();
    if (snap.empty) return removed;
    const batch = db.batch();
    for (const doc of snap.docs) {
      if (anonymize) {
        batch.update(doc.ref, {
          uid: FieldValue.delete(),
          accountDeletedAt: FieldValue.serverTimestamp(),
        });
      } else {
        batch.delete(doc.ref);
      }
    }
    await batch.commit();
    removed += snap.size;
  }
}

exports.delete_account = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const uid = request.auth.uid;
    const userRef = db.collection("users").doc(uid);
    try {
      const userSnap = await userRef.get();
      const referralCode = String(userSnap.data()?.referralCode || "");
      await leaveTeamForUser(uid);
      await db.recursiveDelete(db.collection("chats").doc(uid));
      await removeUserRelatedRows("analytics_events", uid);
      await removeUserRelatedRows("purchase_events", uid, true);
      await removeUserRelatedRows("admob_ssv_transactions", uid, true);
      if (referralCode.startsWith("C")) {
        const codeRef = db.collection("referral_codes").doc(referralCode);
        const codeSnap = await codeRef.get();
        if (codeSnap.exists && codeSnap.data()?.uid === uid) {
          await codeRef.set({
            uid: FieldValue.delete(),
            deactivated: true,
            deactivatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }
      await db.recursiveDelete(userRef);
      await getAuth().deleteUser(uid);
      return { ok: true };
    } catch (error) {
      console.error("delete_account failed", { uid, code: error?.code });
      throw new HttpsError(
        "internal",
        "Hesap tamamen silinemedi. Lütfen tekrar deneyin."
      );
    }
  }
);

function miningReadyMessage(lang, userData = {}) {
  const messages = {
    tr: ["Günlük puanların hazır", "Candar Network'e dön, günlük puanlarını topla ve serini koru."],
    en: ["Daily points are ready", "Open Candar Network, collect your daily points, and keep your streak alive."],
    de: ["Tägliche Punkte sind bereit", "Öffne Candar Network, sammle deine täglichen Punkte und halte deine Serie aktiv."],
    fr: ["Vos points du jour sont prêts", "Ouvrez Candar Network, récupérez vos points quotidiens et gardez votre série active."],
    es: ["Tus puntos diarios están listos", "Abre Candar Network, recoge tus puntos diarios y conserva tu racha."],
    pt: ["Seus pontos diários estão prontos", "Abra o Candar Network, colete seus pontos diários e mantenha sua sequência."],
    ru: ["Ежедневные баллы готовы", "Откройте Candar Network, заберите ежедневные баллы и сохраните серию."],
    zh: ["每日积分已准备好", "打开 Candar Network，领取每日积分并保持连续记录。"],
    ja: ["デイリーポイントの準備ができました", "Candar Networkを開いてデイリーポイントを受け取り、連続記録を続けましょう。"],
    ko: ["일일 포인트가 준비됐어요", "Candar Network를 열고 일일 포인트를 받고 연속 기록을 이어가세요."],
    ar: ["نقاطك اليومية جاهزة", "افتح Candar Network واجمع نقاطك اليومية وحافظ على سلسلتك."],
    hi: ["आपके दैनिक पॉइंट तैयार हैं", "Candar Network खोलें, दैनिक पॉइंट लें और अपनी स्ट्रीक बनाए रखें।"],
  };
  const normalizedLang = normalizeLang(lang);
  const streak = Math.max(0, intField(userData, "dailyStreak", 0));
  const shieldCount = Math.max(0, intField(userData, "streakShieldCount", 0));
  if (normalizedLang === "tr" && streak > 0) {
    return shieldCount > 0
      ? {
          title: `🛡️ ${streak} günlük serin hazır`,
          body: "Günlük puanını al; Seri Kalkanın da beklenmedik bir günü kaçırırsan seni korur.",
        }
      : {
          title: `🔥 ${streak} günlük serini koru`,
          body: "Günlük puanın hazır. 7 günlük bölümü tamamla, Seri Kalkanı kazan.",
        };
  }
  if (normalizedLang === "en" && streak > 0) {
    return shieldCount > 0
      ? {
          title: `🛡️ Your ${streak}-day streak is ready`,
          body: "Claim today's points. Your Streak Shield will also protect one unexpected missed day.",
        }
      : {
          title: `🔥 Keep your ${streak}-day streak`,
          body: "Your daily points are ready. Complete the 7-day journey to earn a Streak Shield.",
        };
  }
  const msg = messages[normalizedLang] || messages.en;
  return { title: msg[0], body: msg[1] };
}

function firstMiningMessage(lang) {
  const messages = {
    tr: ["İlk kazımın seni bekliyor", "Candar Network'ü aç, ilk günlük puanını kazan ve 3 günlük serini başlat."],
    en: ["Your first mining is waiting", "Open Candar Network, earn your first daily points, and start your 3-day streak."],
    de: ["Dein erstes Mining wartet", "Öffne Candar Network, sammle deine ersten Tagespunkte und starte deine 3-Tage-Serie."],
    fr: ["Votre premier minage vous attend", "Ouvrez Candar Network, gagnez vos premiers points et lancez votre série de 3 jours."],
    es: ["Tu primera minería te espera", "Abre Candar Network, gana tus primeros puntos diarios e inicia tu racha de 3 días."],
    pt: ["Sua primeira mineração está esperando", "Abra o Candar Network, ganhe seus primeiros pontos e comece sua sequência de 3 dias."],
    ru: ["Вас ждёт первый майнинг", "Откройте Candar Network, получите первые баллы и начните серию из 3 дней."],
    zh: ["首次挖矿正等着你", "打开 Candar Network，领取首次每日积分并开始连续 3 天记录。"],
    ja: ["最初のマイニングを始めよう", "Candar Networkを開き、最初のデイリーポイントを獲得して3日間の連続記録を始めましょう。"],
    ko: ["첫 채굴이 기다리고 있어요", "Candar Network를 열고 첫 일일 포인트를 받아 3일 연속 기록을 시작하세요."],
    ar: ["أول عملية تعدين بانتظارك", "افتح Candar Network واجمع أول نقاطك اليومية وابدأ سلسلة 3 أيام."],
    hi: ["आपकी पहली माइनिंग तैयार है", "Candar Network खोलें, अपने पहले दैनिक पॉइंट पाएं और 3-दिन की स्ट्रीक शुरू करें।"],
  };
  const msg = messages[normalizeLang(lang)] || messages.en;
  return { title: msg[0], body: msg[1] };
}

async function sendDailyPointsNotifications(options = {}) {
  const nowSeconds = Math.trunc(Date.now() / 1000);
  const readyBefore = nowSeconds - DAILY_REWARD_SECONDS;
  const campaignKey = String(options.campaignKey || "daily_points_ready").slice(0, 64);
  const limit = Math.min(Math.max(Number(options.limit || MAX_NOTIFICATION_BATCH), 1), MAX_NOTIFICATION_BATCH);
  const force = options.force === true;
  const eligibleOnly = options.eligibleOnly === true;

  // Tokenı olmayan hesapları baştan elemek hem Firestore okumasını azaltır hem
  // de eski profillerde lastMiningStart alanı bulunmasa bile ilk-kazım
  // hatırlatmasının değerlendirilmesini sağlar.
  const cursorRef = db.collection("notification_scan_state").doc("daily_points_ready");
  const cursorSnap = await cursorRef.get();
  const cursor = cursorSnap.data() || {};
  // Resume at the next token/uid on the following run. Without a cursor the
  // first 400 accounts would monopolize every scheduled notification run.
  const query = db.collection("users")
    .where("pushToken", ">", "")
    .orderBy("pushToken", "asc")
    .orderBy(FieldPath.documentId(), "asc")
    .limit(limit);
  let pagedQuery = query;
  if (cursor.lastToken && cursor.lastUid) {
    pagedQuery = query.startAfter(cursor.lastToken, cursor.lastUid);
  }
  let querySnap = await pagedQuery.get();
  if (querySnap.empty && cursor.lastUid) {
    // Reached the end: begin a new scan from the first eligible account.
    querySnap = await query.get();
  }
  let sent = 0;
  let skipped = 0;
  let failed = 0;
  const writes = [];

  for (const doc of querySnap.docs) {
    const data = doc.data() || {};
    const token = String(data.pushToken || "").trim();
    const lastMining = intField(data, "lastMiningStart", 0);
    const notifiedFor = String(data.dailyPointsPushCampaignKey || "");
    const scheduledNotifiedFor = intField(data, "miningReadyNotifiedFor", 0);
    const lastReminderAt = intField(data, "miningReadyNotificationSentAt", 0);
    const createdAt = intField(data, "createdAt", 0);
    const neverMinedNotifiedAt = intField(data, "miningNeverStartedPushAt", 0);
    const isNeverMined = lastMining <= 0;
    const reminderDecision = getMiningReminderDecision({
      nowSeconds,
      lastMining,
      createdAt,
      readyAfterSeconds: DAILY_REWARD_SECONDS,
      firstReminderDelaySeconds: NEVER_MINED_REMINDER_DELAY_SECONDS,
      scheduledNotifiedFor,
      lastReminderAt,
      neverMinedNotifiedAt,
    });
    const isReadyNow = isNeverMined
      ? createdAt > 0 && nowSeconds - createdAt >= NEVER_MINED_REMINDER_DELAY_SECONDS
      : lastMining <= readyBefore;
    const shouldSend = force
      ? (!eligibleOnly || isReadyNow)
      : reminderDecision.eligible;

    if (!token || !shouldSend || (force && notifiedFor === campaignKey)) {
      skipped += 1;
      continue;
    }

    const deliveryKey = notificationDeliveryKey({
      force,
      campaignKey,
      type: reminderDecision.type,
      lastMining,
      createdAt,
      nowSeconds,
      readyAfterSeconds: DAILY_REWARD_SECONDS,
    });
    const claimed = await claimPushNotification({
      userRef: doc.ref,
      expectedToken: token,
      deliveryKey,
      campaignKey,
      force,
      nowSeconds,
    });
    if (!claimed) {
      skipped += 1;
      continue;
    }

    const lang = data.language || data.locale || data.deviceLocale || "en";
    const message = isNeverMined ? firstMiningMessage(lang) : miningReadyMessage(lang, data);

    try {
      await getMessaging().send({
        token,
        notification: message,
        data: {
          type: isNeverMined ? "first_mining_reminder" : "daily_points_ready",
          screen: "home",
          campaignKey,
          lastMiningStart: String(lastMining),
        },
        android: {
          priority: "high",
          notification: {
            channelId: "daily_points",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      const update = {
        dailyPointsPushCampaignKey: campaignKey,
        dailyPointsPushSentAt: FieldValue.serverTimestamp(),
        dailyPointsPushDeliveryKey: deliveryKey,
        dailyPointsPushClaimKey: FieldValue.delete(),
        dailyPointsPushClaimedAt: FieldValue.delete(),
      };
      if (!force) {
        if (isNeverMined) {
          update.miningNeverStartedPushAt = FieldValue.serverTimestamp();
        } else {
          update.miningReadyNotifiedFor = lastMining;
        }
        update.miningReadyNotificationSentAt = FieldValue.serverTimestamp();
      }
      writes.push(doc.ref.set(update, { merge: true }));
      sent += 1;
    } catch (error) {
      failed += 1;
      const code = String(error?.code || "");
      console.error("Daily points notification failed", doc.id, code, error?.message || error);
      writes.push(
        doc.ref.set(
          {
            dailyPointsPushLastErrorCode: code || "unknown",
            dailyPointsPushLastErrorAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        )
      );
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-argument")
      ) {
        writes.push(markInvalidPushToken(doc.id, token));
      } else {
        writes.push(releasePushNotificationClaim(doc.ref, deliveryKey));
      }
    }
  }

  await Promise.all(writes);

  if (!querySnap.empty) {
    const lastDoc = querySnap.docs[querySnap.docs.length - 1];
    await cursorRef.set({
      lastToken: String(lastDoc.data()?.pushToken || ""),
      lastUid: lastDoc.id,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  const result = {
    scanned: querySnap.size,
    sent,
    skipped,
    failed,
    campaignKey,
    force,
    eligibleOnly,
  };
  console.log("Daily points notifications", result);
  await db.collection("notification_runs").add({
    ...result,
    createdAt: FieldValue.serverTimestamp(),
  });
  return result;
}

async function claimPushNotification({
  userRef,
  expectedToken,
  deliveryKey,
  campaignKey,
  force,
  nowSeconds,
}) {
  const claimTtlSeconds = 10 * 60;
  return db.runTransaction(async (tx) => {
    const latest = await tx.get(userRef);
    if (!latest.exists) return false;
    const data = latest.data() || {};
    if (String(data.pushToken || "").trim() !== expectedToken) return false;
    if (String(data.dailyPointsPushDeliveryKey || "") === deliveryKey) return false;
    if (force && String(data.dailyPointsPushCampaignKey || "") === campaignKey) return false;

    const activeClaimKey = String(data.dailyPointsPushClaimKey || "");
    const claimedAt = intField(data, "dailyPointsPushClaimedAt", 0);
    if (
      activeClaimKey === deliveryKey &&
      claimedAt > 0 &&
      nowSeconds - claimedAt < claimTtlSeconds
    ) {
      return false;
    }

    tx.set(
      userRef,
      {
        dailyPointsPushClaimKey: deliveryKey,
        dailyPointsPushClaimedAt: nowSeconds,
      },
      { merge: true }
    );
    return true;
  });
}

async function releasePushNotificationClaim(userRef, deliveryKey) {
  await db.runTransaction(async (tx) => {
    const latest = await tx.get(userRef);
    if (!latest.exists) return;
    if (String(latest.data()?.dailyPointsPushClaimKey || "") !== deliveryKey) return;
    tx.set(
      userRef,
      {
        dailyPointsPushClaimKey: FieldValue.delete(),
        dailyPointsPushClaimedAt: FieldValue.delete(),
      },
      { merge: true }
    );
  });
}

async function markInvalidPushToken(uid, expectedToken) {
  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (tx) => {
    const latest = await tx.get(userRef);
    if (!latest.exists) return;
    if (String(latest.data()?.pushToken || "").trim() !== expectedToken) return;
    tx.set(
      userRef,
      {
        pushToken: FieldValue.delete(),
        pushTokenInvalidAt: FieldValue.serverTimestamp(),
        dailyPointsPushClaimKey: FieldValue.delete(),
        dailyPointsPushClaimedAt: FieldValue.delete(),
      },
      { merge: true }
    );
  });
}

function buildSystemPrompt(lang) {
  const isTr = String(lang || "").toLowerCase().startsWith("tr");
  if (isTr) {
    return [
      "Sen Candar Network uygulamasının yapay zeka asistanı Candar Ai'sın.",
      "Kullanıcılara günlük ödül, uygulama içi puan, boost, referans kodu ve premium paketler hakkında kısa ve net yardım et.",
      "Candar puanlarını yatırım, kripto varlık, para veya harici değeri olan bir ürün gibi tanımlama.",
      "Uygulama dışı konularda kibarca yönlendir. Günlük ödül ana ekrandaki günlük ödül alma butonuna dokunularak, 24 saatte bir alınır; otomatik verilmez. Referans başına oran +0.05 artar. Paket satın almak zorunlu değildir. Hesap bakiyesine veya canlı hesap bilgisine erişimin yok; bunları uydurma. En fazla 4 kısa cümle kullan.",
      "Türkçe yanıt ver.",
    ].join(" ");
  }

  return [
    "You are Candar Ai, the AI assistant for the Candar Network app.",
    "Help users with daily rewards, in-app points, boosts, referral codes, and premium packages.",
    "Never describe Candar points as an investment, crypto asset, money, or product with external value.",
    "Politely redirect off-topic questions. Daily rewards are claimed manually with the daily reward button on the home screen, once every 24 hours; they are not automatic. Each referral adds +0.05 to the rate. Purchases are optional. You cannot access live account data; never invent it. Use at most 4 short sentences.",
    "Reply in English.",
  ].join(" ");
}

exports.chat_send = onCall(
  {
    region: "europe-west1",
    secrets: [candarAiConfig],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const prompt = String(request.data?.prompt || "").trim();
    const lang = String(request.data?.lang || "tr_TR");
    if (!prompt) {
      throw new HttpsError("invalid-argument", "Mesaj boş olamaz.");
    }
    if (prompt.length > 1000) {
      throw new HttpsError("invalid-argument", "Mesaj çok uzun.");
    }

    const uid = request.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const userData = userSnap.exists ? userSnap.data() : {};
    const premium = isPremiumUser(userData);
    const dailyLimit = premium ? PREMIUM_DAILY_LIMIT : FREE_DAILY_LIMIT;

    const usageRef = userRef.collection("chatUsage").doc(todayKey());
    const usageSnap = await usageRef.get();
    const used = usageSnap.exists ? Number(usageSnap.data()?.count || 0) : 0;

    const bonusCredits = Math.max(0, intField(userData, "aiBonusCredits", 0));
    if (used >= dailyLimit && bonusCredits <= 0) {
      throw new HttpsError(
        "resource-exhausted",
        premium
          ? "Günlük premium mesaj limitiniz doldu."
          : "Günlük ücretsiz mesaj limitiniz doldu. Premium ile daha fazla mesaj gönderebilirsiniz."
      );
    }

    let answer;
    try {
      answer = await generateAnswer(JSON.parse(candarAiConfig.value()), buildSystemPrompt(lang), prompt);
    } catch (error) {
      // Never log credentials, prompts, or raw provider errors.
      const code = error.code === "resource-exhausted" ? "resource-exhausted" : "unavailable";
      console.warn("Candar Ai provider unavailable", { code });
      throw new HttpsError(code, code === "resource-exhausted"
        ? "Ücretsiz AI kapasitesi şu anda dolu. Mesaj hakkınız kullanılmadı; daha sonra tekrar deneyin."
        : "Candar Ai şu anda yanıt veremiyor. Mesaj hakkınız kullanılmadı; tekrar deneyin.");
    }

    const committedUsage = await db.runTransaction(async (tx) => {
      const [latestUserSnap, latestUsageSnap] = await Promise.all([
        tx.get(userRef),
        tx.get(usageRef),
      ]);
      const latestUser = latestUserSnap.data() || {};
      const latestUsed = latestUsageSnap.exists
        ? Math.max(0, Number(latestUsageSnap.data()?.count || 0))
        : 0;
      const latestPremium = isPremiumUser(latestUser);
      const latestLimit = latestPremium ? PREMIUM_DAILY_LIMIT : FREE_DAILY_LIMIT;
      const latestCredits = Math.max(0, intField(latestUser, "aiBonusCredits", 0));
      const useBonus = latestUsed >= latestLimit;
      if (useBonus && latestCredits <= 0) {
        throw new HttpsError("resource-exhausted", "Günlük AI hakkınız doldu.");
      }

      tx.set(
        usageRef,
        {
          count: latestUsed + 1,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      if (useBonus) {
        tx.set(
          userRef,
          {
            aiBonusCredits: FieldValue.increment(-1),
            lastAiBonusUsedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      return {
        premium: latestPremium,
        remaining: Math.max(0, latestLimit - latestUsed - 1),
        bonusCredits: latestCredits - (useBonus ? 1 : 0),
        usedBonusCredit: useBonus,
      };
    });

    return {
      answer,
      ...committedUsage,
    };
  }
);

exports.do_mining = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const uid = request.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const nowSeconds = Math.trunc(Date.now() / 1000);

    // Eski sürümler yalnızca referredBy kodunu yazıyordu. Üretim verisini
    // topluca değiştirmeden, kullanıcı bir sonraki kazımını yaptığında kodu
    // gerçek hesapla eşleştirip yeni atomik ödül akışına dahil ediyoruz.
    let legacyReferralCode = "";
    let legacyReferrerUid = "";
    const preMiningSnap = await userRef.get();
    if (preMiningSnap.exists) {
      const preMiningData = preMiningSnap.data() || {};
      legacyReferralCode = sanitizeReferralCode(preMiningData.referredBy);
      if (
        legacyReferralCode &&
        !String(preMiningData.referredByUid || "").trim() &&
        !Boolean(preMiningData.referralBonusApplied)
      ) {
        const legacyReferrerSnap = await db
          .collection("users")
          .where("referralCode", "==", legacyReferralCode)
          .limit(1)
          .get();
        if (!legacyReferrerSnap.empty && legacyReferrerSnap.docs[0].id !== uid) {
          legacyReferrerUid = legacyReferrerSnap.docs[0].id;
        }
      }
    }

    return db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
      }

      const data = snap.data() || {};
      const lastMining = intField(data, "lastMiningStart", 0);
      const waitLeft = DAILY_REWARD_SECONDS - (nowSeconds - lastMining);
      if (lastMining > 0 && waitLeft > 0) {
        throw new HttpsError(
          "failed-precondition",
          `Günlük ödül zaten alınmış. Yaklaşık ${Math.ceil(waitLeft / 3600)} saat sonra tekrar dene.`
        );
      }

      const today = Math.floor(nowSeconds / DAILY_REWARD_SECONDS);
      const storedRewardDay = intField(data, "lastRewardDay", -1);
      const previousRewardDay =
        storedRewardDay >= 0
          ? storedRewardDay
          : lastMining > 0
            ? Math.floor(lastMining / DAILY_REWARD_SECONDS)
            : -1;
      const currentStreak = Math.max(0, intField(data, "dailyStreak", 0));
      const currentShieldCount = Math.min(
        1,
        Math.max(0, intField(data, "streakShieldCount", 0))
      );
      const streakProgress = calculateStreakProgress({
        previousRewardDay,
        today,
        currentStreak,
        currentShieldCount,
      });
      const {
        dailyStreak,
        streakShieldCount,
        streakShieldUsed,
        streakShieldEarned,
      } = streakProgress;
      const streakBonus = streakBonusFor(dailyStreak);
      const rateComponents = calculateMiningRateComponents({
        ...data,
        dailyStreak,
        streakBonus,
      });
      const reward = rateComponents.totalRate;
      const currentPoints = numberField(data, "points", 0);
      const nextPoints = Number((currentPoints + reward).toFixed(2));
      const nextXp = Math.max(0, intField(data, "xp", 0)) + 10;
      const nextLevel = levelForXp(nextXp);
      const legacyReferralState = resolveLegacyReferralState({
        selfUid: uid,
        referredBy: data.referredBy,
        referredByUid: data.referredByUid,
        rewardStatus: data.referralRewardStatus,
        resolvedReferrerUid:
          sanitizeReferralCode(data.referredBy) === legacyReferralCode
            ? legacyReferrerUid
            : "",
      });
      const effectiveReferrerUid = legacyReferralState.referrerUid;
      const effectiveReferralStatus = legacyReferralState.rewardStatus;
      const referralDecision = getReferralQualificationDecision({
        dailyStreak,
        referredByUid: effectiveReferrerUid,
        rewardStatus: effectiveReferralStatus,
      });
      let referralRewardQualified = false;
      let referrerRef = null;
      if (referralDecision.qualifies && effectiveReferrerUid !== uid) {
        referrerRef = db.collection("users").doc(effectiveReferrerUid);
        const referrerSnap = await tx.get(referrerRef);
        referralRewardQualified = referrerSnap.exists;
      }
      const referralRewardPoints = referralRewardQualified ? REFERRAL_REWARD_POINTS : 0;
      const finalPoints = Number((nextPoints + referralRewardPoints).toFixed(2));

      console.log("Daily reward calculated", {
        baseRate: rateComponents.baseRate,
        boostMultiplier: rateComponents.boostMultiplier,
        refMultiplier: rateComponents.refMultiplier,
        rewardedMultiplier: rateComponents.rewardedMultiplier,
        streakMultiplier: rateComponents.streakMultiplier,
        totalRate: rateComponents.totalRate,
      });

      const miningUpdate = {
          points: finalPoints,
          lastMiningStart: nowSeconds,
          lastMiningAt: FieldValue.serverTimestamp(),
          nextMiningAt: Timestamp.fromMillis((nowSeconds + DAILY_REWARD_SECONDS) * 1000),
          lastMiningReward: reward,
          lastRewardDay: today,
          lastLoginDate: nowSeconds,
          dailyStreak,
          streakBonus,
          streakShieldCount,
          xp: nextXp,
          level: nextLevel,
          lastKnownMiningRate: reward,
          lastMiningRateComponents: rateComponents,
          miningReadyNotifiedFor: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
      };
      if (streakShieldUsed) {
        miningUpdate.streakShieldUsedAt = FieldValue.serverTimestamp();
      }
      if (streakShieldEarned) {
        miningUpdate.streakShieldEarnedAt = FieldValue.serverTimestamp();
      }
      if (legacyReferralState.canBackfill) {
        miningUpdate.referredByUid = effectiveReferrerUid;
        miningUpdate.referralRewardStatus = effectiveReferralStatus;
        miningUpdate.referralPendingAt = data.referralPendingAt || FieldValue.serverTimestamp();
      }
      if (referralRewardQualified) {
        miningUpdate.referralBonusApplied = true;
        miningUpdate.referralRewardStatus = "qualified";
        miningUpdate.referralQualifiedAt = FieldValue.serverTimestamp();
        miningUpdate.referralInviteeRewardPoints = REFERRAL_REWARD_POINTS;
        miningUpdate.referralInviterRewardPoints = REFERRAL_REWARD_POINTS;
      }
      tx.set(userRef, miningUpdate, { merge: true });
      if (referralRewardQualified && referrerRef) {
        tx.set(
          referrerRef,
          {
            points: FieldValue.increment(REFERRAL_REWARD_POINTS),
            referralCount: FieldValue.increment(1),
            lastReferralAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      return {
        ok: true,
        points: finalPoints,
        reward,
        rate: reward,
        rateComponents,
        dailyStreak,
        streakBonus,
        streakShieldCount,
        streakShieldUsed,
        streakShieldEarned,
        xp: nextXp,
        level: nextLevel,
        referralRewardQualified,
        referralRewardPoints,
        nextMiningAt: nowSeconds + DAILY_REWARD_SECONDS,
      };
    });
  }
);

exports.sync_achievements = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    const userRef = db.collection("users").doc(request.auth.uid);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Kullanıcı verisi bulunamadı.");
      }

      const data = snap.data() || {};
      const achievementIds = Array.isArray(data.achievements)
        ? data.achievements.map((value) => String(value))
        : [];
      const unlockedSet = new Set(achievementIds);
      const newlyUnlocked = [];

      for (const achievement of ACHIEVEMENT_DEFINITIONS) {
        if (!unlockedSet.has(achievement.id) && achievement.test(data)) {
          unlockedSet.add(achievement.id);
          newlyUnlocked.push({
            achievement: achievement.id,
            name: achievement.name,
            xp: achievement.xp,
            new: true,
          });
        }
      }

      if (newlyUnlocked.length === 0) {
        return {
          ok: true,
          unlocked: [],
          achievements: Array.from(unlockedSet),
          xp: Math.max(0, intField(data, "xp", 0)),
          level: Math.max(1, intField(data, "level", 1)),
        };
      }

      const bonusXp = newlyUnlocked.reduce((sum, item) => sum + item.xp, 0);
      const nextXp = Math.max(0, intField(data, "xp", 0)) + bonusXp;
      const nextLevel = levelForXp(nextXp);
      tx.set(
        userRef,
        {
          achievements: Array.from(unlockedSet),
          xp: nextXp,
          level: nextLevel,
          achievementsUpdatedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        ok: true,
        unlocked: newlyUnlocked,
        achievements: Array.from(unlockedSet),
        xp: nextXp,
        level: nextLevel,
      };
    });
  }
);

exports.verify_and_apply_boost = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: [appleIssuerId, appleKeyId, applePrivateKey, appleBundleId],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    return applyPurchaseToUser(request.auth.uid, request.data, false);
  }
);

exports.apply_premium = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: [appleIssuerId, appleKeyId, applePrivateKey, appleBundleId],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    return applyPurchaseToUser(request.auth.uid, request.data, true);
  }
);

// Client callbacks must never grant points or permanent boosts. Only the
// signed AdMob server-to-server callback can apply a rewarded boost.
exports.apply_rewarded_boost = onCall(
  { region: "europe-west1", timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    const attemptAt = Number(request.data?.attempt_at || 0);
    if (!Number.isSafeInteger(attemptAt) || attemptAt <= 0) {
      throw new HttpsError("invalid-argument", "Reklam denemesi eksik.");
    }
    const userSnap = await db.collection("users").doc(request.auth.uid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "Kullanıcı bulunamadı.");
    const data = userSnap.data() || {};
    const lastApplied = intField(data, "rewardedBoostLastAppliedAttemptAt", 0);
    if (lastApplied < attemptAt) {
      return { ok: false, error: "rewarded_boost_verification_pending" };
    }
    return {
      ok: true,
      idempotent: true,
      attempt_at: attemptAt,
      rewarded_multiplier: numberField(data, "rewardedBoostMultiplier", 1.0),
      total_rate: calculateMiningRate(data),
      daily_count: Math.max(0, intField(data, "rewardedBoostDailyCount", 0)),
      daily_limit: REWARDED_BOOST_DAILY_LIMIT,
    };
  }
);

exports.admob_ssv = onRequest(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB", cors: false },
  async (request, response) => {
    if (request.method !== "GET") {
      response.status(405).send("Method not allowed");
      return;
    }
    let reward;
    try {
      const keys = await fetchVerifyingKeys();
      reward = verifyCallback(request.originalUrl, keys);
    } catch (error) {
      if (error instanceof AdmobVerificationError) {
        response.status(403).send("Invalid callback");
      } else {
        console.error("AdMob verifier unavailable", { code: error?.code });
        response.status(503).send("Verification unavailable");
      }
      return;
    }

    const receiptRef = db.collection("admob_ssv_transactions").doc(reward.transactionId);
    try {
      if ((await receiptRef.get()).exists) {
        response.status(200).send("Already applied");
        return;
      }
      const applied = await applyRewardedBoostToUser(reward.uid, {
        attempt_at: reward.attemptAt,
      });
      if (!applied.ok) {
        response.status(403).send("Unrecognized reward attempt");
        return;
      }
      try {
        await receiptRef.create({
          uid: reward.uid,
          attemptAt: reward.attemptAt,
          adUnit: reward.adUnit,
          receivedAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (error?.code !== 6 && error?.code !== "already-exists") throw error;
      }
      response.status(200).send("OK");
    } catch (error) {
      console.error("AdMob reward processing failed", { code: error?.code });
      response.status(503).send("Temporary failure");
    }
  }
);

exports.reserve_rewarded_boost_attempt = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }
    return reserveRewardedBoostAttemptForUser(request.auth.uid);
  }
);

exports.sendMiningReadyNotifications = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    await sendDailyPointsNotifications({ campaignKey: "daily_points_ready" });
  }
);

function requireOwner(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  }
  const emailHash = sha256(String(request.auth.token?.email || "").trim().toLowerCase());
  if (request.auth.token?.email_verified !== true || !OWNER_EMAIL_HASHES.has(emailHash)) {
    throw new HttpsError("permission-denied", "Yönetici yetkisi gerekli.");
  }
}

exports.admin_get_overview = onCall(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    requireOwner(request);
    const [configSnap, totalUsersSnap] = await Promise.all([
      db.collection("config").doc("general").get(),
      db.collection("users").count().get(),
    ]);
    return {
      ok: true,
      miningRate: normalizeMiningRate(configSnap.data()?.mining_rate, 1.0),
      userCount: totalUsersSnap.data().count,
    };
  }
);

exports.admin_update_config = onCall(
  { region: "europe-west1", timeoutSeconds: 30, memory: "256MiB" },
  async (request) => {
    requireOwner(request);
    const rate = normalizeMiningRate(request.data?.miningRate, null);
    if (rate === null) {
      throw new HttpsError("invalid-argument", "Temel puan oranı 1 ile 5 arasında olmalı.");
    }
    await db.collection("config").doc("general").set({
      mining_rate: rate,
      updatedByUid: request.auth.uid,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, miningRate: rate };
  }
);

exports.send_daily_points_push_now = onCall(
  {
    region: "europe-west1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
    }

    requireOwner(request);

    const campaignKey = String(request.data?.campaignKey || `daily_points_${todayKey()}`);
    const limit = Number(request.data?.limit || MAX_NOTIFICATION_BATCH);
    const force = request.data?.force === true;
    return sendDailyPointsNotifications({ campaignKey, limit, force });
  }
);
