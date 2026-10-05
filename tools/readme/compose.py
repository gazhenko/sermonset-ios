#!/usr/bin/env python3
"""Composes README comparison images: one screen, four looks side by side.

  python3 tools/readme/compose.py <shots-dir>   # needs Pillow

Reads <shots-dir>/<screen>-<look>.png (Simulator screenshots, 1206×2622) and writes
docs/media/looks-<screen>.jpg.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
LOOKS = [("riso", "Riso", "Printed loud, kept close"), ("rubric", "Rubric", "Set like a well-used Bible"),
         ("vespers", "Vespers", "Quiet enough for the pew"), ("lumen", "Lumen", "Light through glass")]
SCREENS = ["library", "sermon", "recording", "takeaways", "card", "pack", "atlas", "onboarding"]
PHONE_W, GAP, MARGIN, RADIUS = 360, 40, 60, 46
BG, INK, MUTED = (232, 234, 237), (24, 26, 29), (96, 102, 110)
FONT = "/System/Library/Fonts/Avenir Next.ttc"


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0), mask)
    return out


def compose(shots: Path, screen: str):
    phones = []
    for key, _, _ in LOOKS:
        im = Image.open(shots / f"{screen}-{key}.png").convert("RGB")
        h = round(im.height * PHONE_W / im.width)
        phones.append(rounded(im.resize((PHONE_W, h), Image.LANCZOS), RADIUS))
    ph = phones[0].height
    width = MARGIN * 2 + PHONE_W * 4 + GAP * 3
    height = MARGIN + ph + 96 + MARGIN // 2
    canvas = Image.new("RGBA", (width, height), BG + (255,))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for i in range(4):
        x = MARGIN + i * (PHONE_W + GAP)
        sd.rounded_rectangle([x + 4, MARGIN + 12, x + PHONE_W + 4, MARGIN + ph + 12], radius=RADIUS, fill=(0, 0, 0, 70))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    draw = ImageDraw.Draw(canvas)
    bold = ImageFont.truetype(FONT, 30, index=2)    # Demi Bold
    regular = ImageFont.truetype(FONT, 22, index=7)  # Regular
    for i, (phone, (_, name, tagline)) in enumerate(zip(phones, LOOKS)):
        x = MARGIN + i * (PHONE_W + GAP)
        canvas.alpha_composite(phone, (x, MARGIN))
        draw.text((x + 4, MARGIN + ph + 26), name, fill=INK, font=bold)
        draw.text((x + 4, MARGIN + ph + 64), tagline, fill=MUTED, font=regular)
    out = ROOT / "docs/media" / f"looks-{screen}.jpg"
    canvas.convert("RGB").save(out, quality=84, optimize=True, progressive=True)
    print(out.relative_to(ROOT), f"{out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    shots = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "build/shots")
    for screen in SCREENS:
        compose(shots, screen)
