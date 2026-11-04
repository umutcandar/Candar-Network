# Candar Network — App Store / Google Play refund reconciliation

## Scope and current state

Server-side refund handling has been implemented but is **not deployed** from
this draft pull request. No refund or entitlement claim below has been tested
against a real App Store Connect or Google Play Console account.

The existing app sells **30-day, one-time in-app products**, not auto-renewable
subscriptions. Current implementation tracks those one-time products only.

## What happens automatically

### Apple App Store Server Notifications V2

1. Configure **App Store Server Notifications V2** with this production and
   (if desired) sandbox callback URL:

   `https://europe-west1-candar-network-007.cloudfunctions.net/apple_store_refund_notification`

2. The Cloud Function accepts POST JSON with `signedPayload`. Only
   `REFUND` and `REVOKE` are processed.
3. The function extracts the transaction ID only as an **untrusted lookup
   hint**. It first locates a matching purchase in our own `purchase_events`
   ledger. Then it authenticates to Apple's **App Store Server API**
   `GET /inApps/v1/transactions/{transactionId}`, falling back to sandbox
   on 404.
4. It requires Apple's TLS-protected API response to confirm **bundle ID,
   product ID, transaction ID, and a nonzero `revocationDate`**.
   Only then does it atomically record the revocation and disable the matching
   currently active entitlement. Unknown and duplicate purchases are ignored.
5. The outer Apple JWS notification signature is **not independently verified**
   by this implementation. This is not an authorization gap for changing a
   purchase's state (the authenticated Apple API call is mandatory), but it
   leaves a potential request-flood/Apple API quota risk for *known*
   transactions. Add full signedPayload chain verification or WAF rate
   limiting before large-scale launch.

Already required Firebase Secrets for the App Store Server API:

- `APPLE_ISSUER_ID`
- `APPLE_KEY_ID`
- `APPLE_PRIVATE_KEY`
- `APPLE_BUNDLE_ID`

Each must be configured in the Firebase Functions project. The callback does
not log signed notifications, credentials or receipts.

### Google Play: Voided Purchases API sweep

The scheduled Cloud Function `reconcile_google_play_refunds` runs **once per
hour**, scanning the official Google Play `purchases.voidedpurchases.list`
endpoint with `type=0` (one-time products). It uses `startTime` and
`tokenPagination.nextPageToken`; progress is persisted at
`purchase_refund_scan_state/google_play`. Each scan overlaps earlier
results so retries and temporary delays do not lose events. Up to four pages
of at most 500 rows each are scanned per invocation, continuing next time.

**Google Play Console prerequisites**:

1. Enable and link the **Google Play Developer API** to the Firebase Google
   Cloud project `candar-network-007`.
2. Give the **Cloud Functions runtime service account** appropriate Play
   Console API access, including the permission for viewing financial
   information required by `purchases.voidedpurchases.list`.
3. Verify the server identity can successfully request the Voided Purchases
   API for application `com.candarnetwork.app`.
4. Deploy `reconcile_google_play_refunds` and monitor Cloud Scheduler/
   Cloud Functions logs. Do not attempt to execute on a client device.

Google Play refunds can precede a user's first Firebase purchase claim. To
prevent later grant, this flow stores two permanent `purchase_revocations`
markers: the SHA-256 hash of order ID (when available) and the SHA-256 hash of
the purchase token. Neither plaintext token nor customer identity is stored
in these markers. The original grant transaction reads these tombstones
atomically and refuses to apply canceled purchases.

Google may omit order IDs for some canceled purchases; the token-hash marker
still works. Duplicate refunds are idempotent. A partial quantity refund is
ignored: this app does not implement partial-unit purchase accounting.

**Limitations**: Google's Voided Purchases API provides only the last
approximately **30 days** of visibility, and a given refund can appear later.
The implementation starts with 29 days of history on first deploy and a
48-hour overlap on later scans, with a resumable cursor. Outages beyond the
available history require manual Play Console reconciliation. Orders refunded
without revocation may not appear in this API. Pub/Sub RTDN push delivery is
not configured; this is **hourly polling, not instant notification**.

## Data integrity

- `purchase_events/{eventId}` has `revoked`, `revokedAt`,
  `revocationSource`, `storeTokenHash` (Android) and the existing payment
  metadata.
- `users/{uid}` now contains server-owned
  `lastPremiumPurchaseEventId` and `lastBoostPurchaseEventId`. These
  identify **which specific purchase currently owns the benefit**.
- An older refund cannot disable a newer purchase. For historic purchases
  that predate these pointers, the code only deactivates a benefit if its
  exact receipt hash or original server timestamp matches the latest recorded
  user purchase.
- Premium is disabled and the purchased mining multiplier is reset to 1.
  Separate point-shop or referral entitlements are not revoked by mistake.
- A refund does **not retroactively debit points** that the user earned
  before the refund. That requires a separate explicit economy and fairness
  policy.

## Required acceptance tests before production

1. In a **staging/test Firebase project**, deploy Functions and Rules
   together with indexes. Confirm new purchases receive event pointers.
2. Apple sandbox: make a one-time purchase, confirm the exact event is
   recorded, initiate a sandbox refund/revocation, inspect webhook logs,
   `purchase_events.revoked` and the changed user entitlement.
3. Google internal testing: purchase both Premium and Boost, revoke through
   Play Console, check Voided Purchases API visibility (may be delayed), and
   confirm the hourly scan records both the event and tombstones.
4. Replay each store event; verify balances and entitlements do not change
   twice. Refund a **previous** product after buying a replacement and verify
   replacement access is preserved.
5. Refund before the Firebase grant; verify a later grant is denied.
6. Test a failure of the Apple Server API and a temporary Google Play 403/
   outage: no unverified revocation or client-local privilege is granted.
7. Inspect production deploy IAM, real device purchase/restore flows and
   separate refunds from purchases that are merely pending/canceled.

Code tests: `functions/purchase-refunds.test.js` and
`functions/purchase-refunds.integration.test.js` use deterministic
store/Firestore fakes. They are **not** tests of the live stores.

Official documentation:

- Apple: https://developer.apple.com/documentation/appstoreservernotifications/receiving-app-store-server-notifications
- Apple transaction lookup: https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info
- Google: https://developers.google.com/android-publisher/voided-purchases
- Google API: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases/list
