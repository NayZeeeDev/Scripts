"""Procedural textures for the shared txd ``nayzeee_console_texture``.

The Record Console upgrade has its OWN texture dictionary (TXD_NAME) so its files are added next to
the speaker pack in nayzeee-speaker/stream and never replace the pack's ``nayzeee_audio_texture``.

Every texture is registered by name with its size, DDS format and kind:

    kind 'color'    sRGB diffuse colour (RGB, or RGBA when fmt == 'DXT5')
    kind 'normal'   tangent-space normal map, DirectX convention (green = image
                    DOWN, like GTA V); lib.glb flips green for glTF
    kind 'spec'     GTA spec map: RGB = specular intensity (masked by
                    specMapIntMask), A (DXT5 only) = glossiness
    kind 'emissive' colour used by emissive shaders (DiffuseSampler)

Generators return float arrays (h, w, 3|4) in 0..1 and are deterministic
(fixed seeds).  ``image(name)`` caches results per process.

Add your own from a model file:

    from lib import textures as tx
    @tx.register("my_panel_d", size=512, fmt="DXT1", kind="color")
    def _my_panel(w, h):
        return tx.solid(w, h, "#202326")
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache
from typing import Callable, Dict, Tuple

import numpy as np
from PIL import Image, ImageDraw

from . import fonts

TXD_NAME = "nayzeee_console_texture"

# house palette (nayzeee-speaker/html/css/style.css)
TEAL = "#08afa2"
TEAL_HI = "#0fd4c4"
TEAL_LO = "#067d74"
RED = "#e5484d"
BASE = "#08090a"
PANEL = "#0e1011"
RAISE = "#15181a"
INK = "#f2f4f5"


# --------------------------------------------------------------------------- registry
@dataclass
class TextureDef:
    name: str
    size: Tuple[int, int]          # (width, height), powers of two
    fmt: str                       # 'DXT1' (opaque) | 'DXT5' (alpha)
    kind: str                      # 'color' | 'normal' | 'spec' | 'emissive'
    fn: Callable[[int, int], np.ndarray]
    description: str = ""
    replaceable: bool = False      # documented as runtime-replaceable by gameplay code

    @property
    def usage(self) -> str:
        """GTA TextureUsage enum string for the ytd."""
        return {"normal": "NORMAL", "spec": "SPECULAR"}.get(self.kind, "DIFFUSE")


_REG: Dict[str, TextureDef] = {}


def register(name: str, size=512, fmt: str = "DXT1", kind: str = "color", description: str = "",
             replaceable: bool = False):
    """Decorator registering ``fn(w, h) -> float array`` as texture ``name``."""
    w, h = (size, size) if isinstance(size, int) else size
    for v in (w, h):
        if v < 4 or v & (v - 1):
            raise ValueError(f"texture {name}: size {size} must be powers of two >= 4")
    if fmt not in ("DXT1", "DXT5"):
        raise ValueError("fmt must be DXT1 or DXT5")
    if name != name.lower():
        raise ValueError("texture names must be lowercase")

    def deco(fn):
        if name in _REG:
            raise KeyError(f"texture {name!r} already registered")
        _REG[name] = TextureDef(name, (int(w), int(h)), fmt, kind, fn, description or (fn.__doc__ or "").strip(),
                                replaceable)
        return fn
    return deco


def get(name: str) -> TextureDef:
    if name not in _REG:
        raise KeyError(f"unknown texture {name!r}")
    return _REG[name]


def names():
    return list(_REG)


def exists(name: str) -> bool:
    return name in _REG


@lru_cache(maxsize=None)
def _image_cached(name: str) -> np.ndarray:
    d = get(name)
    w, h = d.size
    a = np.asarray(d.fn(w, h), dtype=np.float32)
    if a.ndim == 2:
        a = np.repeat(a[:, :, None], 3, axis=2)
    if a.shape[0] != h or a.shape[1] != w:
        raise ValueError(f"texture {name}: generator returned {a.shape}, expected ({h},{w},C)")
    if d.fmt == "DXT1" and a.shape[2] == 4:
        a = a[:, :, :3]
    if d.fmt == "DXT5" and a.shape[2] == 3:
        a = np.concatenate([a, np.ones((h, w, 1), np.float32)], axis=2)
    a = np.clip(a, 0.0, 1.0)
    a.setflags(write=False)
    return a


def image(name: str) -> np.ndarray:
    """Generated texture as float32 (h, w, 3|4) in 0..1 (read-only, cached)."""
    return _image_cached(name)


def to_pil(arr: np.ndarray) -> Image.Image:
    a = np.clip(np.asarray(arr) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(a, "RGBA" if a.shape[2] == 4 else "RGB")


def pil(name: str) -> Image.Image:
    return to_pil(image(name))


# --------------------------------------------------------------------------- building blocks
def hex_rgb(c) -> np.ndarray:
    """'#rrggbb' or (r,g,b) 0..255/0..1 -> float RGB 0..1."""
    if isinstance(c, str):
        c = c.lstrip("#")
        return np.array([int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    c = np.asarray(c, dtype=float)
    return c / 255.0 if c.max() > 1.0 else c


def solid(w: int, h: int, color) -> np.ndarray:
    return np.tile(hex_rgb(color), (h, w, 1)).astype(np.float32)


def rng(seed: int):
    return np.random.default_rng(seed)


def blur(img: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    """Periodic (tileable) gaussian blur via FFT; sx/sy in pixels."""
    sy = sx if sy is None else sy
    a = np.asarray(img, dtype=np.float64)
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * math.pi ** 2 * ((fx * sx) ** 2 + (fy * sy) ** 2))
    if a.ndim == 2:
        return np.fft.irfft2(np.fft.rfft2(a) * g, s=(h, w))
    return np.stack([np.fft.irfft2(np.fft.rfft2(a[:, :, c]) * g, s=(h, w)) for c in range(a.shape[2])], axis=2)


def norm01(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / (hi - lo) if hi > lo else np.zeros_like(a)


def standardize(a: np.ndarray) -> np.ndarray:
    s = float(a.std())
    return (a - a.mean()) / s if s > 0 else a * 0


def value_noise(w: int, h: int, cells_x: int, cells_y: int | None = None, seed: int = 0) -> np.ndarray:
    """Tileable smooth value noise in 0..1 (cubic-interpolated random lattice)."""
    cells_y = cells_x if cells_y is None else cells_y
    g = rng(seed).random((cells_y, cells_x))
    x = np.arange(w) * cells_x / w
    y = np.arange(h) * cells_y / h
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    x0 %= cells_x
    y0 %= cells_y
    x1 = (x0 + 1) % cells_x
    y1 = (y0 + 1) % cells_y
    a = g[y0][:, x0]
    b = g[y0][:, x1]
    c = g[y1][:, x0]
    d = g[y1][:, x1]
    top = a + (b - a) * sx[None, :]
    bot = c + (d - c) * sx[None, :]
    return top + (bot - top) * sy[:, None]


def fbm(w: int, h: int, base: int = 4, octaves: int = 5, gain: float = 0.5, seed: int = 0,
        aspect: float = 1.0) -> np.ndarray:
    """Tileable fractal noise, standardized (mean 0, std 1). ``aspect`` stretches cells in x."""
    out = np.zeros((h, w))
    amp = 1.0
    for o in range(octaves):
        cx = max(1, int(round(base * (2 ** o) / aspect)))
        cy = max(1, base * (2 ** o))
        if cx > w or cy > h:
            break
        out += amp * (value_noise(w, h, cx, cy, seed + o * 101) - 0.5)
        amp *= gain
    return standardize(out)


def white(w: int, h: int, seed: int = 0) -> np.ndarray:
    return rng(seed).standard_normal((h, w))


def smoothstep(e0: float, e1: float, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def height_to_normal(hmap: np.ndarray, strength: float = 1.0, wrap: bool = True) -> np.ndarray:
    """Height field (pixels) -> DirectX-convention tangent-space normal map in 0..1.

    ``strength`` = height units per pixel slope multiplier.  Green encodes the
    image-DOWN component (GTA V); lib.glb converts to OpenGL for glTF.
    """
    hm = np.asarray(hmap, dtype=np.float64)
    if wrap:
        dx = (np.roll(hm, -1, axis=1) - np.roll(hm, 1, axis=1)) * 0.5
        dy = (np.roll(hm, -1, axis=0) - np.roll(hm, 1, axis=0)) * 0.5
    else:
        dy, dx = np.gradient(hm)
    n = np.stack([-dx * strength, -dy * strength, np.ones_like(hm)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return (n * 0.5 + 0.5).astype(np.float32)


def flat_normal(w: int, h: int) -> np.ndarray:
    return np.tile(np.array([0.5, 0.5, 1.0], np.float32), (h, w, 1))


def lerp_colors(t: np.ndarray, stops) -> np.ndarray:
    """Map t (0..1) through colour ``stops`` [(pos, '#hex'), ...]."""
    pos = np.array([p for p, _ in stops])
    cols = np.array([hex_rgb(c) for _, c in stops])
    out = np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], axis=-1)
    return out.astype(np.float32)


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def canvas(w: int, h: int, ss: int = 4, mode: str = "RGBA", color=(0, 0, 0, 0)) -> Image.Image:
    """Supersampled PIL canvas (draw at ``ss`` x, then call ``finish``)."""
    return Image.new(mode, (w * ss, h * ss), color)


def finish(img: Image.Image, ss: int = 4) -> np.ndarray:
    """Box-downsample a supersampled canvas and return float 0..1."""
    if ss > 1:
        img = img.reduce(ss)
    return np.asarray(img, dtype=np.float32) / 255.0


def premul_over(dst: np.ndarray, src_rgba: np.ndarray) -> np.ndarray:
    """Composite straight-alpha ``src_rgba`` over RGB ``dst``."""
    a = src_rgba[:, :, 3:4]
    return dst * (1 - a) + src_rgba[:, :, :3] * a


def draw_text(draw: ImageDraw.ImageDraw, xy, text: str, size: float, weight: int = 500, fill=(255, 255, 255, 255),
              anchor: str = "mm", tracking: float = 0.0):
    """Draw Lexend text; ``tracking`` = extra letter spacing in em (CSS letter-spacing)."""
    font = fonts.pil_font(max(1, int(round(size))), weight)
    if not tracking:
        draw.text(xy, text, font=font, fill=fill, anchor=anchor)
        return font.getlength(text)
    sp = tracking * size
    widths = [font.getlength(c) for c in text]
    total = sum(widths) + sp * (len(text) - 1)
    x, y = xy
    h_anchor, v_anchor = anchor[0], anchor[1]
    x0 = x - (total / 2 if h_anchor == "m" else total if h_anchor == "r" else 0)
    for c, wd in zip(text, widths):
        draw.text((x0, y), c, font=font, fill=fill, anchor="l" + v_anchor)
        x0 += wd + sp
    return total


def text_length(text: str, size: float, weight: int = 500, tracking: float = 0.0) -> float:
    font = fonts.pil_font(max(1, int(round(size))), weight)
    return sum(font.getlength(c) for c in text) + tracking * size * (len(text) - 1) if tracking else \
        font.getlength(text)


def draw_mark(img: Image.Image, x: float, y: float, size: float, style: str = "color"):
    """Draw the nayzeee mark (rounded square, cut corner, black bar) at (x, y) top-left.

    style: 'color' (teal gradient + black bar), 'white' (white, bar knocked out),
    'teal' (flat teal, bar knocked out), 'ink' (black, bar knocked out).
    """
    S = int(round(size))
    if S < 4:
        return
    from .mesh import mark_2d
    outline, bar = mark_2d(1.0, 10)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.polygon([((px + 0.5) * S, (0.5 - py) * S) for px, py in outline], fill=255)
    barm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(barm).polygon([((px + 0.5) * S, (0.5 - py) * S) for px, py in bar], fill=255)
    if style == "color":
        yy, xx = np.mgrid[0:S, 0:S] / max(S - 1, 1)
        ang = math.radians(155)
        d = np.array([math.sin(ang), -math.cos(ang)])            # CSS 155deg as (x, y-down)
        t = (xx - 0.5) * d[0] + (yy - 0.5) * d[1]
        t = norm01(t)
        col = lerp_colors(t, [(0.0, TEAL_HI), (1.0, TEAL_LO)])
        rgb = Image.fromarray((col * 255).astype(np.uint8), "RGB")
        layer = Image.new("RGBA", (S, S))
        layer.paste(rgb, (0, 0))
        bar_a = np.asarray(barm, dtype=np.float32) / 255.0 * 0.85
        arr = np.asarray(layer, dtype=np.float32)
        arr[:, :, :3] *= (1 - bar_a)[:, :, None]
        arr[:, :, 3] = np.asarray(mask, dtype=np.float32)
        layer = Image.fromarray(arr.astype(np.uint8), "RGBA")
    else:
        fill = {"white": (255, 255, 255), "teal": tuple(int(v * 255) for v in hex_rgb(TEAL)),
                "ink": (8, 9, 10)}[style]
        a = np.clip(np.asarray(mask, np.float32) - np.asarray(barm, np.float32), 0, 255)
        arr = np.zeros((S, S, 4), np.uint8)
        arr[:, :, :3] = fill
        arr[:, :, 3] = a.astype(np.uint8)
        layer = Image.fromarray(arr, "RGBA")
    img.alpha_composite(layer, (int(round(x)), int(round(y))))


def arc_text(img: Image.Image, cx: float, cy: float, radius: float, text: str, size: float, weight: int = 500,
             fill=(255, 255, 255, 255), start_deg: float = -90.0, tracking: float = 0.1, outward: bool = True):
    """Draw text along a circle (centred at ``start_deg``, 0 = +x, -90 = top)."""
    font = fonts.pil_font(max(1, int(round(size))), weight)
    widths = [font.getlength(c) for c in text]
    sp = tracking * size
    total = sum(widths) + sp * (len(text) - 1)
    ang = math.radians(start_deg) - (total / 2) / radius
    for c, wd in zip(text, widths):
        mid = ang + (wd / 2) / radius
        cell = int(size * 2.2)
        g = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((cell / 2, cell / 2), c, font=font, fill=fill, anchor="mm")
        rot = -math.degrees(mid) - 90 if outward else -math.degrees(mid) + 90
        g = g.rotate(rot, resample=Image.BICUBIC)
        px = cx + radius * math.cos(mid) - cell / 2
        py = cy + radius * math.sin(mid) - cell / 2
        img.alpha_composite(g, (int(round(px)), int(round(py))))
        ang += (wd + sp) / radius


# --------------------------------------------------------------------------- utility maps
@register("nz_flat_n", 16, kind="normal", description="Flat normal map.")
def _flat_n(w, h):
    return flat_normal(w, h)


@register("nz_spec_full", 16, kind="spec", description="Full-intensity spec map (polished surfaces).")
def _spec_full(w, h):
    return np.ones((h, w, 3), np.float32)


@register("nz_spec_low", 16, kind="spec", description="Low spec map (matte rubber, felt, paper).")
def _spec_low(w, h):
    return np.full((h, w, 3), 0.35, np.float32)


# --------------------------------------------------------------------------- plastics
def _plastic(w, h, color, seed):
    n = fbm(w, h, 3, 4, seed=seed) * 0.018 + blur(white(w, h, seed + 1), 0.7) * 0.06
    c = hex_rgb(color)[None, None, :] * (1.0 + n[:, :, None])
    return c


@register("nz_plastic_black_d", 256, description="Near-black moulded plastic.")
def _plastic_black(w, h):
    return _plastic(w, h, "#17181a", 11)


@register("nz_plastic_graphite_d", 256, description="Graphite grey plastic.")
def _plastic_graphite(w, h):
    return _plastic(w, h, "#2d3034", 12)


@register("nz_plastic_teal_d", 256, description="nayzeee teal plastic.")
def _plastic_teal(w, h):
    return _plastic(w, h, "#07a196", 13)


@register("nz_plastic_white_d", 256, description="Off-white plastic.")
def _plastic_white(w, h):
    return _plastic(w, h, "#d9dcde", 14)


@register("nz_plastic_n", 512, kind="normal", description="Fine orange-peel moulding texture.")
def _plastic_n(w, h):
    hm = blur(white(w, h, 21), 1.1) * 0.7 + blur(white(w, h, 22), 2.6) * 1.0 + fbm(w, h, 8, 3, seed=23) * 0.1
    return height_to_normal(standardize(hm), 0.045)


@register("nz_plastic_s", 256, kind="spec", description="Plastic spec with soft smudges.")
def _plastic_s(w, h):
    sm = fbm(w, h, 3, 5, seed=31)
    v = 0.62 + 0.04 * sm - 0.06 * smoothstep(1.2, 2.4, fbm(w, h, 6, 3, seed=32))
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


# --------------------------------------------------------------------------- rubber
@register("nz_rubber_d", 256, description="Black rubber with faint dust mottling.")
def _rubber_d(w, h):
    m = fbm(w, h, 4, 5, seed=41)
    dust = smoothstep(1.4, 2.6, fbm(w, h, 10, 3, seed=42)) * 0.05
    c = hex_rgb("#1b1b1c")[None, None, :] * (1 + 0.05 * m[:, :, None]) + dust[:, :, None]
    return c


@register("nz_rubber_n", 256, kind="normal", description="Soft-touch rubber grain.")
def _rubber_n(w, h):
    hm = blur(white(w, h, 43), 1.4) + 0.5 * blur(white(w, h, 44), 3.0)
    return height_to_normal(standardize(hm), 0.12)


@register("nz_rubber_knurl_n", 512, kind="normal", description="Diamond knurl, 16 diamonds per tile.")
def _rubber_knurl(w, h):
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    f = 16
    a = (x + y) * f
    b = (x - y) * f
    tri = lambda t: 1 - 2 * np.abs((t % 1.0) - 0.5)
    hm = np.minimum(tri(a), tri(b))
    hm = smoothstep(0.0, 0.6, hm)
    hm = blur(hm, 1.6) + blur(white(w, h, 45), 1.5) * 0.015
    return height_to_normal(hm * 6.0, 1.0)


# --------------------------------------------------------------------------- perforated grilles
def _hex_lattice(w, h, cols, rows):
    """Nearest lattice centre offsets (dx, dy) in pixels for a staggered (hex) lattice."""
    px = w / cols
    py = h / rows
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    best_d = np.full((h, w), np.inf)
    best_dx = np.zeros((h, w))
    best_dy = np.zeros((h, w))
    r0 = np.floor(yy / py)
    for dr in (-1, 0, 1):
        r = r0 + dr
        cy = (r + 0.5) * py
        off = np.where((r.astype(int) % 2) == 0, 0.0, 0.5)
        cbase = np.floor(xx / px - off)
        for dc in (-1, 0, 1):
            cx = (cbase + dc + 0.5 + off) * px
            dx = xx - cx
            dy = yy - cy
            dd = dx * dx + dy * dy
            m = dd < best_d
            best_d = np.where(m, dd, best_d)
            best_dx = np.where(m, dx, best_dx)
            best_dy = np.where(m, dy, best_dy)
    return best_dx, best_dy, px


def _grille(w, h, shape, seed):
    cols = 16
    rows = int(round(cols * 2 / math.sqrt(3) / 2)) * 2       # even rows -> tileable
    dx, dy, pitch = _hex_lattice(w, h, cols, rows)
    if shape == "hex":
        # pointy-top hexagon distance (inradius metric)
        ax, ay = np.abs(dx), np.abs(dy)
        dist = np.maximum(ax, ax * 0.5 + ay * (math.sqrt(3) / 2))
        rad = pitch * 0.40
    else:
        dist = np.sqrt(dx * dx + dy * dy)
        rad = pitch * 0.34
    edge = dist - rad                       # <0 inside hole
    hole = 1.0 - smoothstep(-0.7, 0.7, edge)  # antialiased hole mask
    rim = smoothstep(0.0, 3.0, edge)         # rounded pressed edge
    return hole, rim, edge


def _grille_d(w, h, shape, seed):
    hole, rim, edge = _grille(w, h, shape, seed)
    metal = hex_rgb("#1d1f22")[None, None, :] * (1 + 0.05 * fbm(w, h, 4, 4, seed=seed)[:, :, None]
                                                 + 0.03 * blur(white(w, h, seed + 1), 0.8)[:, :, None])
    ao = 0.65 + 0.35 * smoothstep(0.0, 4.0, edge)
    inside = hex_rgb("#030303")[None, None, :] * (1 + 0.5 * smoothstep(-6, 0, edge))[:, :, None]
    return metal * ao[:, :, None] * (1 - hole[:, :, None]) + inside * hole[:, :, None]


def _grille_n(w, h, shape, seed):
    hole, rim, edge = _grille(w, h, shape, seed)
    hm = rim * 1.0 + blur(white(w, h, seed + 2), 0.9) * 0.02
    return height_to_normal(hm, 1.6)


def _grille_s(w, h, shape, seed):
    hole, rim, edge = _grille(w, h, shape, seed)
    v = 0.78 * (1 - 0.85 * blur(hole, 0.9)) * (0.7 + 0.3 * rim)
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


for _shape in ("hex", "round"):
    register(f"nz_grille_{_shape}_d", 512, description=f"Perforated steel grille ({_shape} holes).")(
        lambda w, h, s=_shape: _grille_d(w, h, s, 51))
    register(f"nz_grille_{_shape}_n", 512, kind="normal", description=f"Grille ({_shape}) normal.")(
        lambda w, h, s=_shape: _grille_n(w, h, s, 51))
    register(f"nz_grille_{_shape}_s", 512, kind="spec", description=f"Grille ({_shape}) spec.")(
        lambda w, h, s=_shape: _grille_s(w, h, s, 51))


# --------------------------------------------------------------------------- fabric
def _weave(w, h, threads=32, seed=61):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    cell = w / threads
    u = x / cell
    v = y / cell
    iu = np.floor(u).astype(int)
    iv = np.floor(v).astype(int)
    fu = u - iu
    fv = v - iv
    over = ((iu + iv) % 2) == 0         # weft (horizontal thread) on top
    prof = lambda t: np.sqrt(np.clip(1 - (2 * t - 1) ** 2 * 1.15, 0, 1))
    weft_h = prof(fv) * (0.55 + 0.45 * np.sin(math.pi * fu))       # bulge between crossings
    warp_h = prof(fu) * (0.55 + 0.45 * np.sin(math.pi * fv))
    hm = np.where(over, weft_h, warp_h)
    fib_x = blur(white(w, h, seed), 6.0, 0.6)
    fib_y = blur(white(w, h, seed + 1), 0.6, 6.0)
    fib = np.where(over, fib_x, fib_y)
    gap = np.minimum(weft_h, warp_h) < 0.05
    return hm, standardize(fib), over, gap


@register("nz_fabric_d", 512, description="Charcoal acoustic cloth, plain weave (32 threads/tile).")
def _fabric_d(w, h):
    hm, fib, over, gap = _weave(w, h)
    tone = 0.75 + 0.25 * hm + 0.06 * fib + 0.04 * fbm(w, h, 4, 3, seed=62)
    c = hex_rgb("#26282b")[None, None, :] * tone[:, :, None]
    c = np.where(hm[:, :, None] < 0.08, hex_rgb("#060607")[None, None, :], c)
    return c


@register("nz_fabric_n", 512, kind="normal", description="Woven cloth normal.")
def _fabric_n(w, h):
    hm, fib, over, gap = _weave(w, h)
    return height_to_normal(blur(hm, 0.9) * 2.6 + fib * 0.04, 1.0)


@register("nz_fabric_s", 256, kind="spec", description="Cloth spec (thread crowns slightly shiny).")
def _fabric_s(w, h):
    hm, fib, over, gap = _weave(w, h, 32)
    v = 0.15 + 0.35 * hm ** 2
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


# --------------------------------------------------------------------------- brushed metals
def _brush_lines(w, h, seed):
    s = blur(white(w, h, seed), 64.0, 0.5) * 1.0 + blur(white(w, h, seed + 1), 220.0, 1.2) * 0.8
    s = standardize(s)
    scratches = np.zeros((h, w))
    r = rng(seed + 2)
    for _ in range(6):
        y0 = r.integers(0, h)
        x0 = r.integers(0, w)
        ln = r.integers(w // 6, w // 2)
        xs = (x0 + np.arange(ln)) % w
        scratches[y0, xs] += r.uniform(0.3, 0.6)
    scratches = blur(scratches, 1.0, 0.5) * 2
    return s, scratches


@register("nz_brushed_d", 512, description="Linear brushed aluminium (brushing along U).")
def _brushed_d(w, h):
    s, sc = _brush_lines(w, h, 71)
    tone = 1.0 + 0.03 * s + 0.03 * sc + 0.02 * fbm(w, h, 2, 3, seed=72)
    return hex_rgb("#a3a8ad")[None, None, :] * tone[:, :, None]


@register("nz_brushed_n", 512, kind="normal", description="Brushed aluminium micro grooves.")
def _brushed_n(w, h):
    s, sc = _brush_lines(w, h, 71)
    return height_to_normal(s * 0.6 - sc * 0.8, 0.35)


@register("nz_brushed_s", 256, kind="spec", description="Brushed aluminium spec.")
def _brushed_s(w, h):
    s, sc = _brush_lines(w, h, 73)
    v = 0.86 + 0.05 * s + 0.05 * sc
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


def _radial_field(w, h, seed):
    """Concentric brushing: streaks follow circles around the image centre."""
    nr, nt = 512, 2048
    polar = standardize(blur(white(nt, nr, seed), 60.0, 0.5)) + 0.8 * standardize(blur(white(nt, nr, seed + 1), 400.0, 0.8))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    dx = (xx - w / 2) / (w / 2)
    dy = (yy - h / 2) / (h / 2)
    r = np.clip(np.sqrt(dx * dx + dy * dy), 0, 1.0)
    t = (np.arctan2(dy, dx) / (2 * math.pi)) % 1.0
    ri = r * (nr - 1)
    ti = t * nt
    r0 = np.floor(ri).astype(int)
    t0 = np.floor(ti).astype(int) % nt
    fr = ri - r0
    ft = ti - np.floor(ti)
    r1 = np.minimum(r0 + 1, nr - 1)
    t1 = (t0 + 1) % nt
    v = (polar[r0, t0] * (1 - fr) * (1 - ft) + polar[r1, t0] * fr * (1 - ft) + polar[r0, t1] * (1 - fr) * ft
         + polar[r1, t1] * fr * ft)
    rings = np.sin(r * 2 * math.pi * 90) * 0.25
    return v + rings, r


@register("nz_radial_d", 512, description="Concentric brushed aluminium (map a disc with uv_radial).")
def _radial_d(w, h):
    v, r = _radial_field(w, h, 81)
    tone = 1.0 + 0.04 * v
    return hex_rgb("#a7acb1")[None, None, :] * tone[:, :, None]


@register("nz_radial_n", 512, kind="normal", description="Concentric brushing normal.")
def _radial_n(w, h):
    v, r = _radial_field(w, h, 81)
    return height_to_normal(v * 0.5, 0.5, wrap=False)


@register("nz_radial_s", 256, kind="spec", description="Concentric brushing spec.")
def _radial_s(w, h):
    v, r = _radial_field(w, h, 82)
    return np.repeat(np.clip(0.86 + 0.08 * v, 0, 1)[:, :, None], 3, axis=2)


@register("nz_chrome_d", 64, description="Chrome base colour (bright, used with spec.sps).")
def _chrome_d(w, h):
    y = np.linspace(0, 1, h)[:, None, None]
    return hex_rgb("#c3c8cd")[None, None, :] * (0.92 + 0.08 * y) * np.ones((h, w, 1))


@register("nz_gunmetal_d", 256, description="Gunmetal base colour with mottling.")
def _gunmetal_d(w, h):
    m = fbm(w, h, 4, 5, seed=91)
    return hex_rgb("#3a3e44")[None, None, :] * (1 + 0.05 * m[:, :, None])


@register("nz_metal_fine_n", 512, kind="normal", description="Bead-blasted metal micro texture.")
def _metal_fine_n(w, h):
    hm = blur(white(w, h, 92), 0.8) + 0.4 * blur(white(w, h, 93), 2.0)
    return height_to_normal(standardize(hm), 0.12)


@register("nz_gunmetal_s", 256, kind="spec", description="Gunmetal spec.")
def _gunmetal_s(w, h):
    v = 0.7 + 0.1 * fbm(w, h, 4, 4, seed=94) + 0.05 * blur(white(w, h, 95), 0.7)
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


# --------------------------------------------------------------------------- walnut
def spectral_noise(w: int, h: int, sx: float, sy: float | None = None, seed: int = 0) -> np.ndarray:
    """Tileable organic noise: white noise low-passed with an (anisotropic) gaussian, std 1."""
    return standardize(blur(white(w, h, seed), sx, sx if sy is None else sy))


def _walnut_fields(w, h, seed=101):
    yy = np.mgrid[0:h, 0:w][0].astype(np.float64)
    flow = spectral_noise(w, h, w / 5, h / 14, seed) * 1.3 + spectral_noise(w, h, w / 14, h / 40, seed + 1) * 0.35
    rings = 26
    v = yy / h * rings + flow
    ring = v % 1.0
    late = np.exp(-((ring - 0.82) / 0.07) ** 2) + 0.35 * np.exp(-((ring - 0.5) / 0.18) ** 2)
    fibre = spectral_noise(w, h, 40.0, 0.6, seed + 2) + 0.5 * spectral_noise(w, h, 160.0, 1.2, seed + 5)
    pores = smoothstep(2.0, 3.0, spectral_noise(w, h, 4.0, 0.55, seed + 3))
    figure = spectral_noise(w, h, w / 3, h / 10, seed + 4)
    return late, fibre, pores, figure


@register("nz_walnut_d", 1024, description="Walnut veneer, grain along U (26 growth rings per tile).")
def _walnut_d(w, h):
    late, fibre, pores, figure = _walnut_fields(w, h)
    t = np.clip(0.58 + 0.12 * figure - 0.32 * late + 0.07 * fibre, 0, 1)
    c = lerp_colors(t, [(0.0, "#22130a"), (0.3, "#3b2415"), (0.6, "#563620"), (0.85, "#6e4a2d"), (1.0, "#86603e")])
    c *= (1 - 0.4 * pores)[:, :, None]
    return c


@register("nz_walnut_n", 512, kind="normal", description="Walnut pores and grain relief.")
def _walnut_n(w, h):
    late, fibre, pores, figure = _walnut_fields(w, h)
    return height_to_normal(-pores * 0.5 + fibre * 0.06 - late * 0.1, 0.8)


@register("nz_walnut_s", 512, kind="spec", description="Lacquered walnut spec (pores dull).")
def _walnut_s(w, h):
    late, fibre, pores, figure = _walnut_fields(w, h)
    v = 0.7 - 0.3 * pores + 0.04 * fibre
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


# --------------------------------------------------------------------------- felt
def _felt_fields(w, h, seed=111):
    ss = 2
    img = Image.new("L", (w * ss, h * ss), 128)
    d = ImageDraw.Draw(img)
    r = rng(seed)
    n = int(w * h / 18)
    W, H = w * ss, h * ss
    for _ in range(n):
        x, y = r.uniform(0, W), r.uniform(0, H)
        ang = r.uniform(0, math.pi)
        ln = r.uniform(4, 14) * ss
        bend = r.uniform(-0.4, 0.4)
        pts = []
        for k in range(4):
            t = k / 3
            a = ang + bend * t
            pts.append((x + math.cos(a) * ln * t, y + math.sin(a) * ln * t))
        val = int(r.uniform(70, 200))
        for ox in (0, -W, W):
            for oy in (0, -H, H):
                d.line([(px + ox, py + oy) for px, py in pts], fill=val, width=1)
    a = np.asarray(img.reduce(ss), dtype=np.float64) / 255.0
    return standardize(blur(a, 0.6))


@register("nz_felt_d", 512, description="Black felt fibres.")
def _felt_d(w, h):
    f = _felt_fields(w, h)
    tone = 1 + 0.12 * f + 0.05 * fbm(w, h, 3, 4, seed=112)
    return hex_rgb("#141416")[None, None, :] * tone[:, :, None]


@register("nz_felt_n", 512, kind="normal", description="Felt fibre relief.")
def _felt_n(w, h):
    return height_to_normal(blur(_felt_fields(w, h), 0.8), 0.3)


# --------------------------------------------------------------------------- paper / card
@register("nz_paper_n", 256, kind="normal", description="Paper / card fibre grain.")
def _paper_n(w, h):
    hm = blur(white(w, h, 121), 0.9) + 0.6 * blur(white(w, h, 122), 4.0, 1.5)
    return height_to_normal(standardize(hm), 0.06)


@register("nz_paper_s", 64, kind="spec", description="Printed card spec.")
def _paper_s(w, h):
    return np.full((h, w, 3), 0.45, np.float32)


@register("nz_sleeve_card_d", 256, description="Black card stock.")
def _sleeve_card_d(w, h):
    f = blur(white(w, h, 123), 0.8) * 0.04 + fbm(w, h, 3, 4, seed=124) * 0.02
    return hex_rgb("#141517")[None, None, :] * (1 + f[:, :, None])


# --------------------------------------------------------------------------- vinyl record
VINYL_RADIUS = 0.1515       # metres; the groove/disc textures span this radius
VINYL_LEAD_IN = 0.146
VINYL_RUN_OUT = 0.062
VINYL_LABEL = 0.050
VINYL_TRACK_GAPS = (0.131, 0.114, 0.097, 0.081)     # silent bands between tracks (centre radii)


def _vinyl_radius_map(w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    dx = (xx - w / 2) / (w / 2) * VINYL_RADIUS
    dy = (yy - h / 2) / (h / 2) * VINYL_RADIUS
    return np.sqrt(dx * dx + dy * dy)


def _vinyl_height(w, h):
    r = _vinyl_radius_map(w, h)
    px = 2 * VINYL_RADIUS / w                       # metres per pixel
    pitch = 3.2 * px                                # visual groove pitch
    groove_zone = (r > VINYL_RUN_OUT) & (r < VINYL_LEAD_IN)
    rr = rng(131)
    loud = np.interp(r, np.linspace(0, VINYL_RADIUS, 400), 0.6 + 0.4 * rr.random(400))
    hm = np.where(groove_zone, np.sin(r / pitch * 2 * math.pi) * loud, 0.0)
    gap_w = 0.0013
    for g in VINYL_TRACK_GAPS:
        band = 1 - smoothstep(gap_w * 0.5, gap_w * 0.5 + 2 * px, np.abs(r - g))
        hm *= (1 - band)
    # lead-in: three widely spaced grooves
    lead = (r >= VINYL_LEAD_IN) & (r < VINYL_LEAD_IN + 0.0025)
    hm = np.where(lead, 0.6 * np.sin((r - VINYL_LEAD_IN) / (4 * pitch) * 2 * math.pi), hm)
    # run-out: two faint wide spirals and the locked groove
    for rg in (0.0585, 0.0552, 0.0528):
        hm += 0.7 * np.exp(-((r - rg) / (1.2 * px)) ** 2)
    edge = smoothstep(VINYL_RADIUS - 4 * px, VINYL_RADIUS - 1 * px, r)
    hm *= (1 - edge)
    return hm, r, groove_zone


@register("nz_vinyl_n", 1024, kind="normal", description="Record grooves: concentric rings, track gaps, lead-in/out "
                                                         "(spans the whole 12in disc).")
def _vinyl_n(w, h):
    hm, r, gz = _vinyl_height(w, h)
    return height_to_normal(hm, 0.45, wrap=False)


@register("nz_vinyl_d", 512, description="Record base colour: grooved areas a touch greyer than gaps.")
def _vinyl_d(w, h):
    r = _vinyl_radius_map(w, h)
    px = 2 * VINYL_RADIUS / w
    gz = (r > VINYL_RUN_OUT) & (r < VINYL_LEAD_IN)
    t = np.where(gz, 1.0, 0.0)
    for g in VINYL_TRACK_GAPS:
        t *= smoothstep(0.00065, 0.00065 + 2 * px, np.abs(r - g))
    c = lerp_colors(t, [(0.0, "#08080a"), (1.0, "#131316")])
    return c


@register("nz_vinyl_s", 512, kind="spec", description="Record spec: gaps glossier than grooves.")
def _vinyl_s(w, h):
    r = _vinyl_radius_map(w, h)
    px = 2 * VINYL_RADIUS / w
    gz = (r > VINYL_RUN_OUT) & (r < VINYL_LEAD_IN)
    v = np.where(gz, 0.72, 1.0)
    for g in VINYL_TRACK_GAPS:
        v = np.where(np.abs(r - g) < 0.00065 + px, 1.0, v)
    return np.repeat(v[:, :, None], 3, axis=2).astype(np.float32)


@register("nayzeee_vinyl_label", 512, description="Default centre label (runtime-replaceable). The inscribed "
                                                  "circle maps to the 0.050 m label disc.", replaceable=True)
def _vinyl_label(w, h):
    ss = 2
    S = w * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    c = S / 2
    R = S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) + 0.5
    rr = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / R
    ang = np.arctan2(yy - c, xx - c)
    base = lerp_colors(np.clip(rr, 0, 1), [(0.0, "#121517"), (0.75, "#0d0f10"), (1.0, "#08090a")])
    sheen = 0.035 * np.cos(2 * (ang - 0.6)) * rr
    base = base + sheen[:, :, None]
    arr = np.concatenate([np.clip(base, 0, 1), np.ones((S, S, 1))], axis=2)
    img = Image.fromarray((arr * 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    teal = tuple(int(v * 255) for v in hex_rgb(TEAL)) + (255,)
    for rad, wd, col in ((0.965, 0.012, teal), (0.90, 0.004, (255, 255, 255, 55))):
        r0 = rad * R
        d.ellipse([c - r0, c - r0, c + r0, c + r0], outline=col, width=max(1, int(wd * S)))
    ms = 0.19 * S
    draw_mark(img, c - ms / 2, c - 0.66 * R, ms, "color")
    draw_text(d, (c, c + 0.40 * R), "nayzeee", 0.105 * S, 600, (255, 255, 255, 255), "mm")
    draw_text(d, (c, c + 0.57 * R), "SESSIONS  ·  33 RPM", 0.033 * S, 500, (158, 165, 170, 255), "mm", 0.14)
    draw_text(d, (c - 0.5 * R, c - 0.05 * R), "SIDE", 0.03 * S, 500, (99, 105, 109, 255), "mm", 0.18)
    draw_text(d, (c - 0.5 * R, c + 0.08 * R), "A", 0.075 * S, 600, teal, "mm")
    draw_text(d, (c + 0.5 * R, c - 0.05 * R), "STEREO", 0.03 * S, 500, (99, 105, 109, 255), "mm", 0.18)
    draw_text(d, (c + 0.5 * R, c + 0.08 * R), "HI-FI", 0.048 * S, 600, (230, 233, 235, 255), "mm", 0.06)
    arc_text(img, c, c, 0.81 * R, "NAYZEEE RECORDS  ·  HIGH FIDELITY  ·  NAYZEEE RECORDS", 0.034 * S, 500,
             (120, 128, 133, 255), -90, 0.16)
    # spindle hole surround (the mesh has a real 3.7 mm hole)
    hole = 0.0037 / VINYL_LABEL * R
    for k, col in ((2.6, (22, 24, 26, 255)), (1.25, (6, 6, 7, 255))):
        d.ellipse([c - hole * k, c - hole * k, c + hole * k, c + hole * k], fill=col)
    out = finish(img, ss)[:, :, :3]
    return out


# --------------------------------------------------------------------------- light emitters
def _led(w, h, color, hot=0.25):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    c = hex_rgb(color)[None, None, :]
    return np.clip(c * (0.94 + 0.06 * (1 - r))[:, :, None] + hot * 0.25 * (1 - smoothstep(0, 1.0, r))[:, :, None], 0, 1)


register("nz_led_teal_e", 32, kind="emissive", description="Teal LED.")(lambda w, h: _led(w, h, TEAL_HI))
register("nz_led_amber_e", 32, kind="emissive", description="Amber LED.")(lambda w, h: _led(w, h, "#ff9419"))
register("nz_led_red_e", 32, kind="emissive", description="Red LED.")(lambda w, h: _led(w, h, "#ff3b3f"))
register("nz_led_white_e", 32, kind="emissive", description="White LED.")(lambda w, h: _led(w, h, "#eef4ff", 0.1))


@register("nz_vu_amber_e", (512, 256), kind="emissive", description="Back-lit amber VU meter face (2:1).")
def _vu_face(w, h):
    ss = 2
    W, H = w * ss, h * ss
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64) + 0.5
    cx, cy = W / 2, H * 1.18
    rr = np.sqrt(((xx - W / 2) / W) ** 2 + ((yy - H * 0.55) / H) ** 2)
    base = lerp_colors(np.clip(rr * 1.6, 0, 1), [(0.0, "#ffd88a"), (0.6, "#f6b24a"), (1.0, "#c9781e")])
    img = Image.fromarray((np.concatenate([base, np.ones((H, W, 1))], 2) * 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    ink = (34, 22, 10, 255)
    red = (200, 40, 36, 255)
    R = H * 0.98
    a0, a1 = -140.0, -40.0          # degrees (0 = +x), arc on the top of a circle centred below
    db = [-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3]
    pos = [(v + 20) / 23.0 for v in db]
    # arc lines
    for rad, wd, col, s0, s1 in ((R, 4, ink, a0, a0 + (a1 - a0) * pos[7]), (R, 9, red, a0 + (a1 - a0) * pos[7], a1)):
        d.arc([cx - rad, cy - rad, cx + rad, cy + rad], s0, s1, fill=col, width=wd)
    for v, p in zip(db, pos):
        a = math.radians(a0 + (a1 - a0) * p)
        col = red if v > 0 else ink
        r1, r2 = R + 6, R + (40 if v in (-20, -10, 0, 3) else 28)
        d.line([(cx + r1 * math.cos(a), cy + r1 * math.sin(a)), (cx + r2 * math.cos(a), cy + r2 * math.sin(a))],
               fill=col, width=5)
        tx, ty = cx + (R + 70) * math.cos(a), cy + (R + 70) * math.sin(a)
        draw_text(d, (tx, ty), str(abs(v)) if v else "0", 30, 600, col, "mm")
    for k in range(41):
        a = math.radians(a0 + (a1 - a0) * k / 40)
        d.line([(cx + (R - 2) * math.cos(a), cy + (R - 2) * math.sin(a)),
                (cx + (R - 16) * math.cos(a), cy + (R - 16) * math.sin(a))], fill=ink, width=2)
    draw_text(d, (W / 2, H * 0.72), "VU", 58, 600, ink, "mm")
    draw_text(d, (W * 0.12, H * 0.2), "-", 44, 600, ink, "mm")
    draw_text(d, (W * 0.88, H * 0.2), "+", 44, 600, red, "mm")
    draw_text(d, (W / 2, H * 0.88), "NAYZEEE  AUDIO", 22, 500, (90, 60, 25, 255), "mm", 0.2)
    return finish(img, ss)[:, :, :3]


@register("nz_glass_dark_d", 128, description="Smoked glass base colour.")
def _glass_dark_d(w, h):
    y = np.linspace(0, 1, h)[:, None, None]
    return hex_rgb("#08090b")[None, None, :] * (1.0 + 0.4 * (1 - y)) * np.ones((h, w, 1))


# --------------------------------------------------------------------------- print atlas
ATLAS_TEXTURE = "nz_print_atlas"
ATLAS_SIZE = (1024, 512)
_LABELS = ["VOLUME", "TONE", "BASS", "TREBLE", "POWER", "START", "STOP", "START · STOP", "33", "45", "RPM",
           "33 / 45", "PITCH", "PHONO", "LINE", "AUX", "BLUETOOTH", "PAIR", "LIGHT", "BOOST", "MODE", "PLAY",
           "HI-FI STEREO", "SIDE A", "SIDE B", "RECORD CONSOLE", "NAYZEEE AUDIO"]
_ICONS = ["icon_power", "icon_play", "icon_pause", "icon_bluetooth", "icon_plus", "icon_minus", "icon_up",
          "icon_down", "icon_note", "icon_speaker"]
LABEL_PX = 24          # font size of atlas labels in pixels
_PAD = 4


def _label_key(text: str) -> str:
    k = text.lower().replace("·", "").replace("/", " ").replace("-", " ")
    return "_".join(k.split())


@lru_cache(maxsize=1)
def _atlas_layout():
    """Deterministic shelf packing -> {entry: (x, y, w, h, kind, payload)} in pixels."""
    entries = [("logo", 440, 98, "logo", None), ("wordmark", 340, 88, "wordmark", (255, 255, 255)),
               ("wordmark_teal", 340, 88, "wordmark", hex_rgb(TEAL)), ("mark", 88, 88, "mark", "color"),
               ("mark_white", 88, 88, "mark", "white"), ("knob_scale", 128, 128, "knob_scale", None),
               ("knob_ticks", 128, 128, "knob_ticks", None), ("ring_ticks", 128, 128, "ring_ticks", None)]
    size = LABEL_PX * 1.0
    for t in _LABELS:
        wd = int(math.ceil(text_length(t, size, 500, 0.16))) + 8
        entries.append((_label_key(t), wd, int(size * 1.4), "label", (t, (255, 255, 255))))
    for t in ("VOLUME", "33 / 45", "NAYZEEE AUDIO"):
        wd = int(math.ceil(text_length(t, size, 500, 0.16))) + 8
        entries.append((_label_key(t) + "_teal", wd, int(size * 1.4), "label", (t, hex_rgb(TEAL))))
    for ic in _ICONS:
        entries.append((ic, 48, 48, "icon", ic))
    W, H = ATLAS_SIZE
    # skyline bottom-left packing, tallest entries first (deterministic)
    sky = np.zeros(W, dtype=np.int64)
    out = {}
    order = sorted(range(len(entries)), key=lambda i: (-entries[i][2], -entries[i][1], i))
    for name, ew, eh, kind, payload in (entries[i] for i in order):
        bw = ew + _PAD
        best = None
        for x in range(0, W - bw + 1, 2):
            y = int(sky[x:x + bw].max())
            if best is None or y < best[1]:
                best = (x, y)
        if best is None or best[1] + eh + _PAD > H:
            raise RuntimeError("print atlas overflow; enlarge ATLAS_SIZE")
        x, y = best
        out[name] = (x + _PAD, y + _PAD, ew, eh, kind, payload)
        sky[x:x + bw] = y + eh + _PAD
    return out


def atlas_entries():
    """Names available in the print atlas."""
    return list(_atlas_layout())


def atlas_rect(name: str):
    """(u0, v0, u1, v1) of an atlas entry -- pass to mesh.plane(rect=...) / Mesh.uv_fit(rect=...)."""
    x, y, w, h, _, _ = _atlas_layout()[name]
    W, H = ATLAS_SIZE
    return (x / W, y / H, (x + w) / W, (y + h) / H)


def atlas_aspect(name: str) -> float:
    """Width / height of an atlas entry (for sizing decal quads)."""
    _, _, w, h, _, _ = _atlas_layout()[name]
    return w / h


def _icon(d: ImageDraw.ImageDraw, kind: str, x, y, s, col):
    cx, cy = x + s / 2, y + s / 2
    lw = max(2, int(s * 0.09))
    if kind == "icon_power":
        r = s * 0.32
        d.arc([cx - r, cy - r, cx + r, cy + r], -60, 240, fill=col, width=lw)
        d.line([(cx, cy - s * 0.42), (cx, cy - s * 0.05)], fill=col, width=lw)
    elif kind == "icon_play":
        d.polygon([(cx - s * 0.22, cy - s * 0.3), (cx + s * 0.32, cy), (cx - s * 0.22, cy + s * 0.3)], fill=col)
    elif kind == "icon_pause":
        for ox in (-0.17, 0.07):
            d.rectangle([cx + s * ox, cy - s * 0.3, cx + s * (ox + 0.1), cy + s * 0.3], fill=col)
    elif kind == "icon_bluetooth":
        pts = [(cx - s * 0.2, cy - s * 0.18), (cx + s * 0.18, cy + s * 0.18), (cx, cy + s * 0.38),
               (cx, cy - s * 0.38), (cx + s * 0.18, cy - s * 0.18), (cx - s * 0.2, cy + s * 0.18)]
        d.line(pts, fill=col, width=lw, joint="curve")
    elif kind in ("icon_plus", "icon_minus"):
        d.line([(cx - s * 0.3, cy), (cx + s * 0.3, cy)], fill=col, width=lw)
        if kind == "icon_plus":
            d.line([(cx, cy - s * 0.3), (cx, cy + s * 0.3)], fill=col, width=lw)
    elif kind in ("icon_up", "icon_down"):
        sg = -1 if kind == "icon_up" else 1
        d.polygon([(cx - s * 0.3, cy - sg * s * 0.15), (cx + s * 0.3, cy - sg * s * 0.15), (cx, cy + sg * s * 0.22)],
                  fill=col)
    elif kind == "icon_note":
        d.ellipse([cx - s * 0.3, cy + s * 0.08, cx - s * 0.04, cy + s * 0.3], fill=col)
        d.line([(cx - s * 0.06, cy + s * 0.2), (cx - s * 0.06, cy - s * 0.32)], fill=col, width=lw)
        d.line([(cx - s * 0.06, cy - s * 0.32), (cx + s * 0.26, cy - s * 0.2)], fill=col, width=lw)
    elif kind == "icon_speaker":
        d.polygon([(cx - s * 0.34, cy - s * 0.12), (cx - s * 0.16, cy - s * 0.12), (cx + s * 0.06, cy - s * 0.3),
                   (cx + s * 0.06, cy + s * 0.3), (cx - s * 0.16, cy + s * 0.12), (cx - s * 0.34, cy + s * 0.12)],
                  fill=col)
        for rr in (0.18, 0.3):
            d.arc([cx + s * 0.06 - s * rr, cy - s * rr, cx + s * 0.06 + s * rr, cy + s * rr], -45, 45, fill=col,
                  width=max(1, lw - 1))


def _scale_ring(img: Image.Image, x, y, s, numbers: bool, n_ticks: int, sweep: float = 270.0):
    d = ImageDraw.Draw(img)
    cx, cy = x + s / 2, y + s / 2
    col = (255, 255, 255, 255)
    r_out = s * 0.47
    start = 90 + (360 - sweep) / 2          # PIL angles: 0 = +x, clockwise (y down); 90 = bottom
    for k in range(n_ticks):
        a = math.radians(start + sweep * k / (n_ticks - 1))
        major = (k % (2 if n_ticks > 11 else 1) == 0)
        r_in = r_out - (s * 0.09 if major else s * 0.05)
        d.line([(cx + r_in * math.cos(a), cy + r_in * math.sin(a)), (cx + r_out * math.cos(a), cy + r_out * math.sin(a))],
               fill=col, width=max(2, int(s * 0.018)))
    if numbers:
        for k in range(11):
            a = math.radians(start + sweep * k / 10)
            rr = r_out - s * 0.2
            draw_text(d, (cx + rr * math.cos(a), cy + rr * math.sin(a)), str(k), s * 0.1, 500, col, "mm")


@register(ATLAS_TEXTURE, ATLAS_SIZE, fmt="DXT5", description="Silkscreen prints, labels, icons, knob scales and "
                                                             "logos (white/teal on transparent).")
def _print_atlas(w, h):
    ss = 2
    img = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for name, (x, y, ew, eh, kind, payload) in _atlas_layout().items():
        X, Y, EW, EH = x * ss, y * ss, ew * ss, eh * ss
        if kind == "label":
            text, col = payload
            col = tuple(int(c * 255) if isinstance(c, float) else int(c) for c in col) + (255,)
            draw_text(d, (X + EW / 2, Y + EH / 2), text, LABEL_PX * ss, 500, col, "mm", 0.16)
        elif kind == "wordmark":
            col = tuple(int(c * 255) if isinstance(c, float) else int(c) for c in payload) + (255,)
            draw_text(d, (X + EW / 2, Y + EH * 0.52), "nayzeee", EH * 0.82, 600, col, "mm")
        elif kind == "logo":
            draw_mark(img, X + EH * 0.08, Y + EH * 0.08, EH * 0.84, "color")
            draw_text(d, (X + EH * 1.02, Y + EH * 0.52), "nayzeee", EH * 0.78, 600, (255, 255, 255, 255), "lm")
        elif kind == "mark":
            draw_mark(img, X + 2 * ss, Y + 2 * ss, EW - 4 * ss, payload)
        elif kind == "knob_scale":
            _scale_ring(img, X, Y, EW, True, 11)
        elif kind == "knob_ticks":
            _scale_ring(img, X, Y, EW, False, 21)
        elif kind == "ring_ticks":
            _scale_ring(img, X, Y, EW, False, 60, 354.0)
        elif kind == "icon":
            _icon(d, payload, X, Y, EW, (255, 255, 255, 255))
    a = finish(img, ss)
    # bleed colour into transparent texels so filtering/mips do not darken edges
    rgb, al = a[:, :, :3], a[:, :, 3:4]
    prem = blur(rgb * al, 2.0)
    wsum = blur(al, 2.0)
    fill = np.where(wsum > 1e-4, prem / np.maximum(wsum, 1e-4), 1.0)
    rgb = np.where(al > 0.02, rgb, np.clip(fill, 0, 1))
    return np.concatenate([rgb, al], axis=2)


# --------------------------------------------------------------------------- record sleeve covers
def _cover_base(S, top, bottom):
    yy = np.linspace(0, 1, S)[:, None]
    c = lerp_colors(np.repeat(yy, S, axis=1), [(0.0, top), (1.0, bottom)])
    grain = blur(white(S, S, 141), 0.8) * 0.012
    c = np.clip(c + grain[:, :, None], 0, 1)
    return Image.fromarray((np.concatenate([c, np.ones((S, S, 1))], 2) * 255).astype(np.uint8), "RGBA")


@register("nayzeee_cover_a", 512, description="Default sleeve art A (runtime-replaceable).", replaceable=True)
def _cover_a(w, h):
    ss = 2
    S = w * ss
    img = _cover_base(S, "#0e1011", "#060708")
    d = ImageDraw.Draw(img)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    cx, cy, R = S * 0.62, S * 0.44, S * 0.36
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / R
    disc = (r < 1.0).astype(np.float64)
    rings = 0.5 + 0.5 * np.sin(r * 2 * math.pi * 26)
    col = lerp_colors(np.clip(r, 0, 1), [(0.0, TEAL_HI), (0.55, TEAL), (1.0, TEAL_LO)])
    col = col * (0.82 + 0.18 * rings[:, :, None])
    lab = r < 0.33
    col[lab] = hex_rgb("#08090a")
    layer = np.concatenate([col, disc[:, :, None]], 2)
    img.alpha_composite(Image.fromarray((layer * 255).astype(np.uint8), "RGBA"))
    draw_mark(img, cx - S * 0.05, cy - S * 0.05, S * 0.1, "color")
    draw_text(d, (S * 0.07, S * 0.84), "nayzeee", S * 0.12, 600, (255, 255, 255, 255), "ls")
    draw_text(d, (S * 0.075, S * 0.91), "SESSIONS  VOL. 1", S * 0.032, 500, (158, 165, 170, 255), "ls", 0.22)
    d.rectangle([S * 0.07, S * 0.06, S * 0.07 + S * 0.08, S * 0.06 + S * 0.006], fill=(8, 175, 162, 255))
    return finish(img, ss)[:, :, :3]


@register("nayzeee_cover_b", 512, description="Default sleeve art B (runtime-replaceable).", replaceable=True)
def _cover_b(w, h):
    ss = 2
    S = w * ss
    img = _cover_base(S, "#121416", "#08090a")
    d = ImageDraw.Draw(img)
    for k, col in enumerate([(229, 72, 77, 255), (8, 175, 162, 255), (242, 244, 245, 255)]):
        off = S * (0.16 + 0.11 * k)
        wd = S * 0.07
        d.polygon([(off, S), (off + wd, S), (off + wd + S * 0.62, 0), (off + S * 0.62, 0)], fill=col)
    d.rectangle([0, S * 0.66, S, S], fill=(8, 9, 10, 235))
    draw_text(d, (S * 0.07, S * 0.79), "AFTER", S * 0.1, 700, (255, 255, 255, 255), "ls", 0.04)
    draw_text(d, (S * 0.07, S * 0.9), "HOURS", S * 0.1, 700, (229, 72, 77, 255), "ls", 0.04)
    draw_mark(img, S * 0.82, S * 0.8, S * 0.1, "white")
    draw_text(d, (S * 0.93, S * 0.96), "NAYZEEE", S * 0.024, 500, (158, 165, 170, 255), "rs", 0.2)
    return finish(img, ss)[:, :, :3]


@register("nayzeee_cover_c", 512, description="Default sleeve art C (runtime-replaceable).", replaceable=True)
def _cover_c(w, h):
    ss = 2
    S = w * ss
    img = _cover_base(S, "#0b0c0d", "#0e1011")
    d = ImageDraw.Draw(img)
    r = rng(151)
    n = 18
    bw = S * 0.8 / n
    for i in range(n):
        hgt = S * (0.08 + 0.42 * abs(math.sin(i * 0.55 + 0.3)) * r.uniform(0.6, 1.0))
        x0 = S * 0.1 + i * bw
        t = i / (n - 1)
        col = tuple(int(255 * v) for v in lerp_colors(np.array([t]), [(0, TEAL_HI), (1, TEAL_LO)])[0]) + (255,)
        d.rounded_rectangle([x0 + bw * 0.18, S * 0.58 - hgt, x0 + bw * 0.82, S * 0.58], radius=bw * 0.2, fill=col)
        d.rounded_rectangle([x0 + bw * 0.18, S * 0.6, x0 + bw * 0.82, S * 0.6 + hgt * 0.25], radius=bw * 0.2,
                            fill=col[:3] + (60,))
    draw_text(d, (S / 2, S * 0.8), "GROOVE THEORY", S * 0.072, 600, (255, 255, 255, 255), "mm", 0.08)
    draw_text(d, (S / 2, S * 0.87), "NAYZEEE  RECORDS", S * 0.026, 500, (158, 165, 170, 255), "mm", 0.3)
    draw_mark(img, S / 2 - S * 0.035, S * 0.07, S * 0.07, "color")
    return finish(img, ss)[:, :, :3]
