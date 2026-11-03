# Conversion Audit - 2026-06-19

## What Looks Broken

The campaign is getting attention, but the funnel is not optimized for installs.

- Meta Ads Manager shows active campaigns optimized for `Landing page view` and `Instagram profile visit`, not app installs.
- Facebook Ad Centre shows 706 reach, 146 post engagements, 11 link clicks, and 11 landing page views in the last 60 days.
- X pinned post analytics is still tiny: 1 view, 9 engagements, 5 detail expands, 2 profile visits, 0 link clicks.
- TikTok Studio shows 1.5K video views and 25 profile views in the last 7 days, but the profile has no direct download link visible in Studio.
- Instagram had a major bio-link issue earlier: `candarnetwok.com` was visible. It now shows `candarnetwork.com`, but still points to the homepage instead of a tracked download page.
- Instagram web does not allow editing profile links; it says links can only be edited from the mobile app.
- Meta Ads Manager shows a crypto-ads verification warning. Words like `mine`, `mining`, `earn`, `coin`, and `kazim` can push the account into crypto/financial ad review.

## Fixes Applied

- Added a dedicated download funnel at `/download`.
- Deployed Firebase Hosting successfully.
- Verified live URL:
  `https://candarnetwork.com/download?src=instagram_bio&utm_medium=social&utm_campaign=urgent_fix&utm_content=bio_link`
- Updated the X profile website link to:
  `https://candarnetwork.com/download?src=x_profile&utm_medium=social&utm_campaign=urgent_fix`
- Added a tracked reply under the promoted X post with 30.3K views:
  `https://candarnetwork.com/download?src=x_promoted_reply&utm_medium=social&utm_campaign=urgent_fix`
- The page creates tracked store links:
  - iOS: App Store link with `ct=<source>_<campaign>`
  - Android: Google Play link with encoded `referrer=utm_source...`
- The page sends GTM/dataLayer events:
  - `download_page_view`
  - `store_click`

## Immediate Manual Fixes

Instagram mobile app:
Set website link to:
`https://candarnetwork.com/download?src=instagram_bio&utm_medium=social&utm_campaign=urgent_fix`

TikTok profile:
If website link is available, set it to:
`https://candarnetwork.com/download?src=tiktok_bio&utm_medium=social&utm_campaign=urgent_fix`

Facebook page:
Use:
`https://candarnetwork.com/download?src=facebook_page&utm_medium=social&utm_campaign=urgent_fix`

X profile/pinned post:
Use:
`https://candarnetwork.com/download?src=x_profile&utm_medium=social&utm_campaign=urgent_fix`

Promoted X post:
Tracked reply is already live under:
`https://x.com/CandarNetwork/status/2068007591335051656`

## Ad Strategy Change Needed

Do not scale current engagement/profile-visit ads.

Next paid campaign should be optimized for app installs or store/download intent, not profile visits, video views, or engagement.

Safe ad language:
```text
Candar Network is live on iOS and Android.
Collect daily points, build your referral network, and use Candar AI inside the app.
Download now and start your daily streak.

No financial promises. App-based points experience only.
```

Avoid in ads:
`earn`, `money`, `income`, `mining`, `coin`, `kazim`, `reward system`, `share and earn`.

## Next Metrics To Watch

- Landing page views to `/download`
- `store_click` events by source
- Google Play first opens
- App Store first-time downloads
- Firebase new users and DAU
- Cost per store click
- Cost per first open
