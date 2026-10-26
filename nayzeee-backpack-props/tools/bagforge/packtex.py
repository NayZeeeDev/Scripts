"""
Backpack atlas. A backpack shows art on its front, so unlike the handbag
atlas every face gets its own area (no mirrored copy on the back):

    FRONT   0..512 x 0..736    front face + front pocket, 1600 px/m
    BACK    512..768 x 0..368  back face, 800 px/m
    BAND0/1 0..768 x 740..1016 the two sides (+X then -X), 950 px/m
    PBAND   pocket sides       SOLID  back panel (air mesh)   PATCH  label
    768..1024                  trim + metal strips (shared with textures.py)

Styles (all original): graffiti scribble print with a marker tag, split
check, dipped gloss paint with drips, tone-on-tone NZ monogram.
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import mesh as M
import textures as T

S = 1024
W, H, D = 0.30, 0.44, 0.13          # body, metres
RT, RB = 0.12, 0.045                # top / bottom corner radius
SWELL = 0.06
FW, FH = 0.32, 0.46                 # front frame, centred on the section
POCKET = (0.24, 0.17, 0.045, -0.11)  # w, h, depth, centre height on the section
SS = 2                              # supersampling for the ink

#        x0   y0   w    h    px/m
FRONT = (0, 0, 512, 736, 1600)
BACK = (512, 0, 256, 368, 800)
BAND = [(0, 740, 768, 136, 950), (0, 880, 768, 136, 950)]
PBAND = (512, 372, 256, 20, 360)
SOLID = (512, 396, 256, 240, 650)
PATCH = (512, 640, 256, 96, 3200)


def section():
    return M.arch_rect(W, H, RT, RB, n=120)


# ---- uv maps (used by designs.backpack) -----------------------------------------

def front_uv(dz=0.0):
    x0, y0, w, h, ppm = FRONT
    return lambda x, z: ((x0 + (x + FW / 2) * ppm) / S, (y0 + (FH / 2 - (z + dz)) * ppm) / S)


def back_uv():
    x0, y0, w, h, ppm = BACK
    return lambda x, z: ((x0 + (FW / 2 - x) * ppm) / S, (y0 + (FH / 2 - z) * ppm) / S)


def band_uv():
    def f(half, s, d):
        x0, y0, w, h, ppm = BAND[half]
        return (x0 + s * ppm) / S, (y0 + d * ppm) / S
    return f


def area_uv(area, sx=None, sz=None):
    """Planar, centred in `area`; sx/sz squeeze a face bigger than it."""
    x0, y0, w, h, ppm = area
    kx, kz = sx or ppm, sz or ppm
    return lambda x, z: ((x0 + w / 2 + x * kx) / S, (y0 + h / 2 - z * kz) / S)


def strip_uv(area, half_len, depth):
    """A small shell's sides laid end to end along `area`."""
    x0, y0, w, h, ppm = area
    ku = min(ppm, (w - 2) / (2 * half_len)); kv = min(ppm, (h - 2) / depth)
    return lambda half, s, d: ((x0 + 1 + (s + half * half_len) * ku) / S, (y0 + 1 + d * kv) / S)


def band_height():
    """s along a side band -> height on the section, for paint that follows height."""
    sec, arc, h = M.shell_frame(section())
    arc = np.array(arc); ys = np.array([p[1] for p in sec] + [sec[0][1]])

    def f(half, s):
        a = s + (arc[h] if half else 0.0)
        return np.interp(a, arc, ys) * (1 + SWELL)
    return f


# ---- hand lettering --------------------------------------------------------------

def _arc(cx, cy, rx, ry, a0, a1, n=10):
    return [(cx + rx * math.cos(math.radians(a)), cy - ry * math.sin(math.radians(a))) for a in np.linspace(a0, a1, n)]


GLYPHS = {   # single-stroke skeletons in a unit box, y down
    'A': [[(0, 1), (0.5, 0), (1, 1)], [(0.24, 0.6), (0.76, 0.6)]],
    'B': [[(0, 1), (0, 0)] + _arc(0.45, 0.25, 0.45, 0.25, 90, -90) + _arc(0.5, 0.75, 0.5, 0.25, 90, -90) + [(0, 1)]],
    'C': [_arc(0.55, 0.5, 0.5, 0.5, 50, 310)],
    'D': [[(0, 0), (0, 1)] + _arc(0.35, 0.5, 0.6, 0.5, -90, 90) + [(0, 0)]],
    'E': [[(1, 0), (0, 0), (0, 1), (1, 1)], [(0, 0.5), (0.75, 0.5)]],
    'F': [[(1, 0), (0, 0), (0, 1)], [(0, 0.5), (0.7, 0.5)]],
    'G': [_arc(0.55, 0.5, 0.5, 0.5, 50, 330) + [(1, 0.55), (0.6, 0.55)]],
    'H': [[(0, 0), (0, 1)], [(1, 0), (1, 1)], [(0, 0.5), (1, 0.5)]],
    'I': [[(0.5, 0), (0.5, 1)]],
    'K': [[(0, 0), (0, 1)], [(1, 0), (0.05, 0.6)], [(0.35, 0.4), (1, 1)]],
    'L': [[(0, 0), (0, 1), (0.9, 1)]],
    'M': [[(0, 1), (0.05, 0), (0.5, 0.65), (0.95, 0), (1, 1)]],
    'N': [[(0, 1), (0, 0), (1, 1), (1, 0)]],
    'O': [_arc(0.5, 0.5, 0.5, 0.5, 0, 360, 16)],
    'P': [[(0, 1), (0, 0)] + _arc(0.45, 0.27, 0.5, 0.27, 90, -90) + [(0, 0.54)]],
    'R': [[(0, 1), (0, 0)] + _arc(0.45, 0.27, 0.5, 0.27, 90, -90) + [(0, 0.54), (0.95, 1)]],
    'S': [_arc(0.5, 0.25, 0.48, 0.25, 30, 270) + _arc(0.5, 0.75, 0.48, 0.25, 90, -150)],
    'T': [[(0, 0), (1, 0)], [(0.5, 0), (0.5, 1)]],
    'U': [[(0, 0), (0, 0.6)] + _arc(0.5, 0.6, 0.5, 0.4, 180, 360) + [(1, 0)]],
    'V': [[(0, 0), (0.5, 1), (1, 0)]],
    'W': [[(0, 0), (0.22, 1), (0.5, 0.35), (0.78, 1), (1, 0)]],
    'Y': [[(0, 0), (0.5, 0.5), (1, 0)], [(0.5, 0.5), (0.5, 1)]],
    'Z': [[(0, 0), (1, 0), (0, 1), (1, 1)]],
}
SCRIBBLE = 'NAYZEEKMRSWTOCDGHUVBLP'


def chaikin(pts, n=2):
    for _ in range(n):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            out += [(0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]), (0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1])]
        pts = out + [pts[-1]]
    return pts


def word(text, x, y, size, rng, slant=0.25, jitter=0.03, advance=0.78, rot=0.0, width=0.62, vary=0.1, smooth=0):
    """Polylines (px) for `text` written from (x, y) = left baseline."""
    lines = []
    c, s = math.cos(rot), math.sin(rot)
    pen = 0.0
    for ch in text:
        if ch == ' ':
            pen += advance * size * 0.7
            continue
        g = GLYPHS.get(ch)
        if not g:
            continue
        sc = size * (1 + rng.uniform(-vary, vary))
        for stroke in g:
            pts = []
            for gx, gy in stroke:
                lx = pen + gx * width * sc + (1 - gy) * slant * sc + rng.normal(0, jitter * sc)
                ly = -(1 - gy) * sc + rng.normal(0, jitter * sc)
                pts.append((x + lx * c - ly * s, y + lx * s + ly * c))
            lines.append(chaikin(pts, smooth) if smooth else pts)
        pen += advance * size
    return lines


def ink(draw, lines, width, fill, rng, taper=True):
    """Marker strokes: rounded joins, slightly uneven pressure."""
    for pts in lines:
        if len(pts) < 2:
            continue
        for a, b in zip(pts, pts[1:]):
            w = max(1, int(width * (rng.uniform(0.8, 1.1) if taper else 1)))
            draw.line([a, b], fill=fill, width=w)
            r = w / 2
            draw.ellipse([b[0] - r, b[1] - r, b[0] + r, b[1] + r], fill=fill)
        r = width / 2
        draw.ellipse([pts[0][0] - r, pts[0][1] - r, pts[0][0] + r, pts[0][1] + r], fill=fill)


# ---- areas -------------------------------------------------------------------------

class Area:
    """One atlas area being painted: colour, height, shine, gloss, plus a
    supersampled RGBA ink layer and its height layer."""

    def __init__(self, rect, kind, base, rng, grain=0.8, material='leather'):
        self.x0, self.y0, self.w, self.h, self.ppm = rect
        self.kind = kind
        if material == 'saffiano':
            yy, xx = np.mgrid[0:self.h, 0:self.w].astype(float)
            p = self.ppm * 0.0016
            hh = (np.abs(np.sin((xx + yy) / p)) * np.abs(np.sin((xx - yy) / p))) ** 0.5 * 0.5
            hh += T.value_noise(self.w, self.h, 30, rng, 2) * 0.2
            self.col = np.clip(base[None, None, :] * (0.9 + 0.15 * hh[..., None]), 0, 255)
        elif material == 'weave':
            yy, xx = np.mgrid[0:self.h, 0:self.w].astype(float)
            p = max(1.2, self.ppm * 0.0012)
            hh = 0.25 * (np.sin(xx / p) * np.sin(yy / p) > 0) + T.value_noise(self.w, self.h, 20, rng, 2) * 0.15
            self.col = np.clip(base[None, None, :] * (0.92 + 0.12 * hh[..., None]), 0, 255)
        else:
            self.col, hh = T.leather(self.w, self.h, base, rng, grain=grain, ppm=self.ppm)
        self.hgt = hh
        self.shine = np.full((self.h, self.w), 0.3); self.gloss = np.full((self.h, self.w), 0.4)
        self.inkimg = Image.new('RGBA', (self.w * SS, self.h * SS), (0, 0, 0, 0))
        self.himg = Image.new('L', (self.w * SS, self.h * SS), 0)
        self.d = ImageDraw.Draw(self.inkimg); self.hd = ImageDraw.Draw(self.himg)

    def m(self, metres):                   # metres -> supersampled px
        return metres * self.ppm * SS

    def world(self, x, z):                 # front/back face metres -> supersampled px
        if self.kind == 'back':
            return ((FW / 2 - x) * self.ppm * SS, (FH / 2 - z) * self.ppm * SS)
        return ((x + FW / 2) * self.ppm * SS, (FH / 2 - z) * self.ppm * SS)

    def grid(self):
        """Per-pixel coords: (x, z) on faces, (s, d) on bands (metres)."""
        yy, xx = np.mgrid[0:self.h, 0:self.w].astype(float)
        u, v = (xx + 0.5) / self.ppm, (yy + 0.5) / self.ppm
        if self.kind == 'front':
            return u - FW / 2, FH / 2 - v
        if self.kind == 'back':
            return FW / 2 - u, FH / 2 - v
        return u, v

    def finish(self, relief=0.8):
        a = self.inkimg.resize((self.w, self.h), Image.LANCZOS)
        a = np.asarray(a, float)
        al = a[..., 3:4] / 255
        self.col = self.col * (1 - al) + a[..., :3] * al * (0.94 + 0.06 * (self.hgt[..., None] / max(self.hgt.max(), 1e-6)))
        hh = np.asarray(self.himg.resize((self.w, self.h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8)), float) / 255
        self.hgt = self.hgt * (1 - 0.6 * hh) + hh * relief * 2.0


def scatter_scribbles(ar, rng, inks, per_m2=260, big=False):
    area_m2 = (ar.w / ar.ppm) * (ar.h / ar.ppm)
    for _ in range(int(per_m2 * area_m2) + 1):
        size = ar.m(rng.uniform(0.014, 0.05))
        n = int(rng.integers(3, 8))
        text = ''.join(rng.choice(list(SCRIBBLE), n))
        x = rng.uniform(-0.1, 1.0) * ar.w * SS; y = rng.uniform(0, 1.1) * ar.h * SS
        rot = rng.normal(0, 0.35)
        lines = word(text, x, y, size, rng, slant=rng.uniform(0.0, 0.5), jitter=0.05, advance=rng.uniform(0.42, 0.62), rot=rot, smooth=2)
        c = inks[int(rng.integers(len(inks)))]
        alpha = int(rng.uniform(110, 230))
        ink(ar.d, lines, max(2, size * rng.uniform(0.04, 0.07)), c + (alpha,), rng)
    # scrawled loops and hatching
    for _ in range(int(per_m2 * area_m2 * 0.6) + 1):
        cx, cy = rng.uniform(0, ar.w * SS), rng.uniform(0, ar.h * SS)
        r = ar.m(rng.uniform(0.01, 0.04)); n = int(rng.integers(8, 22)); a0 = rng.uniform(0, 6.3)
        pts = [(cx + t * r * 0.25 + r * math.cos(a0 + t * 2.6) * rng.uniform(0.6, 1.0),
                cy + r * 0.5 * math.sin(a0 + t * 2.6) * rng.uniform(0.6, 1.0)) for t in range(n)]
        c = inks[int(rng.integers(len(inks)))]
        ink(ar.d, [pts], max(2, ar.m(0.0018)), c + (int(rng.uniform(90, 200)),), rng)


# ---- styles --------------------------------------------------------------------------

def style_graffiti(ar, spec, rng):
    inks = [tuple(int(v) for v in T.hexrgb(c)) for c in spec['inks']]
    scatter_scribbles(ar, rng, inks)
    if ar.kind == 'front':
        tag = tuple(int(v) for v in T.hexrgb(spec['tag']))
        trng = np.random.default_rng(7)          # same tag on every colour (shared relief)
        x, y = ar.world(-0.13, 0.03)
        lines = word('NAYZEEE', x, y, ar.m(0.055), trng, slant=0.18, jitter=0.025, advance=0.66, rot=-0.06, width=0.6)
        ink(ar.d, lines, ar.m(0.0075), tag + (255,), trng, taper=False)
        ink(ar.hd, lines, ar.m(0.0075), 255, trng, taper=False)
        for k in range(6):                       # a few drips off the tag
            p = lines[int(trng.integers(len(lines)))][-1]
            ln = ar.m(trng.uniform(0.006, 0.022)); r = ar.m(0.0018)
            ar.d.line([p, (p[0], p[1] + ln)], fill=tag + (255,), width=int(r * 1.4))
            ar.d.ellipse([p[0] - r, p[1] + ln - r, p[0] + r, p[1] + ln + r], fill=tag + (255,))
        # pocket slogan, small
        for i, line in enumerate(('NO DAYS OFF', 'STAY TEN TOES', 'BUILT NOT BOUGHT')):
            x, y = ar.world(-0.105 + 0.012 * i, -0.075 - 0.028 * i)
            lines = word(line, x, y, ar.m(0.017), trng, slant=0.2, jitter=0.04, advance=0.72, rot=-0.03)
            ink(ar.d, lines, ar.m(0.0022), tag + (240,), trng)
            ink(ar.hd, lines, ar.m(0.0022), 160, trng)
    ar.shine[:] = 0.28; ar.gloss[:] = 0.4


def style_check(ar, spec, rng):
    dark = [T.hexrgb(c) for c in spec['dark']]; light = [T.hexrgb(c) for c in spec['light']]
    a, b = ar.grid()
    sq = 0.024
    ch = ((np.floor(a / sq) + np.floor(b / sq)) % 2).astype(int)
    if ar.kind in ('front', 'back'):
        x, z = a, b
        edge = 0.012 + 0.004 * np.sin(z * 37) + 0.002 * np.sin(z * 113)
        side = x > edge                    # same world side front and back
    elif ar.kind == 'band0':
        side = np.ones_like(a, bool)
    else:
        side = np.zeros_like(a, bool) if ar.kind != 'pband' else (a < (ar.w / ar.ppm) / 2)
    pal = np.where(side[..., None], np.where(ch[..., None] == 1, light[0], light[1]), np.where(ch[..., None] == 1, dark[0], dark[1]))
    grain = ar.hgt / max(ar.hgt.max(), 1e-6)
    ar.col = np.clip(pal * (0.94 + 0.1 * grain[..., None]), 0, 255)
    ar.shine[:] = 0.35; ar.gloss[:] = 0.45


def style_mono(ar, spec, rng):
    base = T.hexrgb(spec['colour']); motif = T.hexrgb(spec['motif'])
    tile = ar.m(0.042)
    c = tuple(int(v) for v in motif)
    rows = int(ar.h * SS / tile) + 3; cols = int(ar.w * SS / tile) + 3
    lrng = np.random.default_rng(3)
    for j in range(-1, rows):
        for i in range(-1, cols):
            cx = (i + 0.5 * (j % 2)) * tile; cy = j * tile * 0.86
            r = tile * 0.36
            ar.d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c + (255,), width=max(2, int(tile * 0.05)))
            ar.hd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=200, width=max(2, int(tile * 0.05)))
            g = r * 0.62   # N, and the same N turned a quarter: a Z
            n = [(cx - g, cy + g), (cx - g, cy - g), (cx + g, cy + g), (cx + g, cy - g)]
            z = [(cx - g, cy - g), (cx + g, cy - g), (cx - g, cy + g), (cx + g, cy + g)]
            for pts, alpha in ((n, 255), (z, 170)):
                ink(ar.d, [pts], max(2, tile * 0.055), c + (alpha,), lrng, taper=False)
                ink(ar.hd, [pts], max(2, tile * 0.055), 255, lrng, taper=False)
            d = tile * 0.06; dx, dy = cx + tile * 0.5, cy + tile * 0.43
            ar.d.polygon([(dx, dy - d), (dx + d, dy), (dx, dy + d), (dx - d, dy)], fill=c + (200,))
    ar.shine[:] = 0.18; ar.gloss[:] = 0.3


def style_drip(ar, spec, rng, heights):
    paint = T.hexrgb(spec['paint'])
    a, b = ar.grid()
    drng = np.random.default_rng({'front': 11, 'back': 12, 'band0': 13, 'band1': 14}.get(ar.kind, 15))
    if ar.kind in ('front', 'back'):
        x, z = a, b
    elif ar.kind in ('band0', 'band1'):
        half = 0 if ar.kind == 'band0' else 1
        x, z = b, heights(half, a)         # drips sit across the depth, run down the side
    else:
        return
    zline = 0.075 + 0.006 * np.sin(x * 47 + drng.uniform(0, 6)) + 0.003 * np.sin(x * 131)
    drop = np.zeros_like(x)
    xs = np.linspace(x.min(), x.max(), 200)
    for _ in range(int((x.max() - x.min()) / 0.03) + 2):
        xc = drng.uniform(x.min(), x.max()); wd = drng.uniform(0.008, 0.02); ln = drng.uniform(0.02, 0.13)
        t = np.clip(1 - ((x - xc) / (wd / 2)) ** 2, 0, None)
        drop = np.maximum(drop, ln * t ** 0.35)
    mask = (z > zline - drop).astype(float)
    if ar.kind in ('band0', 'band1'):
        mask = np.maximum(mask, 0) * 1.0
    soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(ar.ppm * 0.0012)), float) / 255
    ar.col = ar.col * (1 - mask[..., None]) + paint * (0.9 + 0.12 * soft[..., None]) * mask[..., None]
    ar.hgt = ar.hgt * (1 - mask) * 0.6 + soft ** 0.6 * 1.6
    ar.shine = 0.12 + 0.85 * mask; ar.gloss = 0.22 + 0.73 * mask


# ---- atlas -----------------------------------------------------------------------------

def pack_atlas(spec, seed=1):
    rng = np.random.default_rng(seed)
    dif = np.zeros((S, S, 3)); hgt = np.zeros((S, S)); shine = np.zeros((S, S)); gloss = np.zeros((S, S))
    style = spec['style']
    base = T.hexrgb(spec.get('colour', '#151515'))
    material = {'drip': 'saffiano', 'mono': 'weave'}.get(style, 'leather')
    heights = band_height()
    areas = [(FRONT, 'front'), (BACK, 'back'), (BAND[0], 'band0'), (BAND[1], 'band1'), (PBAND, 'pband')]
    for rect, kind in areas:
        ar = Area(rect, kind, base, rng, material=material)
        if style == 'graffiti':
            style_graffiti(ar, spec, rng)
        elif style == 'check':
            style_check(ar, spec, rng)
        elif style == 'mono':
            style_mono(ar, spec, rng)
        elif style == 'drip':
            style_drip(ar, spec, rng, heights)
        ar.finish()
        x0, y0 = ar.x0, ar.y0
        dif[y0:y0 + ar.h, x0:x0 + ar.w] = ar.col; hgt[y0:y0 + ar.h, x0:x0 + ar.w] = ar.hgt
        shine[y0:y0 + ar.h, x0:x0 + ar.w] = ar.shine; gloss[y0:y0 + ar.h, x0:x0 + ar.w] = ar.gloss

    # back panel: perforated air mesh in the trim colour
    x0, y0, w, h, ppm = SOLID
    mesh_col = T.hexrgb(spec.get('panel', '#161616'))
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    p = ppm * 0.006
    holes = (((xx % p) - p / 2) ** 2 + (((yy + (np.floor(xx / p) % 2) * p / 2) % p) - p / 2) ** 2) < (p * 0.22) ** 2
    hh = 0.8 - holes * 0.8 + T.value_noise(w, h, 6, rng, 2) * 0.2
    dif[y0:y0 + h, x0:x0 + w] = mesh_col * (0.75 + 0.3 * hh[..., None]); hgt[y0:y0 + h, x0:x0 + w] = hh
    shine[y0:y0 + h, x0:x0 + w] = 0.1; gloss[y0:y0 + h, x0:x0 + w] = 0.2

    # label patch: rubber with the name raised
    x0, y0, w, h, ppm = PATCH
    img = Image.new('RGB', (w * SS, h * SS), (24, 24, 26)); hi = Image.new('L', (w * SS, h * SS), 60)
    dr, hd = ImageDraw.Draw(img), ImageDraw.Draw(hi)
    pr = np.random.default_rng(5)
    acc = tuple(int(v) for v in T.hexrgb(spec.get('accent', '#08afa2')))
    m = ppm * SS
    lines = word('NAYZEEE', w * SS / 2 - 0.029 * m, h * SS / 2 + 0.0055 * m, 0.011 * m, pr, slant=0.0, jitter=0.0, advance=0.86, width=0.62, vary=0)
    ink(dr, lines, 0.0018 * m, acc, pr, taper=False); ink(hd, lines, 0.0018 * m, 255, pr, taper=False)
    dr.rounded_rectangle([0.0045 * m, 0.0045 * m, w * SS - 0.0045 * m, h * SS - 0.0045 * m], radius=0.003 * m, outline=acc, width=int(0.0007 * m))
    dif[y0:y0 + h, x0:x0 + w] = np.asarray(img.resize((w, h), Image.LANCZOS), float)
    hgt[y0:y0 + h, x0:x0 + w] = np.asarray(hi.resize((w, h), Image.LANCZOS), float) / 255 * 2
    shine[y0:y0 + h, x0:x0 + w] = 0.25; gloss[y0:y0 + h, x0:x0 + w] = 0.35

    T.trim_metal(dif, hgt, shine, gloss, spec, rng)
    diffuse = Image.fromarray(np.clip(dif, 0, 255).astype(np.uint8)).convert('RGBA')
    normal = Image.fromarray(T.normal_from_height(hgt, 1.6))
    specular = Image.fromarray((np.dstack([shine, shine, shine, gloss]) * 255).astype(np.uint8), 'RGBA')
    return diffuse, normal, specular
