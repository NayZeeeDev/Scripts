"""
Default images for the emissive screens of the part-2 props (what a prop shows before a DUI
replaces its 'nz_amb_screen' texture). Everything is drawn with Pillow; generic UI, no maker names.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nzprops import AMBER, RED, TEAL, TEAL_HI, font

INK = (200, 206, 210)
INK_DIM = (120, 128, 134)
PANEL = (14, 17, 20)


def _star(d: ImageDraw.ImageDraw, cx, cy, size, color=(40, 110, 210), rod=(255, 255, 255)):
    """Six-armed star of life (generic EMS symbol), centred at (cx, cy), tip-to-tip `size`."""
    half, w = size / 2, size * 0.15
    for a in (90.0, 30.0, -30.0):
        t = (math.cos(math.radians(a)), -math.sin(math.radians(a)))
        n = (-t[1], t[0])
        pts = [(cx + t[0] * half + n[0] * w, cy + t[1] * half + n[1] * w), (cx + t[0] * half - n[0] * w, cy + t[1] * half - n[1] * w),
               (cx - t[0] * half - n[0] * w, cy - t[1] * half - n[1] * w), (cx - t[0] * half + n[0] * w, cy - t[1] * half + n[1] * w)]
        d.polygon(pts, fill=color)
    d.rectangle([cx - size * 0.022, cy - size * 0.36, cx + size * 0.022, cy + size * 0.34], fill=rod)
    pts = [(cx + size * 0.075 * math.sin(k / 12 * 2.6 * math.pi), cy + size * 0.27 - k / 12 * size * 0.51) for k in range(13)]
    d.line(pts, fill=rod, width=max(1, int(size * 0.03)))


def _header(d, w, s, title, right):
    d.rectangle([0, 0, w, int(24 * s)], fill=PANEL)
    d.text((int(8 * s), int(12 * s)), title, font=font("label", 11 * s), fill=INK, anchor="lm")
    d.text((w - int(8 * s), int(12 * s)), right, font=font("mono", 10 * s), fill=INK_DIM, anchor="rm")


# ---------------------------------------------------------------------------------------------
def draw_ultrasound_ui(w=512, h=320, seed=3):
    """B-mode eFAST screen: sector image with speckle, liver / kidney interface, side menu."""
    rng = np.random.default_rng(seed)
    s = w / 512.0
    img = Image.new("RGB", (w, h), (4, 5, 6))
    d = ImageDraw.Draw(img)
    _header(d, w, s, "eFAST  ·  ABDOMEN  ·  ADULT", "C5-2   MI 0.9   12:04")
    # sector image
    cx, cy = int(170 * s), int(34 * s)
    R0, R1 = 18 * s, 270 * s
    ang = math.radians(36)
    sw, sh = int(340 * s), int(h - 40 * s)
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    dx, dy = xx - (cx), yy + (int(34 * s) - cy)
    r = np.hypot(dx, dy)
    a = np.arctan2(dx, dy)
    inside = (r > R0) & (r < R1) & (np.abs(a) < ang)
    speck = rng.random((sh, sw)).astype(np.float32)
    speck = np.asarray(Image.fromarray((speck * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.9 * s)), np.float32) / 255
    depth = (r - R0) / (R1 - R0)
    tissue = 0.35 + 0.25 * np.sin(a * 5 + depth * 9) * 0.3
    # liver (homogeneous), kidney ellipse (darker cortex, bright sinus), bright capsule line
    kx, ky = 0.18, 0.62
    ke = ((a / ang - kx) / 0.28) ** 2 + ((depth - ky) / 0.16) ** 2
    tissue = np.where(ke < 1, 0.22 + 0.5 * (ke < 0.35), tissue)
    tissue += 0.55 * np.exp(-((ke - 1.0) / 0.06) ** 2)
    # free fluid stripe (anechoic) between liver and kidney - Morison's pouch
    fluid = np.exp(-((ke - 1.25) / 0.07) ** 2) * (a / ang > -0.2)
    tissue = tissue * (1 - 0.9 * fluid)
    val = np.clip(tissue * (0.55 + 0.9 * speck) * (1.0 - 0.35 * depth), 0, 1) * inside
    g = (val * 235).astype(np.uint8)
    sector = Image.fromarray(np.dstack([g, g, (g * 1.02).clip(0, 255).astype(np.uint8)]), "RGB")
    img.paste(sector, (0, int(34 * s)), Image.fromarray((inside * 255).astype(np.uint8), "L"))
    # depth scale + labels
    for k in range(0, 17, 2):
        yk = int(34 * s + R0 + (R1 - R0) * k / 16)
        if yk < h - 8 * s:
            d.line([(int(338 * s), yk), (int(346 * s), yk)], fill=INK_DIM, width=1)
            d.text((int(334 * s), yk), str(k), font=font("mono", 8 * s), fill=INK_DIM, anchor="rm")
    d.text((int(10 * s), int(34 * s)), "B", font=font("label", 12 * s), fill=TEAL_HI, anchor="lt")
    for k, t in enumerate(("Frq 3.5", "Gn 51", "D 16", "DR 72", "FR 30")):
        d.text((int(10 * s), int((52 + k * 13) * s)), t, font=font("mono", 9 * s), fill=INK_DIM, anchor="lt")
    d.text((int(118 * s), int(h - 26 * s)), "RUQ  ·  MORISON", font=font("label-semi", 9 * s), fill=INK, anchor="lt")
    # right column: eFAST checklist
    x0 = int(356 * s)
    d.rectangle([x0, int(30 * s), w - int(6 * s), h - int(6 * s)], fill=(10, 12, 14))
    d.text((x0 + int(8 * s), int(40 * s)), "eFAST", font=font("label", 11 * s), fill=INK, anchor="lt")
    d.text((w - int(12 * s), int(40 * s)), "1/6", font=font("mono", 9 * s), fill=INK_DIM, anchor="rt")
    rows = [("RUQ", "POS", RED), ("LUQ", "--", INK_DIM), ("PELVIS", "--", INK_DIM), ("CARDIAC", "--", INK_DIM),
            ("LUNG R", "--", INK_DIM), ("LUNG L", "--", INK_DIM)]
    for k, (lbl, res, col) in enumerate(rows):
        y = int((62 + k * 24) * s)
        if k == 0:
            d.rectangle([x0 + int(4 * s), y - int(3 * s), w - int(10 * s), y + int(16 * s)], fill=(18, 40, 38))
            d.rectangle([x0 + int(4 * s), y - int(3 * s), x0 + int(6 * s), y + int(16 * s)], fill=TEAL)
        d.text((x0 + int(12 * s), y + int(6 * s)), lbl, font=font("label-semi", 10 * s), fill=INK, anchor="lm")
        d.text((w - int(14 * s), y + int(6 * s)), res, font=font("mono-bold", 9 * s), fill=col, anchor="rm")
    d.text((x0 + int(8 * s), h - int(14 * s)), "FREE FLUID", font=font("label", 10 * s), fill=AMBER, anchor="lm")
    return img


def draw_angio_ui(w=512, h=288, seed=5):
    """Fluoroscopy live image: grey abdomen with spine, contrast-filled vessel tree, overlay text."""
    rng = np.random.default_rng(seed)
    s = w / 512.0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * 0.5, h * 0.52
    rr = np.hypot((xx - cx) / (w * 0.42), (yy - cy) / (h * 0.62))
    base = 0.55 - 0.35 * np.clip(rr, 0, 1.4) ** 2
    # spine: vertebral bodies down the middle
    for k in range(-3, 4):
        vy = cy + k * h * 0.15
        e = ((xx - cx) / (w * 0.055)) ** 2 + ((yy - vy) / (h * 0.06)) ** 2
        base += 0.22 * np.exp(-e ** 2)
    noise = rng.normal(0, 0.035, (h, w)).astype(np.float32)
    val = np.clip(base + noise, 0, 1)
    img = Image.fromarray((val * 210).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.8 * s)).convert("RGB")
    d = ImageDraw.Draw(img)
    # contrast vessels (dark): aorta + branches
    ink = (24, 26, 28)
    pts = [(cx + 0.06 * w, h * 0.02), (cx + 0.05 * w, h * 0.35), (cx + 0.045 * w, h * 0.70), (cx + 0.04 * w, h * 0.98)]
    d.line(pts, fill=ink, width=int(9 * s), joint="curve")

    def branch(x, y, ang, ln, wd, depth):
        if depth == 0 or wd < 1:
            return
        x2 = x + math.cos(ang) * ln
        y2 = y + math.sin(ang) * ln
        d.line([(x, y), (x2, y2)], fill=ink, width=max(1, int(wd)))
        branch(x2, y2, ang - 0.45 + rng.random() * 0.2, ln * 0.72, wd * 0.68, depth - 1)
        branch(x2, y2, ang + 0.35 + rng.random() * 0.2, ln * 0.70, wd * 0.62, depth - 1)
    branch(cx + 0.05 * w, h * 0.30, math.radians(205), 60 * s, 5 * s, 5)
    branch(cx + 0.05 * w, h * 0.42, math.radians(-25), 58 * s, 5 * s, 5)
    branch(cx + 0.045 * w, h * 0.56, math.radians(160), 70 * s, 4.5 * s, 5)
    # bleed blush
    bx, by = cx - 0.22 * w, h * 0.66
    d.ellipse([bx - 10 * s, by - 7 * s, bx + 10 * s, by + 7 * s], fill=(40, 42, 44))
    img = img.filter(ImageFilter.GaussianBlur(0.6 * s))
    d = ImageDraw.Draw(img)
    # circular collimator vignette
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([w * 0.5 - h * 0.62, h * 0.5 - h * 0.62, w * 0.5 + h * 0.62, h * 0.5 + h * 0.62], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(10 * s))
    black = Image.new("RGB", (w, h), (3, 4, 5))
    img = Image.composite(img, black, mask)
    d = ImageDraw.Draw(img)
    d.text((int(10 * s), int(17 * s)), "FLUORO  ·  ROOM 2", font=font("label", 11 * s), fill=INK, anchor="lm")
    d.text((int(10 * s), int(36 * s)), "LIVE  ·  FLUORO 7.5 p/s", font=font("mono", 9 * s), fill=TEAL_HI, anchor="lm")
    d.text((w - int(10 * s), int(17 * s)), "AP 0°  CRAN 0°", font=font("mono", 9 * s), fill=INK, anchor="rm")
    d.text((w - int(10 * s), int(32 * s)), "kV 78   mA 12", font=font("mono", 9 * s), fill=INK_DIM, anchor="rm")
    d.text((int(10 * s), h - int(12 * s)), "DOSE 41 mGy", font=font("mono", 9 * s), fill=INK_DIM, anchor="lm")
    d.text((w - int(10 * s), h - int(12 * s)), "00:42", font=font("mono-bold", 10 * s), fill=AMBER, anchor="rm")
    d.ellipse([bx - 16 * s, by - 13 * s, bx + 16 * s, by + 13 * s], outline=RED, width=max(1, int(2 * s)))
    d.text((bx, by + 22 * s), "BLEED", font=font("label", 9 * s), fill=RED, anchor="mm")
    return img


def draw_waiting_board(w=1024, h=576):
    """Waiting-room information board: header with the star of life, now-serving ticket, queue,
    clock and a hygiene notice (default image before a DUI replaces the screen)."""
    img = Image.new("RGB", (w, h), (6, 9, 12))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    glow = np.clip(1 - np.hypot((xx - w * 0.3) / (w * 0.6), (yy - h * 0.5) / (h * 0.7)), 0, 1) ** 2
    arr = np.asarray(img, np.float32) + glow[..., None] * np.array([6, 18, 24], np.float32)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    s = h / 576.0
    d.rectangle([0, 0, w, int(70 * s)], fill=(14, 20, 26))
    _star(d, int(44 * s), int(35 * s), 46 * s)
    d.text((int(82 * s), int(35 * s)), "EMERGENCY DEPARTMENT  ·  PATIENT INFORMATION", font=font("label", 24 * s), fill=(230, 236, 240), anchor="lm")
    d.text((w - int(28 * s), int(35 * s)), "12:04", font=font("mono-bold", 28 * s), fill=(230, 236, 240), anchor="rm")
    # now serving tile
    d.rounded_rectangle([int(28 * s), int(96 * s), int(500 * s), int(420 * s)], radius=int(14 * s), fill=(12, 34, 40))
    d.text((int(60 * s), int(132 * s)), "NOW SERVING", font=font("label-semi", 26 * s), fill=TEAL_HI, anchor="lm")
    d.text((int(264 * s), int(262 * s)), "A-014", font=font("label", 128 * s), fill=(240, 244, 246), anchor="mm")
    d.text((int(264 * s), int(370 * s)), "TRIAGE  ROOM 2", font=font("label-semi", 30 * s), fill=(170, 200, 206), anchor="mm")
    # queue list
    x0 = int(530 * s)
    d.text((x0, int(112 * s)), "NEXT", font=font("label-semi", 22 * s), fill=(150, 162, 170), anchor="lm")
    rows = [("A-015", "TRIAGE", "4 min"), ("B-007", "X-RAY", "9 min"), ("A-016", "TRIAGE", "12 min"), ("C-002", "BLOOD", "15 min")]
    for k, (t, room, eta) in enumerate(rows):
        y = int((150 + k * 66) * s)
        d.rounded_rectangle([x0, y, w - int(28 * s), y + int(54 * s)], radius=int(8 * s), fill=(14, 20, 26))
        d.text((x0 + int(18 * s), y + int(27 * s)), t, font=font("mono-bold", 28 * s), fill=(220, 226, 230), anchor="lm")
        d.text((x0 + int(190 * s), y + int(27 * s)), room, font=font("label-semi", 22 * s), fill=(150, 162, 170), anchor="lm")
        d.text((w - int(46 * s), y + int(27 * s)), eta, font=font("mono", 22 * s), fill=AMBER, anchor="rm")
    # footer notice
    d.rectangle([0, h - int(110 * s), w, h], fill=(12, 16, 20))
    d.text((int(28 * s), h - int(76 * s)), "Average wait  38 min", font=font("label-semi", 24 * s), fill=(200, 210, 214), anchor="lm")
    d.text((int(28 * s), h - int(38 * s)), "Please clean your hands at the entrance  ·  Tell staff if your condition gets worse",
           font=font("label-reg", 20 * s), fill=(130, 140, 146), anchor="lm")
    return img


def draw_lightbox_panel(w=512, h=512):
    """Cool white diffuser with a faint lamp gradient (three tubes behind it)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 0.93 + 0.05 * np.cos((xx / w - 0.5) * math.pi) * np.cos((yy / h - 0.5) * math.pi)
    for k in range(1, 4):   # three fluorescent tubes behind the diffuser
        v += 0.025 * np.exp(-((xx / w - k / 4) / 0.06) ** 2)
    col = np.clip(np.dstack([v * 236, v * 244, v * 250]), 0, 255).astype(np.uint8)
    img = Image.fromarray(col, "RGB")
    return img


def draw_mixer_lcd(w=256, h=128):
    """Collection mixer display: volume, target, flow bar, rocking indicator."""
    img = Image.new("RGB", (w, h), (8, 14, 16))
    d = ImageDraw.Draw(img)
    s = w / 256.0
    d.text((int(8 * s), int(8 * s)), "COLLECT", font=font("label", 12 * s), fill=TEAL_HI, anchor="lt")
    d.text((w - int(8 * s), int(8 * s)), "O NEG", font=font("label", 12 * s), fill=RED, anchor="rt")
    d.text((int(8 * s), int(64 * s)), "312", font=font("label", 44 * s), fill=(236, 240, 242), anchor="lm")
    d.text((int(100 * s), int(74 * s)), "mL / 450", font=font("mono", 13 * s), fill=INK_DIM, anchor="lm")
    d.rectangle([int(8 * s), int(98 * s), w - int(8 * s), int(110 * s)], outline=(40, 60, 62), width=max(1, int(1 * s)))
    d.rectangle([int(10 * s), int(100 * s), int(10 * s + (w - 20 * s) * 0.69), int(108 * s)], fill=TEAL)
    d.text((w - int(8 * s), int(66 * s)), "62 mL/min", font=font("mono", 11 * s), fill=AMBER, anchor="rm")
    return img


def draw_bay_monitor(w=512, h=256):
    """Bay wall monitor (dark, standby): star of life, clock, cabin climate and oxygen supply."""
    img = Image.new("RGB", (w, h), (4, 6, 7))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    d.rectangle([0, 0, w, int(26 * s)], fill=PANEL)
    d.text((int(10 * s), int(13 * s)), "TREATMENT BAY", font=font("label", 11 * s), fill=INK, anchor="lm")
    d.text((w - int(10 * s), int(13 * s)), "STANDBY", font=font("mono", 10 * s), fill=AMBER, anchor="rm")
    _star(d, int(84 * s), int(118 * s), 92 * s)
    d.text((int(150 * s), int(98 * s)), "12:04", font=font("label", 52 * s), fill=(220, 226, 230), anchor="lm")
    d.text((int(152 * s), int(146 * s)), "TUE 14 OCT", font=font("label-semi", 14 * s), fill=INK_DIM, anchor="lm")
    tiles = [("CABIN", "21 °C"), ("O2 MAIN", "1850 L"), ("INVERTER", "OK")]
    for k, (a, v) in enumerate(tiles):
        x = int((24 + k * 160) * s)
        d.rectangle([x, int(184 * s), x + int(150 * s), int(240 * s)], fill=(10, 14, 16))
        d.rectangle([x, int(184 * s), x + int(3 * s), int(240 * s)], fill=TEAL)
        d.text((x + int(12 * s), int(198 * s)), a, font=font("label-semi", 10 * s), fill=INK_DIM, anchor="lm")
        d.text((x + int(12 * s), int(222 * s)), v, font=font("label", 18 * s), fill=(220, 226, 230), anchor="lm")
    return img
