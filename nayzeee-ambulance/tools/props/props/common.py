"""
Shared materials, brand decals and small parts used by several NAYZEEE props.

Material helpers register a material on the builder under a fixed name and return that name, so
calling them twice is harmless.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (BLACK, TEAL_HI, WHITE, DecalCanvas, Geo, cylinder, extrude, lathe, normalize, rrect, vec)

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


def m_red_fabric(b):
    return b.mat("red_fabric", color=(178, 30, 36), spec=0.14, gloss=0.2, bump="fabric", bump_amp=0.00022,
                 bump_scale=0.0018, grain=0.05, grain_scale=0.05, edge=0.15, dirt=0.18, color2=(150, 22, 28))


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
# decals
# ---------------------------------------------------------------------------------------------
def brand_canvas(w, h, ppm=2400, sub="MEDICAL", color=WHITE, sub_color=TEAL_HI, mark=True, emboss=None):
    """Mark + NAYZEEE wordmark lockup filling a w x h (m) canvas."""
    dc = DecalCanvas(w, h, ppm)
    mh = h * 0.86
    dc.lockup(h * 0.07, (h - mh) / 2, mh, sub=sub, color=color, sub_color=sub_color, mark=mark, height=emboss)
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


def biohazard(dc: DecalCanvas, cx, cy, r, color=BLACK):
    """Draw the biohazard symbol centred at (cx, cy) with outer radius r (canvas metres)."""
    for k in range(3):
        a = math.radians(90 + 120 * k)
        ox, oy = cx + math.cos(a) * r * 0.42, cy - math.sin(a) * r * 0.42
        dc.circle(ox, oy, r * 0.48, color=color)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        ox, oy = cx + math.cos(a) * r * 0.56, cy - math.sin(a) * r * 0.56
        dc.circle(ox, oy, r * 0.36, color=(238, 196, 26))
    dc.circle(cx, cy, r * 0.30, fill=False, width=r * 0.09, color=color)
    dc.circle(cx, cy, r * 0.13, color=(238, 196, 26))
    for k in range(3):
        a = math.radians(-90 + 120 * k)
        dc.line([(cx + math.cos(a) * r * 0.10, cy - math.sin(a) * r * 0.10), (cx + math.cos(a) * r * 0.36, cy - math.sin(a) * r * 0.36)],
                r * 0.06, color=(238, 196, 26))
    return dc


def lightning(dc: DecalCanvas, cx, cy, s, color=WHITE):
    pts = [(0.15, -0.5), (-0.25, 0.08), (0.02, 0.08), (-0.15, 0.5), (0.27, -0.12), (0.0, -0.12), (0.15, -0.5)]
    dc.polygon([(cx + x * s, cy + y * s) for x, y in pts], color=color)


def cross_mark(dc: DecalCanvas, cx, cy, s, color=WHITE, **kw):
    t = s * 0.34
    dc.rect(cx - t / 2, cy - s / 2, t, s, r=t * 0.12, color=color, **kw)
    dc.rect(cx - s / 2, cy - t / 2, s, t, r=t * 0.12, color=color, **kw)


def serial_label(w=0.05, h=0.02, model="NZ-AMB", serial="SN 2026-0417", ppm=4000):
    """Grey rating plate: mark + maker on top, model / serial on the left, barcode on the right."""
    dc = DecalCanvas(w, h, ppm)
    ink = (30, 32, 35)
    dc.rect(0, 0, w, h, r=h * 0.1, color=(214, 217, 219), spec=0.3, gloss=0.5)
    dc.rect(h * 0.06, h * 0.06, w - h * 0.12, h - h * 0.12, r=h * 0.08, fill=False, width=h * 0.03, color=(150, 153, 156))
    m = h * 0.30
    dc.mark(h * 0.14, h * 0.12, m)
    col = w * 0.56
    dc.text(h * 0.14 + m * 1.25, h * 0.12 + m * 0.5, "NAYZEEE MEDICAL", h * 0.15, fnt="brand", anchor="lm", color=ink,
            spacing=h * 0.015, max_w=col - (h * 0.14 + m * 1.25))
    dc.text(h * 0.14, h * 0.64, model, h * 0.13, fnt="mono-bold", anchor="lm", color=ink, max_w=col - h * 0.2)
    dc.text(h * 0.14, h * 0.84, serial, h * 0.11, fnt="mono", anchor="lm", color=(60, 63, 66), max_w=col - h * 0.2)
    rng = np.random.default_rng(len(model) * 7 + len(serial))
    x = col + h * 0.08
    while x < w - h * 0.16:
        bw = h * (0.012 + rng.random() * 0.03)
        dc.rect(x, h * 0.16, bw, h * 0.52, color=ink)
        x += bw + h * (0.012 + rng.random() * 0.022)
    dc.text((col + w) / 2, h * 0.83, serial.split()[-1], h * 0.1, fnt="mono", color=ink, max_w=w - col - h * 0.2)
    return dc


__all__ = [k for k in dir() if not k.startswith("_")]
