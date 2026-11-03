# Candar Notification Audit - 2026-06-19

## Goal

Send a safe daily-points reminder to users so they return to the app and collect daily points.

## Message Copy

Turkish:
- Title: `Günlük puanların hazır`
- Body: `Candar Network'e dön, günlük puanlarını topla ve serini koru.`

English:
- Title: `Daily points are ready`
- Body: `Open Candar Network, collect your daily points, and keep your streak alive.`

The copy avoids financial promises and risky words such as mining, money, income, profit, and returns.

## Actions Taken

- Updated `functions/index.js` notification copy from mining/rate language to daily points/streak language.
- Added `sendDailyPointsNotifications()` shared sender logic.
- Updated scheduled `sendMiningReadyNotifications` to use the safer daily-points sender.
- Added callable `send_daily_points_push_now` for owner-triggered manual sends.
- Deployed both functions to Firebase project `candar-network-007`.
- Forced the Cloud Scheduler job `firebase-schedule-sendMiningReadyNotifications-europe-west1` to run from Google Cloud Console.

## Result

The forced run executed, but FCM delivery did not succeed:

- Scanned: 363 user documents
- Skipped: 361
- Sent: 0
- Failed: 2
- Error: `messaging/third-party-auth-error`

This points to Firebase Cloud Messaging third-party credential configuration, most likely iOS/APNs auth setup for the existing push tokens. Until that is fixed, push notifications will not reliably reach users.

## Next Fix

- In Firebase Console, configure Apple APNs Auth Key for the iOS app.
- Required Apple-side values: APNs `.p8` key file, Key ID, Team ID, and app bundle id.
- After APNs/FCM credentials are fixed, run the scheduler again or call `send_daily_points_push_now` with a new campaign key.
