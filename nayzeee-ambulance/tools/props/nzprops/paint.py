"""
nzprops.paint - materials, procedural noise and decal painting.

Mat          surface material (colour, specular, gloss, bump pattern, edge wear, layer)
noise3 / fbm3 / noise2 / fbm2   vectorised value noise (numpy only, deterministic)
DecalCanvas  vector painting in METRES (text, rounded rects, lines, circles, generic medical symbols,
             barcodes, screws, stitching, engraved seams) with per-ink height / specular / gloss ->
             projected or chart-space decals
font(name, px)  bundled fonts (Lexend = label face, JetBrains Mono, VT323 LCD, DejaVu fallback)
screen helpers: draw_monitor_ui / draw_defib_ui / draw_pager_lcd produce default screen images
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fonts")
FONTS = {
    "label": "lexend-latin-700-normal.woff2",
    "label-black": "lexend-latin-800-normal.woff2",
    "label-semi": "lexend-latin-600-normal.woff2",
    "label-reg": "lexend-latin-400-normal.woff2",
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
# palette (UI accents + realistic equipment colours), sRGB 0..255
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
               orange_peel crinkle (crumpled foil) ...  (bump_amp metres, bump_scale metres)
    edge       convex edge brightening (worn edges / highlights) 0..1
    ao         how much baked ambient occlusion darkens this material 0..1
    alpha      opacity for layer 'alpha' (translucent bags), 1 elsewhere
    layer      'main' (normal_spec), 'alpha' (normal_spec_alpha), 'glow' (emissive)
    dirt       grime in crevices / dust on top faces 0..1
    wear       chipped edge wear 0..1 (-1 = follow `edge`); wear_color what shows through (None = auto:
               lighter base for plastics, bright bare metal for metals / painted metal with metal > 0)
    scratch    fine scratches in gloss + colour 0..1 (-1 = auto from gloss)
    smudge     low frequency gloss variation (handling marks, fingerprints) 0..1 (-1 = auto)
    cavity     darkening of concave creases 0..1
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
    wear: float = -1.0
    wear_color: tuple | None = None
    scratch: float = -1.0
    smudge: float = -1.0
    cavity: float = 0.5
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

    def text(self, x, y, s, size, fnt="label", anchor="mm", spacing=0.0, blur=0.0, rotate=0, max_w=None, **ink):
        """size = cap height-ish in metres (font pixel size = size * ppm * 1.38). max_w shrinks the
        text (and its spacing) until it fits that width."""
        if max_w is not None:
            wdt = self.text_width(s, size, fnt, spacing)
            if wdt > max_w:
                k = max_w / wdt
                size *= k
                spacing *= k
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

    def text_width(self, s, size, fnt="label", spacing=0.0):
        px = size * self.ppm * 1.38
        f = font(fnt, px)
        return (sum(f.getlength(ch) for ch in s) + spacing * self.ppm * (len(s) - 1)) / self.ppm

    # engraved / stitched / mechanical details ------------------------------------------
    def groove(self, pts, width=0.0006, depth=0.00025, color=(0, 0, 0), alpha=0.45, closed=False, blur=0.0):
        """Engraved line (panel split line, seam): a shallow dark channel along a polyline."""
        P = list(pts) + ([pts[0]] if closed else [])
        m = self.line(P, width, blur=blur)
        self.ink(m, color=color, alpha=alpha)
        self.ink(m, height=-depth)
        return m

    def groove_rect(self, x, y, w, h, r=0.0, width=0.0006, depth=0.00025, color=(0, 0, 0), alpha=0.45):
        """Rounded rectangular split line (battery doors, service hatches, panel inserts)."""
        m = self.rect(x, y, w, h, r=r, fill=False, width=width)
        self.ink(m, color=color, alpha=alpha)
        self.ink(m, height=-depth)
        return m

    def stitch(self, pts, length=0.0032, gap=0.0016, width=0.0007, color=None, height=0.00014, thread_spec=0.25,
               thread_gloss=0.35, closed=False):
        """Lock-stitch seam: raised thread dashes along a polyline over a faint sunk channel."""
        P = np.asarray(list(pts) + ([pts[0]] if closed else []), np.float64)
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        sl = np.concatenate([[0.0], np.cumsum(seg)])
        dashes = []
        t = gap * 0.5
        while t + length <= sl[-1]:
            t0, t1 = t, t + length
            dashes.append([(float(np.interp(tt, sl, P[:, 0])), float(np.interp(tt, sl, P[:, 1]))) for tt in (t0, (t0 + t1) / 2, t1)])
            t += length + gap
        lw = max(1, int(round(self._px(width))))
        ch = self._mask(lambda d: d.line([(self._px(x), self._px(y)) for x, y in P], fill=255, width=max(1, int(lw * 1.6))))
        self.ink(ch, height=-height * 0.6)
        self.ink(ch, color=(0, 0, 0), alpha=0.18)

        def fn(d):
            for ds in dashes:
                d.line([(self._px(x), self._px(y)) for x, y in ds], fill=255, width=lw, joint="curve")
        m = self._mask(fn, blur=0.35)
        self.ink(m, color=color, height=height * 1.6, spec=thread_spec if color is not None else None,
                 gloss=thread_gloss if color is not None else None)
        return m

    def stitch_rect(self, x, y, w, h, r=0.0, inset=0.0, **kw):
        """Stitched outline of a rounded rectangle (patches, pockets, strap ends)."""
        x, y, w, h = x + inset, y + inset, w - 2 * inset, h - 2 * inset
        r = min(r, w / 2, h / 2)
        pts = []
        if r > 0:
            for cx, cy, a0 in ((x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)):
                for k in range(7):
                    a = np.radians(a0 + 90 * k / 6)
                    pts.append((cx + r * np.cos(a), cy + r * np.sin(a)))
        else:
            pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        return self.stitch(pts, closed=True, **kw)

    def screw(self, cx, cy, r, kind="phillips", color=(150, 154, 160), height=0.0005, spec=0.7, gloss=0.62, metal=1.0,
              recess=(28, 30, 33), washer=False):
        """Pan-head screw seen from the front: domed head + recess (phillips / slot / hex / torx) +
        a soft contact shadow ring. Draws metal ink, raised height and the sunk drive."""
        if washer:
            self.circle(cx, cy, r * 1.45, color=(120, 124, 130), spec=0.6, gloss=0.5, metal=1.0, height=height * 0.25)
        self.circle(cx, cy, r * 1.16, fill=False, width=r * 0.18, color=(0, 0, 0), alpha=0.35, blur=0.6)
        self.circle(cx, cy, r, color=color, spec=spec, gloss=gloss, metal=metal, height=height * 0.45)
        bl = max(0.6, r * self.ppm * 0.18)
        self.circle(cx, cy, r * 0.82, height=height * 0.30, blur=bl)
        self.circle(cx, cy, r * 0.55, height=height * 0.25, blur=bl)
        self.circle(cx - r * 0.25, cy - r * 0.25, r * 0.35, color=(255, 255, 255), alpha=0.18, blur=bl)
        d = height * 1.6
        if kind == "phillips":
            for w_, h_ in ((r * 1.15, r * 0.24), (r * 0.24, r * 1.15)):
                m = self.rect(cx - w_ / 2, cy - h_ / 2, w_, h_, r=min(w_, h_) * 0.3)
                self.ink(m, color=recess, alpha=0.9)
                self.ink(m, height=-d)
        elif kind == "slot":
            m = self.rect(cx - r * 0.65, cy - r * 0.12, r * 1.3, r * 0.24)
            self.ink(m, color=recess, alpha=0.9)
            self.ink(m, height=-d)
        else:
            n = 6 if kind == "hex" else 12
            pts = []
            for k in range(n):
                a = np.radians(30 + 360 * k / n)
                rr = r * (0.48 if (kind == "hex" or k % 2 == 0) else 0.32)
                pts.append((cx + rr * np.cos(a), cy + rr * np.sin(a)))
            m = self.polygon(pts)
            self.ink(m, color=recess, alpha=0.9)
            self.ink(m, height=-d)

    def rivet(self, cx, cy, r, color=(170, 174, 180), height=0.0004, spec=0.7, gloss=0.6):
        self.circle(cx, cy, r * 1.15, fill=False, width=r * 0.16, color=(0, 0, 0), alpha=0.3, blur=0.5)
        self.circle(cx, cy, r, color=color, spec=spec, gloss=gloss, metal=1.0, height=height * 0.5)
        self.circle(cx, cy, r * 0.6, height=height * 0.5, blur=max(0.6, r * self.ppm * 0.2))

    def perforate(self, x, y, cols, rows, pitch, r, depth=0.0008, color=(16, 17, 19), stagger=False):
        """Grid of round holes (speaker grilles, vents): dark, sunk."""
        pts = []
        for j in range(rows):
            for i in range(cols):
                ox = pitch * 0.5 if (stagger and j % 2) else 0.0
                pts.append((x + i * pitch + ox, y + j * pitch))

        def fn(d):
            for px, py in pts:
                d.ellipse([self._px(px - r), self._px(py - r), self._px(px + r), self._px(py + r)], fill=255)
        m = self._mask(fn)
        self.ink(m, color=color, spec=0.05, gloss=0.1)
        self.ink(m, height=-depth)
        return m

    def slots(self, x, y, w, h, n, vertical=False, fill=0.5, depth=0.0008, color=(16, 17, 19)):
        """Row of rounded vent slots inside the box (x, y, w, h)."""
        if not vertical:
            sh = h / n * fill
            for k in range(n):
                yy = y + (k + 0.5) * h / n - sh / 2
                m = self.rect(x, yy, w, sh, r=sh / 2)
                self.ink(m, color=color, spec=0.05, gloss=0.1)
                self.ink(m, height=-depth)
        else:
            sw = w / n * fill
            for k in range(n):
                xx = x + (k + 0.5) * w / n - sw / 2
                m = self.rect(xx, y, sw, h, r=sw / 2)
                self.ink(m, color=color, spec=0.05, gloss=0.1)
                self.ink(m, height=-depth)

    # codes ------------------------------------------------------------------------------
    def barcode(self, x, y, w, h, seed=0, color=(18, 19, 21), digits=None, digit_size=None, quiet=True):
        """Linear barcode (code-128 look) in the box; optional human readable digits underneath."""
        rng = np.random.default_rng(seed)
        bars_h = h * (0.74 if digits else 1.0)
        mod = w / 112.0
        pts = []
        xx = x + (mod * 4 if quiet else 0.0)
        end = x + w - (mod * 4 if quiet else 0.0)
        pts.append((xx, mod * 2))
        xx += mod * 3
        while xx < end - mod * 6:
            bw = mod * int(rng.integers(1, 5))
            pts.append((xx, bw))
            xx += bw + mod * int(rng.integers(1, 4))
        pts.append((end - mod * 4, mod * 2))
        pts.append((end - mod * 1.5, mod))

        def fn(d):
            for bx, bw in pts:
                d.rectangle([self._px(bx), self._px(y), self._px(bx + bw) - 1, self._px(y + bars_h)], fill=255)
        self.ink(self._mask(fn), color=color, spec=0.2, gloss=0.3)
        if digits:
            self.text(x + w / 2, y + h * 0.88, digits, digit_size or h * 0.16, fnt="mono", color=color, max_w=w * 0.96)

    def datamatrix(self, x, y, s, n=14, seed=0, color=(18, 19, 21)):
        """2D data-matrix style code (L finder + clock track + random modules), s = side length."""
        rng = np.random.default_rng(seed + 97)
        c = s / n
        cells = []
        for j in range(n):
            for i in range(n):
                on = False
                if i == 0 or j == n - 1:
                    on = True
                elif j == 0:
                    on = i % 2 == 0
                elif i == n - 1:
                    on = j % 2 == 1
                else:
                    on = rng.random() < 0.48
                if on:
                    cells.append((i, j))

        def fn(d):
            for i, j in cells:
                d.rectangle([self._px(x + i * c), self._px(y + j * c), self._px(x + (i + 1) * c) - 1, self._px(y + (j + 1) * c) - 1], fill=255)
        self.ink(self._mask(fn), color=color, spec=0.2, gloss=0.3)

    # generic medical / regulatory symbols ---------------------------------------------
    def star_of_life(self, cx, cy, s, color=(32, 92, 196), rod=(255, 255, 255), border=None, height=None, **ink):
        """Six-armed star of life with the rod and serpent; s = tip-to-tip height."""
        def bars(half, w, col, **kw):
            m = None
            for a in (90.0, 30.0, -30.0):
                t = np.array([np.cos(np.radians(a)), -np.sin(np.radians(a))])
                n = np.array([-t[1], t[0]])
                c = np.array([cx, cy])
                pts = [tuple(c + t * half + n * w), tuple(c + t * half - n * w), tuple(c - t * half - n * w), tuple(c - t * half + n * w)]
                mm = self._mask(lambda d, pts=pts: d.polygon([(self._px(px), self._px(py)) for px, py in pts], fill=255))
                m = mm if m is None else np.maximum(m, mm)
            return self.ink(m, color=col, height=height, **kw)
        if border is not None:
            bars(s / 2 + s * 0.05, s * 0.15 + s * 0.05, border, **ink)
        bars(s / 2, s * 0.15, color, **ink)
        self.rect(cx - s * 0.022, cy - s * 0.36, s * 0.044, s * 0.70, r=s * 0.01, color=rod, **ink)
        ys = np.linspace(cy + s * 0.27, cy - s * 0.24, 24)
        xs = cx + s * 0.075 * np.sin((ys - ys[0]) / (ys[-1] - ys[0]) * 2.6 * np.pi)
        self.line(list(zip(xs, ys)), s * 0.032, color=rod, **ink)
        self.circle(xs[-1] + s * 0.01, ys[-1] - s * 0.02, s * 0.035, color=rod, **ink)

    def cross(self, cx, cy, s, color=(255, 255, 255), arm=0.34, r=0.12, **ink):
        """Plain (Greek) cross, s = overall size, arm = bar thickness / s."""
        t = s * arm
        m1 = self.rect(cx - t / 2, cy - s / 2, t, s, r=t * r)
        m2 = self.rect(cx - s / 2, cy - t / 2, s, t, r=t * r)
        return self.ink(np.maximum(m1, m2), color=color, **ink)

    def icon(self, kind, x, y, s, color=(24, 26, 28), **ink):
        """Small regulatory / handling symbols in an s x s box at (x, y) top-left:
        book (consult instructions), factory (manufacturer), date (date of manufacture), bin (WEEE),
        bf (type BF applied part), cf (type CF), warn (caution triangle), noreuse (single use),
        drop (keep dry), temp (temperature limit), latex (latex free), rx (Rx only), ip (IP rating)."""
        lw = s * 0.08
        cx, cy = x + s / 2, y + s / 2
        if kind == "book":
            self.polygon([(x + s * 0.05, y + s * 0.18), (cx, y + s * 0.28), (x + s * 0.95, y + s * 0.18), (x + s * 0.95, y + s * 0.85),
                          (cx, y + s * 0.95), (x + s * 0.05, y + s * 0.85)], color=color, **ink)
            self.line([(cx, y + s * 0.30), (cx, y + s * 0.92)], lw * 0.6, color=(255, 255, 255), **ink)
            self.circle(x + s * 0.72, y + s * 0.38, s * 0.05, color=(255, 255, 255), **ink)
            self.line([(x + s * 0.72, y + s * 0.5), (x + s * 0.72, y + s * 0.74)], lw * 0.8, color=(255, 255, 255), **ink)
        elif kind in ("factory", "date"):
            pts = [(x + s * 0.05, y + s * 0.95), (x + s * 0.05, y + s * 0.45), (x + s * 0.30, y + s * 0.60), (x + s * 0.30, y + s * 0.45),
                   (x + s * 0.55, y + s * 0.60), (x + s * 0.55, y + s * 0.45), (x + s * 0.72, y + s * 0.55), (x + s * 0.72, y + s * 0.08),
                   (x + s * 0.88, y + s * 0.08), (x + s * 0.88, y + s * 0.62), (x + s * 0.95, y + s * 0.62), (x + s * 0.95, y + s * 0.95)]
            if kind == "factory":
                self.polygon(pts, color=color, **ink)
            else:
                self.line(pts + [pts[0]], lw, color=color, **ink)
        elif kind == "bin":
            self.polygon([(x + s * 0.22, y + s * 0.22), (x + s * 0.78, y + s * 0.22), (x + s * 0.72, y + s * 0.80), (x + s * 0.28, y + s * 0.80)],
                         color=color, **ink)
            self.polygon([(x + s * 0.28, y + s * 0.28), (x + s * 0.72, y + s * 0.28), (x + s * 0.67, y + s * 0.74), (x + s * 0.33, y + s * 0.74)],
                         color=(255, 255, 255), **ink)
            self.rect(x + s * 0.15, y + s * 0.13, s * 0.7, lw, color=color, **ink)
            self.line([(x + s * 0.1, y + s * 0.08), (x + s * 0.9, y + s * 0.84)], lw, color=color, **ink)
            self.line([(x + s * 0.9, y + s * 0.08), (x + s * 0.1, y + s * 0.84)], lw, color=color, **ink)
            self.rect(x + s * 0.1, y + s * 0.88, s * 0.8, lw * 1.3, color=color, **ink)
        elif kind in ("bf", "cf"):
            self.rect(x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.84, fill=False, width=lw, color=color, **ink)
            if kind == "bf":
                self.circle(cx, y + s * 0.27, s * 0.09, color=color, **ink)
                self.line([(cx, y + s * 0.38), (cx, y + s * 0.62)], lw * 1.4, color=color, **ink)
                self.line([(x + s * 0.28, y + s * 0.44), (x + s * 0.72, y + s * 0.44)], lw, color=color, **ink)
                self.line([(cx, y + s * 0.6), (x + s * 0.34, y + s * 0.82)], lw, color=color, **ink)
                self.line([(cx, y + s * 0.6), (x + s * 0.66, y + s * 0.82)], lw, color=color, **ink)
            else:
                self.circle(x + s * 0.38, y + s * 0.42, s * 0.15, color=color, **ink)
                self.circle(x + s * 0.62, y + s * 0.42, s * 0.15, color=color, **ink)
                self.polygon([(x + s * 0.24, y + s * 0.48), (x + s * 0.76, y + s * 0.48), (cx, y + s * 0.8)], color=color, **ink)
        elif kind == "warn":
            self.polygon([(cx, y + s * 0.04), (x + s * 0.98, y + s * 0.94), (x + s * 0.02, y + s * 0.94)], color=color, **ink)
            self.polygon([(cx, y + s * 0.22), (x + s * 0.83, y + s * 0.86), (x + s * 0.17, y + s * 0.86)], color=(240, 196, 30), **ink)
            self.rect(cx - lw * 0.6, y + s * 0.38, lw * 1.2, s * 0.28, r=lw * 0.3, color=color, **ink)
            self.circle(cx, y + s * 0.76, lw * 0.75, color=color, **ink)
        elif kind == "noreuse":
            self.circle(cx, cy, s * 0.44, fill=False, width=lw, color=color, **ink)
            self.text(cx, cy + s * 0.03, "2", s * 0.5, fnt="label", color=color, **ink)
            self.line([(x + s * 0.18, y + s * 0.82), (x + s * 0.82, y + s * 0.18)], lw, color=color, **ink)
        elif kind == "drop":
            self.polygon([(x + s * 0.08, y + s * 0.5), (x + s * 0.2, y + s * 0.25), (cx, y + s * 0.12), (x + s * 0.8, y + s * 0.25),
                          (x + s * 0.92, y + s * 0.5)], color=color, **ink)
            self.line([(cx, y + s * 0.5), (cx, y + s * 0.82), (x + s * 0.38, y + s * 0.86)], lw, color=color, **ink)
            for k in range(3):
                self.circle(x + s * (0.2 + 0.3 * k), y + s * 0.04, s * 0.04, color=color, **ink)
        elif kind == "temp":
            self.line([(x + s * 0.2, y + s * 0.1), (x + s * 0.2, y + s * 0.9), (x + s * 0.8, y + s * 0.9), (x + s * 0.8, y + s * 0.1)], lw,
                      color=color, **ink)
            self.rect(cx - lw / 2, y + s * 0.3, lw, s * 0.45, color=color, **ink)
            self.circle(cx, y + s * 0.75, s * 0.09, color=color, **ink)
        elif kind == "latex":
            self.circle(cx, cy, s * 0.44, fill=False, width=lw, color=color, **ink)
            self.text(cx, cy + s * 0.02, "LATEX", s * 0.2, fnt="label", color=color, max_w=s * 0.7, **ink)
            self.line([(x + s * 0.18, y + s * 0.82), (x + s * 0.82, y + s * 0.18)], lw, color=color, **ink)
        elif kind == "rx":
            self.text(cx, cy, "Rx", s * 0.5, fnt="label", color=color, **ink)
        elif kind == "ip":
            self.text(cx, cy, "IP54", s * 0.34, fnt="label", color=color, max_w=s * 0.96, **ink)

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
    """Dark bedside-monitor UI (ECG / SpO2 / NIBP / RR)."""
    img = Image.new("RGB", (w, h), (6, 8, 10))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    # header bar: bed / patient category on the left, alarm state + battery + clock on the right
    d.rectangle([0, 0, w, int(22 * s)], fill=(14, 17, 20))
    d.text((int(8 * s), int(11 * s)), "BED 01   ADULT", font=font("label-semi", 10.5 * s), fill=(200, 206, 210), anchor="lm")
    d.rectangle([int(120 * s), int(5 * s), int(176 * s), int(17 * s)], fill=(40, 30, 8))
    d.text((int(148 * s), int(11 * s)), "ALARMS ON", font=font("mono", 8 * s), fill=AMBER, anchor="mm")
    bx = w - int(70 * s)
    d.rectangle([bx, int(7 * s), bx + int(18 * s), int(15 * s)], outline=(150, 156, 160), width=max(1, int(s)))
    d.rectangle([bx + int(2 * s), int(9 * s), bx + int(13 * s), int(13 * s)], fill=(60, 230, 120))
    d.text((w - int(8 * s), int(11 * s)), "12:04", font=font("mono", 10 * s), fill=(140, 148, 152), anchor="rm")
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
        d.text((x1 + int(10 * s), y0 + int(8 * s)), vlab, font=font("label-semi", 10 * s), fill=col, anchor="lt")
        big = 34 if len(val) <= 3 else 24
        d.text((w - int(14 * s), y0 + rh * 0.62), val, font=font("label", big * s), fill=col, anchor="rm")
        d.text((x1 + int(10 * s), y0 + rh - int(10 * s)), unit, font=font("mono", 9 * s), fill=(120, 126, 130), anchor="lb")
    return img


def draw_defib_ui(w=512, h=256):
    img = Image.new("RGB", (w, h), (6, 8, 10))
    d = ImageDraw.Draw(img)
    s = w / 512.0
    d.rectangle([0, 0, w, int(24 * s)], fill=(14, 17, 20))
    d.text((int(10 * s), int(12 * s)), "PADS", font=font("label-semi", 12 * s), fill=(200, 206, 210), anchor="lm")
    d.text((w // 2, int(12 * s)), "MANUAL  DEFIB", font=font("label", 12 * s), fill=AMBER, anchor="mm")
    d.text((w - int(10 * s), int(12 * s)), "00:42", font=font("mono", 11 * s), fill=(160, 166, 170), anchor="rm")
    tw = int(330 * s)
    for gy in range(int(30 * s), h - int(6 * s), int(12 * s)):
        d.line([(0, gy), (tw, gy)], fill=(12, 18, 18), width=1)
    _trace(d, int(6 * s), int(40 * s), tw - int(12 * s), int(120 * s), _ecg_wave, 4.2, (60, 230, 120), max(2, int(2.6 * s)))
    d.text((int(8 * s), int(32 * s)), "II  x1.0", font=font("mono", 10 * s), fill=(60, 230, 120), anchor="lt")
    _trace(d, int(6 * s), int(170 * s), tw - int(12 * s), int(70 * s), _pleth_wave, 4.2, (40, 210, 230), max(2, int(2.2 * s)))
    x1 = tw + int(8 * s)
    d.rectangle([x1, int(32 * s), w - int(8 * s), int(128 * s)], fill=(12, 15, 18))
    d.text((x1 + int(8 * s), int(40 * s)), "HR", font=font("label-semi", 11 * s), fill=(60, 230, 120), anchor="lt")
    d.text((w - int(14 * s), int(92 * s)), "84", font=font("label", 44 * s), fill=(60, 230, 120), anchor="rm")
    d.rectangle([x1, int(136 * s), w - int(8 * s), int(248 * s)], fill=(30, 14, 10))
    d.text((x1 + int(8 * s), int(144 * s)), "ENERGY", font=font("label-semi", 11 * s), fill=ORANGE, anchor="lt")
    d.text((w - int(14 * s), int(196 * s)), "200J", font=font("label", 36 * s), fill=ORANGE, anchor="rm")
    d.text((x1 + int(8 * s), int(238 * s)), "CHARGE TO ARM", font=font("mono", 9 * s), fill=(200, 140, 90), anchor="lb")
    return img


def draw_pager_lcd(w=256, h=128):
    bg = (126, 156, 92)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    s = h / 128.0
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
