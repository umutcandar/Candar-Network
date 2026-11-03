# Candar Purchase Audit - 2026-06-19

## What I checked

- App Store Connect Monetization > Sales for app `6756212781`.
- App Store Connect Distribution > In-App Purchases for app `6756212781`.
- Firebase Cloud Functions logs for `verify_and_apply_boost` and `apply_premium`.
- IAP/backend code paths in `IAPManager.gd`, `market.gd`, `scripts/FirebaseClient.gd`, `global.gd`, and `functions/index.js`.

## Findings

- A `verify_and_apply_boost` callable request was logged on 2026-06-19 around 21:09 Turkey time. This means the x2 boost flow reached the backend with valid Firebase Auth.
- App Store Connect Sales still showed June 18 data with `Not Enough Data` for proceeds, paying users, and in-app purchases. A same-day June 19 purchase may not appear immediately in App Store analytics.
- App Store Connect In-App Purchases showed four iOS IAP drafts with `Missing Metadata`:
  - `candar.ios.boost.basic.30d`
  - `candar.ios.boost.pro.30d`
  - `candar.ios.boost.ultra.30d`
  - `candar.ios.premium.30d`
- The Basic x2 detail page showed the product under draft state, and availability had a `Removed from Sale` signal. Treat this as a critical iOS monetization blocker until the IAPs are metadata-complete, available, attached to an editable iOS version, and submitted/reviewed.
- Current backend purchase application accepts a non-empty receipt/proof and writes the entitlement. It does not yet perform Apple/Google server-side receipt validation.

## Actions Taken

- Added safe purchase observability to `functions/index.js`.
- Deployed `verify_and_apply_boost` and `apply_premium` to Firebase project `candar-network-007`.
- New purchases now write aggregate-safe records to `purchase_events` with product, platform, premium/boost, multiplier, timestamps, and no receipt/token.
- New purchases now log a safe `Purchase applied` line without exposing receipt/token.
- Updated heartbeat automation `candar-download-watch` into `Candar growth, store ranking and purchase agent` so each run checks purchases/IAP in addition to downloads, ASO, retention, and social growth.

## Next Best Fixes

- Complete iOS IAP metadata and availability for all four products in App Store Connect.
- Attach the first IAPs to the next editable iOS version and submit them with the app version after explicit approval.
- Add real Apple/Google server-side purchase validation when store credentials/API access are available.
- Recheck App Store Sales after analytics delay; use store reports for revenue confirmation and backend logs for entitlement confirmation.

## 2026-06-20 Boost x2 Fix

- Fixed the backend boost rate path in `functions/index.js` so iOS product IDs are normalized safely and x2/x3/x7 multipliers are applied consistently.
- Added rate component tracking to purchase and daily claim responses: base rate, boost multiplier, referral multiplier, rewarded multiplier, and total daily points.
- Added one-time same-day boost catch-up logic: if a user claims daily points and then buys a boost in the same claim window, the backend applies only the positive delta once.
- Deployed `verify_and_apply_boost` and `do_mining` to Firebase project `candar-network-007`.
- Corrected the latest x2 purchase aggregate state without exposing UID/email/receipt: `currentMultiplier=2`, `mining.active_multiplier=2`, `lastKnownMiningRate=3.26`, `lastMiningReward=3.26`, `points=12.03`, one-time catch-up delta `+0.45`.
- Fixed app-side Firestore number parsing for `currentMultiplier` and refreshed the Market UI after purchase so the user sees the new daily points total.
- Built and uploaded iOS `2.0.10 (37)` with the boost fix. App Store Connect accepted the upload and the package is processing.
- Fixed iOS build hygiene while shipping: narrowed Xcode framework/library search paths so old `.xcarchive` folders cannot poison future builds, and restored iPhone+iPad `UIDeviceFamily` support required by Apple.
