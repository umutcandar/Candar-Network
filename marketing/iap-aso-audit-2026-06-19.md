# Candar IAP + ASO Audit - 2026-06-19

## App Store Connect

- Created iOS app version `2.0.10` in `Prepare for Submission`.
- Fixed all first iOS IAP drafts from `Missing Metadata` to `Ready to Submit`:
  - `candar.ios.boost.basic.30d`
  - `candar.ios.boost.pro.30d`
  - `candar.ios.boost.ultra.30d`
  - `candar.ios.premium.30d`
- Added review screenshot for all four IAPs using the iOS boost/premium screenshot.
- Set/confirmed country availability where missing.
- Replaced risky IAP wording such as "mining boost" with safe English daily-points language.
- Attached all four Ready-to-Submit IAPs to iOS version `2.0.10`.
- Updated iOS `2.0.10` ASO fields:
  - Promotional Text: daily points, streak, friends, Candar AI.
  - What's New: daily points, boosts, referral flow, Candar AI, purchase setup.
  - Keywords: AI chat, points, streak, referral, network, community, daily, boost, premium, social, Candar.

## Google Play Console

- Confirmed default store listing language is `English (United States) - en-US`.
- Confirmed Play Store copy is English-first and uses safe positioning:
  - AI chat
  - daily points
  - streaks
  - referrals
  - leaderboard progress
  - no financial promises or guaranteed external value

## Review Submission Check

- App Store `Add for Review` validation reached the expected remaining blocker: `You must choose a build.`
- App Store version `2.0.10` is prepared with IAPs attached.
- Built and uploaded iOS archive `2.0.10` build `36` to App Store Connect.
- Xcode upload result: `Upload succeeded`; App Store Connect package state: processing.
- Upload warning: missing dSYM for `GodotApplePlugins.framework`; this is not a submission blocker, but it can reduce crash symbolication quality for that framework.
- App Store `2.0.10` page was refreshed after upload; build `36` was not selectable yet, so Apple processing was still effectively pending.
- TestFlight Build Uploads confirmed `Version 2.0.10, Build (36)` exists with status `Processing`.
- App Store `2.0.10` still needs build `36` to appear and be selected on the version page before full review submission can proceed.
- Google Play Publishing overview did not show a pending `Send for review` action during this check.
