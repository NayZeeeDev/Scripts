"""
nzprops.paint - materials, procedural noise and decal painting.

Mat          surface material (colour, specular, gloss, bump pattern, edge wear, layer)
noise3 / fbm3 / noise2 / fbm2   vectorised value noise (numpy only, deterministic)
DecalCanvas  vector painting in METRES (text, rounded rects, lines, circles, the NAYZEEE mark)
             with per-ink height / specular / gloss -> projected or chart-space decals
font(name, px)  bundled fonts (Lexend = brand, JetBrains Mono, VT323 LCD, DejaVu fallback)
screen helpers: draw_monitor_ui / draw_defib_ui / draw_pager_lcd produce default screen images
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fonts")
FONTS = {
    "brand": "lexend-latin-700-normal.woff2",
    "brand-black": "lexend-latin-800-normal.woff2",
    "brand-semi": "lexend-latin-600-normal.woff2",
    "brand-reg": "lexend-latin-400-normal.woff2",
    "mono": "jetbrains-mono-latin-500-normal.woff2",
    "mono-bold": "jetbrains-mono-latin-700-normal.woff2",
    "lcd": "vt323-latin-400-normal.woff2",
    "sans": "DejaVuSans.ttf",
    "sans-bold": "DejaVuSans-Bold.ttf",
    "dmono": "DejaVuSansMono.ttf",
    "dmono-bold": "DejaVuSansMono-Bold.ttf",
}
_font_cache: dict = {}


def font(name: str, px: int):
    """Load a bundled font by key (see FONTS) or file name at a pixel size."""
    px = max(4, int(round(px)))
    key = (name, px)
    if key in _font_cache:
        return _font_cache[key]
    fname = FONTS.get(name, name)
    for path in (os.path.join(FONT_DIR, fname), os.path.join("/usr/share/fonts/truetype/dejavu", fname)):
        if os.path.exists(path):
            f = ImageFont.truetype(path, px)
            _font_cache[key] = f
            return f
    raise FileNotFoundError(f"font {fname} not found in {FONT_DIR}")


# ---------------------------------------------------------------------------------------------
# palette (NAYZEEE UI tokens + realistic equipment colours), sRGB 0..255
# ---------------------------------------------------------------------------------------------
TEAL = (8, 175, 162)
TEAL_HI = (15, 212, 196)
TEAL_LO = (6, 125, 116)
RED = (229, 72, 77)
AMBER = (229, 165, 10)
WHITE = (242, 244, 245)
INK2 = (158, 165, 170)
BLACK = (12, 13, 16)
MED_RED = (196, 30, 36)
ORANGE = (232, 106, 26)
YELLOW = (238, 196, 26)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------------------------------------
# material
# ---------------------------------------------------------------------------------------------
@dataclass
class Mat:
    """Surface material evaluated per texel by the baker.

    color      base colour sRGB (0..255)
    spec       specular intensity 0..1 (GTA spec map RGB)
    gloss      glossiness 0..1 (GTA spec map alpha -> specularFalloffMult)
    metal      metalness for the glTF preview only (GTA's spec workflow has no metal channel)
    grain      low frequency colour variation (fraction) ; grain_scale its size in metres
    bump       height pattern: none stipple brushed fabric webbing foam rubber knurl ribs leather
               orange_peel  (bump_amp metres, bump_scale metres)
    edge       convex edge brightening (worn edges / highlights) 0..1
    ao         how much baked ambient occlusion darkens this material 0..1
    alpha      opacity for layer 'alpha' (translucent bags), 1 elsewhere
    layer      'main' (normal_spec), 'alpha' (normal_spec_alpha), 'glow' (emissive)
    """

    color: tuple = (128, 128, 128)
    spec: float = 0.25
    gloss: float = 0.35
    metal: float = 0.0
    grain: float = 0.03
    grain_scale: float = 0.02
    bump: str = "none"
    bump_amp: float = 0.00015
    bump_scale: float = 0.0015
    edge: float = 0.0
    ao: float = 0.85
    alpha: float = 1.0
    layer: str = "main"
    dirt: float = 0.0
    color2: tuple | None = None     # secondary colour used by some bump patterns (fabric weave)
    extra: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------------------------
def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.uint32) * np.uint32(73856093)) ^ (iy.astype(np.uint32) * np.uint32(19349663)) \
        ^ (iz.astype(np.uint32) * np.uint32(83492791)) ^ np.uint32((seed * 2654435761) & 0xFFFFFFFF)
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    h = h ^ (h >> np.uint32(16))
    return (h & np.uint32(0xFFFF)).astype(np.float32) / 32767.5 - 1.0


def noise3(p, seed=0):
    """Value noise in [-1, 1] for points p (..., 3)."""
    p = np.asarray(p, dtype=np.float64)
    fl = np.floor(p)
    f = (p - fl).astype(np.float32)
    i = fl.astype(np.int64)
    w = f * f * (3 - 2 * f)
    ix, iy, iz = i[..., 0], i[..., 1], i[..., 2]
    wx, wy, wz = w[..., 0], w[..., 1], w[..., 2]
    out = 0.0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                v = _hash(ix + dx, iy + dy, iz + dz, seed)
                wgt = (wx if dx else 1 - wx) * (wy if dy else 1 - wy) * (wz if dz else 1 - wz)
                out = out + v * wgt
    return out


def fbm3(p, octaves=4, seed=0, lac=2.03, gain=0.5):
    total = 0.0
    amp = 1.0
    norm = 0.0
    q = np.asarray(p, dtype=np.float64)
    for o in range(octaves):
        total = total + amp * noise3(q, seed + o * 17)
        norm += amp
        amp *= gain
        q = q * lac
    return total / norm


def noise2(u, v, seed=0):
    z = np.zeros_like(u)
    return noise3(np.stack([u, v, z], axis=-1), seed)


def fbm2(u, v, octaves=4, seed=0):
    z = np.zeros_like(u)
    return fbm3(np.stack([u, v, z], axis=-1), octaves, seed)


# ---------------------------------------------------------------------------------------------
# decal canvas
# ---------------------------------------------------------------------------------------------
class DecalCanvas:
    """A painting surface of w x h METRES at `ppm` pixels per metre.

    Every drawing call takes an ink: colour (sRGB or None for height-only), opacity, height (m,
    positive = raised), spec / gloss overrides. Shapes are rasterised with 4x supersampling.
    Coordinates: x right, y DOWN, origin top-left, all in metres.
    """

    SS = 4

    def __init__(self, w, h, ppm=2000):
        self.w_m, self.h_m, self.ppm = float(w), float(h), float(ppm)
        self.W = max(8, int(round(w * ppm)))
        self.H = max(8, int(round(h * ppm)))
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        self.height = np.zeros((self.H, self.W), np.float32)
        self.spec = np.zeros((self.H, self.W), np.float32)
        self.gloss = np.zeros((self.H, self.W), np.float32)
        self.sg_a = np.zeros((self.H, self.W), np.float32)
        self.metal = np.zeros((self.H, self.W), np.float32)

    # internal ---------------------------------------------------------------------------
    def _px(self, v):
        return v * self.ppm * self.SS

    def _mask(self, draw_fn, blur=0.0):
        img = Image.new("L", (self.W * self.SS, self.H * self.SS), 0)
        draw_fn(ImageDraw.Draw(img))
        img = img.resize((self.W, self.H), Image.BOX)
        if blur > 0:
            img = img.filter(ImageFilter.GaussianBlur(blur))
        return np.asarray(img, np.float32) / 255.0

    def ink(self, m, color=None, alpha=1.0, height=None, spec=None, gloss=None, metal=None, height_mode="add"):
        m = np.clip(m * alpha, 0, 1)
        if color is not None:
            c = np.asarray(color, np.float32)[None, None, :]
            self.rgb = self.rgb * (1 - m[..., None]) + c * m[..., None]
            self.a = np.maximum(self.a, m) if alpha >= 0.999 else self.a + m * (1 - self.a)
        if height is not None:
            if height_mode == "add":
                self.height += m * height
            else:
                self.height = self.height * (1 - m) + height * m
        if spec is not None or gloss is not None:
            if spec is not None:
                self.spec = self.spec * (1 - m) + spec * m
            if gloss is not None:
                self.gloss = self.gloss * (1 - m) + gloss * m
            self.sg_a = np.maximum(self.sg_a, m)
        if metal is not None:
            self.metal = self.metal * (1 - m) + metal * m
        return m

    # shapes -----------------------------------------------------------------------------
    def rect(self, x, y, w, h, r=0.0, fill=True, width=0.0, blur=0.0, **ink):
        box = [self._px(x), self._px(y), self._px(x + w), self._px(y + h)]
        rr = self._px(r)
        lw = max(1, int(round(self._px(width)))) if not fill else 0

        def fn(d):
            if fill:
                d.rounded_rectangle(box, radius=rr, fill=255)
            else:
                d.rounded_rectangle(box, radius=rr, outline=255, width=lw)
        return self.ink(self._mask(fn, blur), **ink)

    def circle(self, cx, cy, r, fill=True, width=0.0, blur=0.0, **ink):
        box = [self._px(cx - r), self._px(cy - r), self._px(cx + r), self._px(cy + r)]
        lw = max(1, int(round(self._px(width)))) if not fill else 0

        def fn(d):
            if fill:
                d.ellipse(box, fill=255)
            else:
                d.ellipse(box, outline=255, width=lw)
        return self.ink(self._mask(fn, blur), **ink)

    def line(self, pts, width, blur=0.0, **ink):
        P = [(self._px(x), self._px(y)) for x, y in pts]
        lw = max(1, int(round(self._px(width))))

        def fn(d):
            d.line(P, fill=255, width=lw, joint="curve")
        return self.ink(self._mask(fn, blur), **ink)

    def polygon(self, pts, blur=0.0, **ink):
        P = [(self._px(x), self._px(y)) for x, y in pts]

        def fn(d):
            d.polygon(P, fill=255)
        return self.ink(self._mask(fn, blur), **ink)

    def text(self, x, y, s, size, fnt="brand", anchor="mm", spacing=0.0, blur=0.0, rotate=0, **ink):
        """size = cap height-ish in metres (font pixel size = size * ppm * 1.38)."""
        px = size * self.ppm * self.SS * 1.38
        f = font(fnt, px)
        sp = self._px(spacing)

        def fn(d):
            if rotate:
                return
            if sp == 0:
                d.text((self._px(x), self._px(y)), s, font=f, fill=255, anchor=anchor)
            else:
                widths = [f.getlength(ch) for ch in s]
                total = sum(widths) + sp * (len(s) - 1)
                ax = anchor[0]
                x0 = self._px(x) - (total / 2 if ax == "m" else (total if ax == "r" else 0))
                for ch, wch in zip(s, widths):
                    d.text((x0, self._px(y)), ch, font=f, fill=255, anchor="l" + anchor[1])
                    x0 += wch + sp
        if rotate:
            # draw rotated text through a temporary canvas
            tmp = Image.new("L", (self.W * self.SS, self.H * self.SS), 0)
            td = ImageDraw.Draw(tmp)
            widths = [f.getlength(ch) for ch in s]
            total = sum(widths) + sp * (len(s) - 1)
            big = Image.new("L", (int(total + px * 2), int(px * 2.2)), 0)
            bd = ImageDraw.Draw(big)
            x0 = px
            for ch, wch in zip(s, widths):
                bd.text((x0, big.height / 2), ch, font=f, fill=255, anchor="lm")
                x0 += wch + sp
            big = big.rotate(rotate, expand=True, resample=Image.BICUBIC)
            tmp.paste(big, (int(self._px(x) - big.width / 2), int(self._px(y) - big.height / 2)))
            m = np.asarray(tmp.resize((self.W, self.H), Image.BOX), np.float32) / 255.0
            if blur > 0:
                m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255.0
            _ = td
            return self.ink(m, **ink)
        return self.ink(self._mask(fn, blur), **ink)

    def text_width(self, s, size, fnt="brand", spacing=0.0):
        px = size * self.ppm * 1.38
        f = font(fnt, px)
        return (sum(f.getlength(ch) for ch in s) + spacing * self.ppm * (len(s) - 1)) / self.ppm

    def mark(self, x, y, size, color_hi=TEAL_HI, color_lo=TEAL_LO, cut=(0, 0, 0), height=None, spec=0.45, gloss=0.6):
        """The NAYZEEE chamfered mark (square, bottom-right corner cut, inner bar) at (x, y) top-left."""
        s = size
        pts = [(x, y), (x + s, y), (x + s, y + 0.56 * s), (x + 0.56 * s, y + s), (x, y + s)]
        m = self._mask(lambda d: d.polygon([(self._px(a), self._px(b)) for a, b in pts], fill=255))
        # gradient 155deg from hi (top-left) to lo (bottom-right)
        yy, xx = np.mgrid[0:self.H, 0:self.W].astype(np.float32)
        gx = (xx / self.ppm - x) / s
        gy = (yy / self.ppm - y) / s
        t = np.clip((gx * 0.42 + gy * 0.91) / 1.33, 0, 1)
        col = np.asarray(color_hi, np.float32) * (1 - t[..., None]) + np.asarray(color_lo, np.float32) * t[..., None]
        self.rgb = self.rgb * (1 - m[..., None]) + col * m[..., None]
        self.a = np.maximum(self.a, m)
        if height is not None:
            self.height += m * height
        self.spec = self.spec * (1 - m) + spec * m
        self.gloss = self.gloss * (1 - m) + gloss * m
        self.sg_a = np.maximum(self.sg_a, m)
        bar = self._mask(lambda d: d.rounded_rectangle([self._px(x + 0.22 * s), self._px(y + 0.22 * s), self._px(x + 0.78 * s), self._px(y + 0.44 * s)],
                                                       radius=self._px(0.02 * s), fill=255))
        self.ink(bar, color=cut, alpha=0.88)
        return m

    def lockup(self, x, y, h, text="NAYZEEE", sub="MEDICAL", color=WHITE, sub_color=None, mark=True, height=None,
               spec=0.35, gloss=0.5, fnt="brand", spacing=0.16):
        """Mark + wordmark lockup, h = mark size (metres). Returns total width."""
        cx = x
        if mark:
            self.mark(x, y, h, height=height)
            cx = x + h * 1.32
        ts = h * 0.40
        self.text(cx, y + h * (0.30 if sub else 0.5), text, ts, fnt=fnt, anchor="lm", spacing=ts * spacing,
                  color=color, height=height, spec=spec, gloss=gloss)
        if sub:
            self.text(cx, y + h * 0.78, sub, ts * 0.62, fnt="brand-semi", anchor="lm", spacing=ts * 0.62 * 0.42,
                      color=sub_color or TEAL, height=height, spec=spec, gloss=gloss)
        w = self.text_width(text, ts, fnt, ts * spacing)
        return (cx - x) + w

    # finishing --------------------------------------------------------------------------
    def soften(self, sigma_px=0.6):
        img = Image.fromarray((np.clip(self.height / (np.abs(self.height).max() + 1e-12), -1, 1) * 127 + 128).astype(np.uint8))
        _ = img
        return self


# ---------------------------------------------------------------------------------------------
# default screen images (what the prop shows before a DUI replaces 'nz_amb_screen')
# ---------------------------------------------------------------------------------------------
def _ecg_wave(t):
    """Normalised ECG-ish waveform for t in beats (fractional part used)."""
    f = t - np.floor(t)
    y = 0.08 * np.exp(-((f - 0.18) / 0.035) ** 2)          # P
    y += -0.12 * np.exp(-((f - 0.295) / 0.008) ** 2)       # Q
    y += 1.0 * np.exp(-((f - 0.315) / 0.011) ** 2)         # R
    y += -0.25 * np.exp(-((f - 0.335) / 0.010) ** 2)       # S
    y += 0.22 * np.exp(-((f - 0.55) / 0.06) ** 2)          # T
    return y


def _pleth_wave(t):
    f = t - np.floor(t)
    return np.clip(np.sin(np.pi * np.clip(f / 0.32, 0, 1)) ** 1.5, 0, 1) * (f < 0.32) + \
        (f >= 0.32) * (0.85 * np.exp(-(f - 0.32) * 3.2) + 0.1 * np.exp(-((f - 0.55) / 0.05) ** 2))


def _trace(d, x0, y0, w, h, fn, beats, color, width=3):
    xs = np.linspace(0, 1, int(w))
    ys = fn(xs * beats)
    pts = [(x0 + xi * w, y0 + h - (yi * 0.8 + 0.1) * h) for xi, yi in zip(xs, ys)]
    d.line(pts, fill=color, width=width, joint="curve")


def draw_monitor_ui(w=512, h=320):
    """Dark bedside-monitor UI in the NAYZEEE palette (ECG / SpO2 / NIBP / RR)."""
    img = Image.new("RGB", (w, h), (6, 8, 10))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    # header bar
    d.rectangle([0, 0, w, int(22 * s)], fill=(14, 17, 20))
    d.polygon([(int(8 * s), int(5 * s)), (int(20 * s), int(5 * s)), (int(20 * s), int(12 * s)), (int(15 * s), int(17 * s)), (int(8 * s), int(17 * s))], fill=TEAL)
    d.text((int(26 * s), int(11 * s)), "NAYZEEE  MEDICAL", font=font("brand", 11 * s), fill=(200, 206, 210), anchor="lm")
    d.text((w - int(8 * s), int(11 * s)), "ADULT   12:04", font=font("mono", 10 * s), fill=(140, 148, 152), anchor="rm")
    # grid lines of the trace area
    tw = int(330 * s)
    for gy in range(int(28 * s), h - int(8 * s), int(12 * s)):
        d.line([(0, gy), (tw, gy)], fill=(12, 18, 18), width=1)
    rows = [("II", _ecg_wave, 4.6, (60, 230, 120), "HR", "78", "bpm"),
            ("PLETH", _pleth_wave, 4.6, (40, 210, 230), "SpO2", "97", "%"),
            ("NIBP", None, 0, (235, 235, 235), "NIBP", "118/76", "(90)"),
            ("RESP", lambda t: 0.5 + 0.45 * np.sin(2 * np.pi * t), 1.4, (240, 200, 40), "RR", "16", "rpm")]
    rh = (h - int(30 * s)) / 4.0
    for k, (lbl, fn, beats, col, vlab, val, unit) in enumerate(rows):
        y0 = int(28 * s + k * rh)
        if fn is not None:
            _trace(d, int(6 * s), y0 + int(4 * s), tw - int(12 * s), rh - int(10 * s), fn, beats, col, max(2, int(2.4 * s)))
            d.text((int(8 * s), y0 + int(6 * s)), lbl, font=font("mono", 10 * s), fill=col, anchor="lt")
        else:
            d.text((int(8 * s), y0 + int(6 * s)), "NIBP  AUTO 5 min   last 12:01", font=font("mono", 10 * s), fill=(150, 156, 160), anchor="lt")
        # value tile
        x1 = tw + int(6 * s)
        d.rectangle([x1, y0 + int(2 * s), w - int(6 * s), y0 + rh - int(3 * s)], fill=(12, 15, 18))
        d.rectangle([x1, y0 + int(2 * s), x1 + int(3 * s), y0 + rh - int(3 * s)], fill=col)
        d.text((x1 + int(10 * s), y0 + int(8 * s)), vlab, font=font("brand-semi", 10 * s), fill=col, anchor="lt")
        big = 34 if len(val) <= 3 else 24
        d.text((w - int(14 * s), y0 + rh * 0.62), val, font=font("brand", big * s), fill=col, anchor="rm")
        d.text((x1 + int(10 * s), y0 + rh - int(10 * s)), unit, font=font("mono", 9 * s), fill=(120, 126, 130), anchor="lb")
    return img


def draw_defib_ui(w=512, h=256):
    img = Image.new("RGB", (w, h), (6, 8, 10))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    d.rectangle([0, 0, w, int(24 * s)], fill=(14, 17, 20))
    d.text((int(10 * s), int(12 * s)), "PADS", font=font("brand-semi", 12 * s), fill=(200, 206, 210), anchor="lm")
    d.text((w // 2, int(12 * s)), "MANUAL  DEFIB", font=font("brand", 12 * s), fill=AMBER, anchor="mm")
    d.text((w - int(10 * s), int(12 * s)), "00:42", font=font("mono", 11 * s), fill=(160, 166, 170), anchor="rm")
    tw = int(330 * s)
    for gy in range(int(30 * s), h - int(6 * s), int(12 * s)):
        d.line([(0, gy), (tw, gy)], fill=(12, 18, 18), width=1)
    _trace(d, int(6 * s), int(40 * s), tw - int(12 * s), int(120 * s), _ecg_wave, 4.2, (60, 230, 120), max(2, int(2.6 * s)))
    d.text((int(8 * s), int(32 * s)), "II  x1.0", font=font("mono", 10 * s), fill=(60, 230, 120), anchor="lt")
    _trace(d, int(6 * s), int(170 * s), tw - int(12 * s), int(70 * s), _pleth_wave, 4.2, (40, 210, 230), max(2, int(2.2 * s)))
    x1 = tw + int(8 * s)
    d.rectangle([x1, int(32 * s), w - int(8 * s), int(128 * s)], fill=(12, 15, 18))
    d.text((x1 + int(8 * s), int(40 * s)), "HR", font=font("brand-semi", 11 * s), fill=(60, 230, 120), anchor="lt")
    d.text((w - int(14 * s), int(92 * s)), "84", font=font("brand", 44 * s), fill=(60, 230, 120), anchor="rm")
    d.rectangle([x1, int(136 * s), w - int(8 * s), int(248 * s)], fill=(30, 14, 10))
    d.text((x1 + int(8 * s), int(144 * s)), "ENERGY", font=font("brand-semi", 11 * s), fill=ORANGE, anchor="lt")
    d.text((w - int(14 * s), int(196 * s)), "200J", font=font("brand", 36 * s), fill=ORANGE, anchor="rm")
    d.text((x1 + int(8 * s), int(238 * s)), "CHARGE TO ARM", font=font("mono", 9 * s), fill=(200, 140, 90), anchor="lb")
    return img


def draw_pager_lcd(w=256, h=128):
    bg = (126, 156, 92)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    s = w / 256.0
    ink = (28, 40, 22)
    # faint pixel grid
    for gx in range(0, w, max(2, int(3 * s))):
        d.line([(gx, 0), (gx, h)], fill=(118, 148, 86))
    d.text((int(6 * s), int(4 * s)), "EMS-1  ", font=font("lcd", 22 * s), fill=ink, anchor="lt")
    d.text((w - int(6 * s), int(4 * s)), "12:04", font=font("lcd", 22 * s), fill=ink, anchor="rt")
    d.line([(int(4 * s), int(26 * s)), (w - int(4 * s), int(26 * s))], fill=ink, width=max(1, int(2 * s)))
    d.text((int(6 * s), int(32 * s)), "P1 10-52 GSW", font=font("lcd", 30 * s), fill=ink, anchor="lt")
    d.text((int(6 * s), int(62 * s)), "STRAWBERRY AVE", font=font("lcd", 26 * s), fill=ink, anchor="lt")
    d.text((int(6 * s), int(90 * s)), "UNIT 3 RESPOND", font=font("lcd", 26 * s), fill=ink, anchor="lt")
    # battery
    d.rectangle([w - int(30 * s), int(112 * s), w - int(8 * s), int(122 * s)], outline=ink, width=max(1, int(1.5 * s)))
    d.rectangle([w - int(27 * s), int(115 * s), w - int(14 * s), int(119 * s)], fill=ink)
    return img
