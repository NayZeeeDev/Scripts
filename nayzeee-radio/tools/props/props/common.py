"""
Shared materials, generic labelling (name plates, rating plates, caution / calibration stickers,
asset tags) and small detail parts (align, buttons, knobs, screws, rubber feet, strain reliefs,
coiled cords, hinges, LED lenses, grommets) used by several props. No maker names or logos anywhere
(Rule B): labels name the device type and an invented model code only - never NAYZEEE.

Material helpers register a material on the builder under a fixed name and return that name, so
calling them twice is harmless.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL_HI, WHITE, DecalCanvas, Geo, cylinder, extrude, lathe, normalize, rrect, torus, tube,
                     vec)

# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
TEAL_PLASTIC = (10, 158, 147)
CASE_GREY = (96, 101, 106)
CHARCOAL = (44, 47, 51)


def m_case_grey(b):
    return b.mat("case_grey", color=CASE_GREY, spec=0.30, gloss=0.40, bump="stipple", bump_amp=0.00009,
                 bump_scale=0.0010, grain=0.035, grain_scale=0.06, edge=0.55, dirt=0.18)


def m_charcoal(b):
    return b.mat("charcoal", color=CHARCOAL, spec=0.30, gloss=0.42, bump="stipple", bump_amp=0.00006,
                 bump_scale=0.0008, grain=0.03, grain_scale=0.05, edge=0.6, dirt=0.12)


def m_teal(b):
    return b.mat("teal", color=TEAL_PLASTIC, spec=0.45, gloss=0.58, bump="orange_peel", bump_amp=0.00002,
                 bump_scale=0.002, grain=0.025, grain_scale=0.04, edge=0.45, dirt=0.08)


def m_black_plastic(b):
    return b.mat("black_plastic", color=(30, 32, 35), spec=0.32, gloss=0.48, bump="stipple", bump_amp=0.00005,
                 bump_scale=0.0007, grain=0.03, grain_scale=0.04, edge=0.55, dirt=0.1)


def m_gloss_black(b):
    return b.mat("gloss_black", color=(14, 15, 17), spec=0.7, gloss=0.85, grain=0.01, edge=0.3)


def m_rubber(b):
    return b.mat("rubber", color=(26, 27, 29), spec=0.10, gloss=0.16, bump="rubber", bump_amp=0.00006,
                 bump_scale=0.0006, grain=0.04, grain_scale=0.03, edge=0.25, dirt=0.15)


def m_grip(b):
    return b.mat("grip", color=(28, 29, 31), spec=0.10, gloss=0.15, bump="knurl", bump_amp=0.00025,
                 bump_scale=0.0032, grain=0.04, grain_scale=0.03, edge=0.2, dirt=0.15)


def m_alu(b):
    return b.mat("alu", color=(150, 155, 161), spec=0.75, gloss=0.62, metal=1.0, bump="brushed",
                 bump_amp=0.000012, bump_scale=0.0004, grain=0.03, grain_scale=0.05, edge=0.25)


def m_chrome(b):
    return b.mat("chrome", color=(190, 194, 200), spec=0.95, gloss=0.88, metal=1.0, grain=0.015, grain_scale=0.05, edge=0.15)


def m_steel(b):
    return b.mat("steel", color=(120, 124, 130), spec=0.8, gloss=0.7, metal=1.0, bump="brushed", bump_amp=0.00001,
                 bump_scale=0.0004, grain=0.02, edge=0.2)


def m_white_plastic(b):
    return b.mat("white_plastic", color=(222, 225, 227), spec=0.35, gloss=0.5, bump="orange_peel", bump_amp=0.00002,
                 bump_scale=0.002, grain=0.02, grain_scale=0.05, edge=0.2, dirt=0.2)


def m_foam(b):
    return b.mat("foam", color=(40, 42, 45), spec=0.04, gloss=0.06, bump="foam", bump_amp=0.0005, bump_scale=0.0035,
                 grain=0.05, grain_scale=0.04, ao=1.0)


def m_webbing(b, name="webbing", color=(32, 33, 36)):
    return b.mat(name, color=color, spec=0.14, gloss=0.22, bump="webbing", bump_amp=0.00022, bump_scale=0.0016,
                 grain=0.05, grain_scale=0.03, edge=0.15, dirt=0.1)


def m_led(b, name, color):
    return b.mat(name, color=color, layer="glow")


# ---------------------------------------------------------------------------------------------
# orientation helpers
# ---------------------------------------------------------------------------------------------
def align(geo: Geo, normal, up=(0, 0, 1), at=(0, 0, 0)):
    """Rotate a part built around +Z (pointing out) so +Z points along `normal`, local +Y along `up`."""
    n = normalize(vec(normal))
    u = vec(up)
    u = u - n * float(np.dot(u, n))
    if np.linalg.norm(u) < 1e-6:
        u = vec(0, 1, 0) if abs(n[1]) < 0.9 else vec(1, 0, 0)
        u = u - n * float(np.dot(u, n))
    u = normalize(u)
    x = np.cross(u, n)
    m = np.stack([x, u, n], axis=1)
    geo.transform(m)
    return geo.translate(at)


def button(mat, d=0.012, h=0.004, kind="round", bevel=0.0012, segs=20):
    """Push button standing on +Z from z=0 (round or rounded-square)."""
    if kind == "round":
        return cylinder(d / 2, h, mat, segs=segs, bevel=bevel, bevel_seg=2, caps=(False, True))
    return extrude(rrect(d, d, d * 0.22, 3), h, mat, bevel=bevel, bevel_seg=2, caps=(False, True))


def screw_head(mat, d=0.005, h=0.0012):
    return cylinder(d / 2, h, mat, segs=12, bevel=h * 0.6, bevel_seg=2, caps=(False, True))


def knob(mat, d=0.03, h=0.016, ridges=True):
    prof = [(0.0, 0.0), (d / 2, 0.0), (d / 2, h * 0.85), (d / 2 - h * 0.15, h), (0.0, h)]
    g = lathe(prof, mat, segs=36 if ridges else 24, smooth_angle=50)
    return g


# ---------------------------------------------------------------------------------------------
# small detail parts (geometry)
# ---------------------------------------------------------------------------------------------
def m_screw(b, d=0.005, kind="phillips", color=(160, 164, 170)):
    """Screw-head material: the drive recess is a bump pattern centred on each head (chart space)."""
    bump = {"phillips": "phillips", "hex": "hexsocket", "torx": "torx"}.get(kind, "phillips")
    return b.mat(f"screw_{kind}_{int(round(d * 10000))}", color=color, spec=0.75, gloss=0.6, metal=1.0, bump=bump,
                 bump_amp=d * 0.12, bump_scale=d / 2, grain=0.03, grain_scale=0.01, edge=0.35, dirt=0.25, scratch=0.3)


def screw(b, at, normal, up=(0, 0, 1), d=0.005, kind="phillips", color=(160, 164, 170), segs=12, washer=False):
    """Pan-head screw sitting on a surface at `at` facing `normal` (head height ~ d * 0.35);
    kind 'phillips' | 'hex' | 'torx' (the drive recess is a bump pattern centred on the head)."""
    mat = m_screw(b, d, kind, color)
    r = d / 2
    h = d * 0.36
    prof = [(0.0, 0.0), (r, 0.0), (r, h * 0.45), (r * 0.86, h * 0.9), (r * 0.62, h), (0.0, h)]
    g = lathe(prof, mat, segs=segs, smooth_angle=40)
    if washer:
        g += cylinder(r * 1.45, d * 0.08, mat, segs=segs + 4, bevel=d * 0.02, bevel_seg=1).translate(0, 0, -d * 0.04)
        g.translate(0, 0, d * 0.04)
    return align(g, normal, up, at)


def screws(b, pts, normal, up=(0, 0, 1), **kw):
    g = Geo()
    for p in pts:
        g += screw(b, p, normal, up, **kw)
    return g


def rubber_foot(b, x, y, z=0.0, r=0.01, h=0.006, segs=16):
    """Moulded rubber foot (stands on z): soft taper + recessed centre ring."""
    rub = m_rubber(b)
    prof = [(0.0, z), (r * 0.82, z), (r, z + h * 0.25), (r, z + h * 0.7), (r * 0.9, z + h), (0.0, z + h)]
    return lathe(prof, rub, segs=segs, smooth_angle=40).translate(x, y, 0)


def strain_relief(b, at, direction, length=0.03, r0=0.006, r1=0.0035, rings=6, mat=None, segs=14):
    """Tapered, ribbed cable boot from `at` along `direction` (the cable leaves at the thin end)."""
    mat = mat or m_rubber(b)
    prof = [(0.0, 0.0), (r0, 0.0)]
    for k in range(rings):
        t0 = (k + 0.15) / rings
        t1 = (k + 0.65) / rings
        rr0 = r0 + (r1 - r0) * t0
        rr1 = r0 + (r1 - r0) * t1
        prof += [(rr0 * 1.08, length * t0), (rr1 * 1.08, length * (t1 - 0.12 / rings)), (rr1 * 0.94, length * t1)]
    prof += [(r1, length), (0.0, length)]
    g = lathe(prof, mat, segs=segs, smooth_angle=55)
    return align(g, direction, (0, 0, 1) if abs(vec(direction)[2]) < 0.9 else (0, 1, 0), at)


def coil_cord(b, p0, p1, coil_r=0.008, wire_r=0.0022, turns=12, mat=None, segs=6, side=None):
    """Telephone-style coiled cord between p0 and p1 (straight axis)."""
    mat = mat or m_black_plastic(b)
    p0, p1 = vec(p0), vec(p1)
    ax = normalize(p1 - p0)
    ref = vec(side) if side is not None else (vec(1, 0, 0) if abs(ax[0]) < 0.9 else vec(0, 1, 0))
    e1 = normalize(ref - ax * np.dot(ref, ax))
    e2 = np.cross(ax, e1)
    n = max(24, int(turns * 14))
    t = np.linspace(0, 1, n)
    a = t * 2 * math.pi * turns
    pts = p0[None, :] + (p1 - p0)[None, :] * t[:, None] + coil_r * (np.cos(a)[:, None] * e1 + np.sin(a)[:, None] * e2)
    return tube(pts, wire_r, mat, segs=segs, split=0.15, tag="coil")


def hinge(b, p0, p1, r=0.005, knuckles=5, mat=None, gap=0.0008, segs=14):
    """Barrel hinge along p0 -> p1: alternating knuckles + pin heads."""
    mat = mat or m_steel(b)
    p0, p1 = vec(p0), vec(p1)
    L = float(np.linalg.norm(p1 - p0))
    ax = (p1 - p0) / L
    g = Geo()
    kl = (L - gap * (knuckles - 1)) / knuckles
    for k in range(knuckles):
        z0 = k * (kl + gap)
        g += cylinder(r, kl, mat, segs=segs, bevel=min(r * 0.25, kl * 0.2), bevel_seg=1, z0=z0)
    g += cylinder(r * 0.55, L + 0.002, mat, segs=10, bevel=r * 0.15, bevel_seg=1, z0=-0.001)
    return align(g, ax, (0, 0, 1) if abs(ax[2]) < 0.9 else (0, 1, 0), p0)


def led_lens(b, at, normal, up=(0, 0, 1), r=0.0025, color=(70, 255, 140), name=None):
    """Indicator LED: dark bezel ring + domed emissive lens."""
    g = Geo()
    g += cylinder(r * 1.5, r * 0.35, m_black_plastic(b), segs=14, bevel=r * 0.12, bevel_seg=1)
    lens = m_led(b, name or f"led_{color[0]}_{color[1]}_{color[2]}", color)
    g += lathe([(0.0, r * 0.3), (r, r * 0.3), (r * 0.8, r * 0.75), (0.0, r * 0.9)], lens, segs=12, smooth_angle=60)
    return align(g, normal, up, at)


def grommet(b, at, normal, up=(0, 0, 1), r=0.004, mat=None):
    """Metal eyelet / grommet ring."""
    mat = mat or m_chrome(b)
    return align(torus(r, r * 0.28, mat, segs=16, tube_segs=6), normal, up, at)


# ---------------------------------------------------------------------------------------------
# labelling (generic: device types, model codes, regulatory symbols, fine print - no maker names)
# ---------------------------------------------------------------------------------------------
def label_canvas(w, h, title, sub=None, ppm=2400, color=WHITE, sub_color=TEAL_HI, emboss=None, spacing=0.10, bg=None,
                 bg_r=0.0, rule=None):
    """Device name plate: the device type / model code + an optional sub line, with an optional thin
    accent rule (colour) under the title. Fills a w x h (m) canvas. No logos."""
    dc = DecalCanvas(w, h, ppm)
    if bg is not None:
        dc.rect(0, 0, w, h, r=bg_r, color=bg, spec=0.3, gloss=0.45)
    tx = h * 0.08
    ts = h * (0.38 if sub else 0.5)
    dc.text(tx, h * (0.36 if sub else 0.52), title, ts, fnt="label", anchor="lm", color=color, spacing=ts * spacing,
            max_w=w - tx - h * 0.06, height=emboss, spec=0.35, gloss=0.5)
    if rule is not None:
        dc.rect(tx, h * 0.60, (w - 2 * tx) * 0.5, h * 0.04, color=rule, spec=0.35, gloss=0.5)
    if sub:
        dc.text(tx, h * 0.80, sub, ts * 0.58, fnt="label-semi", anchor="lm", color=sub_color, spacing=ts * 0.58 * 0.2,
                max_w=w - tx - h * 0.06, height=emboss, spec=0.35, gloss=0.5)
    return dc


def rating_plate(w=0.07, h=0.025, title="TWO-WAY RADIO", model="PX-740", serial="SN 26-04117", ref=None, rating=None,
                 ppm=4000, bg=(216, 219, 221), ink=(30, 32, 35), seed=None, icons=("factory", "date", "book", "bin"),
                 ref_label="REF", foot="IP54"):
    """Silver / grey rating plate with fine print: device type, MODEL / SN / REF (or ID) lines, electrical
    rating, a row of generic regulatory symbols, barcode + data-matrix code."""
    dc = DecalCanvas(w, h, ppm)
    seed = seed if seed is not None else (sum(map(ord, model + serial)) % 997)
    dc.rect(0, 0, w, h, r=h * 0.08, color=bg, spec=0.45, gloss=0.55)
    dc.rect(h * 0.05, h * 0.05, w - h * 0.1, h - h * 0.1, r=h * 0.06, fill=False, width=h * 0.02, color=(150, 153, 156))
    pad = h * 0.12
    col = w * 0.58
    dc.text(pad, h * 0.17, title, h * 0.12, fnt="label", anchor="lm", color=ink, spacing=h * 0.008, max_w=col - pad)
    dc.rect(pad, h * 0.27, col - pad * 1.5, h * 0.012, color=ink)
    lines = [("MODEL", model), ("SN", serial.replace("SN ", "")), (ref_label, ref or f"{model}-{(seed * 37) % 900 + 100}")]
    for k, (a, v) in enumerate(lines):
        y = h * (0.38 + k * 0.13)
        dc.text(pad, y, a, h * 0.075, fnt="mono", anchor="lm", color=(70, 73, 76))
        dc.text(pad + h * 0.42, y, v, h * 0.09, fnt="mono-bold", anchor="lm", color=ink, max_w=col - pad - h * 0.45)
    dc.text(pad, h * 0.755, rating or "7.4 V  2250 mAh  Li-ion", h * 0.07, fnt="mono", anchor="lm", color=(60, 63, 66),
            max_w=col - pad)
    isz = h * 0.13
    for k, kind in enumerate(icons):
        dc.icon(kind, pad + k * isz * 1.25, h * 0.83, isz, color=ink)
    bx = col + h * 0.04
    dc.barcode(bx, h * 0.12, w - bx - pad * 0.8, h * 0.42, seed=seed, color=ink, digits=f"{seed:04d}{(seed * 7919) % 100000:05d}",
               digit_size=h * 0.065)
    ds = h * 0.30
    dc.datamatrix(w - pad * 0.8 - ds, h * 0.62, ds, n=12, seed=seed, color=ink)
    dc.text(bx, h * 0.68, "LOT", h * 0.065, fnt="mono", anchor="lm", color=(70, 73, 76))
    dc.text(bx, h * 0.80, f"26{chr(65 + seed % 20)}{seed % 90 + 10}", h * 0.08, fnt="mono-bold", anchor="lm", color=ink)
    dc.text(bx, h * 0.91, foot, h * 0.06, fnt="mono", anchor="lm", color=(70, 73, 76), max_w=w - bx - ds - pad)
    return dc


CAUTION_STYLES = {
    "caution": ((240, 196, 30), (16, 16, 18)),
    "warning": ((236, 110, 30), (16, 16, 18)),
    "danger": ((200, 32, 38), (255, 255, 255)),
    "notice": ((30, 88, 186), (255, 255, 255)),
}


def caution_label(w, h, head="CAUTION", lines=("Read the instructions before use",), kind="caution", ppm=4000, symbol="warn"):
    """Safety sticker: coloured header band with a symbol + bold word, white body with fine print."""
    band, hink = CAUTION_STYLES[kind]
    dc = DecalCanvas(w, h, ppm)
    hb = min(h * 0.36, w * 0.22)
    dc.rect(0, 0, w, h, r=h * 0.05, color=(246, 246, 244), spec=0.4, gloss=0.55)
    dc.rect(0, 0, w, hb, r=h * 0.05, color=band, spec=0.4, gloss=0.55)
    dc.rect(0, hb * 0.6, w, hb * 0.4, color=band)
    if symbol == "warn":
        dc.icon("warn", hb * 0.15, hb * 0.1, hb * 0.8, color=hink if kind != "caution" else (16, 16, 18))
        tx = hb * 1.1
    elif symbol == "bolt":
        dc.polygon([(hb * 0.5, hb * 0.08), (hb * 0.95, hb * 0.92), (hb * 0.05, hb * 0.92)], color=(16, 16, 18))
        dc.polygon([(hb * 0.5, hb * 0.24), (hb * 0.8, hb * 0.84), (hb * 0.2, hb * 0.84)], color=(240, 196, 30))
        lightning(dc, hb * 0.5, hb * 0.6, hb * 0.42, color=(16, 16, 18))
        tx = hb * 1.1
    else:
        tx = hb * 0.25
    dc.text(tx, hb * 0.52, head, hb * 0.5, fnt="label", anchor="lm", color=hink, spacing=hb * 0.04, max_w=w - tx - hb * 0.2)
    n = max(1, len(lines))
    lh = (h - hb) / (n + 0.6)
    fs = min(lh * 0.62, h * 0.13)
    for k, t in enumerate(lines):
        dc.text(w * 0.05, hb + lh * (k + 0.8), t, fs, fnt="label-semi", anchor="lm", color=(24, 26, 28), max_w=w * 0.9)
    return dc


def cal_sticker(w=0.03, h=0.018, title="SAFETY TESTED", date="03/2026", due="03/2027", tech="0417", ppm=6000,
                color=(30, 140, 70)):
    """Maintenance sticker (electrical safety / calibration): coloured frame, fields filled in."""
    dc = DecalCanvas(w, h, ppm)
    dc.rect(0, 0, w, h, r=h * 0.12, color=(248, 248, 246), spec=0.35, gloss=0.5)
    dc.rect(0, 0, w, h * 0.3, r=h * 0.12, color=color)
    dc.rect(0, h * 0.18, w, h * 0.12, color=color)
    dc.text(w / 2, h * 0.15, title, h * 0.14, fnt="label", color=(255, 255, 255), max_w=w * 0.9)
    for k, (a, v) in enumerate((("DATE", date), ("DUE", due), ("BY", tech))):
        y = h * (0.45 + k * 0.2)
        dc.text(w * 0.06, y, a, h * 0.1, fnt="label-semi", anchor="lm", color=(60, 63, 66))
        dc.line([(w * 0.34, y + h * 0.06), (w * 0.94, y + h * 0.06)], h * 0.012, color=(120, 124, 128))
        dc.text(w * 0.38, y - h * 0.005, v, h * 0.12, fnt="mono-bold", anchor="lm", color=(20, 40, 120), max_w=w * 0.55)
    return dc


def asset_tag(w=0.04, h=0.012, text="FLEET 07-A", ppm=6000, seed=3):
    """Metallic asset tag with a barcode."""
    dc = DecalCanvas(w, h, ppm)
    dc.rect(0, 0, w, h, r=h * 0.15, color=(196, 200, 204), spec=0.7, gloss=0.6, metal=1.0)
    dc.text(w * 0.05, h * 0.26, "ASSET", h * 0.17, fnt="label", anchor="lm", color=(30, 32, 35))
    dc.text(w * 0.95, h * 0.26, text, h * 0.17, fnt="mono-bold", anchor="rm", color=(30, 32, 35), max_w=w * 0.6)
    dc.barcode(w * 0.05, h * 0.42, w * 0.9, h * 0.5, seed=seed, color=(30, 32, 35))
    return dc


def text_canvas(lines, w, h, ppm=2400, bg=None, bg_r=0.0, **kw):
    """lines: list of (text, x, y, size, font, color, anchor) in metres."""
    dc = DecalCanvas(w, h, ppm)
    if bg is not None:
        dc.rect(0, 0, w, h, r=bg_r, color=bg, spec=kw.get("bg_spec", 0.25), gloss=kw.get("bg_gloss", 0.35))
    for ln in lines:
        text, x, y, size, fnt, col = ln[:6]
        anchor = ln[6] if len(ln) > 6 else "mm"
        spacing = ln[7] if len(ln) > 7 else 0.0
        dc.text(x, y, text, size, fnt=fnt, anchor=anchor, color=col, spacing=spacing,
                height=kw.get("emboss"), spec=kw.get("spec", 0.3), gloss=kw.get("gloss", 0.4))
    return dc


def lightning(dc: DecalCanvas, cx, cy, s, color=WHITE):
    pts = [(0.15, -0.5), (-0.25, 0.08), (0.02, 0.08), (-0.15, 0.5), (0.27, -0.12), (0.0, -0.12), (0.15, -0.5)]
    dc.polygon([(cx + x * s, cy + y * s) for x, y in pts], color=color)


def split_lines(dc: DecalCanvas, rects, width=0.0006, depth=0.0003):
    """Engraved rectangles (x, y, w, h, r) on a canvas - panel inserts, doors, hatches."""
    for x, y, w, h, r in rects:
        dc.groove_rect(x, y, w, h, r=r, width=width, depth=depth)
    return dc


__all__ = [k for k in dir() if not k.startswith("_")]
