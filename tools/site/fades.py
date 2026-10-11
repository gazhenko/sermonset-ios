#!/usr/bin/env python3
"""Writes the site's dithered fade masks: a 4x4 Bayer screen that thins from solid to nothing.

Each PNG is a mask tile (opaque = ink) four cells wide, drawn at 2x so the cells stay crisp on
Retina screens. CSS colors them with the theme, so they work in light and dark.

    python3 tools/site/fades.py
"""
import os
import struct
import zlib

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "site", "assets", "dither")
SCALE = 6  # device pixels per cell (3 CSS px at 2x)


def png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def fade(name, cells):
    """`cells` rows of cells, solid at the top and empty at the bottom."""
    width, height = 4 * SCALE, cells * SCALE
    rows = []
    for y in range(height):
        r = y // SCALE
        cover = 1 - (r + 0.5) / cells
        row = []
        for x in range(width):
            c = x // SCALE
            on = (BAYER[r % 4][c] + 0.5) / 16 < cover
            row += [0, 0, 0, 255 if on else 0]
        rows.append(row)
    png(os.path.join(OUT, name), width, height, rows)


os.makedirs(OUT, exist_ok=True)
fade("fade-16.png", 16)
fade("fade-40.png", 40)
print("wrote", os.path.normpath(OUT))
