from __future__ import annotations

import math
from pathlib import Path
import subprocess
import sys
import wave

sys.path.insert(0, "/tmp/candar-media-py")

import imageio.v2 as imageio
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "marketing" / "social-media"
SILENT_VIDEO = OUT_DIR / "candar-first-post-tiktok-silent.mp4"
FINAL_VIDEO = OUT_DIR / "candar-first-post-tiktok-en-1080x1920.mp4"
AUDIO_FILE = OUT_DIR / "candar-first-post-audio.wav"

W, H = 1080, 1920
FPS = 24
DURATION = 9.0

NAVY = (5, 13, 27)
ORANGE = (245, 158, 11)
GOLD = (251, 191, 36)
TEAL = (45, 212, 191)
WHITE = (248, 250, 252)
MUTED = (190, 202, 216)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf"
    )
    return ImageFont.truetype(path, size)


FONT_BRAND = font(70, True)
FONT_HERO = font(82, True)
FONT_CTA = font(66, True)
FONT_BODY = font(43, False)
FONT_URL = font(36, True)


def ease_out(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return 1.0 - (1.0 - value) ** 3


def fade_window(t: float, start: float, end: float, fade: float = 0.45) -> float:
    if t < start or t > end:
        return 0.0
    fade_in = min(1.0, (t - start) / fade)
    fade_out = min(1.0, (end - t) / fade)
    return max(0.0, min(fade_in, fade_out))


def centered_text(
    layer: Image.Image,
    text: str,
    y: int,
    selected_font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    opacity: float,
) -> None:
    if opacity <= 0:
        return
    draw = ImageDraw.Draw(layer)
    box = draw.textbbox((0, 0), text, font=selected_font)
    x = (W - (box[2] - box[0])) // 2
    draw.text((x, y), text, font=selected_font, fill=fill + (int(255 * opacity),))


def make_background(t: float) -> Image.Image:
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    top = np.array([3, 10, 23], dtype=np.float32)[None, None, :]
    bottom = np.array([11, 24, 39], dtype=np.float32)[None, None, :]
    arr = top * (1 - y) + bottom * y
    arr = np.repeat(arr, W, axis=1)

    xx, yy = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    orange_glow = np.exp(
        -((xx + 0.78 + math.sin(t * 0.45) * 0.08) ** 2 + (yy + 0.68) ** 2) * 5.2
    )
    teal_glow = np.exp(
        -((xx - 0.74) ** 2 + (yy - 0.62 + math.cos(t * 0.4) * 0.08) ** 2) * 5.0
    )
    arr += orange_glow[..., None] * np.array(ORANGE) * 0.23
    arr += teal_glow[..., None] * np.array(TEAL) * 0.17
    image = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    network = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(network)
    left_nodes = [(20, 160), (150, 270), (55, 420), (250, 540), (80, 730)]
    right_nodes = [(1040, 1190), (900, 1310), (1010, 1470), (820, 1590), (970, 1770)]
    pulse = 0.72 + 0.28 * math.sin(t * 2.0)

    for nodes, color in ((left_nodes, ORANGE), (right_nodes, TEAL)):
        for index, point in enumerate(nodes):
            next_point = nodes[(index + 1) % len(nodes)]
            draw.line([point, next_point], fill=color + (75,), width=2)
            radius = 5 + int(2 * pulse)
            draw.ellipse(
                [point[0] - radius, point[1] - radius, point[0] + radius, point[1] + radius],
                fill=color + (210,),
            )

    network = network.filter(ImageFilter.GaussianBlur(0.4))
    image.alpha_composite(network)
    return image


def render_frame(t: float, logo: Image.Image) -> np.ndarray:
    frame = make_background(t)
    panel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle(
        [82, 250, W - 82, H - 250],
        radius=46,
        fill=(2, 9, 20, 175),
        outline=(255, 255, 255, 25),
        width=2,
    )
    frame.alpha_composite(panel)

    logo_progress = ease_out(min(1.0, t / 1.0))
    logo_size = int(210 * (0.9 + 0.1 * logo_progress))
    logo_scaled = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)
    logo_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    logo_layer.alpha_composite(
        logo_scaled,
        ((W - logo_size) // 2, 390 - int((1 - logo_progress) * 35)),
    )
    frame.alpha_composite(logo_layer)

    text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    brand_alpha = fade_window(t, 0.25, 3.1)
    centered_text(text_layer, "CANDAR NETWORK", 660, FONT_BRAND, WHITE, brand_alpha)
    centered_text(
        text_layer,
        "From participation to ecosystem.",
        770,
        FONT_BODY,
        GOLD,
        brand_alpha,
    )

    points_alpha = fade_window(t, 2.75, 6.15)
    centered_text(text_layer, "Collect daily points.", 680, FONT_HERO, WHITE, points_alpha)
    centered_text(text_layer, "Grow your network.", 790, FONT_HERO, GOLD, points_alpha)
    centered_text(
        text_layer,
        "Build your place in the Candar ecosystem.",
        930,
        FONT_BODY,
        MUTED,
        points_alpha,
    )

    cta_alpha = fade_window(t, 5.8, 9.0, 0.55)
    centered_text(text_layer, "START YOUR JOURNEY", 705, FONT_CTA, WHITE, cta_alpha)
    centered_text(
        text_layer,
        "Available on iOS and Android",
        825,
        FONT_BODY,
        MUTED,
        cta_alpha,
    )
    centered_text(text_layer, "candarnetwork.com", 930, FONT_URL, TEAL, cta_alpha)

    frame.alpha_composite(text_layer)
    return np.asarray(frame.convert("RGB"))


def create_audio() -> None:
    sample_rate = 44100
    total_samples = int(sample_rate * DURATION)
    audio = np.zeros(total_samples, dtype=np.float64)
    tones = [
        (0.0, 110.0, 0.10),
        (0.0, 164.81, 0.055),
        (2.9, 220.0, 0.08),
        (2.9, 329.63, 0.04),
        (5.9, 261.63, 0.09),
        (5.9, 392.0, 0.04),
    ]

    for start, frequency, volume in tones:
        start_sample = int(start * sample_rate)
        length = int(2.4 * sample_rate)
        end_sample = min(total_samples, start_sample + length)
        local_t = np.arange(end_sample - start_sample) / sample_rate
        envelope = np.exp(-local_t * 1.55) * np.minimum(1.0, local_t * 8)
        audio[start_sample:end_sample] += volume * np.sin(2 * np.pi * frequency * local_t) * envelope

    audio = np.clip(audio, -0.85, 0.85)
    pcm = (audio * 32767).astype(np.int16)
    with wave.open(str(AUDIO_FILE), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes())


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    logo = Image.open(ROOT / "assets" / "candar_logo_192x192.png").convert("RGBA")
    writer = imageio.get_writer(
        SILENT_VIDEO,
        fps=FPS,
        codec="libx264",
        quality=8,
        macro_block_size=8,
        pixelformat="yuv420p",
        ffmpeg_log_level="error",
        output_params=["-movflags", "+faststart"],
    )
    try:
        for frame_index in range(int(DURATION * FPS)):
            writer.append_data(render_frame(frame_index / FPS, logo))
    finally:
        writer.close()

    create_audio()
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-i",
            str(SILENT_VIDEO),
            "-i",
            str(AUDIO_FILE),
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-shortest",
            "-movflags",
            "+faststart",
            str(FINAL_VIDEO),
        ],
        check=True,
    )
    SILENT_VIDEO.unlink(missing_ok=True)
    AUDIO_FILE.unlink(missing_ok=True)
    print(FINAL_VIDEO)


if __name__ == "__main__":
    main()
