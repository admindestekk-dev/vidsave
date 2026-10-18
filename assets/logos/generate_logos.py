"""Generates the platform logo tiles used on the VidSave home screen.

Run from the project root:

    python assets/logos/generate_logos.py

Each logo is drawn as a rounded, brand-coloured badge carrying the platform's
initial. The badge is a *nominative* reference ("this app can download from
this platform"): it uses the platform's own colour and initial, contains no
third-party artwork or wordmark, and is not presented as the platform's
official app icon. That keeps the app clear of asset-licensing complaints
while still being instantly recognisable to users.

Need pixel-perfect official icons instead? Download each brand's press asset
from its own brand page and drop it in this folder under the matching file
name; the Flutter widget picks it up automatically and nothing else changes.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

SIZE = 256
FONT_CANDIDATES = (
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)

# file name -> (top-left colour, bottom-right colour, initial)
LOGOS = {
    "facebook.png": ((24, 119, 242), (59, 89, 152), "f"),
    "instagram.png": ((245, 133, 41), (221, 42, 123), "I"),
    "tiktok.png": ((37, 244, 238), (1, 1, 1), "t"),
    "vimeo.png": ((26, 183, 234), (22, 34, 33), "V"),
    "x.png": ((47, 51, 54), (0, 0, 0), "X"),
    "dailymotion.png": ((0, 175, 240), (0, 102, 204), "d"),
    "pinterest.png": ((189, 8, 28), (140, 5, 20), "P"),
    "mp3.png": ((29, 185, 84), (14, 124, 75), "M"),
}


def _font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def _gradient(top_left, bottom_right) -> Image.Image:
    gradient = Image.new("RGB", (SIZE, SIZE))
    pixels = gradient.load()
    for y in range(SIZE):
        for x in range(SIZE):
            ratio = (x + y) / (2 * (SIZE - 1))
            pixels[x, y] = tuple(
                round(start + (end - start) * ratio)
                for start, end in zip(top_left, bottom_right)
            )
    return gradient


def _rounded_mask(radius: int) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, SIZE - 1, SIZE - 1), radius=radius, fill=255
    )
    return mask


def build_logo(top_left, bottom_right, initial: str) -> Image.Image:
    badge = _gradient(top_left, bottom_right).convert("RGBA")

    font = _font(round(SIZE * 0.58))
    text_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(text_layer)
    box = draw.textbbox((0, 0), initial, font=font)
    draw.text(
        ((SIZE - box[2] + box[0]) / 2, (SIZE - box[3] + box[1]) / 2),
        initial,
        font=font,
        fill=(255, 255, 255, 255),
    )

    badge.alpha_composite(text_layer)
    badge.putalpha(_rounded_mask(round(SIZE * 0.28)))
    return badge


def main() -> None:
    directory = os.path.dirname(os.path.abspath(__file__))
    for name, (top_left, bottom_right, initial) in LOGOS.items():
        path = os.path.join(directory, name)
        build_logo(top_left, bottom_right, initial).save(path, "PNG")
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
