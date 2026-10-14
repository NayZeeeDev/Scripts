"""
Default images for the emissive screens of the part-2 props (what a prop shows before a DUI
replaces its 'nz_amb_screen' texture). Everything is drawn with Pillow in the NAYZEEE palette.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nzprops import AMBER, RED, TEAL, TEAL_HI, TEAL_LO, font

INK = (200, 206, 210)
INK_DIM = (120, 128, 134)
PANEL = (14, 17, 20)


def _mark(d: ImageDraw.ImageDraw, x, y, s, hi=TEAL_HI, lo=TEAL_LO, cut=(0, 0, 0)):
    """NAYZEEE mark (chamfered square + inner bar) with its 155 deg gradient, top-left at (x, y)."""
    img = Image.new("RGB", (int(s) + 2, int(s) + 2), (0, 0, 0))
    yy, xx = np.mgrid[0:img.height, 0:img.width].astype(np.float32)
    t = np.clip((xx / s * 0.42 + yy / s * 0.91) / 1.33, 0, 1)[..., None]
    grad = (np.asarray(hi, np.float32) * (1 - t) + np.asarray(lo, np.float32) * t).astype(np.uint8)
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(0, 0), (s, 0), (s, 0.56 * s), (0.56 * s, s), (0, s)], fill=255)
    d._image.paste(Image.fromarray(grad, "RGB"), (int(x), int(y)), mask)
    d.rounded_rectangle([x + 0.22 * s, y + 0.22 * s, x + 0.78 * s, y + 0.44 * s], radius=max(1, 0.02 * s), fill=cut)


def _header(d, w, s, title, right):
    d.rectangle([0, 0, w, int(24 * s)], fill=PANEL)
    _mark(d, int(8 * s), int(5 * s), 14 * s)
    d.text((int(28 * s), int(12 * s)), title, font=font("brand", 11 * s), fill=INK, anchor="lm")
    d.text((w - int(8 * s), int(12 * s)), right, font=font("mono", 10 * s), fill=INK_DIM, anchor="rm")


# ---------------------------------------------------------------------------------------------
def draw_ultrasound_ui(w=512, h=320, seed=3):
    """B-mode eFAST screen: sector image with speckle, liver / kidney interface, side menu."""
    rng = np.random.default_rng(seed)
    s = w / 512.0
    img = Image.new("RGB", (w, h), (4, 5, 6))
    d = ImageDraw.Draw(img)
    _header(d, w, s, "NAYZEEE ECHO  ·  eFAST", "C5-2   MI 0.9   12:04")
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
    d.text((int(10 * s), int(34 * s)), "B", font=font("brand", 12 * s), fill=TEAL_HI, anchor="lt")
    for k, t in enumerate(("Frq 3.5", "Gn 51", "D 16", "DR 72", "FR 30")):
        d.text((int(10 * s), int((52 + k * 13) * s)), t, font=font("mono", 9 * s), fill=INK_DIM, anchor="lt")
    d.text((int(118 * s), int(h - 26 * s)), "RUQ  ·  MORISON", font=font("brand-semi", 9 * s), fill=INK, anchor="lt")
    # right column: eFAST checklist
    x0 = int(356 * s)
    d.rectangle([x0, int(30 * s), w - int(6 * s), h - int(6 * s)], fill=(10, 12, 14))
    d.text((x0 + int(8 * s), int(40 * s)), "eFAST", font=font("brand", 11 * s), fill=INK, anchor="lt")
    d.text((w - int(12 * s), int(40 * s)), "1/6", font=font("mono", 9 * s), fill=INK_DIM, anchor="rt")
    rows = [("RUQ", "POS", RED), ("LUQ", "--", INK_DIM), ("PELVIS", "--", INK_DIM), ("CARDIAC", "--", INK_DIM),
            ("LUNG R", "--", INK_DIM), ("LUNG L", "--", INK_DIM)]
    for k, (lbl, res, col) in enumerate(rows):
        y = int((62 + k * 24) * s)
        if k == 0:
            d.rectangle([x0 + int(4 * s), y - int(3 * s), w - int(10 * s), y + int(16 * s)], fill=(18, 40, 38))
            d.rectangle([x0 + int(4 * s), y - int(3 * s), x0 + int(6 * s), y + int(16 * s)], fill=TEAL)
        d.text((x0 + int(12 * s), y + int(6 * s)), lbl, font=font("brand-semi", 10 * s), fill=INK, anchor="lm")
        d.text((w - int(14 * s), y + int(6 * s)), res, font=font("mono-bold", 9 * s), fill=col, anchor="rm")
    d.text((x0 + int(8 * s), h - int(14 * s)), "FREE FLUID", font=font("brand", 10 * s), fill=AMBER, anchor="lm")
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
    _mark(d, int(10 * s), int(10 * s), 14 * s)
    d.text((int(30 * s), int(17 * s)), "NAYZEEE ANGIO", font=font("brand", 11 * s), fill=INK, anchor="lm")
    d.text((int(10 * s), int(36 * s)), "LIVE  ·  FLUORO 7.5 p/s", font=font("mono", 9 * s), fill=TEAL_HI, anchor="lm")
    d.text((w - int(10 * s), int(17 * s)), "AP 0°  CRAN 0°", font=font("mono", 9 * s), fill=INK, anchor="rm")
    d.text((w - int(10 * s), int(32 * s)), "kV 78   mA 12", font=font("mono", 9 * s), fill=INK_DIM, anchor="rm")
    d.text((int(10 * s), h - int(12 * s)), "DOSE 41 mGy", font=font("mono", 9 * s), fill=INK_DIM, anchor="lm")
    d.text((w - int(10 * s), h - int(12 * s)), "00:42", font=font("mono-bold", 10 * s), fill=AMBER, anchor="rm")
    d.ellipse([bx - 16 * s, by - 13 * s, bx + 16 * s, by + 13 * s], outline=RED, width=max(1, int(2 * s)))
    d.text((bx, by + 22 * s), "BLEED", font=font("brand", 9 * s), fill=RED, anchor="mm")
    return img


def draw_brand_standby(w=1024, h=576, sub="MEDICAL"):
    """Black screen with the teal NAYZEEE mark + wordmark centred (waiting-room TV default)."""
    img = Image.new("RGB", (w, h), (3, 4, 5))
    # faint radial glow behind the mark
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rr = np.hypot((xx - w / 2) / (w * 0.4), (yy - h * 0.45) / (h * 0.5))
    glow = np.clip(1 - rr, 0, 1) ** 2.2
    arr = np.asarray(img, np.float32) + glow[..., None] * np.array([4, 26, 24], np.float32)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    s = h / 576.0
    ms = 150 * s
    tw = font("brand", 74 * s).getlength("NAYZEEE")
    total = ms + 36 * s + tw
    x0 = (w - total) / 2
    y0 = h * 0.45 - ms / 2
    _mark(d, x0, y0, ms)
    d.text((x0 + ms + 36 * s, y0 + ms * 0.36), "NAYZEEE", font=font("brand", 74 * s), fill=(236, 240, 242), anchor="lm")
    d.text((x0 + ms + 38 * s, y0 + ms * 0.80), sub, font=font("brand-semi", 34 * s), fill=TEAL_HI, anchor="lm")
    d.line([(w * 0.38, h * 0.80), (w * 0.62, h * 0.80)], fill=(20, 60, 56), width=max(1, int(2 * s)))
    d.text((w / 2, h * 0.86), "PATIENT INFORMATION  ·  PLEASE WAIT TO BE CALLED", font=font("brand-semi", 15 * s),
           fill=(110, 120, 126), anchor="mm")
    return img


def draw_lightbox_panel(w=512, h=512):
    """Cool white diffuser with a faint lamp gradient and the NAYZEEE mark in the corner."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = 0.93 + 0.05 * np.cos((xx / w - 0.5) * math.pi) * np.cos((yy / h - 0.5) * math.pi)
    for k in range(1, 4):   # three fluorescent tubes behind the diffuser
        v += 0.025 * np.exp(-((xx / w - k / 4) / 0.06) ** 2)
    col = np.clip(np.dstack([v * 236, v * 244, v * 250]), 0, 255).astype(np.uint8)
    img = Image.fromarray(col, "RGB")
    d = ImageDraw.Draw(img)
    s = w / 512.0
    _mark(d, w - int(40 * s), h - int(40 * s), 24 * s, hi=(150, 210, 205), lo=(120, 190, 184), cut=(236, 244, 248))
    return img


def draw_mixer_lcd(w=256, h=128):
    """Collection mixer display: volume, target, flow bar, rocking indicator."""
    img = Image.new("RGB", (w, h), (8, 14, 16))
    d = ImageDraw.Draw(img)
    s = w / 256.0
    d.text((int(8 * s), int(8 * s)), "COLLECT", font=font("brand", 12 * s), fill=TEAL_HI, anchor="lt")
    d.text((w - int(8 * s), int(8 * s)), "O NEG", font=font("brand", 12 * s), fill=RED, anchor="rt")
    d.text((int(8 * s), int(64 * s)), "312", font=font("brand", 44 * s), fill=(236, 240, 242), anchor="lm")
    d.text((int(100 * s), int(74 * s)), "mL / 450", font=font("mono", 13 * s), fill=INK_DIM, anchor="lm")
    d.rectangle([int(8 * s), int(98 * s), w - int(8 * s), int(110 * s)], outline=(40, 60, 62), width=max(1, int(1 * s)))
    d.rectangle([int(10 * s), int(100 * s), int(10 * s + (w - 20 * s) * 0.69), int(108 * s)], fill=TEAL)
    d.text((w - int(8 * s), int(66 * s)), "62 mL/min", font=font("mono", 11 * s), fill=AMBER, anchor="rm")
    return img


def draw_bay_monitor(w=512, h=256):
    """Bay wall monitor (dark, standby): NAYZEEE mark + unit / clock line."""
    img = Image.new("RGB", (w, h), (4, 6, 7))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    _mark(d, int(196 * s), int(70 * s), 52 * s)
    d.text((int(262 * s), int(86 * s)), "NAYZEEE", font=font("brand", 26 * s), fill=(210, 216, 220), anchor="lm")
    d.text((int(263 * s), int(110 * s)), "MEDIC 1", font=font("brand-semi", 13 * s), fill=TEAL_HI, anchor="lm")
    d.line([(int(140 * s), int(150 * s)), (int(372 * s), int(150 * s))], fill=(18, 42, 40), width=max(1, int(1 * s)))
    d.text((int(256 * s), int(172 * s)), "TREATMENT BAY  ·  STANDBY", font=font("mono", 11 * s), fill=(96, 106, 110), anchor="mm")
    return img
