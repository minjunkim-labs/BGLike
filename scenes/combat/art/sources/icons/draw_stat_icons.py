#!/usr/bin/env python3
"""Draw the 5 combat stat icons as 48x48 RGBA PNGs (#824).

Usage: python3 scenes/combat/art/sources/icons/draw_stat_icons.py <output-directory>
Writes <output-directory>/{hp,ac,attack,range,movement}.png.

Standard library only (binascii, struct, zlib), matching draw_ability_icons.py.
Uses the same 64px design grid, 48px canvas, 2px #120d16 dark outline, and upper-left light.
"""

import argparse
import binascii
import json
import math
from pathlib import Path
import struct
import zlib

DESIGN = 64
SIZE = 48
OUTLINE = (18, 13, 22)

# Stat palettes as (dark, mid, light).
HP_GREEN = ((56, 132, 62), (112, 199, 109), (178, 240, 174))       # #70C76D
AC_SKY = ((34, 128, 196), (92, 200, 255), (186, 236, 255))         # #5CC8FF
ATK_AMBER = ((176, 98, 12), (245, 158, 11), (255, 218, 118))       # #F59E0B
ATK_HILT = ((124, 72, 34), (178, 114, 58), (226, 172, 110))
RANGE_GOLD = ((176, 134, 34), (244, 207, 105), (255, 242, 184))    # #F4CF69
MOVE_BLUE = ((32, 98, 186), (77, 163, 255), (168, 214, 255))       # #4DA3FF
MOVE_SOLE = ((48, 56, 74), (82, 96, 124), (132, 150, 182))


def dist_segment(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    length_sq = dx * dx + dy * dy
    if length_sq == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / length_sq))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def inside_polygon(px, py, points):
    odd = False
    for index, (x1, y1) in enumerate(points):
        x2, y2 = points[(index + 1) % len(points)]
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            odd = not odd
    return odd


def shade(palette, value):
    if value < -0.32:
        return palette[2]
    if value > 0.35:
        return palette[0]
    return palette[1]


def hp(x, y):
    """Green heart (#70C76D) for HP."""
    px, py = x + 0.5, y + 0.5
    left_lobe = math.hypot(px - 22.0, py - 24.5) <= 13.0
    right_lobe = math.hypot(px - 42.0, py - 24.5) <= 13.0
    lower = False
    if 24.5 <= py <= 54.0:
        t = (py - 24.5) / 29.5
        half_w = 22.5 * ((1.0 - t) ** 0.88)
        lower = abs(px - 32.0) <= half_w
    if not (left_lobe or right_lobe or lower):
        return None
    if ((px - 19.5) / 4.2) ** 2 + ((py - 21.5) / 3.4) ** 2 <= 1.0:
        return HP_GREEN[2]
    light = ((px - 25.0) * 0.45 + (py - 24.0) * 0.72) / 22.0
    return shade(HP_GREEN, light)


def ac(x, y):
    """Sky-blue heater shield (#5CC8FF) for AC."""
    px, py = x + 0.5, y + 0.5
    if py < 10.5 or py > 54.5:
        return None
    if py <= 30.0:
        half_w = 20.0 - (py - 10.5) * 0.08
    else:
        t = (py - 30.0) / 24.5
        half_w = 18.4 * ((1.0 - t) ** 0.72)
    if abs(px - 32.0) > half_w:
        return None
    # Inner ridge / bevel for readability at 12px.
    if abs(px - 32.0) <= 2.2 and 16.0 <= py <= 46.0:
        return AC_SKY[2] if px < 32.0 else AC_SKY[0]
    if abs(py - 25.0) <= 2.2 and abs(px - 32.0) <= half_w - 5.0:
        return AC_SKY[2] if py < 25.0 else AC_SKY[0]
    light = ((px - 26.0) * 0.65 + (py - 22.0) * 0.45) / 22.0
    return shade(AC_SKY, light)


def attack(x, y):
    """Amber diagonal sword (#F59E0B) for attack bonus."""
    px, py = x + 0.5, y + 0.5
    blade = inside_polygon(px, py, [
        (52.0, 11.5), (49.5, 22.0), (27.0, 44.5), (19.5, 37.0), (42.0, 14.5),
    ])
    guard = dist_segment(px, py, 16.0, 31.5, 32.5, 48.0) <= 3.6
    grip = dist_segment(px, py, 22.0, 42.0, 12.5, 51.5) <= 3.3
    pommel = math.hypot(px - 12.0, py - 52.0) <= 4.6
    if guard or grip or pommel:
        light = ((px - 20.0) + (py - 40.0)) / 14.0
        return shade(ATK_HILT, light)
    if blade:
        # Center fuller bright edge on upper-left half of blade.
        side = (px - 36.0) + (py - 28.0)
        if abs((px - 35.5) - (51.0 - py - 15.5)) <= 1.6:
            return ATK_AMBER[2]
        return ATK_AMBER[2] if side < -2.0 else (ATK_AMBER[0] if side > 6.0 else ATK_AMBER[1])
    return None


def range_icon(x, y):
    """Gold target/crosshair (#F4CF69) for attack range."""
    px, py = x + 0.5, y + 0.5
    dx, dy = px - 32.0, py - 32.0
    r = math.hypot(dx, dy)
    outer_ring = 16.5 <= r <= 21.5
    center_dot = r <= 5.5
    h_tick = abs(dy) <= 2.4 and (11.0 <= abs(dx) <= 25.0)
    v_tick = abs(dx) <= 2.4 and (11.0 <= abs(dy) <= 25.0)
    if not (outer_ring or center_dot or h_tick or v_tick):
        return None
    if center_dot:
        return RANGE_GOLD[2] if dx + dy < 0 else RANGE_GOLD[1]
    light = (dx * 0.55 + dy * 0.55) / 22.0
    return shade(RANGE_GOLD, light)


def movement(x, y):
    """Blue winged/tactical boot (#4DA3FF) for movement."""
    px, py = x + 0.5, y + 0.5
    shaft = inside_polygon(px, py, [
        (17.0, 12.0), (35.0, 12.0), (34.5, 36.5), (16.5, 36.5),
    ])
    foot = inside_polygon(px, py, [
        (16.5, 34.0), (36.0, 34.0), (50.5, 40.5), (51.5, 48.0), (16.5, 48.0),
    ])
    sole = 16.0 <= px <= 51.5 and 47.0 <= py <= 52.5
    if sole:
        return MOVE_SOLE[2] if px < 28.0 else (MOVE_SOLE[0] if px > 42.0 else MOVE_SOLE[1])
    if shaft or foot:
        # Boot cuff highlight at top.
        if 12.0 <= py <= 17.5:
            return MOVE_BLUE[2]
        light = ((px - 24.0) * 0.5 + (py - 28.0) * 0.65) / 22.0
        return shade(MOVE_BLUE, light)
    return None


def outlined(draw, size=SIZE):
    pixels = {}
    filled = set()
    step = DESIGN / size
    for y in range(size):
        for x in range(size):
            color = draw((x + 0.5) * step - 0.5, (y + 0.5) * step - 0.5)
            if color is not None:
                pixels[(x, y)] = color
                filled.add((x, y))
    for y in range(size):
        for x in range(size):
            if (x, y) in filled:
                continue
            if any((x + dx, y + dy) in filled for dx in range(-2, 3) for dy in range(-2, 3)
                   if abs(dx) + abs(dy) <= 3):
                pixels[(x, y)] = OUTLINE
    return pixels, filled


def png_chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)


def encode_png(pixels, width=SIZE, height=SIZE):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            color = pixels.get((x, y))
            if color is None:
                raw.extend((0, 0, 0, 0))
            else:
                raw.extend((*color, 255))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), level=9))
        + png_chunk(b"IEND", b"")
    )


ICONS = {
    "hp": hp,
    "ac": ac,
    "attack": attack,
    "range": range_icon,
    "movement": movement,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        pixels, filled = outlined(draw)
        xs = [x for x, _ in pixels]
        ys = [y for _, y in pixels]
        bounds = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
        assert min(bounds[:2]) >= 2 and max(bounds[2:]) <= SIZE - 2, (name, bounds)
        fill_ratio = len(filled) / float(SIZE * SIZE)
        assert fill_ratio >= 0.15, (name, fill_ratio)
        (args.destination / f"{name}.png").write_bytes(encode_png(pixels))
        print(json.dumps({
            "icon": name,
            "canvas": [SIZE, SIZE],
            "content": bounds,
            "fill_ratio": round(fill_ratio, 3),
        }))


if __name__ == "__main__":
    main()
