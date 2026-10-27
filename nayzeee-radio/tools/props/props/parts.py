"""
Generic shared parts: casters, star bases, poles and collars, rounded slabs, texel-density boost,
vent slots and rulers. Radio-specific blocks live in radio_common.py.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import DecalCanvas, Geo, box, cylinder, lathe, rrect, sweep

from .common import m_black_plastic, m_chrome, m_rubber

# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def m_stainless(b):
    return b.mat("stainless", color=(176, 181, 186), spec=0.85, gloss=0.72, metal=1.0, bump="brushed", bump_amp=0.000008,
                 bump_scale=0.0004, grain=0.02, grain_scale=0.05, edge=0.2, dirt=0.05)


# ---------------------------------------------------------------------------------------------
# casters / bases / poles
# ---------------------------------------------------------------------------------------------
def caster(b, x, y, r=0.036, w=0.022, yaw=0.0, lock=False):
    """Small swivel caster standing on z = 0: wheel (radius r), fork, swivel plate. Returns Geo."""
    blk = m_black_plastic(b)
    rub = m_rubber(b)
    chrome = m_chrome(b)
    g = Geo()
    tyre = lathe([(0.0, -w / 2), (r * 0.62, -w / 2), (r - 0.006, -w / 2 + 0.001), (r - 0.001, -w / 2 + 0.004), (r, 0.0),
                  (r - 0.001, w / 2 - 0.004), (r - 0.006, w / 2 - 0.001), (r * 0.62, w / 2), (0.0, w / 2)], rub, segs=24, smooth_angle=35)
    hub = cylinder(r * 0.55, w + 0.002, blk, segs=18, bevel=0.002, z0=-(w + 0.002) / 2)
    off = r * 0.55          # trailing offset of the wheel behind the swivel axis
    g += (tyre + hub).rotate(0, 90, 0).translate(0, -off, r)
    for sx in (-1, 1):
        g += box((0.005, r * 1.5, r * 1.3), blk, r=0.002, seg=1, center=(sx * (w / 2 + 0.004), -off * 0.6, r + r * 0.35))
    g += box((w + 0.016, r * 1.6, 0.012), blk, r=0.004, seg=2, center=(0, -off * 0.45, 2 * r + 0.012))
    g += cylinder(0.006, w + 0.014, chrome, segs=10, z0=-(w + 0.014) / 2).rotate(0, 90, 0).translate(0, -off, r)
    g += cylinder(r * 0.42, 0.01, chrome, segs=16, bevel=0.002, z0=2 * r + 0.018)
    if lock:
        g += box((0.014, 0.022, 0.008), b.mat("lock_red", color=(200, 46, 50), spec=0.4, gloss=0.55, edge=0.4),
                 r=0.003, seg=1, center=(0, r * 0.75, 2 * r + 0.004))
    g.rotate(0, 0, yaw)
    return g.translate(x, y, 0)


def caster_top(r=0.036):
    """Height of a caster's mounting plate (z of the swivel plate top)."""
    return 2 * r + 0.028


def star_base(b, mat, radius=0.30, n=5, hub_r=0.05, z=None, caster_r=0.032, start=90.0):
    """Five-leg star base with casters (hub at the origin). Returns (Geo, hub top z)."""
    zc = caster_top(caster_r) if z is None else z
    g = Geo()
    for k in range(n):
        a = math.radians(start + 360.0 * k / n)
        ca, sa = math.cos(a), math.sin(a)
        p0 = np.array([ca * hub_r * 0.6, sa * hub_r * 0.6, zc + 0.022])
        p1 = np.array([ca * (radius - 0.01), sa * (radius - 0.01), zc + 0.008])
        g += sweep(rrect(0.034, 0.026, 0.008, 2), np.array([p0, p1]), mat, up=(0, 0, 1), tag="leg", smooth_angle=50)
        g += caster(b, ca * radius, sa * radius, r=caster_r, w=0.02, yaw=math.degrees(a) + 90)
    g += cylinder(hub_r, 0.06, mat, segs=24, bevel=0.01, z0=zc - 0.004)
    return g, zc + 0.056


def boost(b, k, mats=None, zmin=None, zmax=None):
    """Multiply the texel density of charts (optionally only these materials / inside a height band) - used for
    panels that carry small printed text, which a uniform atlas density would leave unreadable."""
    for c in b.geo.charts:
        if mats is not None and c.mat not in mats:
            continue
        z = c.pos[:, 2]
        if (zmin is not None and z.min() < zmin) or (zmax is not None and z.max() > zmax):
            continue
        c.density *= k


def pole(mat, x, y, z0, z1, r=0.018, segs=18):
    return cylinder(r, z1 - z0, mat, segs=segs, bevel=min(0.004, r * 0.3), z0=z0).translate(x, y, 0)


def collar(mat, x, y, z, r=0.026, h=0.03, segs=24):
    return cylinder(r, h, mat, segs=segs, bevel=0.004, z0=z - h / 2).translate(x, y, 0)


def rounded_slab(w, d, h, mat, r, center, seg=3, **kw):
    return box((w, d, h), mat, r=r, seg=seg, center=center, **kw)


# ---------------------------------------------------------------------------------------------
# decals
# ---------------------------------------------------------------------------------------------
def vents(w, h, n, slot_h=None, ppm=3000, color=(30, 32, 35), vertical=False, margin=0.1):
    """Row of rounded vent slots (recessed) on a w x h canvas."""
    dc = DecalCanvas(w, h, ppm)
    if not vertical:
        sh = slot_h or h / (n * 2.2)
        gap = (h * (1 - 2 * margin) - n * sh) / max(n - 1, 1)
        for k in range(n):
            y = h * margin + k * (sh + gap)
            dc.rect(w * margin, y, w * (1 - 2 * margin), sh, r=sh / 2, color=color, height=-0.0008, spec=0.1, gloss=0.2)
    else:
        sw = slot_h or w / (n * 2.2)
        gap = (w * (1 - 2 * margin) - n * sw) / max(n - 1, 1)
        for k in range(n):
            x = w * margin + k * (sw + gap)
            dc.rect(x, h * margin, sw, h * (1 - 2 * margin), r=sw / 2, color=color, height=-0.0008, spec=0.1, gloss=0.2)
    return dc


def ruler(w, h, step=0.01, ppm=3000, color=(24, 26, 28), numbers=10, start=0, unit_step=1, font_scale=0.42, bg=None):
    """Millimetre-style ruler strip along x: ticks every `step` m, numbers every `numbers` ticks."""
    dc = DecalCanvas(w, h, ppm)
    if bg is not None:
        dc.rect(0, 0, w, h, color=bg, spec=0.3, gloss=0.45)
    n = int(w / step)
    for k in range(n + 1):
        x = k * step
        major = k % numbers == 0
        mid = k % (numbers // 2 or 1) == 0
        th = h * (0.55 if major else (0.38 if mid else 0.24))
        dc.rect(x - h * 0.012, 0, h * 0.024, th, color=color)
        if major and 0 < x < w - h * 0.4:
            dc.text(x + h * 0.06, h * 0.78, str(start + (k // numbers) * unit_step), h * font_scale * 0.6, fnt="label-semi",
                    anchor="lm", color=color)
    return dc


__all__ = [k for k in dir() if not k.startswith("_")]
