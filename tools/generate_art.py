#!/usr/bin/env python3
"""Generates the game's original pixel-art backgrounds and item icons.

All art is drawn procedurally here (no third-party assets). Backgrounds are
320x180 and are displayed at 4x (1280x720) with nearest-neighbour filtering,
so one art pixel = 4 screen pixels. Hotspot rects in data/rooms are in screen
pixels: divide by 4 to find the matching art coordinates.

Usage:  python3 tools/generate_art.py      (requires Pillow and numpy)
Re-run after editing, then reopen Godot (or run `godot --headless --import`).
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG_DIR = ROOT / "assets/art/backgrounds"
ITEM_DIR = ROOT / "assets/art/items"
W, H = 320, 180

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def hexc(value):
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


class Canvas:
    def __init__(self, w, h, color="#000000", alpha=False):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 3), np.float32) + hexc(color)
        self.a = np.zeros((h, w), np.float32) if alpha else None
        yy, xx = np.mgrid[0:h, 0:w]
        self.yy, self.xx = yy, xx
        self.bayer = BAYER[yy % 4, xx % 4]

    # --- masks -----------------------------------------------------------
    def _mask(self, draw_fn):
        img = Image.new("L", (self.w, self.h), 0)
        draw_fn(ImageDraw.Draw(img))
        return np.array(img) > 127

    def rect_mask(self, x, y, w, h):
        m = np.zeros((self.h, self.w), bool)
        m[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)] = True
        return m

    def apply(self, mask, color):
        self.px[mask] = hexc(color)
        if self.a is not None:
            self.a[mask] = 255

    # --- primitives ------------------------------------------------------
    def rect(self, x, y, w, h, color):
        self.apply(self.rect_mask(x, y, w, h), color)

    def poly(self, points, color):
        self.apply(self._mask(lambda d: d.polygon(points, fill=255)), color)

    def line(self, points, color, width=1):
        self.apply(self._mask(lambda d: d.line(points, fill=255, width=width)), color)

    def ellipse(self, box, color):
        self.apply(self._mask(lambda d: d.ellipse(box, fill=255)), color)

    def pixel(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = hexc(color)
            if self.a is not None:
                self.a[y, x] = 255

    def outline_rect(self, x, y, w, h, color):
        self.rect(x, y, w, 1, color)
        self.rect(x, y + h - 1, w, 1, color)
        self.rect(x, y, 1, h, color)
        self.rect(x + w - 1, y, 1, h, color)

    def dither(self, mask, c1, c2, t):
        """Ordered-dither blend: t=0 all c1, t=1 all c2 (t may be an array)."""
        pick = (self.bayer < t) & mask
        self.px[mask & ~pick] = hexc(c1)
        self.px[pick] = hexc(c2)
        if self.a is not None:
            self.a[mask] = 255

    def vgrad(self, x, y, w, h, c1, c2):
        t = np.clip((self.yy - y) / max(h - 1, 1), 0, 1)
        self.dither(self.rect_mask(x, y, w, h), c1, c2, t)

    def grain(self, mask, amount, seed, density=0.18):
        rng = np.random.default_rng(seed)
        noise = rng.random((self.h, self.w))
        sign = np.where(rng.random((self.h, self.w)) < 0.5, -1.0, 1.0)
        hit = mask & (noise < density)
        self.px[hit] += (sign[hit] * amount)[:, None]

    # --- lighting --------------------------------------------------------
    def light(self, cx, cy, radius, color, strength, levels=5, squash=1.0, mask=None):
        """Additive light, quantized with ordered dithering for a pixel look."""
        d = np.sqrt((self.xx - cx) ** 2 + ((self.yy - cy) / squash) ** 2)
        f = np.clip(1 - d / radius, 0, 1) ** 1.6 * strength
        f = np.floor(f * levels + self.bayer) / levels
        if mask is not None:
            f = f * mask
        self.px += f[..., None] * hexc(color)[None, None, :] / 255.0 * 140

    def shade(self, amount, levels=10):
        """Multiplies by (1 - amount). Array amounts get dithered steps; a scalar is exact."""
        if np.isscalar(amount):
            self.px *= 1 - amount
            return
        f = np.floor(np.clip(amount, 0, 1) * levels + self.bayer) / levels
        self.px *= (1 - f)[..., None]

    def vignette(self, strength):
        nx = (self.xx - self.w / 2) / (self.w / 2)
        ny = (self.yy - self.h / 2) / (self.h / 2)
        self.shade(np.clip((nx ** 2 + ny ** 2) ** 1.4 * strength, 0, 0.8))

    def save(self, path, scale=1):
        rgb = np.clip(np.round(self.px), 0, 255).astype(np.uint8)
        if self.a is not None:
            img = Image.fromarray(np.dstack([rgb, self.a.astype(np.uint8)]), "RGBA")
        else:
            img = Image.fromarray(rgb, "RGB")
        if scale != 1:
            img = img.resize((self.w * scale, self.h * scale), Image.NEAREST)
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path)
        print("wrote", path.relative_to(ROOT))


# =========================================================================
# Shared furniture
# =========================================================================

def night_sky(c, x, y, w, h, seed):
    c.vgrad(x, y, w, h, "#0a1028", "#24304f")
    rng = np.random.default_rng(seed)
    for _ in range(max(1, w * h // 120)):
        c.pixel(x + int(rng.integers(0, w)), y + int(rng.integers(0, h // 2)), "#9fb0d8")
    # Rooftops across the street, one window lit.
    base = y + h - 14
    c.poly([(x, base + 4), (x + w * 0.3, base - 4), (x + w * 0.55, base + 2), (x + w * 0.8, base - 6), (x + w, base), (x + w, y + h), (x, y + h)], "#070a14")
    c.rect(x + int(w * 0.68), base + 3, 3, 3, "#d9a23e")


def streetlamp(c, x, top, bottom):
    c.rect(x, top + 3, 1, bottom - top - 3, "#1a1f2c")
    c.rect(x - 2, top, 5, 3, "#2a2f3a")
    c.rect(x - 1, top + 3, 3, 1, "#ffd27a")


def door(c, x, y, w, h, wood, dark, light, knob_y):
    c.rect(x - 3, y - 3, w + 6, h + 3, "#2b2420")  # frame trim
    c.rect(x - 2, y - 2, w + 4, 1, "#4a3d33")
    c.vgrad(x, y, w, h, light, wood)
    c.grain(c.rect_mask(x, y, w, h), 6, 11, 0.12)
    pw, ph = (w - 9) // 2, (h - 13) // 3
    for col in range(2):
        for row in range(3):
            px, py = x + 3 + col * (pw + 3), y + 4 + row * (ph + 2) + (2 if row == 2 else 0)
            c.rect(px, py, pw, ph, dark)
            c.rect(px + 1, py + 1, pw - 2, ph - 2, wood)
            c.rect(px, py, pw, 1, "#1f1712")
            c.rect(px, py + ph - 1, pw, 1, light)
    kx = x + w - 5
    c.rect(kx - 1, knob_y - 1, 3, 3, "#8a6a2c")
    c.pixel(kx, knob_y - 1, "#f0d27a")
    c.rect(kx - 1, knob_y - 9, 3, 3, "#6d5a3a")  # deadbolt
    c.pixel(kx, knob_y - 8, "#c9b27a")


# =========================================================================
# Living room
# =========================================================================

def living_room():
    c = Canvas(W, H, "#121827")
    floor_y = 125

    # Ceiling and crown molding.
    c.vgrad(0, 0, W, 9, "#06080e", "#0d1220")
    c.rect(0, 9, W, 2, "#2a3146")
    c.rect(0, 11, W, 1, "#090c14")

    # Damask-ish striped wallpaper.
    wall = c.rect_mask(0, 12, W, floor_y - 12)
    c.apply(wall, "#151c2e")
    stripes = wall & ((c.xx % 12) < 5)
    c.apply(stripes, "#18203a")
    motif = wall & ((c.xx % 12) == 8) & ((c.yy % 10) < 3) & (((c.yy // 10) + (c.xx // 12)) % 2 == 0)
    c.apply(motif, "#1d2745")
    c.grain(wall, 4, 1)
    # Chair rail and wainscot.
    c.rect(0, 96, W, 2, "#2c3348")
    c.rect(0, 98, W, 1, "#0b0e17")
    wains = c.rect_mask(0, 99, W, floor_y - 99)
    c.apply(wains, "#121726")
    for px in range(4, W, 26):
        c.outline_rect(px, 102, 21, 18, "#1b2236")
    # Baseboard.
    c.rect(0, floor_y - 4, W, 4, "#2b2622")
    c.rect(0, floor_y - 4, W, 1, "#3f3730")

    # Floorboards.
    for row, y in enumerate(range(floor_y, H, 6)):
        tone = ["#2b2119", "#30251c", "#281f17"][row % 3]
        c.rect(0, y, W, 6, tone)
        c.rect(0, y + 5, W, 1, "#1a140f")
        offset = (row * 37) % 53
        for sx in range(offset, W, 53):
            c.rect(sx, y, 1, 5, "#1a140f")
    c.grain(c.rect_mask(0, floor_y, W, H - floor_y), 5, 2, 0.25)

    # Rug under the couch area.
    c.rect(150, 142, 160, 34, "#3b1a1d")
    c.outline_rect(152, 144, 156, 30, "#7a4a2a")
    c.outline_rect(155, 147, 150, 24, "#5a2a28")
    for rx in range(160, 300, 10):
        c.poly([(rx, 159), (rx + 4, 155), (rx + 8, 159), (rx + 4, 163)], "#6b3a2a")
    c.poly([(268, 142), (310, 142), (310, 176), (296, 176)], "#1f1a17")  # rumpled corner

    # --- Window (15..72, 35..87) with torn curtains --------------------
    night_sky(c, 20, 39, 48, 44, 5)
    streetlamp(c, 52, 46, 83)
    # Frame and mullions.
    c.outline_rect(18, 37, 52, 48, "#3a2e26")
    c.outline_rect(19, 38, 50, 46, "#241c17")
    c.rect(43, 38, 2, 46, "#3a2e26")
    c.rect(19, 60, 50, 2, "#3a2e26")
    c.rect(15, 85, 58, 3, "#4a3d33")  # sill
    c.rect(15, 88, 58, 1, "#1a140f")
    # Shattered panes: jagged glass remnants and cracks.
    glass = "#7f9cc4"
    c.poly([(20, 39), (31, 39), (24, 47), (20, 51)], glass)
    c.poly([(45, 39), (68, 39), (68, 44), (59, 41), (52, 48)], glass)
    c.poly([(20, 62), (27, 62), (21, 70)], glass)
    c.poly([(60, 62), (68, 62), (68, 76), (64, 68)], glass)
    for pts in [[(31, 39), (35, 50), (43, 52)], [(52, 48), (48, 58)], [(27, 62), (33, 70), (30, 82)], [(64, 68), (56, 74)]]:
        c.line(pts, "#c8d8f0")
    c.pixel(23, 41, "#ffffff")
    c.pixel(62, 64, "#ffffff")
    # Curtains (one torn half-down).
    c.poly([(9, 30), (19, 30), (18, 90), (13, 92), (8, 90)], "#1d3a3f")
    for fx in range(10, 18, 3):
        c.rect(fx, 31, 1, 58, "#142a2e")
    c.poly([(69, 30), (79, 30), (80, 62), (76, 70), (73, 64), (70, 72)], "#1d3a3f")
    c.rect(6, 28, 76, 2, "#5a4a3a")  # rod
    c.pixel(5, 28, "#8a7a5a")
    c.pixel(82, 28, "#8a7a5a")

    # --- Front door (82..120, 37..125) ----------------------------------
    door(c, 84, 38, 34, 87, "#3e2c20", "#2a1d15", "#4d3828", 82)
    c.rect(101, 50, 1, 1, "#d9c08a")  # peephole
    c.rect(84, 125, 34, 5, "#3a3f2a")  # doormat
    c.outline_rect(84, 125, 34, 5, "#2a2e1e")
    c.rect(121, 72, 3, 5, "#c9c2b0")  # light switch
    c.pixel(122, 74, "#7a7468")

    # --- Key board (125..138, 54..70) ----------------------------------
    c.rect(125, 54, 14, 12, "#5a4330")
    c.outline_rect(125, 54, 14, 12, "#3a2a1e")
    c.rect(126, 55, 12, 1, "#6e5440")
    for i, hx in enumerate([128, 132, 136]):
        c.rect(hx, 58, 1, 3, "#c8c8c8")
        c.pixel(hx, 61, "#9a9a9a")
        if i < 2:  # keys still on hooks
            c.rect(hx - 1, 62, 3, 2, "#a8a8b0")
            c.rect(hx, 64, 1, 4, "#a8a8b0")
            c.pixel(hx + 1, 66, "#a8a8b0")
    c.pixel(136, 63, "#3a2a1e")  # empty hook shadow
    c.rect(131, 128, 2, 2, "#c9a04a")  # fallen brass tag on the floor
    c.pixel(131, 128, "#f0d27a")

    # --- Crooked painting above couch ----------------------------------
    c.poly([(232, 33), (268, 37), (266, 60), (230, 56)], "#4a3a26")
    c.poly([(234, 35), (265, 39), (263, 58), (232, 54)], "#1b2a33")
    c.poly([(234, 50), (246, 42), (255, 48), (263, 45), (263, 58), (232, 54)], "#22352c")
    c.pixel(254, 41, "#d8c890")
    c.line([(249, 30), (232, 33)], "#555555")
    c.line([(249, 30), (268, 37)], "#555555")

    # --- Couch (217..302, 77..123) with slashed cushions ----------------
    c.rect(222, 80, 76, 26, "#3d4762")  # backrest
    c.rect(222, 80, 76, 2, "#56607e")
    for bx in (247, 272):
        c.rect(bx, 82, 1, 24, "#2c3449")
    c.rect(218, 92, 9, 31, "#47516e")  # arms
    c.rect(293, 92, 9, 31, "#47516e")
    c.rect(218, 92, 9, 2, "#5e6888")
    c.rect(293, 92, 9, 2, "#5e6888")
    c.rect(227, 104, 66, 12, "#4f5a79")  # seat cushions
    c.rect(227, 104, 66, 1, "#6a7598")
    for sx in (249, 271):
        c.rect(sx, 104, 1, 12, "#353e57")
    c.rect(218, 116, 84, 6, "#323a52")  # base
    for lx in (221, 297):
        c.rect(lx, 122, 2, 2, "#1a140f")
    # Slashes and stuffing.
    for pts in [[(231, 86), (241, 98)], [(260, 84), (266, 100)], [(236, 106), (246, 112)], [(276, 105), (286, 113)]]:
        c.line(pts, "#1a1f2c", 2)
    for sx, sy in [(240, 97), (243, 99), (265, 99), (246, 111), (285, 112), (288, 110), (262, 101)]:
        c.rect(sx, sy, 3, 2, "#d8d4c4")
        c.pixel(sx + 1, sy - 1, "#eeeadc")
    for sx, sy in [(232, 130), (275, 136), (190, 141), (300, 128)]:  # stuffing on the floor
        c.rect(sx, sy, 3, 2, "#c8c4b4")
    # The dark gap under the couch, with one faint gold glint.
    c.rect(219, 123, 82, 6, "#030406")
    c.pixel(262, 126, "#5a4a22")

    # --- Toppled bookshelf (141..214, 100..135) ------------------------
    c.poly([(146, 128), (152, 104), (212, 112), (207, 134)], "#3b2a1e")
    c.poly([(152, 104), (212, 112), (211, 115), (151, 107)], "#5a4230")
    for i in range(1, 5):
        t = i / 5
        x0, x1 = 146 + (152 - 146) * 0 + int((207 - 146) * t), 152 + int((212 - 152) * t)
        c.line([(x1, 104 + int(8 * t)), (x0, 128 + int(6 * t))], "#22170f")
    # Spilled books.
    books = [(150, 132, 7, 3, "#7a2e2e"), (160, 136, 5, 2, "#2e5a7a"), (172, 133, 8, 3, "#5a6b2e"),
             (186, 138, 6, 2, "#7a6a2e"), (198, 135, 7, 3, "#4a2e6a"), (208, 139, 5, 2, "#2e7a5a"),
             (143, 139, 6, 2, "#6a4a2e"), (178, 141, 6, 2, "#8a2e3a")]
    for bx, by, bw, bh, col in books:
        c.rect(bx, by, bw, bh, col)
        c.rect(bx, by, bw, 1, "#d8d0b8")
    for ox, oy in [(166, 141), (192, 131)]:  # open books, pages up
        c.poly([(ox, oy), (ox + 4, oy - 2), (ox + 8, oy), (ox + 4, oy + 2)], "#e4dcc4")
        c.pixel(ox + 4, oy, "#8a8270")
    for px, py in [(184, 128), (156, 143), (214, 130)]:  # loose papers
        c.rect(px, py, 4, 3, "#c8c4b8")

    # --- Face-down photo frame (102..135, 137..160) --------------------
    c.rect(106, 143, 25, 15, "#6e5a3e")
    c.outline_rect(106, 143, 25, 15, "#4a3a26")
    c.rect(108, 145, 21, 11, "#8a7656")
    c.line([(118, 146), (122, 154)], "#5a4a30")  # easel stand
    for gx, gy in [(104, 141), (133, 148), (112, 159), (129, 140)]:  # glass glints
        c.pixel(gx, gy, "#c8d8f0")

    # --- Kitchen doorway (303..320, 37..125) ---------------------------
    c.rect(304, 38, 16, 87, "#1e2a24")
    c.vgrad(306, 40, 14, 85, "#2e4036", "#1a241f")
    c.rect(303, 37, 2, 88, "#2b2420")
    c.rect(303, 37, 17, 2, "#2b2420")

    # --- Lighting -------------------------------------------------------
    c.shade(0.28)
    c.light(46, 60, 70, "#e08a3a", 0.75)                     # streetlight through the window
    c.light(70, 150, 90, "#e08a3a", 0.45, squash=0.45)        # spill on the floor
    c.light(312, 90, 50, "#7fb89a", 0.35, squash=1.6)         # cold kitchen light
    c.light(52, 47, 8, "#ffd27a", 0.9)                        # lamp head glow
    c.light(262, 126, 5, "#ffe9a8", 0.5)                      # the feather's faint glow
    c.vignette(0.55)
    c.save(BG_DIR / "living_room.png")


# =========================================================================
# Kitchen
# =========================================================================

def kitchen():
    c = Canvas(W, H, "#151b1f")
    floor_y = 130

    c.vgrad(0, 0, W, 10, "#06090b", "#0f1518")
    c.rect(0, 10, W, 2, "#2a3332")
    wall = c.rect_mask(0, 12, W, floor_y - 12)
    c.apply(wall, "#1a2422")
    c.grain(wall, 4, 3)
    # Tiled backsplash behind the counter.
    tile = c.rect_mask(64, 77, 136, 15)
    c.apply(tile, "#2a3a38")
    c.apply(tile & (((c.xx - 64) % 6 == 0) | ((c.yy - 77) % 5 == 0)), "#1d2a28")
    c.rect(0, floor_y - 3, W, 3, "#2a2a26")

    # Checkerboard linoleum.
    flo = c.rect_mask(0, floor_y, W, H - floor_y)
    checker = flo & ((((c.xx // 10) + ((c.yy - floor_y) // 7)) % 2) == 0)
    c.apply(flo, "#3a3832")
    c.apply(checker, "#24231f")
    c.grain(flo, 5, 4, 0.2)

    # --- Back door with bolt and chain (20..57, 42..130) ---------------
    door(c, 21, 43, 34, 87, "#3a2c22", "#281d15", "#4a382a", 88)
    c.rect(26, 47, 24, 18, "#0a1028")  # door window
    night_sky(c, 27, 48, 22, 16, 9)
    c.rect(37, 47, 2, 18, "#3a2c22")
    c.rect(48, 78, 8, 3, "#9aa0aa")  # bolt thrown into the frame
    c.pixel(55, 79, "#d0d4dc")
    for i, (chx, chy) in enumerate([(48, 70), (50, 71), (52, 72), (54, 72), (56, 71)]):
        c.pixel(chx, chy, "#c9a04a" if i % 2 == 0 else "#8a6a2c")

    # --- Window with blinds over the sink (100..160, 42..77) -----------
    night_sky(c, 102, 44, 56, 30, 7)
    streetlamp(c, 140, 50, 74)
    for by in range(44, 60, 3):  # half-drawn blinds
        c.rect(102, by, 56, 2, "#8a8f86")
        c.rect(102, by + 1, 56, 1, "#5a5f58")
    c.rect(102, 60, 56, 1, "#3a3f38")
    c.outline_rect(100, 42, 60, 34, "#3a3a36")
    c.rect(98, 76, 64, 2, "#4a4a44")  # sill
    c.rect(106, 71, 5, 5, "#6a3a2a")  # potted plant
    c.poly([(104, 71), (108, 63), (113, 71)], "#2e5a32")
    c.pixel(108, 65, "#4a8a4a")

    # --- Upper cabinets, doors flung open ------------------------------
    for x0 in (66, 164):
        c.rect(x0, 18, 30, 40, "#0c100f")
        for sy in (30, 42):
            c.rect(x0 + 1, sy, 28, 1, "#3a3a34")
        c.rect(x0 + 4, 26, 6, 4, "#c8c4b8")  # a few dishes left
        c.rect(x0 + 18, 38, 5, 4, "#a8b0b8")
    c.poly([(58, 18), (66, 20), (66, 56), (58, 60)], "#4a4038")  # open doors
    c.poly([(194, 20), (202, 18), (202, 60), (194, 56)], "#4a4038")

    # --- Counter, sink, drawers (80..190, 92..130) ---------------------
    c.rect(64, 92, 136, 4, "#7a7c76")
    c.rect(64, 92, 136, 1, "#a4a69e")
    c.rect(66, 96, 132, 31, "#3a3f3c")
    c.rect(110, 92, 40, 3, "#4a5458")  # sink basin edge
    c.rect(128, 86, 2, 6, "#9aa4a8")  # tap
    c.rect(128, 86, 6, 2, "#9aa4a8")
    c.rect(170, 86, 10, 6, "#5a2a2a")  # toaster
    c.rect(171, 85, 3, 1, "#2a1414")
    c.rect(176, 85, 3, 1, "#2a1414")
    c.rect(74, 85, 9, 7, "#4a5a6a")  # kettle
    c.rect(82, 87, 3, 2, "#4a5a6a")
    # Drawers: yanked open (protruding, dark) except the junk drawer.
    for dx, dw in [(68, 44), (157, 40)]:
        c.rect(dx - 2, 100, dw + 4, 13, "#4e5450")
        c.rect(dx, 101, dw, 6, "#141716")
        for k in range(dx + 3, dx + dw - 3, 6):
            c.rect(k, 102, 3, 2, "#8a8e86")
    c.rect(116, 100, 38, 14, "#4a504c")  # junk drawer, closed
    c.outline_rect(116, 100, 38, 14, "#2a2e2c")
    c.rect(130, 106, 10, 2, "#b8b0a0")
    c.pixel(130, 106, "#e0d8c8")
    for cx0 in range(68, 196, 22):  # lower cabinet doors
        c.outline_rect(cx0, 116, 20, 11, "#2a2e2c")
        c.rect(cx0 + 16, 120, 1, 3, "#8a8e86")
    for fx, fy, col in [(80, 133, "#c8c4b8"), (95, 138, "#7a5a3a"), (170, 135, "#c8c4b8"), (62, 140, "#3a6a8a")]:
        c.rect(fx, fy, 4, 2, col)  # drawer contents on the floor

    # --- Fridge (205..247, 47..130) with calendar ----------------------
    c.rect(206, 46, 41, 83, "#8b918f")
    c.vgrad(207, 47, 39, 81, "#9ea4a2", "#6e7472")
    c.rect(206, 70, 41, 1, "#4a504e")
    c.rect(242, 54, 2, 12, "#c8ccca")
    c.rect(242, 76, 2, 20, "#c8ccca")
    c.rect(206, 128, 41, 2, "#2a2e2c")
    c.rect(214, 75, 20, 22, "#d8d2c0")  # calendar
    c.rect(214, 75, 20, 4, "#5a2a2a")
    for gx in range(214, 234, 4):
        c.rect(gx, 79, 1, 18, "#a8a290")
    for gy in range(79, 97, 4):
        c.rect(214, gy, 20, 1, "#a8a290")
    c.outline_rect(221, 86, 6, 5, "#c02020")  # today, circled in red
    c.pixel(220, 88, "#c02020")
    c.pixel(227, 88, "#c02020")
    for mx, my, col in [(211, 52, "#c84a3a"), (232, 58, "#3a7ac8"), (210, 104, "#e0c040")]:
        c.rect(mx, my, 3, 3, col)

    # --- Muddy footprints that stop dead (185..295, 145..165) ----------
    for i, fx in enumerate(range(286, 196, -15)):
        fy = 150 if i % 2 == 0 else 158
        c.ellipse([fx, fy, fx + 8, fy + 4], "#6a4824")
        c.rect(fx + 9, fy + 1, 3, 3, "#6a4824")
        c.rect(fx + 2, fy + 1, 4, 2, "#3a2612")
        c.pixel(fx + 10, fy + 2, "#3a2612")

    # --- Doorway back to the living room (295..320, 42..130) -----------
    c.rect(296, 43, 24, 87, "#14171f")
    c.vgrad(298, 45, 22, 85, "#20222c", "#151820")
    c.rect(295, 42, 2, 88, "#2b2420")
    c.rect(295, 42, 25, 2, "#2b2420")

    # --- Lighting -------------------------------------------------------
    c.shade(0.25)
    c.light(130, 60, 70, "#e08a3a", 0.6)                  # streetlight through the blinds
    c.light(130, 150, 80, "#e08a3a", 0.35, squash=0.4)
    c.light(226, 100, 60, "#8ab0c8", 0.25, squash=1.4)    # cold fridge sheen
    c.light(140, 51, 7, "#ffd27a", 0.9)
    c.light(318, 95, 40, "#e08a3a", 0.2, squash=1.6)      # warm spill from the living room
    c.vignette(0.55)
    c.save(BG_DIR / "kitchen.png")


# =========================================================================
# Item icons (32x32, transparent, dark outline)
# =========================================================================

def outline(c, color="#0b0d12"):
    filled = c.a > 0
    edge = np.zeros_like(filled)
    for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        edge |= np.roll(np.roll(filled, dy, 0), dx, 1)
    c.apply(edge & ~filled, color)


def icon_flashlight():
    c = Canvas(32, 32, alpha=True)
    c.poly([(5, 21), (19, 7), (24, 12), (10, 26)], "#e0b020")   # body
    c.poly([(6, 21), (19, 8), (20, 9), (7, 22)], "#f8dc60")     # highlight
    c.poly([(19, 5), (26, 12), (28, 10), (21, 3)], "#c09018")   # head
    c.line([(21, 4), (27, 10)], "#d8f0ff", 2)                   # lens
    c.pixel(23, 5, "#ffffff")
    for k in range(4):                                           # rubber grip
        c.line([(9 + k * 2, 19 + k * 2 - 4), (13 + k * 2, 23 + k * 2 - 4)], "#2a2418")
    c.rect(14, 15, 3, 3, "#3a3a3a")                              # switch
    c.pixel(15, 15, "#8a8a8a")
    outline(c)
    c.save(ITEM_DIR / "flashlight.png")


def icon_glass_shard():
    c = Canvas(32, 32, alpha=True)
    c.poly([(8, 27), (13, 6), (17, 12), (24, 4), (22, 18), (26, 26)], "#6f8fbf")
    c.poly([(13, 8), (16, 13), (12, 24), (10, 24)], "#a8c4e8")
    c.poly([(23, 7), (21, 17), (19, 15)], "#c8dcf4")
    c.line([(16, 13), (20, 24)], "#4a6a98")
    c.pixel(14, 10, "#ffffff")
    c.pixel(22, 9, "#ffffff")
    c.pixel(20, 22, "#ffffff")
    outline(c, "#182030")
    c.save(ITEM_DIR / "glass_shard.png")


def icon_key_tag():
    c = Canvas(32, 32, alpha=True)
    c.ellipse([4, 3, 13, 12], "#9a9a9a")                         # split ring
    c.ellipse([6, 5, 11, 10], "#000000")
    c.a[6:10, 7:11] = 0
    c.ellipse([9, 9, 28, 28], "#b8862c")                         # brass tag
    c.ellipse([10, 10, 26, 26], "#d8a640")
    c.ellipse([12, 11, 20, 17], "#f0cc70")
    c.ellipse([11, 11, 15, 15], "#3a2a10")                       # hole
    c.ellipse([12, 12, 14, 14], "#000000")
    c.a[12:15, 12:15] = 0
    for ty in (19, 22):                                          # stamped lettering
        for tx in range(14, 24, 2):
            c.pixel(tx, ty, "#7a5418")
    outline(c)
    c.save(ITEM_DIR / "key_tag.png")


def icon_gold_feather():
    c = Canvas(32, 32, alpha=True)
    c.light(16, 16, 15, "#ffe9a8", 0.0)                          # (keeps API symmetric)
    halo = (np.sqrt((c.xx - 16) ** 2 + (c.yy - 15) ** 2) < 14) & (c.bayer < 0.25)
    c.apply(halo, "#5a4a1c")
    c.a[halo] = 110
    c.poly([(7, 27), (12, 14), (19, 5), (25, 3), (23, 10), (17, 19), (10, 26)], "#e8c870")
    c.poly([(12, 16), (19, 7), (24, 4), (20, 9), (14, 17)], "#fff0b8")
    for k in range(6):                                           # barbs
        x, y = 11 + k * 2, 22 - k * 3
        c.line([(x, y), (x + 5, y - 1)], "#c8a048")
    c.line([(5, 29), (24, 4)], "#fff8e0")                        # shaft
    c.pixel(5, 29, "#8a6a2c")
    c.pixel(6, 28, "#8a6a2c")
    for sx, sy in [(27, 8), (8, 12), (26, 20)]:                  # sparkles
        c.pixel(sx, sy, "#ffffff")
    solid = c.a == 255
    a_backup = c.a.copy()
    c.a = solid.astype(np.float32) * 255
    outline(c, "#3a2a08")
    c.a = np.maximum(c.a, a_backup)
    c.save(ITEM_DIR / "gold_feather.png")


if __name__ == "__main__":
    living_room()
    kitchen()
    icon_flashlight()
    icon_glass_shard()
    icon_key_tag()
    icon_gold_feather()
