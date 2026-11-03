from pathlib import Path
import asyncio
import math
import shutil
import subprocess
import textwrap

import imageio.v2 as imageio
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "marketing"
OUT_VIDEO = OUT_DIR / "candar_reels_ad_voice_32s.mp4"
OUT_SILENT = OUT_DIR / "candar_reels_ad_voice_32s_silent.mp4"
OUT_AUDIO = OUT_DIR / "candar_reels_ad_voice_32s_natural_emel_fast.mp3"
OUT_STORY = OUT_DIR / "candar_reels_ad_voice_32s_storyboard.txt"

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
        except OSError:
            pass
    return ImageFont.load_default()


FONT_HERO = font(78, True)
FONT_TITLE = font(58, True)
FONT_SUB = font(44, True)
FONT_BODY = font(34, False)
FONT_SMALL = font(27, True)
FONT_TINY = font(23, False)


def ease(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - pow(1 - t, 3)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def wrap_lines(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if draw.textbbox((0, 0), candidate, font=fnt)[2] <= max_width:
            current = candidate
            continue
        if current:
            lines.append(current)
        current = word
    if current:
        lines.append(current)
    return lines


def draw_center(
    draw: ImageDraw.ImageDraw,
    text: str,
    y: int,
    fnt,
    fill,
    max_width: int = 930,
    line_gap: int = 10,
) -> int:
    lines = wrap_lines(draw, text, fnt, max_width)
    heights = [draw.textbbox((0, 0), line, font=fnt)[3] - draw.textbbox((0, 0), line, font=fnt)[1] for line in lines]
    total = sum(heights) + line_gap * max(0, len(lines) - 1)
    yy = y - total // 2
    for line, height in zip(lines, heights):
        box = draw.textbbox((0, 0), line, font=fnt)
        draw.text(((W - (box[2] - box[0])) // 2, yy), line, font=fnt, fill=fill)
        yy += height + line_gap
    return yy


def draw_left(
    draw: ImageDraw.ImageDraw,
    text: str,
    x: int,
    y: int,
    fnt,
    fill,
    max_width: int,
    line_gap: int = 8,
) -> int:
    yy = y
    for line in wrap_lines(draw, text, fnt, max_width):
        draw.text((x, yy), line, font=fnt, fill=fill)
        box = draw.textbbox((0, 0), line, font=fnt)
        yy += (box[3] - box[1]) + line_gap
    return yy


def background(t: float) -> Image.Image:
    top = np.array([8, 15, 30], dtype=np.float32)
    mid = np.array([10, 35, 44], dtype=np.float32)
    bot = np.array([30, 23, 42], dtype=np.float32)
    y = np.linspace(0, 1, H)[:, None]
    grad = np.where(
        y < 0.58,
        top * (1 - y / 0.58) + mid * (y / 0.58),
        mid * (1 - (y - 0.58) / 0.42) + bot * ((y - 0.58) / 0.42),
    )
    arr = np.repeat(grad[:, None, :], W, axis=1)
    xgrid, ygrid = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    amber = np.exp(-((xgrid - 0.62 + 0.08 * math.sin(t)) ** 2 + (ygrid + 0.68) ** 2) * 3.6)
    cyan = np.exp(-((xgrid + 0.65) ** 2 + (ygrid - 0.35 + 0.08 * math.cos(t)) ** 2) * 4.2)
    violet = np.exp(-((xgrid - 0.15) ** 2 + (ygrid - 0.92) ** 2) * 6.0)
    arr += amber[..., None] * np.array([255, 161, 30]) * 0.22
    arr += cyan[..., None] * np.array([55, 197, 187]) * 0.24
    arr += violet[..., None] * np.array([91, 80, 255]) * 0.14
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def pill(draw: ImageDraw.ImageDraw, text: str, x: int, y: int, fill, text_fill=(11, 16, 27, 255)) -> tuple[int, int]:
    pad_x, pad_y = 22, 10
    box = draw.textbbox((0, 0), text, font=FONT_SMALL)
    ww = box[2] - box[0] + pad_x * 2
    hh = box[3] - box[1] + pad_y * 2
    draw.rounded_rectangle([x, y, x + ww, y + hh], radius=hh // 2, fill=fill)
    draw.text((x + pad_x, y + pad_y - 2), text, font=FONT_SMALL, fill=text_fill)
    return ww, hh


def phone_image(path: Path, height: int = 1120) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    ratio = height / img.height
    size = (int(img.width * ratio), height)
    img = img.resize(size, Image.Resampling.LANCZOS)
    radius = 54
    mask = rounded_mask(size, radius)
    shadow = Image.new("RGBA", (size[0] + 96, size[1] + 96), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([48, 48, size[0] + 48, size[1] + 48], radius=radius + 10, fill=(0, 0, 0, 145))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    phone = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    phone.alpha_composite(shadow, (0, 0))
    frame = Image.new("RGBA", size, (12, 18, 31, 255))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, outline=(255, 166, 33, 220), width=5)
    frame.paste(img, (0, 0), mask)
    phone.alpha_composite(frame, (48, 48))
    return phone


def screenshot_card(path: Path, width: int, crop: tuple[int, int, int, int] | None = None, radius: int = 34) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    if crop:
        img = img.crop(crop)
    height = int(img.height * (width / img.width))
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    mask = rounded_mask(img.size, radius)
    shadow = Image.new("RGBA", (width + 88, height + 88), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([44, 44, width + 44, height + 44], radius=radius + 10, fill=(0, 0, 0, 145))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    card = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    card.alpha_composite(shadow, (0, 0))
    body = Image.new("RGBA", img.size, (12, 18, 31, 255))
    body.paste(img, (0, 0), mask)
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([0, 0, width - 1, height - 1], radius=radius, outline=(255, 166, 33, 185), width=3)
    card.alpha_composite(body, (44, 44))
    return card


def scene_header(frame: Image.Image, kicker: str, title: str, body: str) -> None:
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle([58, 54, W - 58, 330], radius=36, fill=(6, 13, 25, 214), outline=(255, 166, 33, 70), width=2)
    pill(draw, kicker, 86, 82, (255, 166, 33, 255))
    next_y = draw_left(draw, title, 86, 142, FONT_TITLE, (255, 255, 255, 255), 900, 6)
    draw_left(draw, body, 86, next_y + 12, FONT_BODY, (207, 227, 229, 255), 900, 6)


def subtitle_bar(frame: Image.Image, subtitle: str, t: float, total: float) -> None:
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle([62, H - 310, W - 62, H - 156], radius=32, fill=(6, 13, 25, 224), outline=(255, 255, 255, 38), width=2)
    draw_center(draw, subtitle, H - 234, FONT_SUB, (255, 255, 255, 255), 860, 8)
    draw.rounded_rectangle([60, H - 72, W - 60, H - 60], radius=8, fill=(255, 255, 255, 35))
    progress = int((t / total) * (W - 120))
    draw.rounded_rectangle([60, H - 72, 60 + progress, H - 60], radius=8, fill=(255, 166, 33, 235))


SCENES = [
    {
        "dur": 3.5,
        "kind": "hero",
        "kicker": "CANDAR NETWORK",
        "title": "Kazım / mining deneyimi cebinde",
        "body": "Günlük puanını topla, oranını takip et, ağını büyüt.",
        "subtitle": "Kazım / mining deneyimi cebinde",
        "voice": "Candar Network ile kazım, yani mining deneyimini cebine al.",
    },
    {
        "dur": 4.2,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/02-daily-points.png",
        "kicker": "GÜNLÜK KAZIM",
        "title": "Puanını ve oranını tek ekranda gör",
        "body": "Günlük hak, Candar coin ilerlemesi ve kazım oranı net.",
        "subtitle": "Günlük puan + kişisel kazım oranı",
        "voice": "Her gün puanını topla; kazım oranını ve Candar coin ilerlemeni tek ekrandan takip et.",
    },
    {
        "dur": 4.6,
        "kind": "market_packages",
        "kicker": "CANDAR MARKET",
        "title": "Boost paketleri detaylı görünsün",
        "body": "Basic x2, Pro x3 ve Ultra x7 kazım hızı seçenekleri.",
        "subtitle": "Market: Basic x2, Pro x3, Ultra x7",
        "voice": "Candar Market'te boost paketlerini detaylı gör: Basic x2, Pro x3 ve Ultra x7 kazım hızı.",
    },
    {
        "dur": 4.9,
        "kind": "market_calc",
        "kicker": "BOOST HESAPLAYICI",
        "title": "Oranı önceden gör",
        "body": "Referans ve reklam boost etkisiyle günlük sonuç hesaplanır.",
        "subtitle": "Referans + reklam boost = özel mining oranı",
        "voice": "Boost hesaplayıcı, referans ve reklam boost etkisini gösterir; hangi paketle günlük oranın nasıl değişir, net görürsün.",
    },
    {
        "dur": 3.8,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/03-referral-network.png",
        "kicker": "REFERANS",
        "title": "Davet ettikçe oran güçlenir",
        "body": "Her kullanıcı için mining oranı kişiye özel büyür.",
        "subtitle": "Referans ekle, kazım oranını büyüt",
        "voice": "Referans ekledikçe mining hızın kişiye özel artar.",
    },
    {
        "dur": 3.8,
        "kind": "phone",
        "image": ROOT / "store-screenshots/play/04-boost-premium.png",
        "kicker": "REKLAM BOOST",
        "title": "Reklam izle, ekstra oran al",
        "body": "Video varsa yüklenir; ödülün oranına yansır.",
        "subtitle": "Reklam izle, ekstra kazım oranı kazan",
        "voice": "Reklam izleyerek ekstra oran al; kazım yaptığında ödülün puanına yansısın.",
    },
    {
        "dur": 4.0,
        "kind": "ai_full",
        "kicker": "CANDAR AI",
        "title": "AI ekranı tam kadraj",
        "body": "Soru önerileri, cevap alanı ve mesaj kutusu net görünür.",
        "subtitle": "Candar AI: sor, yaz, stratejini hızlandır",
        "voice": "Candar AI tarafında sorularını yaz, stratejini hızlandır; mesaj alanı her zaman elinin altında.",
    },
    {
        "dur": 3.2,
        "kind": "cta",
        "kicker": "ŞİMDİ KATIL",
        "title": "Candar Network",
        "body": "App Store ve Google Play'de.",
        "subtitle": "İndir. Puanını topla. Kazımını büyüt.",
        "voice": "Candar Network, App Store ve Google Play'de. İndir, puanını topla, kazımını büyüt.",
    },
]


def starts() -> list[float]:
    out = []
    cursor = 0.0
    for scene in SCENES:
        out.append(cursor)
        cursor += scene["dur"]
    return out


STARTS = starts()
TOTAL = sum(scene["dur"] for scene in SCENES)


def scene_at(t: float):
    for idx, (start, scene) in enumerate(zip(STARTS, SCENES)):
        if start <= t < start + scene["dur"]:
            return idx, scene, (t - start) / scene["dur"]
    return len(SCENES) - 1, SCENES[-1], 1.0


def draw_market_badges(draw: ImageDraw.ImageDraw, y: int) -> None:
    x = 90
    for label, color in [
        ("x2 Basic", (255, 166, 33, 255)),
        ("x3 Pro", (91, 96, 255, 255)),
        ("x7 Ultra", (80, 220, 184, 255)),
    ]:
        ww, _ = pill(draw, label, x, y, color, (255, 255, 255, 255) if color[0] < 120 else (12, 16, 25, 255))
        x += ww + 18


def draw_market_rows(draw: ImageDraw.ImageDraw, y: int, rows=None) -> None:
    rows = rows or [
        ("Boost Basic", "x2", "30 gün - x2 kazım hızı", "1.49$", (255, 166, 33, 255)),
        ("Boost Pro", "x3", "30 gün - x3 kazım hızı", "1.99$", (91, 96, 255, 255)),
        ("Boost Ultra", "x7", "30 gün - x7 kazım hızı", "2.99$", (80, 220, 184, 255)),
    ]
    for idx, (name, mult, desc, price, color) in enumerate(rows):
        top = y + idx * 142
        draw.rounded_rectangle([76, top, W - 76, top + 112], radius=26, fill=(17, 28, 48, 235), outline=color, width=2)
        draw.text((110, top + 24), name, font=FONT_SUB, fill=(255, 255, 255, 255))
        draw.text((390, top + 24), mult, font=FONT_SUB, fill=color)
        draw.text((110, top + 72), desc, font=FONT_SMALL, fill=(190, 207, 215, 255))
        box = draw.textbbox((0, 0), price, font=FONT_SUB)
        draw.rounded_rectangle([W - 260, top + 28, W - 110, top + 86], radius=22, fill=(255, 166, 33, 255))
        draw.text((W - 185 - (box[2] - box[0]) // 2, top + 37), price, font=FONT_SMALL, fill=(11, 16, 27, 255))


def draw_calc_panel(draw: ImageDraw.ImageDraw, y: int, copy=None) -> None:
    copy = copy or {
        "title": "Boost Hesaplayıcı",
        "current": "Şu an: 3.85 / gün",
        "referral": "Referans: 7  ·  x1.35",
        "ad": "Reklam boost: x1.10",
        "values": [("Basic x2", "2.97 / gün"), ("Pro x3", "4.46 / gün"), ("Ultra x7", "10.40 / gün")],
    }
    draw.rounded_rectangle([76, y, W - 76, y + 380], radius=30, fill=(7, 14, 27, 238), outline=(255, 166, 33, 135), width=2)
    draw_center(draw, copy["title"], y + 46, FONT_BODY, (255, 166, 33, 255), 760, 6)
    draw.text((112, y + 100), copy["current"], font=FONT_BODY, fill=(221, 235, 238, 255))
    draw.text((112, y + 148), copy["referral"], font=FONT_BODY, fill=(221, 235, 238, 255))
    draw.text((112, y + 196), copy["ad"], font=FONT_BODY, fill=(221, 235, 238, 255))
    values = copy["values"]
    for idx, (label, value) in enumerate(values):
        top = y + 250 + idx * 42
        draw.text((112, top), label, font=FONT_SMALL, fill=(184, 202, 211, 255))
        draw.text((330, top), value, font=FONT_SMALL, fill=(80, 220, 184, 255) if idx == 2 else (255, 255, 255, 255))


def make_frame(t: float, logo: Image.Image, assets: dict[str, Image.Image]) -> np.ndarray:
    idx, scene, p = scene_at(t)
    frame = background(t * 0.55)
    draw = ImageDraw.Draw(frame)

    if scene["kind"] == "hero":
        logo_size = int(360 + 35 * ease(p))
        logo_img = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)
        frame.alpha_composite(logo_img, ((W - logo_size) // 2, 248))
        pill(draw, scene["kicker"], 347, 150, (255, 166, 33, 255))
        draw_center(draw, scene["title"], 770, FONT_HERO, (255, 255, 255, 255), 920, 10)
        draw_center(draw, scene["body"], 970, FONT_BODY, (210, 230, 231, 255), 850, 8)
        draw.rounded_rectangle([190, 1100, W - 190, 1192], radius=46, fill=(80, 220, 184, 235))
        draw_center(draw, scene.get("hero_badge", "Günlük kazım oranını takip et"), 1146, FONT_BODY, (8, 15, 26, 255), 640, 5)

    elif scene["kind"] == "phone":
        scene_header(frame, scene["kicker"], scene["title"], scene["body"])
        phone = assets[str(scene["image"])]
        zoom = 1.0 + 0.025 * ease(p)
        img = phone.resize((int(phone.width * zoom), int(phone.height * zoom)), Image.Resampling.LANCZOS)
        frame.alpha_composite(img, ((W - img.width) // 2, 352))

    elif scene["kind"] == "market_packages":
        scene_header(frame, scene["kicker"], scene["title"], scene["body"])
        card = assets["market_packages"]
        y = 365 - int(10 * math.sin(p * math.pi))
        frame.alpha_composite(card, ((W - card.width) // 2, y))
        draw_market_rows(draw, 705, scene.get("market_rows"))
        draw_market_badges(draw, 1165)
        draw.rounded_rectangle([78, 1248, W - 78, 1350], radius=28, fill=(6, 13, 25, 218), outline=(255, 166, 33, 92), width=2)
        draw_center(draw, scene.get("market_note", "Market: paket adı, süre, çarpan ve fiyat aynı kadrajda."), 1298, FONT_BODY, (219, 236, 235, 255), 850, 6)

    elif scene["kind"] == "market_calc":
        scene_header(frame, scene["kicker"], scene["title"], scene["body"])
        full = assets["market_full"]
        frame.alpha_composite(full, ((W - full.width) // 2, 368))
        draw_calc_panel(draw, 765, scene.get("calc_copy"))
        calc_pills = scene.get("calc_pills", ["Referans x1.35", "Reklam boost x1.10", "Ultra x7 = 10.40/gün"])
        pill(draw, calc_pills[0], 92, 1192, (91, 96, 255, 255), (255, 255, 255, 255))
        pill(draw, calc_pills[1], 382, 1192, (255, 166, 33, 255))
        pill(draw, calc_pills[2], 92, 1265, (80, 220, 184, 255))

    elif scene["kind"] == "ai_full":
        scene_header(frame, scene["kicker"], scene["title"], scene["body"])
        ai = assets["ai_full"]
        frame.alpha_composite(ai, ((W - ai.width) // 2, 396))
        draw.rounded_rectangle([86, 1112, W - 86, 1216], radius=30, fill=(6, 13, 25, 222), outline=(80, 220, 184, 95), width=2)
        draw_center(draw, "Mesaj kutusu ve gönder butonu kesilmeden görünür.", 1165, FONT_BODY, (219, 236, 235, 255), 840, 6)
        pill(draw, "Soru önerileri", 110, 1278, (91, 96, 255, 255), (255, 255, 255, 255))
        pill(draw, "Mesaj alanı", 408, 1278, (255, 166, 33, 255))
        pill(draw, "Candar AI hazır", 690, 1278, (80, 220, 184, 255))

    elif scene["kind"] == "cta":
        logo_size = 330
        logo_img = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)
        frame.alpha_composite(logo_img, ((W - logo_size) // 2, 250))
        pill(draw, scene["kicker"], 392, 145, (255, 166, 33, 255))
        draw_center(draw, scene["title"], 740, FONT_HERO, (255, 255, 255, 255), 920, 10)
        draw_center(draw, scene["body"], 920, FONT_BODY, (210, 230, 231, 255), 850, 8)
        draw.rounded_rectangle([150, 1065, W - 150, 1160], radius=44, fill=(255, 166, 33, 255))
        draw_center(draw, "App Store  |  Google Play", 1112, FONT_BODY, (9, 15, 27, 255), 760, 5)
        draw_center(draw, scene.get("cta_note", "Uygulama içi puan deneyimi."), 1255, FONT_TINY, (180, 203, 207, 255), 700, 4)

    subtitle_bar(frame, scene["subtitle"], t, TOTAL)
    return np.asarray(frame.convert("RGB"))


def render_video(logo: Image.Image, assets: dict[str, Image.Image]) -> None:
    writer = imageio.get_writer(
        OUT_SILENT,
        fps=FPS,
        codec="libx264",
        quality=8,
        pixelformat="yuv420p",
        macro_block_size=1,
        ffmpeg_params=["-movflags", "+faststart"],
    )
    try:
        for i in range(int(TOTAL * FPS)):
            writer.append_data(make_frame(i / FPS, logo, assets))
    finally:
        writer.close()


def render_audio() -> bool:
    narration = " ".join(scene["voice"] for scene in SCENES)
    try:
        import edge_tts

        async def make_natural_voice() -> None:
            communicate = edge_tts.Communicate(narration, "tr-TR-EmelNeural", rate="+55%", volume="+0%")
            await communicate.save(str(OUT_AUDIO))

        asyncio.run(make_natural_voice())
        return OUT_AUDIO.exists()
    except Exception:
        say = shutil.which("say")
        if not say:
            return False
        fallback_audio = OUT_DIR / "candar_reels_ad_voice_32s_narration.aiff"
        subprocess.run([say, "-v", "Yelda", "-r", "172", "-o", str(fallback_audio), narration], check=True)
        OUT_AUDIO.write_bytes(fallback_audio.read_bytes())
        return OUT_AUDIO.exists()


def mux_audio() -> bool:
    if not OUT_AUDIO.exists():
        return False
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
            "160k",
            "-af",
            "loudnorm=I=-16:TP=-1.5:LRA=11",
            "-movflags",
            "+faststart",
            str(OUT_VIDEO),
        ],
        check=True,
    )
    return OUT_VIDEO.exists()


def save_previews(logo: Image.Image, assets: dict[str, Image.Image]) -> None:
    preview_times = {
        "voice_preview_market_packages.jpg": STARTS[2] + 2.2,
        "voice_preview_market_calc.jpg": STARTS[3] + 2.5,
        "voice_preview_ai.jpg": STARTS[6] + 2.1,
        "voice_preview_end.jpg": TOTAL - 1.4,
    }
    for name, ts in preview_times.items():
        Image.fromarray(make_frame(ts, logo, assets)).save(OUT_DIR / name, quality=92)


def write_storyboard(has_audio: bool) -> None:
    lines = [
        "Candar Network Reels/TikTok ad - voiced detailed version",
        "Format: 1080x1920, H.264, 30fps",
        f"Audio: {'Turkish Yelda voiceover + subtitles' if has_audio else 'subtitles only; macOS say voice unavailable'}",
        "",
        "Narration:",
        " ".join(scene["voice"] for scene in SCENES),
        "",
        "Scenes:",
    ]
    for start, scene in zip(STARTS, SCENES):
        lines.append(f"{start:04.1f}s - {start + scene['dur']:04.1f}s: {scene['kicker']} / {scene['title']} / {scene['subtitle']}")
    lines.append("")
    lines.append("Market copy calls out Basic x2, Pro x3, Ultra x7, referral and rewarded-ad boost.")
    lines.append("AI scene keeps the full screenshot visible so the message field is not cropped.")
    OUT_STORY.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    logo = Image.open(ROOT / "assets/logoyazisiz.png").convert("RGBA")
    assets = {
        str(ROOT / "store-screenshots/play/02-daily-points.png"): phone_image(ROOT / "store-screenshots/play/02-daily-points.png", 1068),
        str(ROOT / "store-screenshots/play/03-referral-network.png"): phone_image(ROOT / "store-screenshots/play/03-referral-network.png", 1068),
        str(ROOT / "store-screenshots/play/04-boost-premium.png"): phone_image(ROOT / "store-screenshots/play/04-boost-premium.png", 1068),
        "market_packages": screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 986, (0, 104, 2880, 720), 34),
        "market_full": screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 936, (0, 0, 2880, 910), 30),
        "market_calc": screenshot_card(ROOT / "store-screenshots/raw/02-market.png", 936, (0, 720, 2880, 1148), 30),
        "ai_full": screenshot_card(ROOT / "store-screenshots/raw/04-ai.png", 982, None, 34),
    }

    render_video(logo, assets)
    has_audio = render_audio()
    if has_audio:
        mux_audio()
    else:
        OUT_VIDEO.write_bytes(OUT_SILENT.read_bytes())
    save_previews(logo, assets)
    write_storyboard(has_audio)

    print(OUT_VIDEO)
    print(OUT_STORY)
    print(f"duration={TOTAL:.1f}s audio={has_audio}")


if __name__ == "__main__":
    main()
