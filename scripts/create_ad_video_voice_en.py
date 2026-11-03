from pathlib import Path
import json
import urllib.request
import urllib.error
import subprocess
import sys

from PIL import Image
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import scripts.create_ad_video_voice as ad


OUT_DIR = ROOT / "marketing"
OUT_VIDEO = OUT_DIR / "candar_reels_ad_voice_32s_openai_en.mp4"
OUT_SILENT = OUT_DIR / "candar_reels_ad_voice_32s_en_silent.mp4"
OUT_AUDIO = OUT_DIR / "candar_reels_ad_voice_32s_openai_en_nova.mp3"
OUT_STORY = OUT_DIR / "candar_reels_ad_voice_32s_en_storyboard.txt"


EN_SCENES = [
    {
        "dur": 3.5,
        "kind": "hero",
        "kicker": "CANDAR NETWORK",
        "title": "Mining experience in your pocket",
        "body": "Collect daily points, track your rate, grow your network.",
        "subtitle": "Mining experience in your pocket",
        "voice": "With Candar Network, the mining experience is right in your pocket.",
        "hero_badge": "Track your daily mining rate",
    },
    {
        "dur": 4.2,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/02-daily-points.png",
        "kicker": "DAILY MINING",
        "title": "Track points and rate in one screen",
        "body": "Daily rewards, Candar coin progress, and your mining rate are clear.",
        "subtitle": "Daily points plus your personal mining rate",
        "voice": "Collect your daily points and track your Candar coin progress and personal mining rate in one screen.",
    },
    {
        "dur": 4.6,
        "kind": "market_packages",
        "kicker": "CANDAR MARKET",
        "title": "Boost packages, clearly detailed",
        "body": "Basic x2, Pro x3, and Ultra x7 mining speed options.",
        "subtitle": "Market: Basic x2, Pro x3, Ultra x7",
        "voice": "In Candar Market, compare Basic x2, Pro x3, and Ultra x7 boost packages.",
        "market_rows": [
            ("Boost Basic", "x2", "30 days - x2 mining speed", "1.49$", (255, 166, 33, 255)),
            ("Boost Pro", "x3", "30 days - x3 mining speed", "1.99$", (91, 96, 255, 255)),
            ("Boost Ultra", "x7", "30 days - x7 mining speed", "2.99$", (80, 220, 184, 255)),
        ],
        "market_note": "Market: package name, duration, multiplier, and price in one view.",
    },
    {
        "dur": 4.9,
        "kind": "market_calc",
        "kicker": "BOOST CALCULATOR",
        "title": "See your rate before you boost",
        "body": "Referral and ad boosts show your estimated daily result.",
        "subtitle": "Referrals plus ad boost equals your own mining rate",
        "voice": "The boost calculator shows how referrals and ad boosts can change your daily mining rate before you choose.",
        "calc_copy": {
            "title": "Boost Calculator",
            "current": "Current: 3.85 / day",
            "referral": "Referrals: 7  ·  x1.35",
            "ad": "Ad boost: x1.10",
            "values": [("Basic x2", "2.97 / day"), ("Pro x3", "4.46 / day"), ("Ultra x7", "10.40 / day")],
        },
        "calc_pills": ["Referrals x1.35", "Ad boost x1.10", "Ultra x7 = 10.40/day"],
    },
    {
        "dur": 3.8,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/03-referral-network.png",
        "kicker": "REFERRALS",
        "title": "Invite more, grow your rate",
        "body": "Your mining rate can grow personally with your network.",
        "subtitle": "Add referrals, grow your mining rate",
        "voice": "Add referrals and your mining speed can grow with your own network.",
    },
    {
        "dur": 3.8,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/04-boost-premium.png",
        "kicker": "AD BOOST",
        "title": "Watch an ad, earn extra rate",
        "body": "When a video is available, your reward supports your rate.",
        "subtitle": "Watch ads, earn extra mining rate",
        "voice": "Watch rewarded ads and earn extra rate for your mining experience.",
    },
    {
        "dur": 4.0,
        "kind": "ai_full",
        "kicker": "CANDAR AI",
        "title": "Candar AI stays in full view",
        "body": "Prompt chips, answer area, and message box stay visible.",
        "subtitle": "Candar AI: ask, write, move faster",
        "voice": "Use Candar AI to ask questions, plan your strategy, and move faster.",
    },
    {
        "dur": 3.2,
        "kind": "cta",
        "kicker": "JOIN NOW",
        "title": "Candar Network",
        "body": "Available on the App Store and Google Play.",
        "subtitle": "Download. Collect points. Grow your mining.",
        "voice": "Candar Network is available on the App Store and Google Play. Download, collect points, and grow your mining.",
        "cta_note": "In-app points experience.",
    },
]


def configure_english_output() -> None:
    ad.SCENES = EN_SCENES
    ad.STARTS = ad.starts()
    ad.TOTAL = sum(scene["dur"] for scene in ad.SCENES)
    ad.OUT_VIDEO = OUT_VIDEO
    ad.OUT_SILENT = OUT_SILENT
    ad.OUT_AUDIO = OUT_AUDIO
    ad.OUT_STORY = OUT_STORY


def assets() -> tuple[Image.Image, dict[str, Image.Image]]:
    logo = Image.open(ROOT / "assets/logoyazisiz.png").convert("RGBA")
    prepared = {
        str(ROOT / "store-screenshots/play/02-daily-points.png"): ad.phone_image(ROOT / "store-screenshots/play/02-daily-points.png", 1068),
        str(ROOT / "store-screenshots/play/03-referral-network.png"): ad.phone_image(ROOT / "store-screenshots/play/03-referral-network.png", 1068),
        str(ROOT / "store-screenshots/play/04-boost-premium.png"): ad.phone_image(ROOT / "store-screenshots/play/04-boost-premium.png", 1068),
        "market_packages": ad.screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 986, (0, 104, 2880, 720), 34),
        "market_full": ad.screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 936, (0, 0, 2880, 910), 30),
        "market_calc": ad.screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 936, (0, 720, 2880, 1148), 30),
        "ai_full": ad.screenshot_card(ROOT / "store-screenshots/raw/04-ai.png", 982, None, 34),
    }
    return logo, prepared


def read_openai_key() -> str:
    env_key = Path("/tmp/candar_openai_key.txt")
    if env_key.exists():
        return env_key.read_text().strip()
    result = subprocess.run(
        ["firebase", "functions:secrets:access", "OPENAI_API_KEY", "--project", "candar-network-007"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def render_openai_audio() -> None:
    text = (
        "With Candar Network, the mining experience is right in your pocket. "
        "Collect daily points and track Candar coin progress and your personal mining rate in one screen. "
        "In Candar Market, compare Basic x2, Pro x3, and Ultra x7 boost packages. "
        "The boost calculator shows how referrals and ad boosts can change your daily rate before you choose. "
        "Add referrals, watch rewarded ads, and grow your mining rate. "
        "Use Candar AI to ask questions, plan your strategy, and move faster. "
        "Candar Network is available on the App Store and Google Play. Download, collect points, and grow your mining."
    )
    body = {
        "model": "gpt-4o-mini-tts",
        "voice": "nova",
        "input": text,
        "instructions": "Speak as a professional female English app advertisement voiceover. Sound natural, polished, warm, confident, and energetic for TikTok or Instagram Reels. Do not sound robotic.",
        "response_format": "mp3",
        "speed": 1.18,
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/audio/speech",
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {read_openai_key()}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            OUT_AUDIO.write_bytes(response.read())
    except urllib.error.HTTPError as error:
        print(error.read().decode("utf-8", errors="replace")[:1200])
        raise


def mux_audio() -> None:
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-i",
            str(OUT_SILENT),
            "-i",
            str(OUT_AUDIO),
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-af",
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            "-movflags",
            "+faststart",
            str(OUT_VIDEO),
        ],
        check=True,
    )


def write_storyboard() -> None:
    lines = [
        "Candar Network Reels/TikTok ad - English OpenAI voice version",
        "Format: 1080x1920, H.264, 30fps",
        "Audio: OpenAI nova English female-style voice + English subtitles",
        "",
        "Narration:",
        " ".join(scene["voice"] for scene in EN_SCENES),
        "",
        "Scenes:",
    ]
    for start, scene in zip(ad.STARTS, ad.SCENES):
        lines.append(f"{start:04.1f}s - {start + scene['dur']:04.1f}s: {scene['kicker']} / {scene['title']} / {scene['subtitle']}")
    OUT_STORY.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    configure_english_output()
    logo, prepared_assets = assets()
    ad.render_video(logo, prepared_assets)
    render_openai_audio()
    mux_audio()
    write_storyboard()
    print(OUT_VIDEO)
    print(OUT_STORY)


if __name__ == "__main__":
    main()
