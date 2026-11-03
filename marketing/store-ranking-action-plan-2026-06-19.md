# Store Ranking Action Plan - 2026-06-19

## Problems We Are Fixing

- Low install velocity: social views are not turning into store installs fast enough.
- Low first open: Google Play shows 17 device acquisitions but only 7 first opens.
- Weak retention: Google Play 7-day retention is currently 0.
- Weak keyword positioning: branded search is easier than broader searches like AI chat, daily points, referral network, social app, and leaderboard.
- Missing rating/review proof: early real reviews are needed for trust and conversion.

## Actions Implemented In App Code

- Added one-time `first_open` analytics tracking on install.
- Added Firestore engagement metadata on app open:
  - `firstAppOpenAt`
  - `firstOpenDay`
  - `lastAppOpenAt`
  - `lastOpenDay`
  - `appOpenCount`
  - `retainedDay1`
  - `retainedDay7`
  - `returningSessionAt`
- Added a one-time Home prompt when tutorial is not shown:
  - collect daily points
  - return tomorrow for streak
  - share referral code from Profile
- Improved review/rating flow:
  - iOS native `SKStoreReviewController` watcher added.
  - Android in-app review plugin is attempted first.
  - Android fallback opens Google Play listing if no review plugin exists.
  - No fake reviews, no paid reviews, no reward-for-review flow.

## Google Play ASO Draft

App name:
```text
Candar Network
```

Short description:
```text
Daily points, AI chat, referrals, streaks, and leaderboard progress.
```

Full description:
```text
Candar Network is a social points and AI companion app built around daily progress.

Open the app every day, collect Candar points, keep your streak alive, invite friends with your referral code, and track your leaderboard progress. Candar AI helps you explore the app, get quick answers, and plan your next move inside the community.

What you can do:
- Collect daily Candar points
- Build a daily streak
- Share your referral code with friends
- Track your referral network and leaderboard progress
- Use Candar AI for in-app help and ideas
- Explore boost and Premium options for the app experience

Transparency:
Candar Network is an app-based points and community experience. It does not offer income, investment returns, cryptocurrency mining, cash rewards, or guaranteed financial value.
```

Keyword targets:
```text
daily points, AI chat, referral network, streaks, leaderboard, social app, community, rewards app, productivity streak
```

## App Store ASO Draft

Name:
```text
Candar Network
```

Subtitle:
```text
AI chat, points, referrals
```

Promotional text:
```text
Collect daily points, keep your streak alive, invite friends, and use Candar AI inside one community app.
```

Keyword field:
```text
ai,chat,points,streak,referral,network,leaderboard,community,social,daily,boost
```

Description:
```text
Candar Network brings daily points, referral networking, leaderboard progress, and Candar AI into one mobile experience.

Open the app daily to collect Candar points and keep your streak alive. Share your referral code with friends, follow your progress on the leaderboard, and use Candar AI for quick in-app help and ideas.

Features:
- Daily Candar points
- Streak progress
- Referral code and invite flow
- Leaderboard tracking
- Candar AI assistant
- Boost and Premium options for the app experience

Candar Network is an app-based points and community experience. It does not offer income, investment returns, cryptocurrency mining, cash rewards, or guaranteed financial value.
```

## Screenshot Caption Targets

1. Secure sign in and start your Candar journey.
2. Collect daily points and keep your streak alive.
3. Share your referral code and grow your network.
4. Track progress on the leaderboard.
5. Ask Candar AI for in-app help and ideas.

## Next Console Actions

- Google Play: update short description and full description as a draft, then run a Store Listing Experiment on short description.
- Google Play: check Android vitals; fix any crash/ANR before scaling ads.
- App Store: update subtitle, promotional text, keywords, and description on the next editable version.
- App Store: create Product Page Optimization variants for screenshots/captions.
- Both stores: ask the first real active users to review from inside the app after successful daily point collection, without rewards or pressure.

## Do Not Do

- Do not buy reviews or ratings.
- Do not ask for reviews in exchange for points, boosts, or money.
- Do not promise income, returns, token value, cash rewards, or financial gain.
- Do not stuff irrelevant keywords into the listing.

## Console Actions Applied - 2026-06-19

- Google Play Turkish default listing was saved as draft.
  - Short description:
    ```text
    Günlük puan, AI sohbet, referans ağı, seri ve liderlik.
    ```
  - Full description was rewritten around safe keywords: günlük puan, AI sohbet, referans ağı, seri, liderlik, Candar AI, community points experience.
  - Risky wording removed from the main listing: mining, kripto, madencilik, gelir, yatırım, nakit ödül, finansal kazanç.
- Google Play English (United States) listing was saved as draft.
  - Short description:
    ```text
    AI chat, daily points, streaks, referrals, and leaderboard progress.
    ```
  - Full description was rewritten around global ASO targets: AI chat, daily points, streaks, referrals, leaderboard, community.
  - Risky wording removed: rewards, cryptocurrency mining, income, investment returns, financial gain.
- App Store Connect iOS version `2.0.9` is `Ready for Distribution`; metadata fields are disabled. Apply App Store ASO copy on the next editable iOS version.

## Language Priority

- Primary growth language: English (United States).
- Reason: highest global keyword reach for `AI chat`, `daily points`, `referral network`, `streaks`, `leaderboard`, and social ad traffic.
- Turkish remains important for local trust, but global acquisition should use English-first store copy, social posts, and ad creatives.
