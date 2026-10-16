"""Generate the platform logo assets used by the download screen.

Each logo is drawn programmatically (no third-party image is copied) as a
simple, original geometric mark on the platform's brand colour, then saved as
a 512x512 PNG under ``assets/logos``.

Usage::

    python tools/generate_platform_logos.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 512
OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "logos"

WHITE = (255, 255, 255, 255)


def _font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    names = (
        "arialbd.ttf",
        "Arial_Bold.ttf",
        "seguisb.ttf",
        "DejaVuSans-Bold.ttf",
    ) if bold else ("arial.ttf", "DejaVuSans.ttf")
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _vertical_gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        ratio = y / (SIZE - 1)
        draw.line(
            [(0, y), (SIZE, y)],
            fill=tuple(
                round(top[i] + (bottom[i] - top[i]) * ratio) for i in range(3)
            ),
        )
    return image


def _diagonal_gradient(
    corners: tuple[tuple[int, int, int], ...],
) -> Image.Image:
    """Four-colour gradient sampled per pixel (good enough at this size)."""
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        fy = y / (SIZE - 1)
        for x in range(SIZE):
            fx = x / (SIZE - 1)
            top = tuple(corners[0][i] + (corners[1][i] - corners[0][i]) * fx for i in range(3))
            bottom = tuple(corners[2][i] + (corners[3][i] - corners[2][i]) * fx for i in range(3))
            pixels[x, y] = tuple(round(top[i] + (bottom[i] - top[i]) * fy) for i in range(3))
    return image


def _rounded_mask(radius: int) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    return mask


def _finish(image: Image.Image, name: str, radius: int = 116) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    image = image.convert("RGBA")
    image.putalpha(_rounded_mask(radius))
    image.save(OUT_DIR / name)
    print(f"wrote {OUT_DIR / name}")


def _centered_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    center: tuple[float, float] = (SIZE / 2, SIZE / 2),
) -> None:
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (center[0] - (right - left) / 2 - left, center[1] - (bottom - top) / 2 - top),
        text,
        font=font,
        fill=WHITE,
    )


def facebook() -> None:
    image = _vertical_gradient((24, 119, 242), (59, 89, 152))
    draw = ImageDraw.Draw(image)
    font = _font(340)
    _centered_text(draw, "f", font, center=(SIZE / 2, SIZE / 2 - 12))
    _finish(image, "facebook.png")


def instagram() -> None:
    image = _diagonal_gradient(
        ((255, 221, 85), (245, 133, 41), (221, 42, 123), (81, 91, 212))
    )
    draw = ImageDraw.Draw(image)
    # Camera outline.
    draw.rounded_rectangle([116, 116, 396, 396], radius=88, outline=WHITE, width=30)
    draw.ellipse([196, 196, 316, 316], outline=WHITE, width=30)
    draw.ellipse([330, 150, 362, 182], fill=WHITE)
    _finish(image, "instagram.png")


def tiktok() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (1, 1, 1))
    font = _font(300)
    # Chromatic-aberration style "d": cyan + pink offset behind the white glyph.
    # The coloured copies are composed on a separate RGBA layer so each stroke
    # can have its own colour, then flattened over the black background.
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer_draw = ImageDraw.Draw(layer)
    for dx, dy, color in ((-18, 14, (37, 244, 238)), (18, -14, (254, 44, 85))):
        _centered_text_colored(layer_draw, "d", font, color, (SIZE / 2 + dx, SIZE / 2 + dy))
    _centered_text_colored(layer_draw, "d", font, WHITE, (SIZE / 2, SIZE / 2))
    image = Image.alpha_composite(image.convert("RGBA"), layer).convert("RGB")
    _finish(image, "tiktok.png")


def _centered_text_colored(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    color,
    center: tuple[float, float],
) -> None:
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (center[0] - (right - left) / 2 - left, center[1] - (bottom - top) / 2 - top),
        text,
        font=font,
        fill=color,
    )


def vimeo() -> None:
    image = _vertical_gradient((26, 183, 234), (17, 122, 168))
    draw = ImageDraw.Draw(image)
    font = _font(330)
    _centered_text(draw, "V", font, center=(SIZE / 2, SIZE / 2 - 8))
    _finish(image, "vimeo.png")


def x_twitter() -> None:
    image = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    width = 26
    # Two crossing strokes = the original X mark.
    draw.line([150, 150, 362, 362], fill=WHITE, width=width)
    draw.line([362, 150, 150, 362], fill=WHITE, width=width)
    _finish(image, "x.png")


def dailymotion() -> None:
    image = _vertical_gradient((0, 175, 240), (0, 102, 204))
    draw = ImageDraw.Draw(image)
    font = _font(300)
    # A "d" bowl plus its ascender stroke.
    _centered_text(draw, "d", font, center=(SIZE / 2, SIZE / 2 + 10))
    draw.rounded_rectangle([148, 96, 188, 236], radius=20, fill=WHITE)
    _finish(image, "dailymotion.png")


def main() -> None:
    facebook()
    instagram()
    tiktok()
    vimeo()
    x_twitter()
    dailymotion()


if __name__ == "__main__":
    main()
