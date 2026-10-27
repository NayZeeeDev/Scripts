"""
Generic helpers for the default images of emissive screens (what a prop shows before a DUI replaces
its screen texture): LCD backgrounds with a faint backlight, pixel grids, scan lines, vignettes, a
glass glare, header bars and seven-segment digits with ghost (unlit) segments. Drawn with Pillow;
generic device UI only - no maker names, no NAYZEEE mark (Rule B).
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nzprops import font

INK = (200, 206, 210)
INK_DIM = (120, 128, 134)
PANEL = (14, 17, 20)


def lcd_base(w, h, bg, glow=None, glow_strength=0.35, glow_center=(0.5, 0.42)):
    """New RGB image filled with `bg`, plus a soft radial backlight bloom of `glow` colour."""
    img = Image.new("RGB", (w, h), bg)
    if glow is not None and glow_strength > 0:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        cx, cy = glow_center[0] * w, glow_center[1] * h
        r = np.sqrt(((xx - cx) / (w * 0.75)) ** 2 + ((yy - cy) / (h * 0.75)) ** 2)
        a = np.clip(1 - r, 0, 1) ** 1.6 * glow_strength
        base = np.asarray(img, np.float32)
        base = base * (1 - a[..., None]) + np.asarray(glow, np.float32)[None, None, :] * a[..., None]
        img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
    return img


def pixel_grid(img, pitch=3, strength=0.10, color=(0, 0, 0)):
    """Darken every `pitch`-th row and column a little: visible LCD pixel structure up close."""
    a = np.asarray(img, np.float32)
    h, w = a.shape[:2]
    m = np.zeros((h, w), np.float32)
    m[::pitch, :] = strength
    m[:, ::pitch] = np.maximum(m[:, ::pitch], strength)
    a = a * (1 - m[..., None]) + np.asarray(color, np.float32)[None, None, :] * m[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def scanlines(img, period=2, strength=0.06):
    a = np.asarray(img, np.float32)
    a[::period] *= (1 - strength)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def vignette(img, strength=0.35, power=2.2):
    a = np.asarray(img, np.float32)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / math.sqrt(2)
    k = 1 - strength * np.clip(r, 0, 1) ** power
    return Image.fromarray(np.clip(a * k[..., None], 0, 255).astype(np.uint8), "RGB")


def glass_glare(img, strength=0.05, angle=-28.0, width=0.22, offset=0.18):
    """A faint diagonal reflection band (the cover glass catching a light)."""
    a = np.asarray(img, np.float32)
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = math.radians(angle)
    d = (xx / w - offset) * math.cos(t) + (yy / h) * math.sin(t)
    band = np.exp(-(d / width) ** 2 * 4) * strength
    a = a + (255 - a) * band[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def soften(img, radius=0.6):
    """LCD pixels bleed a little: a tiny blur makes drawn text read as a lit panel, not a vector."""
    return img.filter(ImageFilter.GaussianBlur(radius))


def header(d: ImageDraw.ImageDraw, w, s, title, right, ink=INK, dim=INK_DIM, panel=PANEL, h=24):
    d.rectangle([0, 0, w, int(h * s)], fill=panel)
    d.text((int(8 * s), int(h * s / 2)), title, font=font("label", 11 * s), fill=ink, anchor="lm")
    d.text((w - int(8 * s), int(h * s / 2)), right, font=font("mono", 10 * s), fill=dim, anchor="rm")


# seven-segment digits ------------------------------------------------------------------------
#  a
# f b
#  g
# e c
#  d
_SEG = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc",
    "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "", "A": "abcefg", "b": "cdefg", "C": "adef", "d": "bcdeg",
    "E": "adefg", "F": "aefg", "H": "bcefg", "L": "def", "P": "abefg", "r": "eg", "t": "defg", "U": "bcdef",
}


def _seg_polys(x, y, w, h, t, slant):
    """Segment polygons of one digit cell (top-left x, y; width w; height h; stroke t)."""
    def P(px, py):
        return (x + px + slant * (h - py), y + py)
    hh = h / 2
    g = t * 0.12
    return {
        "a": [P(g + t * 0.5, 0), P(w - g - t * 0.5, 0), P(w - g - t, t), P(g + t, t)],
        "d": [P(g + t, h - t), P(w - g - t, h - t), P(w - g - t * 0.5, h), P(g + t * 0.5, h)],
        "g": [P(g + t * 0.6, hh), P(g + t, hh - t / 2), P(w - g - t, hh - t / 2), P(w - g - t * 0.6, hh), P(w - g - t, hh + t / 2),
              P(g + t, hh + t / 2)],
        "f": [P(0, g + t * 0.5), P(t, g + t), P(t, hh - g - t / 2), P(0, hh - g)],
        "b": [P(w - t, g + t), P(w, g + t * 0.5), P(w, hh - g), P(w - t, hh - g - t / 2)],
        "e": [P(0, hh + g), P(t, hh + g + t / 2), P(t, h - g - t), P(0, h - g - t * 0.5)],
        "c": [P(w - t, hh + g + t / 2), P(w, hh + g), P(w, h - g - t * 0.5), P(w - t, h - g - t)],
    }


def seg_text(d: ImageDraw.ImageDraw, x, y, text, h, on, ghost=None, w=None, t=None, gap=None, slant=0.08, dot=None):
    """Seven-segment readout at (x, y) top-left, digit height h px. `ghost` draws the unlit segments
    (real LCDs show them faintly). '.' and ':' are drawn between cells. Returns the end x."""
    w = w or h * 0.52
    t = t or h * 0.13
    gap = gap or h * 0.16
    cx = x
    for ch in text:
        if ch in ".:":
            r = t * 0.55
            px = cx - gap * 0.55
            if ch == ".":
                d.ellipse([px - r, y + h - r * 2, px + r, y + h], fill=dot or on)
            else:
                for yy in (h * 0.3, h * 0.72):
                    d.ellipse([px + slant * (h - yy) - r, y + yy - r, px + slant * (h - yy) + r, y + yy + r], fill=dot or on)
            continue
        polys = _seg_polys(cx, y, w, h, t, slant)
        lit = _SEG.get(ch, "")
        for k, pts in polys.items():
            if k in lit:
                d.polygon(pts, fill=on)
            elif ghost is not None:
                d.polygon(pts, fill=ghost)
        cx += w + gap
    return cx


def seg_width(text, h, w=None, gap=None):
    w = w or h * 0.52
    gap = gap or h * 0.16
    n = sum(1 for ch in text if ch not in ".:")
    return n * w + max(0, n - 1) * gap


__all__ = [k for k in dir() if not k.startswith("_")]
