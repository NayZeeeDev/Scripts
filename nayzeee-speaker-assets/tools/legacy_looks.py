#!/usr/bin/env python3
"""Looks library for the legacy props (runtime restyle of nayzeee_audio_texture).

    python3 tools/legacy_looks.py                 # write every variant + library.json into nayzeee-speaker/html/looks
    python3 tools/legacy_looks.py --only sp3 repro --swatches /tmp/sw.png   # a few textures + a swatch sheet

For every replaceable texture of the shared dictionary that a prop really samples (see legacy_reader.py) it
writes html/looks/<texture>/<variant>.png and html/looks/library.json:

* fabric sp1..sp5 (256x256; sp3's carbon and honeycomb at 512 because sp3 is stretched over the big drum c):
  the untouched ``original`` plus colourways and designs.  Every variant keeps
  the original's fine weave: the high-pass of the original's log-luminance (sigma ~2.5 px, periodic) drives
  a three-stop colour ramp (shadow / body / sheen, interpolated in OKLab), so fibres keep their light
  and dark threads instead of being flat-tinted.  The original's coarse blotches are mirror-symmetric (the
  author mirrored the left half to make it wrap), so they are replaced by new periodic heather noise.
  Designs (carbon twill, honeycomb mesh, two-tone stripe, urban camo, sunset gradient) are evaluated
  analytically at 4x and box-filtered, with integer repeat counts so they wrap exactly; their sizes are
  set in centimetres from each texture's real UV stretch on its props so cells stay round on the model.
  The props' normal maps (sp1_n, sp2_n) are shared between several speakers and stay untouched.
* repro (128 slot, written at 256): the driver on the ends of nayzeee_audio_f.  Only an ellipse of it is mapped
  onto the end caps; inside it every variant keeps the original's mesh shading (recoloured, or carbon /
  hex grille) and adds a coloured trim ring and a domed dust cap.
* brands (128x32 slot, written at 256x64): the NAYZEEE wordmark (house mark + Lexend), alpha-masked.
* record (256): the vinyl of the old turntable (nayzeee_audio_g): fine grooves, track gaps, NAYZEEE label.

Nothing here touches the third-party files; ``original`` is a lossless decode of the shipped texture.
Opaque variants are written as optimised 8-bit indexed PNGs (see save_png); the output is deterministic.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import legacy_reader as LR  # noqa: E402
from lib import fonts  # noqa: E402

LOOKS = os.path.normpath(os.path.join(ROOT, "..", "nayzeee-speaker", "html", "looks"))
SS = 4                      # supersampling for analytic patterns

# --------------------------------------------------------------------------- colour
def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def hexc(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return srgb_to_lin(np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0)


_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def lin_to_oklab(c):
    lms = np.cbrt(np.asarray(c) @ _M1.T)
    return lms @ _M2.T


def oklab_to_lin(c):
    lms = np.asarray(c) @ np.linalg.inv(_M2).T
    return (lms ** 3) @ np.linalg.inv(_M1).T


def luminance(lin):
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722


def ramp(t: np.ndarray, stops) -> np.ndarray:
    """t (any shape) in 0..1 -> linear RGB, through colour stops [(pos, '#hex'), ...] interpolated in OKLab."""
    pos = np.array([p for p, _ in stops], dtype=np.float64)
    lab = np.array([lin_to_oklab(hexc(c)) for _, c in stops])
    t = np.clip(t, pos[0], pos[-1])
    out = np.empty(t.shape + (3,))
    for k in range(3):
        out[..., k] = np.interp(t, pos, lab[:, k])
    return np.clip(oklab_to_lin(out), 0, 1)


def to_u8(lin: np.ndarray, alpha: np.ndarray | None = None, dither: float = 0.0, seed: int = 7) -> np.ndarray:
    """linear RGB -> sRGB uint8 RGBA (optional triangular dither for smooth gradients)."""
    s = lin_to_srgb(lin) * 255.0
    if dither:
        rng = np.random.default_rng(seed)
        s = s + (rng.random(s.shape) - rng.random(s.shape)) * dither
    rgb = np.clip(np.rint(s), 0, 255).astype(np.uint8)
    a = np.full(rgb.shape[:2] + (1,), 255, np.uint8) if alpha is None else \
        np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)[..., None]
    return np.concatenate([rgb, a], axis=2)


# --------------------------------------------------------------------------- periodic signal helpers
def _freqs(h, w):
    return np.fft.fftfreq(h)[:, None], np.fft.fftfreq(w)[None, :]


def blur(a: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    """Gaussian blur with wrap-around (exactly periodic), sigma in pixels."""
    sy = sx if sy is None else sy
    fy, fx = _freqs(*a.shape[:2])
    g = np.exp(-2 * np.pi ** 2 * ((fx * sx) ** 2 + (fy * sy) ** 2))
    if a.ndim == 3:
        g = g[..., None]
    return np.real(np.fft.ifft2(np.fft.fft2(a, axes=(0, 1)) * g, axes=(0, 1)))


def pnoise(h: int, w: int, cu: float, cv: float, seed: int, rough: float = 0.0) -> np.ndarray:
    """Periodic band-limited noise, ~cu blobs across u and cv blobs across v (zero mean, unit std).
    rough > 0 adds finer octaves (fractal edges)."""
    rng = np.random.default_rng(seed)
    spec = rng.normal(size=(h, w)) + 1j * rng.normal(size=(h, w))
    fy, fx = _freqs(h, w)
    r = np.sqrt((fx * w / max(cu, 1e-6)) ** 2 + (fy * h / max(cv, 1e-6)) ** 2)
    env = np.exp(-0.5 * r ** 2)
    if rough > 0:
        env = env + rough * np.exp(-0.5 * (r / 3.0) ** 2) * (r > 0.5) / 3.0
    env[0, 0] = 0
    n = np.real(np.fft.ifft2(spec * env))
    return (n - n.mean()) / (n.std() + 1e-12)


def box_down(a: np.ndarray, f: int) -> np.ndarray:
    h, w = a.shape[0] // f, a.shape[1] // f
    return a.reshape(h, f, w, f, *a.shape[2:]).mean(axis=(1, 3))


def fft_upsample(a: np.ndarray, f: int) -> np.ndarray:
    """Band-limited (periodic) upsampling by an integer factor: zero-pad the spectrum."""
    h, w = a.shape[:2]
    F = np.fft.fftshift(np.fft.fft2(a, axes=(0, 1)), axes=(0, 1))
    pad = [((f - 1) * h // 2, (f - 1) * h - (f - 1) * h // 2), ((f - 1) * w // 2, (f - 1) * w - (f - 1) * w // 2)]
    pad += [(0, 0)] * (a.ndim - 2)
    G = np.pad(F, pad)
    return np.real(np.fft.ifft2(np.fft.ifftshift(G, axes=(0, 1)), axes=(0, 1))) * f * f


def grid(h: int, w: int, ss: int = SS):
    """Pixel-centre coordinates (x = u, y = v) in [0, 1) at ss x supersampling."""
    y = (np.arange(h * ss) + 0.5) / (h * ss)
    x = (np.arange(w * ss) + 0.5) / (w * ss)
    return np.meshgrid(x, y)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# --------------------------------------------------------------------------- fabric structure
def fabric_detail(rgba: np.ndarray) -> dict:
    """z: the weave as a unit-variance high-pass of log luminance; chroma: per-fibre OKLab a/b jitter;
    p95_50: the original's weave contrast (95th / 50th luminance percentile)."""
    lin = srgb_to_lin(rgba[..., :3] / 255.0)
    L = luminance(lin)
    ll = np.log(L + 0.004)
    fine = ll - blur(ll, 2.5)                  # weave / fibre detail (matches the normal map's relief)
    z = fine / (fine.std() + 1e-9)
    # the original's chroma per fibre, as a small hue jitter around its mean (keeps 'melange' fabrics alive)
    lab = lin_to_oklab(lin)
    chroma = lab[..., 1:] - lab[..., 1:].mean(axis=(0, 1))
    return {"z": z, "chroma": chroma, "p95_50": float(np.percentile(L, 95) / max(np.percentile(L, 50), 1e-6))}


def colourway(det: dict, stops, contrast: float | None = None, heather: float = 0.018, seed: int = 1,
              cells=(6, 6), fleck: tuple | None = None, chroma_keep: float = 0.3, rel_scale: float = 1.0) -> np.ndarray:
    """Gradient-map the fabric detail: t = 0.5 + contrast*z + heather*noise -> 3-stop OKLab ramp.

    With contrast=None the contrast is fitted so the variant keeps the original's weave contrast
    (ratio of the 95th to the 50th luminance percentile, times rel_scale)."""
    h, w = det["z"].shape
    hn = heather * pnoise(h, w, cells[0], cells[1], seed, rough=0.3)

    def make(c):
        return ramp(0.5 + c * det["z"] + hn, stops)

    if contrast is None:
        target = 1 + (det["p95_50"] - 1) * rel_scale
        lo, hi = 0.03, 0.45
        for _ in range(14):
            mid = (lo + hi) / 2
            L = luminance(make(mid))
            r = np.percentile(L, 95) / max(np.percentile(L, 50), 1e-6)
            lo, hi = (mid, hi) if r < target else (lo, mid)
        contrast = (lo + hi) / 2
    col = make(contrast)
    if chroma_keep:
        lab = lin_to_oklab(col)
        lab[..., 1:] += chroma_keep * det["chroma"]
        col = np.clip(oklab_to_lin(lab), 0, 1)
    if fleck:
        amount, colour = fleck
        f = smoothstep(2.2, 3.4, det["z"]) * amount
        col = col * (1 - f[..., None]) + hexc(colour) * f[..., None]
    return col


# --------------------------------------------------------------------------- palettes
COLOURWAYS = {
    # name: (shadow, body, sheen) in sRGB: body is the colour you read, sheen the lit fibres
    "graphite": ([(0.0, "#060708"), (0.5, "#25282c"), (1.0, "#80878f")], 1.0),
    "teal": ([(0.0, "#010d0c"), (0.5, "#08524c"), (1.0, "#3cc7ba")], 1.0),
    "crimson": ([(0.0, "#0d0103"), (0.5, "#5e0b16"), (1.0, "#d9505a")], 1.0),
    "violet": ([(0.0, "#07040f"), (0.5, "#33205f"), (1.0, "#9a80dc")], 1.0),
    "cobalt": ([(0.0, "#02050f"), (0.5, "#142d6b"), (1.0, "#5d8fe6")], 1.0),
    "arctic": ([(0.0, "#4a4f54"), (0.5, "#a9aeb3"), (1.0, "#f4f6f7")], 0.45),
}
FLECK = {"graphite": (0.08, "#8f99a3"), "arctic": (0.10, "#ffffff")}

FABRIC_VARIANTS = ["original", "graphite", "teal", "crimson", "violet", "cobalt", "arctic",
                   "carbon", "honeycomb", "stripe", "camo", "sunset"]


def _counts(span_m: float, cell_m: float, multiple: int = 1, minimum: int = 2) -> int:
    n = max(minimum, span_m / cell_m)
    return int(max(minimum, multiple * round(n / multiple)))


def design_carbon(det, u, h=256, w=256, tow_m=0.0075):
    """2x2 twill carbon weave.  Every tow floats over two cells: it is round across its width (lit crest,
    dark edges), dives under at both float ends, and carries fine filament lines.  Warp floats catch more
    light than weft floats, which draws the twill's diagonal steps."""
    su, sv = u["su"], u["sv"]
    cell = max(tow_m, 6.0 * su / w)                     # ~7.5 mm tows, never under 6 px
    nu, nv = _counts(su, cell, 4), _counts(sv, cell, 4)
    x, y = grid(h, w)
    cu, cv = x * nu, y * nv
    i, j = np.floor(cu).astype(int), np.floor(cv).astype(int)
    fu, fv = cu - i, cv - j
    k = (i + j) % 4
    warp = k < 2
    cross = np.where(warp, fu, fv)                      # across the tow, 0..1
    along = np.where(warp, (k + fv) / 2, (k - 2 + fu) / 2)   # along the 2-cell float, 0..1
    crest = np.sqrt(np.clip(1 - (2 * cross - 1) ** 2, 0, 1))
    ends = smoothstep(0.0, 0.16, along) * smoothstep(0.0, 0.16, 1 - along)
    edges = smoothstep(0.0, 0.08, cross) * smoothstep(0.0, 0.08, 1 - cross)
    fil = 0.05 * np.sin(2 * np.pi * cross * 5) * crest
    sheen = np.where(warp, 0.42 + 0.30 * crest, 0.30 + 0.27 * crest) + fil
    sheen = sheen * (0.30 + 0.70 * ends * edges)
    s = box_down(sheen, SS)
    t = np.clip(0.04 + 0.92 * s + 0.025 * det["z"], 0, 1)
    return ramp(t, [(0.0, "#020203"), (0.35, "#0c0d10"), (0.6, "#1f2226"), (0.82, "#454b52"), (1.0, "#80878f")])


def design_honeycomb(det, u, h=256, w=256, spacing_m=0.017, web=0.11):
    """Hex perforated grille (gunmetal web) over black fabric, with a top-lit bevel in every hole."""
    su, sv = u["su"], u["sv"]
    spacing = max(spacing_m, 11.0 * su / w)            # centre-to-centre
    nu = _counts(su, spacing, 1, 4)
    nv = _counts(sv, spacing * math.sqrt(3) / 2, 2, 4)
    x, y = grid(h, w)
    px, py = x * nu, y * nv                            # lattice units: column, row
    rs = (sv / nv) / (su / nu)                         # physical row spacing in column units (~0.866)
    r0 = np.floor(py).astype(int)
    DX, DY = [], []
    for dr in (-1, 0, 1, 2):
        r = r0 + dr
        off = 0.5 * (r % 2)
        for dc in (-1, 0, 1):
            c = np.round(px - off) + dc
            DX.append(px - (c + off))
            DY.append((py - r) * rs)
    DX, DY = np.stack(DX), np.stack(DY)
    k = np.argmin(DX * DX + DY * DY, axis=0)
    bx = np.take_along_axis(DX, k[None], 0)[0]
    by = np.take_along_axis(DY, k[None], 0)[0]
    edge = np.full(px.shape, np.inf)                   # distance to the cell edge (Voronoi bisectors)
    for m in range(DX.shape[0]):
        ox, oy = bx - DX[m], by - DY[m]
        L = np.sqrt(ox * ox + oy * oy)
        dist = (DX[m] ** 2 + DY[m] ** 2 - bx ** 2 - by ** 2) / (2 * np.maximum(L, 1e-6))
        edge = np.minimum(edge, np.where(L > 1e-6, dist, np.inf))
    aa = 1.0 / (w * SS) * nu
    hole = smoothstep(web - aa, web + aa, edge)
    rlen = np.sqrt(bx * bx + by * by) + 1e-6
    down = by / rlen                                   # +1 toward the lower edge of the hole
    wall = smoothstep(web + 0.09, web + 0.01, edge) * hole            # inner chamfer
    wall_lit = wall * np.clip(0.15 + 0.85 * down, 0, 1)                # lower walls face the light
    rim = (1 - hole) * (0.5 + 0.5 * smoothstep(0.0, web, edge))        # web, a bit brighter at its crest
    H, R, Wl = box_down(hole, SS), box_down(rim, SS), box_down(wall_lit, SS)
    z = det["z"]
    rim_col = ramp(np.clip(0.30 + 0.55 * R + 0.05 * z, 0, 1), [(0.0, "#0b0c0e"), (0.55, "#30353b"), (1.0, "#8b939c")])
    fab_col = ramp(np.clip(0.45 + 0.15 * z, 0, 1), [(0.0, "#010102"), (0.5, "#08090a"), (1.0, "#1d2125")])
    wall_col = ramp(np.clip(Wl * 1.6, 0, 1), [(0.0, "#030304"), (1.0, "#5a626b")])
    col = rim_col * (1 - H[..., None]) + (fab_col * (1 - Wl[..., None]) + wall_col * Wl[..., None]) * H[..., None]
    return col


def design_stripe(det, u, h=256, w=256):
    """Two-tone: graphite body with a teal band around the middle of the visible fabric, edged by pinlines."""
    sv = u["sv"]
    r_top, r_bot = u["rows"]
    centre = (r_top + r_bot) / 2
    half = 0.022 / sv                                   # band 4.4 cm tall
    pin = 0.0025 / sv                                   # 2.5 mm pinline
    gapw = 0.0035 / sv                                  # 3.5 mm graphite gap between band and pinline
    y = (np.arange(h * SS) + 0.5) / (h * SS)
    d = np.abs(y - centre)
    a = 1.0 / (h * SS)
    band = 1 - smoothstep(half - a, half + a, d)
    p_in, p_out = half + gapw, half + gapw + pin
    pinl = smoothstep(p_in - a, p_in + a, d) * (1 - smoothstep(p_out - a, p_out + a, d))
    B = box_down(np.tile(band[:, None], (1, SS)), SS)[:, 0]
    P = box_down(np.tile(pinl[:, None], (1, SS)), SS)[:, 0]
    body = colourway(det, COLOURWAYS["graphite"][0], seed=11, fleck=FLECK["graphite"])
    tealc = colourway(det, COLOURWAYS["teal"][0], seed=12)
    pinc = ramp(np.clip(0.62 + 0.10 * det["z"], 0, 1), [(0.0, "#04403b"), (0.5, "#0fbfb0"), (1.0, "#8ff3e9")])
    col = body * (1 - B[:, None, None]) + tealc * B[:, None, None]
    return col * (1 - P[:, None, None]) + pinc * P[:, None, None]


def design_camo(det, u, h=256, w=256):
    """Urban camo: four greys in organic blobs (~8 cm), periodic, over the fabric weave."""
    su, sv = u["su"], u["sv"]
    blob = 0.085
    cu, cv = su / blob, sv / blob
    n1 = pnoise(h * 2, w * 2, cu, cv, 101, rough=0.35)
    n2 = pnoise(h * 2, w * 2, cu * 1.25, cv * 1.25, 202, rough=0.35)
    n3 = pnoise(h * 2, w * 2, cu * 1.6, cv * 1.6, 303, rough=0.35)
    e = 0.05
    m_dark = smoothstep(0.40 - e, 0.40 + e, n1)
    m_slate = smoothstep(0.45 - e, 0.45 + e, n2) * (1 - m_dark)
    m_light = smoothstep(1.00 - e, 1.00 + e, n3) * (1 - m_dark) * (1 - m_slate)
    md, ms, ml = (box_down(m, 2) for m in (m_dark, m_slate, m_light))
    base = colourway(det, [(0.0, "#08090a"), (0.5, "#2a2e33"), (1.0, "#737a83")], seed=21)
    dark = colourway(det, [(0.0, "#010101"), (0.5, "#0c0d0f"), (1.0, "#3a3e43")], seed=22)
    slate = colourway(det, [(0.0, "#0c1014"), (0.5, "#3b4652"), (1.0, "#8e9cab")], seed=23)
    light = colourway(det, [(0.0, "#2a2d31"), (0.5, "#767d84"), (1.0, "#cdd2d7")], seed=24, rel_scale=0.6)
    return base * (1 - md - ms - ml)[..., None] + dark * md[..., None] + slate * ms[..., None] + light * ml[..., None]


def design_sunset(det, u, h=256, w=256):
    """Gradient over the visible fabric (top violet -> magenta -> orange -> amber), weave kept."""
    r_top, r_bot = u["rows"]
    y = (np.arange(h) + 0.5) / h
    g = np.clip((y - r_top) / (r_bot - r_top), 0, 1)
    stops = [(0.0, "#1d0b40"), (0.4, "#6c1450"), (0.72, "#b2421f"), (1.0, "#cf8420")]
    body = ramp(g, stops)
    lab = lin_to_oklab(body)
    hn = 0.02 * pnoise(h, w, 6, 6, 31, rough=0.3)
    zz = det["z"] * 0.30 + hn
    out = np.empty((h, w, 3))
    for c in range(3):
        out[..., c] = lab[:, None, c]
    out[..., 0] = out[..., 0] * np.exp(zz)
    out[..., 1:] *= (1 - 0.3 * np.clip(zz, 0, None))[..., None]
    return np.clip(oklab_to_lin(out), 0, 1)


DESIGNS = {"carbon": design_carbon, "honeycomb": design_honeycomb, "stripe": design_stripe,
           "camo": design_camo, "sunset": design_sunset}


# (texture, variant) pairs written at 2x: sp3 covers the big drum (c) at only ~3.6 px/cm, which blurs fine
# woven / perforated designs at the original 256 px
HIRES = {("sp3", "carbon"), ("sp3", "honeycomb")}


def fabric_variant(name: str, rgba: np.ndarray, det: dict, u: dict, scale: int = 1) -> np.ndarray:
    if name == "original":
        return rgba.copy()
    h, w = rgba.shape[0] * scale, rgba.shape[1] * scale
    if scale > 1:
        det = dict(det, z=fft_upsample(det["z"], scale), chroma=fft_upsample(det["chroma"], scale))
    if name in COLOURWAYS:
        stops, rel = COLOURWAYS[name]
        cells = (u["su"] / 0.07, u["sv"] / 0.07)              # soft heather ~7 cm
        col = colourway(det, stops, cells=cells, seed=sum(map(ord, name)), fleck=FLECK.get(name), rel_scale=rel)
    else:
        col = DESIGNS[name](det, u, h, w)
    return to_u8(col)


# --------------------------------------------------------------------------- repro (f driver)
# Only the part of the driver texture inside f's end caps is ever seen: an ellipse in texture space
# (centre / radii come from the props' UVs, see texture_usage 'box').  Every variant keeps the original's
# perforated mesh shading inside it and adds a coloured trim ring and a domed dust cap.
REPRO_VARIANTS = {
    # name: (mesh ramp, trim ramp, cap ramp)  shadow|body|light, sRGB
    "graphite": ("#030304|#111316|#3c4248", "#121417|#4a5058|#a8b0b8", "#08090a|#25292e|#8a929a"),
    "chrome": ("#020203|#0c0d0f|#30353a", "#3c4046|#b4bac0|#ffffff", "#2a2d31|#9aa0a6|#ffffff"),
    "teal": ("#010504|#06231f|#118a7f", "#03302c|#0aa396|#9ff7ee", "#021f1c|#08776e|#7ff0e4"),
    "crimson": ("#050102|#260509|#8a1a25", "#2a0408|#b0161f|#ff9aa1", "#1e0306|#7a0f18|#ff7a83"),
    "violet": ("#030107|#170c33|#5a3fb0", "#1a0d38|#6a3fc6|#d2c0ff", "#110826|#4a2b90|#b9a2ff"),
    "gold": ("#020202|#0f0e0c|#3a352b", "#3d2606|#c08f2e|#fff0c2", "#2e1d05|#9c7322|#ffe3a1"),
    "carbon": ("carbon", "#3c4046|#b4bac0|#ffffff", "#08090a|#25292e|#8a929a"),
    "honeycomb": ("hex", "#121417|#4a5058|#a8b0b8", "#021f1c|#08776e|#7ff0e4"),
}


def _stops3(spec: str):
    a, b, c = spec.split("|")
    return [(0.0, a), (0.5, b), (1.0, c)]


def repro_variant(name: str, rgba: np.ndarray, box) -> np.ndarray:
    """box = (u0, u1, row0, row1) of the visible end cap in texture space."""
    if name == "original":
        return rgba.copy()
    up = 2                                             # written at 256 for a crisper trim and cap
    h, w = rgba.shape[0] * up, rgba.shape[1] * up
    lin = srgb_to_lin(rgba[..., :3] / 255.0)
    ll = np.log(luminance(lin) + 0.004)
    hp = ll - blur(ll, 5)
    z = fft_upsample(hp / (hp.std() + 1e-9), up)        # the original's mesh holes / threads
    big = fft_upsample(blur(ll, 5), up)
    big = (big - big.mean()) / (big.std() + 1e-9)
    u0, u1, r0, r1 = box
    cx, cy = (u0 + u1) / 2 * w, (r0 + r1) / 2 * h
    rx, ry = (u1 - u0) / 2 * w, (r1 - r0) / 2 * h
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    ex, ey = (xx - cx) / rx, (yy - cy) / ry
    r = np.sqrt(ex * ex + ey * ey)                     # 1.0 = edge of the visible cap (circle on the model)
    aa = 1.2 / min(rx, ry)
    mesh_spec, trim_spec, cap_spec = REPRO_VARIANTS[name]
    if mesh_spec == "carbon":
        mesh = design_carbon({"z": z}, {"su": 0.16, "sv": 0.16}, h, w)
    elif mesh_spec == "hex":
        mesh = design_honeycomb({"z": z}, {"su": 0.14, "sv": 0.14}, h, w, spacing_m=0.0095, web=0.13)
    else:
        mesh = ramp(np.clip(0.5 + 0.22 * z + 0.06 * big, 0, 1), _stops3(mesh_spec))
    # cone shading: darker toward the trim, a soft top-left highlight
    light = np.clip(0.75 + 0.25 * (1 - r ** 2) - 0.12 * ey - 0.06 * ex, 0.4, 1.1)
    col = mesh * light[..., None]
    # surround between the mesh and the cap's edge
    R_TRIM0, R_TRIM1, R_CAP = 0.80, 0.88, 0.21
    sur = smoothstep(R_TRIM1 - aa, R_TRIM1 + aa, r)
    sur_col = ramp(np.clip(0.45 + 0.10 * z - 0.25 * ey, 0, 1), [(0.0, "#020203"), (0.5, "#0d0e10"), (1.0, "#2c3035")])
    col = col * (1 - sur[..., None]) + sur_col * sur[..., None]
    # trim ring: a metal/coloured band, lit from the top (bevel: brighter on the upper half)
    trim = smoothstep(R_TRIM0 - aa, R_TRIM0 + aa, r) * (1 - smoothstep(R_TRIM1 - aa, R_TRIM1 + aa, r))
    across = np.clip((r - R_TRIM0) / (R_TRIM1 - R_TRIM0), 0, 1)
    tt = 0.45 + 0.35 * np.sin(np.pi * across) - 0.28 * ey / np.maximum(r, 1e-3) + 0.04 * z
    trim_col = ramp(np.clip(tt, 0, 1), _stops3(trim_spec))
    col = col * (1 - trim[..., None]) + trim_col * trim[..., None]
    # dust cap: a dome with a specular-looking highlight up and left
    rc = r / R_CAP
    cap = 1 - smoothstep(1 - aa / R_CAP, 1 + aa / R_CAP, rc)
    dome = np.sqrt(np.clip(1 - rc ** 2, 0, 1))
    hl = np.exp(-(((ex / R_CAP + 0.35) ** 2 + (ey / R_CAP + 0.4) ** 2) / 0.12))
    cap_col = ramp(np.clip(0.25 + 0.35 * dome + 0.45 * hl, 0, 1), _stops3(cap_spec))
    ring_shadow = 1 - 0.45 * np.exp(-((rc - 1.08) / 0.08) ** 2)          # contact shadow round the cap
    col = col * ring_shadow[..., None]
    col = col * (1 - cap[..., None]) + cap_col * cap[..., None]
    return to_u8(col)


# --------------------------------------------------------------------------- brands (logo)
def draw_mark(size: int, ss: int = 4, ghost: bool = False) -> Image.Image:
    """The house 'mark': teal gradient tile, chamfered bottom-right corner, dark bar (as in style.css).
    ghost=True: a dark tile with the bar knocked out (for teal backgrounds such as the record label)."""
    S = size * ss
    yy, xx = np.mgrid[0:S, 0:S] / S
    g = np.clip((xx * math.cos(math.radians(65)) + yy * math.sin(math.radians(65))) / 1.2, 0, 1)   # 155deg CSS
    c0, c1 = srgb_to_lin(np.array([15, 212, 196]) / 255), srgb_to_lin(np.array([6, 125, 116]) / 255)
    if ghost:
        c0, c1 = srgb_to_lin(np.array([36, 41, 45]) / 255), srgb_to_lin(np.array([20, 23, 26]) / 255)
    col = lin_to_srgb(c0 * (1 - g[..., None]) + c1 * g[..., None])
    arr = np.dstack([col * 255, np.full((S, S), 255.0)]).astype(np.uint8)
    tile = Image.fromarray(arr, "RGBA")
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    rad = int(S * 0.2)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=rad, fill=255)
    d.polygon([(S, int(S * 0.56)), (S, S), (int(S * 0.56), S)], fill=0)
    bar = Image.new("L", (S, S), 0)
    ImageDraw.Draw(bar).rounded_rectangle([int(S * 0.22), int(S * 0.22), int(S * 0.78), int(S * 0.44)],
                                          radius=max(1, S // 40), fill=int(255 * 0.85))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    barm = np.asarray(bar).astype(np.float64) * np.asarray(mask) / 255
    if ghost:                                         # knock the bar out: the background shows through
        o = np.asarray(out).astype(np.float64)
        o[..., 3] *= 1 - barm / (255 * 0.85)
        out = Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), "RGBA")
    else:
        out.paste(Image.new("RGBA", (S, S), (0, 0, 0, 255)), (0, 0), Image.fromarray(barm.astype(np.uint8)))
    return out.resize((size, size), Image.LANCZOS)


def brands_logo(text_rgb=(242, 244, 245), mark=True, w=256, h=64, ss=4, fill_w=0.90, cap_h=0.46) -> np.ndarray:
    """NAYZEEE wordmark for the 128x32 'brands' slot (written at 2x).  Transparent background.

    Laid out to fit fill_w of the width with the cap height at most cap_h of the height; the slot is
    stretched differently on each prop (2.8:1 on a/c/e up to 6:1 on h), so the mark and generous tracking
    keep it legible either way."""
    W, H = w * ss, h * ss
    text = "NAYZEEE"
    probe = fonts.pil_font(400, 700)
    cap_ratio = (probe.getbbox("N")[3] - probe.getbbox("N")[1]) / 400.0

    def layout(cap):
        f = fonts.pil_font(max(8, int(round(cap / cap_ratio))), 700)
        track = cap * 0.22
        widths = [f.getlength(ch) for ch in text]
        mk = cap * 1.18 if mark else 0
        gap = cap * 0.42 if mark else 0
        return f, track, widths, mk, gap, mk + gap + sum(widths) + track * (len(text) - 1)

    cap = H * cap_h
    f, track, widths, mk, gap, total = layout(cap)
    if total > W * fill_w:
        cap *= W * fill_w / total
        f, track, widths, mk, gap, total = layout(cap)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = (W - total) / 2
    if mark:
        m = draw_mark(int(round(mk)), ss=4)
        img.alpha_composite(m, (int(round(x)), int(round((H - mk) / 2))))
        x += mk + gap
    bb = f.getbbox("N")
    ty = (H - (bb[3] - bb[1])) / 2 - bb[1]
    for ch, cw in zip(text, widths):
        d.text((x, ty), ch, font=f, fill=tuple(text_rgb) + (255,))
        x += cw + track
    out = np.asarray(img.resize((w, h), Image.LANCZOS)).astype(np.float64)
    alpha = out[..., 3:4] / 255.0
    # un-premultiply the resampled edges and bleed glyph colour into the transparent texels, so the game's
    # bilinear filtering never pulls dark fringes into the (emissive) letters
    rgb = np.where(alpha > 0.01, out[..., :3], 0)
    solid = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    grown = np.asarray(solid.filter(ImageFilter.MaxFilter(5))).astype(np.float64)
    rgb = np.where(alpha > 0.5, rgb, grown)
    return np.concatenate([np.clip(rgb, 0, 255), out[..., 3:4]], axis=2).round().astype(np.uint8)


# --------------------------------------------------------------------------- record (old turntable)
def record_disc(size=256, ss=4, label=("#08afa2", "#067d74"), vinyl=("#050506", "#16181b"), clear=None) -> np.ndarray:
    """Vinyl disc filling the square (like the original): grooves with track gaps, sheen, NAYZEEE label."""
    S = size * ss
    yy, xx = np.mgrid[0:S, 0:S]
    c = (S - 1) / 2
    dx, dy = (xx - c) / (S / 2), (yy - c) / (S / 2)
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    R_OUT, R_LEAD, R_RUN, R_LABEL, R_HOLE = 0.985, 0.955, 0.40, 0.335, 0.026
    # grooves: fine rings + 5 track gaps; brightness from an anisotropic sheen (two highlight lobes)
    rings = 0.5 + 0.5 * np.sin(r * 2 * np.pi * 95)
    gaps = np.zeros_like(r)
    for g in np.linspace(R_RUN + 0.04, R_LEAD - 0.03, 5)[1:]:
        gaps = np.maximum(gaps, 1 - smoothstep(0.0, 0.006, np.abs(r - g)))
    lobe = np.cos(2 * (ang - math.radians(-35))) ** 2
    lobe = 0.15 + 0.85 * lobe ** 6
    groove_zone = smoothstep(R_RUN - 0.004, R_RUN + 0.004, r) * (1 - smoothstep(R_LEAD - 0.004, R_LEAD + 0.004, r))
    t = (0.18 + 0.12 * rings) * (1 - gaps * 0.7) + lobe * 0.55 * groove_zone * (0.6 + 0.4 * rings) * (1 - 0.6 * gaps)
    lead = smoothstep(R_LEAD - 0.003, R_LEAD + 0.003, r) * (1 - smoothstep(R_OUT - 0.004, R_OUT, r))
    t = t * (1 - lead) + lead * (0.30 + 0.25 * lobe)
    vin = ramp(np.clip(t, 0, 1), [(0.0, vinyl[0]), (0.45, vinyl[1]), (1.0, "#8d949c" if clear is None else clear)])
    # label: two-tone teal with ring, mark and text (drawn with PIL, then composited)
    lab_mask = 1 - smoothstep(R_LABEL - 0.002, R_LABEL + 0.002, r)
    gl = np.clip(0.5 + 0.5 * dy / R_LABEL, 0, 1)
    labc = ramp(gl, [(0.0, label[0]), (1.0, label[1])])
    col = vin * (1 - lab_mask[..., None]) + labc * lab_mask[..., None]
    disc = 1 - smoothstep(R_OUT - 0.002, R_OUT + 0.002, r)
    bg = hexc("#ffffff")
    col = col * disc[..., None] + bg * (1 - disc[..., None])
    img = Image.fromarray(to_u8(col, seed=5))
    d = ImageDraw.Draw(img)
    ink = (8, 9, 10, 255)
    # label: one fine ring near its edge, the mark above the spindle, the name and a small line below it
    rr = R_LABEL * 0.92 * S / 2
    d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=(3, 46, 42, 255), width=max(1, ss))
    mk = int(S * 0.074)
    m = draw_mark(mk, ss=1, ghost=label[0].lower() in ("#08afa2", "#0fd4c4"))
    img.alpha_composite(m, (int(c - mk / 2), int(c - S * 0.040 - mk)))
    f1 = fonts.pil_font(int(S * 0.034), 700)
    f2 = fonts.pil_font(int(S * 0.0165), 500)
    for txt, f, yc in (("NAYZEEE", f1, 0.066), ("SIDE A  ·  33 RPM", f2, 0.108)):
        bb = d.textbbox((0, 0), txt, font=f)
        d.text((c - (bb[2] - bb[0]) / 2 - bb[0], c + S * yc - (bb[3] + bb[1]) / 2), txt, font=f, fill=ink)
    # spindle hole
    d.ellipse([c - R_HOLE * S / 2, c - R_HOLE * S / 2, c + R_HOLE * S / 2, c + R_HOLE * S / 2], fill=(12, 13, 14, 255))
    return np.asarray(img.resize((size, size), Image.LANCZOS))


RECORD_VARIANTS = {
    "nayzeee": {},
    "teal_vinyl": {"vinyl": ("#012a26", "#05605a"), "clear": "#6fe8dc", "label": ("#f2f4f5", "#b9bec3")},
    "crimson_vinyl": {"vinyl": ("#2a0207", "#6e0d18"), "clear": "#ff8a92", "label": ("#0e1011", "#15181a")},
    "smoke_vinyl": {"vinyl": ("#0f1113", "#2c3136"), "clear": "#c5ccd2", "label": ("#08afa2", "#067d74")},
}


# --------------------------------------------------------------------------- output
PALETTE = True


def save_png(arr: np.ndarray, path: str, palette: bool = True) -> int:
    """Write an optimised PNG.  Opaque images are stored as 8-bit indexed colour (256-colour median cut, no
    dither: mean error ~0.5/255 on these textures, ~2.5x smaller than truecolour); they decode to RGBA like any
    PNG.  Images with real transparency (the logo) and the untouched originals stay truecolour RGBA."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = Image.fromarray(np.ascontiguousarray(arr), "RGBA")
    if palette and PALETTE and arr[..., 3].min() == 255:
        im = im.convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True, compress_level=9)
    data = buf.getvalue()
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def texture_usage(stream: str = LR.STREAM) -> dict:
    """For every texture of the shared .ytd that a High-LOD geometry samples by name:
    {models: [...], su / sv: metres per UV unit along u / v (area-weighted), rows: visible texture rows
    (top, bottom; image top = prop top), box: (u0, u1, row0, row1) of the mapped area}."""
    use = {}
    for model in LR.MODELS:
        d = LR.read_ydr(os.path.join(stream, model + ".ydr"))
        for m in d["lods"].get("high", []):
            for g in m["geometries"]:
                sh = d["shaders"][g["shader_index"]]
                for samp, tex in sh["textures"].items():
                    if not tex or sh["texture_source"].get(samp) != "txd":
                        continue
                    e = use.setdefault(tex.lower(), {"models": [], "su": [], "sv": [], "w": [], "rows": []})
                    if model not in e["models"]:
                        e["models"].append(model)
                    P, UV, I = g["comps"]["Position"][:, :3], g["comps"]["TexCoord0"][:, :2], g["indices"]
                    v0 = float(UV[:, 1].min())
                    r0 = v0 - math.floor(v0)
                    e["rows"].append((r0, r0 + float(UV[:, 1].max()) - v0))
                    e.setdefault("ubox", []).append((float(UV[:, 0].min()), float(UV[:, 0].max())))
                    p0, p1, p2 = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
                    t0, t1, t2 = UV[I[:, 0]], UV[I[:, 1]], UV[I[:, 2]]
                    e1, e2, d1, d2 = p1 - p0, p2 - p0, t1 - t0, t2 - t0
                    det = d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]
                    ok = np.abs(det) > 1e-9
                    Tu = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / np.where(ok, det, 1)[:, None]
                    Tv = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / np.where(ok, det, 1)[:, None]
                    A = np.linalg.norm(np.cross(e1, e2), axis=1) * ok
                    if A.sum() > 0:
                        e["su"].append(float((np.linalg.norm(Tu, axis=1) * A).sum() / A.sum()))
                        e["sv"].append(float((np.linalg.norm(Tv, axis=1) * A).sum() / A.sum()))
                        e["w"].append(float(A.sum()))
    for e in use.values():
        rows = e.pop("rows")
        e["rows"] = (min(r[0] for r in rows), max(r[1] for r in rows)) if rows else (0.0, 1.0)
        ub = e.pop("ubox", [(0.0, 1.0)])
        e["box"] = (min(b[0] for b in ub), max(b[1] for b in ub), e["rows"][0], e["rows"][1])
        w = np.array(e.pop("w")) if e["su"] else np.ones(1)
        e["su"] = float(np.average(e["su"], weights=w)) if e["su"] else 0.0
        e["sv"] = float(np.average(e["sv"], weights=w)) if e["sv"] else 0.0
    return use


# default look per texture: distinct jewel tones on the plain fabrics, the graphite honeycomb grille on the
# two props that share sp2, chrome-trimmed drivers on the crimson boombox, the NAYZEEE logo and record
DEFAULTS = {"sp1": "violet", "sp2": "honeycomb", "sp3": "cobalt", "sp4": "teal", "sp5": "crimson",
            "repro": "chrome", "brands": "nayzeee", "record": "nayzeee"}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=LOOKS)
    ap.add_argument("--only", nargs="*", help="textures to (re)write, e.g. sp3 repro brands")
    ap.add_argument("--swatches", help="write a swatch sheet (each variant tiled 2x2) to this PNG")
    ap.add_argument("--no-library", action="store_true", help="do not rewrite library.json")
    ap.add_argument("--truecolour", action="store_true",
                    help="write every PNG as truecolour RGBA (about 2x the size) instead of 8-bit indexed")
    a = ap.parse_args(argv)
    global PALETTE
    PALETTE = not a.truecolour

    ytd = LR.read_ytd(os.path.join(LR.STREAM, LR.YTD))
    use = texture_usage()
    only = set(a.only or [])
    want = lambda t: not only or t in only  # noqa: E731
    lib = {"textures": {}}
    sizes = {}
    swatch_rows = []

    for tex in ("sp1", "sp2", "sp3", "sp4", "sp5"):
        u = use.get(tex)
        if not u:
            continue
        rgba = ytd[tex]["rgba"]
        det = fabric_detail(rgba)
        row = []
        for v in FABRIC_VARIANTS:
            if want(tex):
                img = fabric_variant(v, rgba, det, u, scale=2 if (tex, v) in HIRES else 1)
                sizes[f"{tex}/{v}"] = save_png(img, os.path.join(a.out, tex, v + ".png"), palette=v != "original")
                row.append((v, img))
        if row:
            swatch_rows.append((tex, row))
        lib["textures"][tex] = {"usedBy": u["models"], "size": [rgba.shape[1], rgba.shape[0]],
                                "variants": FABRIC_VARIANTS, "default": DEFAULTS[tex]}

    if "repro" in use:
        rgba = ytd["repro"]["rgba"]
        names = ["original"] + list(REPRO_VARIANTS)
        row = []
        for v in names:
            if want("repro"):
                img = repro_variant(v, rgba, use["repro"]["box"])
                sizes[f"repro/{v}"] = save_png(img, os.path.join(a.out, "repro", v + ".png"), palette=v != "original")
                row.append((v, img))
        if row:
            swatch_rows.append(("repro", row))
        lib["textures"]["repro"] = {"usedBy": use["repro"]["models"], "size": [128, 128], "variants": names,
                                    "default": DEFAULTS["repro"]}

    if "brands" in use:
        variants = {"nayzeee": brands_logo(), "nayzeee_teal": brands_logo(text_rgb=(15, 212, 196))}
        row = []
        for v, img in variants.items():
            if want("brands"):
                sizes[f"brands/{v}"] = save_png(img, os.path.join(a.out, "brands", v + ".png"))
                row.append((v, img))
        if row:
            swatch_rows.append(("brands", row))
        lib["textures"]["brands"] = {"usedBy": use["brands"]["models"], "size": [128, 32],
                                     "variants": list(variants), "default": DEFAULTS["brands"]}

    if "record" in use:
        row = []
        for v, kw in RECORD_VARIANTS.items():
            if want("record"):
                img = record_disc(**kw)
                sizes[f"record/{v}"] = save_png(img, os.path.join(a.out, "record", v + ".png"))
                row.append((v, img))
        if row:
            swatch_rows.append(("record", row))
        lib["textures"]["record"] = {"usedBy": use["record"]["models"], "size": [256, 256],
                                     "variants": list(RECORD_VARIANTS), "default": DEFAULTS["record"]}

    if not a.no_library:
        path = os.path.join(a.out, "library.json")
        old = {}
        if only and os.path.exists(path):
            old = json.load(open(path, encoding="utf-8")).get("textures", {})
        old.update(lib["textures"])
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"textures": {k: old[k] for k in sorted(old)}}, f, indent=2)
            f.write("\n")
    total = sum(sizes.values())
    for k in sorted(sizes):
        print(f"  {k:28s} {sizes[k] / 1024:7.1f} KB")
    print(f"wrote {len(sizes)} images, {total / 1024:.0f} KB")
    if a.swatches and swatch_rows:
        write_swatches(a.swatches, swatch_rows)
    return 0


def write_swatches(path: str, rows) -> None:
    cell = 160
    cols = max(len(r) for _, r in rows)
    im = Image.new("RGB", (90 + cols * (cell + 6), len(rows) * (cell + 22)), (40, 42, 44))
    d = ImageDraw.Draw(im)
    f = fonts.pil_font(13, 500)
    for ri, (tex, row) in enumerate(rows):
        y = ri * (cell + 22)
        d.text((8, y + cell // 2), tex, font=f, fill=(230, 230, 230))
        for ci, (v, img) in enumerate(row):
            a = Image.fromarray(img)
            if a.size[0] == a.size[1] and tex.startswith("sp"):
                t = Image.new("RGBA", (a.size[0] * 2, a.size[1] * 2))
                for oy in (0, a.size[1]):
                    for ox in (0, a.size[0]):
                        t.paste(a, (ox, oy))
                a = t.resize((cell, cell), Image.LANCZOS)
            else:
                a.thumbnail((cell, cell), Image.LANCZOS)
            bg = Image.new("RGBA", a.size, (70, 72, 74, 255))
            bg.alpha_composite(a.convert("RGBA"))
            x = 90 + ci * (cell + 6)
            im.paste(bg.convert("RGB"), (x, y + (cell - a.size[1]) // 2))
            d.text((x + 2, y + cell + 3), v, font=f, fill=(200, 200, 200))
    im.save(path)


if __name__ == "__main__":
    sys.exit(main())
