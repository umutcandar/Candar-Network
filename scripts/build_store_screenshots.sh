#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW="$ROOT/store-screenshots/raw"
PLAY="$ROOT/store-screenshots/play"
IOS="$ROOT/store-screenshots/ios"
TMP="$ROOT/store-screenshots/tmp"

FONT="/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
LOGO="$ROOT/assets/candar_logo_192x192.png"

mkdir -p "$PLAY" "$IOS" "$TMP"
rm -f "$PLAY"/*.png "$IOS"/*.png "$TMP"/*.png

make_one() {
  local src="$1"
  local out="$2"
  local title="$3"
  local subtitle="$4"
  local crop="$TMP/crop-$(basename "$out")"
  local phone="$TMP/phone-$(basename "$out")"

  magick "$src" -crop 920x1800+980+0 +repage -resize 930x1819 "$crop"
  magick "$crop" \
    \( -size 930x1819 xc:none -fill white -draw 'roundrectangle 0,0 929,1818 34,34' \) \
    -alpha off -compose CopyOpacity -composite "$phone"

  magick -size 1290x2796 gradient:'#0f172a-#1e293b' \
    -fill 'rgba(245,158,11,0.14)' -draw 'circle 1080,170 1080,760' \
    \( "$LOGO" -resize 132x132 \) -geometry +96+98 -compose over -composite \
    -font "$BOLD" -fill '#f8fafc' -pointsize 84 -interline-spacing -4 -gravity northwest -annotate +96+260 "$title" \
    -font "$FONT" -fill '#cbd5e1' -pointsize 38 -interline-spacing 4 -gravity northwest -annotate +98+475 "$subtitle" \
    -fill 'rgba(0,0,0,0.28)' -draw 'roundrectangle 145,730 1115,2589 44,44' \
    \( "$phone" \) -geometry +165+730 -compose over -composite \
    "$out"
}

make_one "$RAW/01-home.png" "$PLAY/01-daily-streak.png" "Build your daily streak" "Check in, collect Candar points, and keep your progress moving."
make_one "$RAW/03-profile.png" "$PLAY/02-referral-network.png" "Grow your network" "Share your code, reach milestones, and climb the leaderboard."
make_one "$RAW/04-ai.png" "$PLAY/03-candar-ai.png" "Ask Candar AI" "Get quick help for daily goals, referrals, and boosts."
make_one "$RAW/02-market.png" "$PLAY/04-boost-premium.png" "Choose your boost" "Unlock faster in-app progress or a cleaner Premium experience."
make_one "$RAW/00-login.png" "$PLAY/05-create-profile.png" "Start in seconds" "Create your profile with email and an optional referral code."

for f in "$PLAY"/*.png; do
  base="$(basename "$f")"
  magick "$f" -resize 1284x2778! "$IOS/$base"
done

echo "Created Play screenshots in $PLAY"
echo "Created iOS screenshots in $IOS"
