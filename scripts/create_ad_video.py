from pathlib import Path
import math

import imageio.v2 as imageio
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "marketing"
OUT_VIDEO = OUT_DIR / "candar_reels_ad_15s.mp4"
OUT_STORY = OUT_DIR / "candar_reels_ad_15s_storyboard.txt"

W, H = 1080, 1920
FPS = 30


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Helvetica.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


FONT_HUGE = font(92, True)
FONT_TITLE = font(70, True)
FONT_SUB = font(42, True)
FONT_BODY = font(34, False)
FONT_SMALL = font(28, True)


def ease(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - pow(1 - t, 3)


def draw_center(draw: ImageDraw.ImageDraw, text: str, y: int, fnt, fill, max_width=930, line_gap=10):
    words = text.split()
    lines = []
    cur = ""
    for word in words:
        cand = word if not cur else cur + " " + word
        if draw.textbbox((0, 0), cand, font=fnt)[2] <= max_width:
            cur = cand
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    total = sum(draw.textbbox((0, 0), line, font=fnt)[3] - draw.textbbox((0, 0), line, font=fnt)[1] for line in lines)
    total += line_gap * max(0, len(lines) - 1)
    yy = y - total // 2
    for line in lines:
        box = draw.textbbox((0, 0), line, font=fnt)
        x = (W - (box[2] - box[0])) // 2
        draw.text((x, yy), line, font=fnt, fill=fill)
        yy += (box[3] - box[1]) + line_gap


def draw_left_wrapped(draw: ImageDraw.ImageDraw, text: str, x: int, y: int, fnt, fill, max_width=900, line_gap=8):
    words = text.split()
    lines = []
    cur = ""
    for word in words:
        cand = word if not cur else cur + " " + word
        if draw.textbbox((0, 0), cand, font=fnt)[2] <= max_width:
            cur = cand
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    yy = y
    for line in lines:
        draw.text((x, yy), line, font=fnt, fill=fill)
        box = draw.textbbox((0, 0), line, font=fnt)
        yy += (box[3] - box[1]) + line_gap
    return yy


def rounded_rect_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def phone_image(path: Path, height: int = 1180) -> Image.Image:
    img = Image.open(path).convert("RGB")
    ratio = height / img.height
    size = (int(img.width * ratio), height)
    img = img.resize(size, Image.Resampling.LANCZOS)
    radius = 56
    mask = rounded_rect_mask(size, radius)

    shadow = Image.new("RGBA", (size[0] + 90, size[1] + 90), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([45, 45, size[0] + 45, size[1] + 45], radius=radius + 10, fill=(0, 0, 0, 135))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))

    phone = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    phone.alpha_composite(shadow, (0, 0))
    frame = Image.new("RGBA", size, (12, 18, 31, 255))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, outline=(255, 178, 71, 225), width=5)
    frame.paste(img.convert("RGBA"), (0, 0), mask)
    phone.alpha_composite(frame, (45, 45))
    return phone


def background(tone: float) -> Image.Image:
    top = np.array([7, 14, 29], dtype=np.float32)
    mid = np.array([13, 35, 45], dtype=np.float32)
    bot = np.array([33, 20, 47], dtype=np.float32)
    y = np.linspace(0, 1, H)[:, None]
    grad = np.where(y < 0.55, top * (1 - y / 0.55) + mid * (y / 0.55), mid * (1 - (y - 0.55) / 0.45) + bot * ((y - 0.55) / 0.45))
    arr = np.repeat(grad[:, None, :], W, axis=1)

    xgrid, ygrid = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    glow1 = np.exp(-((xgrid + 0.65 - 0.2 * math.sin(tone)) ** 2 + (ygrid + 0.55) ** 2) * 3.0)
    glow2 = np.exp(-((xgrid - 0.7) ** 2 + (ygrid - 0.72 + 0.15 * math.cos(tone)) ** 2) * 4.0)
    arr += glow1[..., None] * np.array([58, 142, 138]) * 0.32
    arr += glow2[..., None] * np.array([255, 168, 54]) * 0.22
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB").convert("RGBA")


def pill(draw, text, x, y, fill=(255, 178, 71, 255), text_fill=(20, 22, 28, 255)):
    pad_x, pad_y = 22, 10
    box = draw.textbbox((0, 0), text, font=FONT_SMALL)
    ww, hh = box[2] - box[0] + pad_x * 2, box[3] - box[1] + pad_y * 2
    draw.rounded_rectangle([x, y, x + ww, y + hh], radius=hh // 2, fill=fill)
    draw.text((x + pad_x, y + pad_y - 2), text, font=FONT_SMALL, fill=text_fill)


SCENES = [
    {
        "start": 0.0,
        "dur": 2.2,
        "img": None,
        "kicker": "CANDAR NETWORK",
        "title": "Günlük puan deneyimini cebine al",
        "body": "Giriş yap, puanını topla, ağını büyüt.",
    },
    {
        "start": 2.2,
        "dur": 2.6,
        "img": ROOT / "store-screenshots/play/01-secure-sign-in.png",
        "kicker": "GÜVENLİ GİRİŞ",
        "title": "Apple ve Google ile hızlı başla",
        "body": "Hesabını saniyeler içinde aç.",
    },
    {
        "start": 4.8,
        "dur": 2.6,
        "img": ROOT / "store-screenshots/play/02-daily-points.png",
        "kicker": "GÜNLÜK PUAN",
        "title": "Her gün puanını topla",
        "body": "Kazım oranını takip et, ilerlemeni gör.",
    },
    {
        "start": 7.4,
        "dur": 2.5,
        "img": ROOT / "store-screenshots/play/03-referral-network.png",
        "kicker": "REFERANS AĞI",
        "title": "Davet et, oranını büyüt",
        "body": "Referansların puan deneyimini güçlendirsin.",
    },
    {
        "start": 9.9,
        "dur": 2.4,
        "img": ROOT / "store-screenshots/play/04-boost-premium.png",
        "kicker": "BOOST & PREMIUM",
        "title": "Ekstra güçlendirmeler",
        "body": "Market üzerinden avantajlarını yönet.",
    },
    {
        "start": 12.3,
        "dur": 2.3,
        "img": ROOT / "store-screenshots/play/05-candar-ai.png",
        "kicker": "CANDAR AI",
        "title": "Sor, yaz, hızlan",
        "body": "Uygulama içi yapay zeka yardımcın yanında.",
    },
    {
        "start": 14.6,
        "dur": 1.6,
        "img": None,
        "kicker": "ŞİMDİ KATIL",
        "title": "Candar Network",
        "body": "App Store ve Google Play'de.",
    },
]


def scene_at(t):
    for i, scene in enumerate(SCENES):
        if scene["start"] <= t < scene["start"] + scene["dur"]:
            return i, scene, (t - scene["start"]) / scene["dur"]
    return len(SCENES) - 1, SCENES[-1], 1.0


def make_frame(t: float, phones, logo) -> np.ndarray:
    idx, scene, p = scene_at(t)
    frame = background(t * 0.7)
    draw = ImageDraw.Draw(frame)

    if scene["img"] is None:
        if idx == 0:
            scale = 0.72 + 0.06 * ease(p)
            lw = int(logo.width * scale)
            logo_scaled = logo.resize((lw, lw), Image.Resampling.LANCZOS)
            frame.alpha_composite(logo_scaled, ((W - lw) // 2, 235))
            draw_center(draw, scene["title"], 905, FONT_TITLE, (255, 255, 255, 255), 920)
            draw_center(draw, scene["body"], 1110, FONT_BODY, (210, 229, 231, 255), 860)
            pill(draw, scene["kicker"], 360, 145)
        else:
            lw = 360
            logo_scaled = logo.resize((lw, lw), Image.Resampling.LANCZOS)
            frame.alpha_composite(logo_scaled, ((W - lw) // 2, 250))
            draw_center(draw, scene["title"], 760, FONT_HUGE, (255, 255, 255, 255), 900)
            draw_center(draw, scene["body"], 960, FONT_BODY, (214, 231, 232, 255), 850)
            pill(draw, "İNDİR", 430, 1115, fill=(82, 219, 185, 255))
            pill(draw, "PUANINI TOPLA", 322, 1200, fill=(255, 178, 71, 255))
    else:
        phone = phones[scene["img"]]
        slide = (1 - ease(min(1, p * 2.0))) * 130
        zoom = 1.0 + 0.035 * ease(p)
        pw, ph = int(phone.width * zoom), int(phone.height * zoom)
        ph_img = phone.resize((pw, ph), Image.Resampling.LANCZOS)
        x = int((W - pw) / 2 + slide)
        y = 472
        frame.alpha_composite(ph_img, (x, y))

        panel = Image.new("RGBA", (W, 480), (0, 0, 0, 0))
        pd = ImageDraw.Draw(panel)
        pd.rounded_rectangle([70, 35, W - 70, 420], radius=38, fill=(6, 12, 24, 205), outline=(255, 178, 71, 100), width=2)
        panel = panel.filter(ImageFilter.GaussianBlur(0.2))
        frame.alpha_composite(panel, (0, 0))
        pill(draw, scene["kicker"], 85, 55)
        body_y = draw_left_wrapped(draw, scene["title"], 85, 130, FONT_TITLE, (255, 255, 255, 255), 900, 6) + 56
        draw_center(draw, scene["body"], max(315, body_y), FONT_BODY, (211, 230, 231, 255), 870)

    progress_w = int((t / (SCENES[-1]["start"] + SCENES[-1]["dur"])) * (W - 120))
    draw.rounded_rectangle([60, H - 72, W - 60, H - 60], radius=8, fill=(255, 255, 255, 35))
    draw.rounded_rectangle([60, H - 72, 60 + progress_w, H - 60], radius=8, fill=(255, 178, 71, 230))
    return np.asarray(frame.convert("RGB"))


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    logo = Image.open(ROOT / "assets/logoyazisiz.png").convert("RGBA")
    phones = {scene["img"]: phone_image(scene["img"]) for scene in SCENES if scene["img"] is not None}

    total = SCENES[-1]["start"] + SCENES[-1]["dur"]
    frames = int(total * FPS)
    writer = imageio.get_writer(
        OUT_VIDEO,
        fps=FPS,
        codec="libx264",
        quality=8,
        pixelformat="yuv420p",
        macro_block_size=1,
        ffmpeg_params=["-movflags", "+faststart"],
    )
    try:
        for i in range(frames):
            writer.append_data(make_frame(i / FPS, phones, logo))
    finally:
        writer.close()

    OUT_STORY.write_text(
        "\n".join(
            [
                "Candar Network 15s Reels/TikTok ad",
                "Format: 1080x1920, no audio. Add a trending sound in TikTok/Instagram.",
                "",
                "Voiceover:",
                "Candar Network ile günlük puan deneyimini cebine al. Güvenli giriş yap, puanını topla, referans ağını büyüt, boost avantajlarını kullan ve Candar AI ile hızlan. App Store ve Google Play'de.",
                "",
                "Scenes:",
            ]
            + [
                f"{scene['start']:.1f}s - {scene['start'] + scene['dur']:.1f}s: {scene['kicker']} / {scene['title']} / {scene['body']}"
                for scene in SCENES
            ]
        ),
        encoding="utf-8",
    )
    print(OUT_VIDEO)
    print(OUT_STORY)


if __name__ == "__main__":
    main()
