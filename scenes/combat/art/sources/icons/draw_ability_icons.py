#!/usr/bin/env python3
"""Draw the 6 ability icons as 48x48 RGBA PNGs (docs/design/combat/ability.md 3-4, #795).

Usage: python3 scenes/combat/art/sources/icons/draw_ability_icons.py <output-directory>
Writes <output-directory>/{strength,agility,finesse,intelligence,will,health}.png.

Standard library only (binascii, struct, zlib), so the same command writes identical bytes
without Pillow. Uses the same 64px design grid, 48px canvas, 2px #120d16 dark outline, and
upper-left light as draw_item_icons.py. No anti-aliasing and no generative model.
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

# Representative colors from docs/design/combat/ability.md 3-4, each as (dark, mid, light).
# Midtone matches the exact design hex.
STRENGTH = ((162, 34, 42), (239, 68, 68), (255, 146, 136))       # #EF4444
AGILITY = ((10, 118, 84), (16, 185, 129), (118, 242, 198))       # #10B981
FINESSE = ((178, 118, 18), (251, 191, 36), (255, 232, 132))      # #FBBF24
SKIN = ((208, 168, 134), (245, 224, 198))                        # exposed fingertips for fingerless glove
INTELLIGENCE = ((8, 112, 138), (6, 182, 212), (122, 236, 250))   # #06B6D4
WILL = ((86, 48, 174), (139, 92, 246), (200, 172, 255))          # #8B5CF6
HEALTH = ((154, 12, 124), (234, 12, 193), (255, 142, 236))       # #EA0CC1


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
    """Map a normalized lighting value (negative = upper-left lit, positive = shaded) to (dark, mid, light)."""
    if value < -0.32:
        return palette[2]
    if value > 0.35:
        return palette[0]
    return palette[1]


def strength(x, y):
    """Flexed bicep arm (#EF4444): fist at upper-left, forearm down to elbow, bulging bicep peak."""
    px, py = x + 0.5, y + 0.5
    fist = math.hypot(px - 19.0, py - 16.5) <= 7.6
    forearm = dist_segment(px, py, 18.0, 21.0, 17.5, 44.5) <= 6.2
    lower_arm = dist_segment(px, py, 18.0, 45.5, 50.5, 44.0) <= 7.8
    bicep = ((px - 37.5) / 14.5) ** 2 + ((py - 33.5) / 11.5) ** 2 <= 1.0
    shoulder = ((px - 49.0) / 8.0) ** 2 + ((py - 41.5) / 10.5) ** 2 <= 1.0
    if not (fist or forearm or lower_arm or bicep or shoulder):
        return None
    # Inner crook crease separating forearm and flexed bicep.
    if dist_segment(px, py, 24.0, 31.0, 26.5, 41.5) <= 1.5:
        return STRENGTH[0]
    # Fist thumb/knuckle detail.
    if fist and dist_segment(px, py, 16.0, 18.5, 22.0, 18.5) <= 1.2:
        return STRENGTH[0]
    if bicep and not forearm:
        light = ((px - 35.0) / 14.5) * 0.45 + ((py - 31.0) / 11.5) * 0.85
        return shade(STRENGTH, light)
    if fist:
        light = ((px - 17.5) + (py - 15.0)) / 10.0
        return shade(STRENGTH, light)
    light = ((px - 22.0) * 0.3 + (py - 36.0) * 0.7) / 14.0
    return shade(STRENGTH, light)


def agility(x, y):
    """Somersaulting acrobat with a curved flip trail (#10B981)."""
    px, py = x + 0.5, y + 0.5
    # Sweeping flip arc on the bottom-left, clearly separated from the acrobat body.
    dx, dy = px - 33.0, py - 33.0
    r = math.hypot(dx, dy)
    angle = math.degrees(math.atan2(dy, dx))
    if angle < 0:
        angle += 360.0
    in_arc = 20.5 <= r <= 24.5 and 118.0 <= angle <= 232.0
    arc_tip = inside_polygon(px, py, [(16.5, 10.5), (25.5, 11.5), (20.0, 18.5)])
    # Upside-down tucked acrobat in the center-right.
    head = math.hypot(px - 43.0, py - 43.5) <= 5.2
    torso = (dist_segment(px, py, 39.5, 36.5, 34.0, 26.5) <= 4.6
             or dist_segment(px, py, 34.0, 26.5, 27.5, 24.5) <= 4.0)
    legs = (dist_segment(px, py, 27.5, 24.5, 35.5, 15.5) <= 3.6
            or dist_segment(px, py, 35.5, 15.5, 48.0, 17.5) <= 3.0)
    arm = dist_segment(px, py, 39.0, 33.5, 50.5, 31.0) <= 2.8
    if head or torso or legs or arm:
        if head:
            light = ((px - 41.5) + (py - 42.0)) / 7.5
            return shade(AGILITY, light)
        light = ((px - 33.0) * 0.35 + (py - 25.0) * 0.85) / 18.0
        return shade(AGILITY, light)
    if in_arc or arc_tip:
        return AGILITY[2] if angle > 185.0 or arc_tip else AGILITY[1]
    return None


def finesse(x, y):
    """Fingerless gloved hand (#FBBF24): yellow glove over palm and lower fingers, exposed fingertips."""
    px, py = x + 0.5 - 3.0, y + 0.5
    cuff = 21.5 <= px <= 44.5 and 48.0 <= py <= 55.5
    palm = 19.5 <= px <= 45.5 and 27.5 <= py <= 48.5 and not (
        abs(px - 32.5) > 10.5 and py > 44.0
    )
    thumb = dist_segment(px, py, 21.0, 39.5, 11.5, 28.0) <= 3.7
    fingers = (
        dist_segment(px, py, 22.0, 28.5, 21.5, 13.5) <= 2.6
        or dist_segment(px, py, 29.0, 28.0, 29.0, 9.5) <= 2.7
        or dist_segment(px, py, 36.0, 28.0, 36.5, 11.5) <= 2.6
        or dist_segment(px, py, 42.5, 29.0, 43.5, 17.5) <= 2.4
    )
    if not (cuff or palm or thumb or fingers):
        return None
    if cuff:
        if py <= 49.6:
            return FINESSE[0]
        return FINESSE[0] if px > 36.0 else FINESSE[1]
    # Exposed fingertips above the fingerless glove hem.
    thumb_tip = thumb and px < 15.8 and py < 33.2
    finger_tip = fingers and py < 20.5
    if thumb_tip or finger_tip:
        if (thumb and px >= 14.3 and py >= 31.7) or (fingers and py >= 19.0):
            return FINESSE[0]
        return SKIN[1] if px < 34.0 else SKIN[0]
    # Knuckle/finger separation accents on the glove.
    if fingers and py < 26.5 and any(abs(px - sep) <= 0.85 for sep in (25.3, 32.5, 39.5)):
        return FINESSE[0]
    if palm and 36.0 <= py <= 38.0 and 25.0 <= px <= 39.5:
        return FINESSE[0]
    light = ((px - 28.0) * 0.55 + (py - 32.0) * 0.65) / 16.0
    return shade(FINESSE, light)


def intelligence(x, y):
    """Two-hemisphere brain with bold cortical folds (#06B6D4)."""
    px, py = x + 0.5, y + 0.5
    left_top = ((px - 22.5) / 11.2) ** 2 + ((py - 24.5) / 12.8) ** 2 <= 1.0
    left_bot = ((px - 23.5) / 10.2) ** 2 + ((py - 38.0) / 11.0) ** 2 <= 1.0
    right_top = ((px - 41.5) / 11.2) ** 2 + ((py - 24.5) / 12.8) ** 2 <= 1.0
    right_bot = ((px - 40.5) / 10.2) ** 2 + ((py - 38.0) / 11.0) ** 2 <= 1.0
    stem = ((px - 32.0) / 5.2) ** 2 + ((py - 50.5) / 4.8) ** 2 <= 1.0
    in_brain = left_top or left_bot or right_top or right_bot
    if not (in_brain or stem):
        return None
    if stem and not in_brain:
        return INTELLIGENCE[0] if px > 32.0 else INTELLIGENCE[1]
    # Central fissure dividing the two hemispheres.
    if abs(px - 32.0) <= 1.5 and 12.5 <= py <= 48.0:
        return INTELLIGENCE[0]
    # Symmetric cortical sulci folds so the brain reads clearly at 12 logical px.
    mx = abs(px - 32.0)
    folds = (
        dist_segment(mx, py, 4.0, 21.5, 13.5, 20.5) <= 1.45
        or dist_segment(mx, py, 13.5, 20.5, 16.0, 26.0) <= 1.45
        or dist_segment(mx, py, 5.0, 32.0, 14.5, 34.0) <= 1.45
        or dist_segment(mx, py, 5.5, 42.0, 12.5, 40.5) <= 1.45
    )
    if folds:
        return INTELLIGENCE[0]
    light = ((px - 30.0) * 0.35 + (py - 28.0) * 0.55) / 22.0
    if light < -0.22:
        return INTELLIGENCE[2]
    if light > 0.52:
        return INTELLIGENCE[0]
    return INTELLIGENCE[1]


def _petal(px, py, cx, cy, angle_deg, length, width):
    """Almond-shaped lotus petal rooted at (cx, cy), pointing along angle_deg (0 = up)."""
    rad = math.radians(angle_deg)
    dx, dy = px - cx, py - cy
    # Local u along petal axis (0 at base, length at tip), v perpendicular.
    u = dx * math.sin(rad) - dy * math.cos(rad)
    v = dx * math.cos(rad) + dy * math.sin(rad)
    if u < 0.0 or u > length:
        return None
    t = u / length
    half_w = width * math.sin(math.pi * (t ** 0.85))
    if abs(v) <= half_w:
        return t, v / max(half_w, 0.001)
    return None


def will(x, y):
    """Symmetrical upright lotus blossom (#8B5CF6), no leaves or stem."""
    px, py = x + 0.5, y + 0.5
    base = ((px - 32.0) / 15.0) ** 2 + ((py - 49.5) / 4.2) ** 2 <= 1.0
    center = _petal(px, py, 32.0, 49.0, 0.0, 39.5, 9.2)
    left_mid = _petal(px, py, 31.0, 49.0, -34.0, 35.0, 8.0)
    right_mid = _petal(px, py, 33.0, 49.0, 34.0, 35.0, 8.0)
    left_out = _petal(px, py, 30.0, 50.0, -62.0, 26.5, 7.2)
    right_out = _petal(px, py, 34.0, 50.0, 62.0, 26.5, 7.2)
    if center is not None:
        t, side = center
        if abs(side) > 0.82 and t < 0.88:
            return WILL[0]
        return shade(WILL, -0.55 * t + 0.35 * side + 0.15)
    for petal, flip in ((left_mid, -1.0), (right_mid, 1.0)):
        if petal is not None:
            t, side = petal
            if abs(side) > 0.84 and t < 0.88:
                return WILL[0]
            return shade(WILL, -0.45 * t + 0.25 * flip + 0.15)
    for petal, flip in ((left_out, -1.0), (right_out, 1.0)):
        if petal is not None:
            t, side = petal
            return shade(WILL, -0.35 * t + 0.35 * flip + 0.22)
    if base:
        return WILL[0] if py > 50.0 else WILL[1]
    return None


def health(x, y):
    """Classic bold heart with upper-left specular highlight (#EA0CC1)."""
    px, py = x + 0.5, y + 0.5
    left_lobe = math.hypot(px - 22.0, py - 24.5) <= 13.2
    right_lobe = math.hypot(px - 42.0, py - 24.5) <= 13.2
    lower = False
    if 24.5 <= py <= 54.5:
        t = (py - 24.5) / 30.0
        half_w = 23.0 * ((1.0 - t) ** 0.88)
        lower = abs(px - 32.0) <= half_w
    if not (left_lobe or right_lobe or lower):
        return None
    # Crisp specular highlight inside the upper-left lobe.
    if ((px - 19.5) / 4.2) ** 2 + ((py - 21.5) / 3.4) ** 2 <= 1.0:
        return HEALTH[2]
    light = ((px - 25.0) * 0.45 + (py - 24.0) * 0.72) / 22.0
    return shade(HEALTH, light)


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
    "strength": strength,
    "agility": agility,
    "finesse": finesse,
    "intelligence": intelligence,
    "will": will,
    "health": health,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    record = json.loads((Path(__file__).parent / "ability_icon_generation.json").read_text(encoding="utf-8"))
    assert [icon["id"] for icon in record["icons"]] == list(ICONS)
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
