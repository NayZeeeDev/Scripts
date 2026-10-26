"""
Texture atlases for bagforge. Every bag uses one 1024 atlas:

    u 0.000 - 0.750  body   (material / print, at real-world scale)
    u 0.750 - 0.875  trim   (handles, piping, tabs: leather)
    u 0.875 - 1.000  metal  (zips, rings, feet, charms)

and three maps of it: diffuse (colour), normal (surface relief) and
spec (R/G/B = shine strength, A = glossiness).
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
BODY = (0.0, 0.0, 0.75, 1.0)
TRIM = (0.75, 0.0, 0.875, 1.0)
METAL = (0.875, 0.0, 1.0, 1.0)


def px(region):
    u0, v0, u1, v1 = region
    return int(u0 * S), int(v0 * S), int(u1 * S), int(v1 * S)


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


# ---- noise ------------------------------------------------------------------

def value_noise(w, h, cell, rng, octaves=4):
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cw, ch = max(2, int(w / cell) + 2), max(2, int(h / cell) + 2)
        g = Image.fromarray((rng.random((ch, cw)) * 255).astype(np.uint8))
        out += np.asarray(g.resize((w, h), Image.BICUBIC), float) / 255 * amp
        total += amp; amp *= 0.5; cell = max(1.0, cell / 2)
    return out / total


def normal_from_height(hgt, strength):
    dy, dx = np.gradient(hgt)
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(hgt)])  # DirectX green
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


# ---- body materials -----------------------------------------------------------

def leather(w, h, base, rng, grain=1.0, ppm=1300):
    hgt = value_noise(w, h, max(2, ppm * 0.0015), rng, 3) * 0.6 + value_noise(w, h, ppm * 0.02, rng, 2) * 0.4
    col = base[None, None, :] * (0.93 + 0.12 * (hgt[..., None] - 0.5))
    return np.clip(col, 0, 255), hgt * grain


def croc(w, h, base, rng, ppm=1300):
    # rectangular scales in staggered rows, uneven widths, narrow dark grooves
    sx, sy = ppm * 0.024, ppm * 0.017
    gx, gy = int(w / sx) + 4, int(h / sy) + 4
    pts = np.zeros((gy, gx, 2))
    for j in range(gy):           # one spare cell all round so edges have neighbours
        off = rng.uniform(0, 1)   # each row shifted its own amount, not brickwork
        for i in range(gx):
            pts[j, i] = ((i - 1 + 0.5 + off + rng.uniform(-0.3, 0.3)) * sx, (j - 1 + 0.5 + rng.uniform(-0.1, 0.1)) * sy)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    ci, cj = (xx / sx).astype(int) + 1, (yy / sy).astype(int) + 1
    d1 = np.full((h, w), 1e9); d2 = np.full((h, w), 1e9)
    for dj in (-1, 0, 1):
        for di in (-2, -1, 0, 1, 2):
            jj = np.clip(cj + dj, 0, gy - 1); ii = np.clip(ci + di, 0, gx - 1)
            p = pts[jj, ii]
            ax, ay = np.abs(xx - p[..., 0]) / sx, np.abs(yy - p[..., 1]) / sy
            d = 0.8 * np.maximum(ax, ay) + 0.2 * np.hypot(ax, ay)
            nd2 = np.where(d < d1, d1, np.minimum(d2, d))
            d1 = np.minimum(d1, d); d2 = nd2
    edge = np.clip((d2 - d1) * 9.0, 0, 1)          # 0 in the grooves
    dome = np.clip(1 - d1 * 0.6, 0, 1)             # each scale slightly domed
    hgt = edge ** 0.5 * (0.7 + 0.3 * dome)
    tone = 0.92 + 0.12 * value_noise(w, h, sx * 1.5, rng, 2)
    col = base[None, None, :] * (tone * (0.8 + 0.22 * hgt))[..., None]
    return np.clip(col, 0, 255), hgt * 3.0


def velvet(w, h, base, rng, ppm=1300):
    n = value_noise(w, h, ppm * 0.05, rng, 3)
    col = base[None, None, :] * (0.85 + 0.3 * n[..., None])
    return np.clip(col, 0, 255), n * 0.25


def crochet(w, h, colours, rng, ppm=1300, pattern='zigzag'):
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    st = ppm * 0.009                               # one stitch ~9mm
    loops = (np.sin(xx / st * math.pi) * np.sin(yy / (st * 0.8) * math.pi)) ** 2
    hgt = 0.6 * loops + 0.4 * value_noise(w, h, st / 2, rng, 2)
    cols = [hexrgb(c) for c in colours]
    if pattern == 'argyle':
        a = ppm * 0.045
        dx = np.abs(((xx / a) % 2) - 1); dy = np.abs(((yy / a) % 2) - 1)
        k = ((dx + dy) < 1).astype(int)
        col = np.where(k[..., None] == 1, cols[0], cols[1 % len(cols)])
    else:
        period, amp = ppm * 0.06, ppm * 0.012
        tri = np.abs(((xx / period) % 1) - 0.5) * 2 * amp
        band = ((yy + tri) / (ppm * 0.022)).astype(int) % len(cols)
        col = np.stack([cols[b] for b in range(len(cols))])[band]
    col = col * (0.75 + 0.35 * hgt[..., None])
    return np.clip(col, 0, 255), hgt * 2.5


def tartan(w, h, base, lines, ppm=1300):
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    col = np.ones((h, w, 3)) * base
    rep = ppm * 0.09
    for (c, pos, width) in lines:
        cc = hexrgb(c)
        for a in (xx, yy):
            m = (np.abs(((a / rep) % 1) - pos) < width).astype(float)[..., None] * 0.55
            col = col * (1 - m) + cc * m
    return np.clip(col, 0, 255)


# ---- prints (original motifs) ---------------------------------------------------

def _scatter(img, motif_fn, ppm, size_m, spacing_m, rng, rot=25):
    w, h = img.size
    step = ppm * spacing_m
    s = int(ppm * size_m * 2)
    row = 0
    y = -step / 2
    while y < h + step:
        x = -step / 2 + (step / 2 if row % 2 else 0)
        while x < w + step:
            m = motif_fn(s, rng)
            m = m.rotate(rng.uniform(-rot, rot), resample=Image.BICUBIC, expand=True)
            m = m.resize((m.width // 2, m.height // 2), Image.LANCZOS)
            img.alpha_composite(m, (int(x - m.width / 2 + rng.uniform(-step * .15, step * .15)),
                                    int(y - m.height / 2 + rng.uniform(-step * .15, step * .15))))
            x += step
        y += step * 0.87
        row += 1


def cherry(s, rng):
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    r = s * 0.17
    stem = (s * 0.52, s * 0.12)
    for cx, cy in ((s * 0.33, s * 0.68), (s * 0.66, s * 0.72)):
        d.line([stem, (cx, cy - r)], fill=(70, 120, 50, 255), width=max(2, int(s * 0.035)))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(200, 30, 45, 255))
        d.ellipse((cx - r * 0.55, cy - r * 0.6, cx - r * 0.1, cy - r * 0.2), fill=(250, 140, 150, 255))
    d.ellipse((s * 0.52, s * 0.05, s * 0.82, s * 0.2), fill=(90, 150, 60, 255))
    return im


def rose(s, rng):
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = s / 2
    pinks = [(236, 150, 170), (225, 120, 150), (245, 185, 195)]
    for k in range(3):
        a = rng.uniform(0, 360)
        lx, ly = c + math.cos(math.radians(a)) * s * 0.3, c + math.sin(math.radians(a)) * s * 0.3
        d.ellipse((lx - s * .12, ly - s * .06, lx + s * .12, ly + s * .06), fill=(130, 165, 120, 255))
    for i, rr in enumerate((0.26, 0.19, 0.12, 0.06)):
        col = pinks[i % 3] + (255,)
        d.ellipse((c - s * rr, c - s * rr, c + s * rr, c + s * rr), fill=col, outline=(200, 100, 125, 255), width=max(1, s // 60))
    return im


def butterfly(s, rng):
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = s / 2
    wing = (205, 170, 235, 255); edge = (150, 110, 200, 255)
    for sx in (-1, 1):
        d.ellipse((c + sx * s * 0.02 - (s * .34 if sx < 0 else 0), c - s * 0.32, c + sx * s * 0.02 + (s * .34 if sx > 0 else 0), c + s * 0.02), fill=wing, outline=edge, width=max(1, s // 50))
        d.ellipse((c + sx * s * 0.02 - (s * .24 if sx < 0 else 0), c - s * 0.02, c + sx * s * 0.02 + (s * .24 if sx > 0 else 0), c + s * 0.28), fill=wing, outline=edge, width=max(1, s // 50))
    d.ellipse((c - s * .025, c - s * .25, c + s * .025, c + s * .25), fill=(110, 80, 150, 255))
    return im


def heart_motif(s, rng):
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    pts = []
    for k in range(60):
        t = 2 * math.pi * k / 60
        x = 16 * math.sin(t) ** 3; y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((s / 2 + x / 40 * s, s / 2 - y / 40 * s))
    d.polygon(pts, fill=(235, 120, 160, 255))
    return im


MOTIFS = {'cherry': (cherry, 0.045, 0.085), 'rose': (rose, 0.05, 0.09),
          'butterfly': (butterfly, 0.05, 0.10), 'hearts': (heart_motif, 0.03, 0.07)}


# ---- atlas ------------------------------------------------------------------------

def atlas(spec, seed=1):
    """
    spec: {
      body: {kind: leather|patent|croc|velvet|crochet|print|tartan|quilt, colour, ...},
      trim: '#hex', metal: 'gold'|'silver'|'gunmetal', ppm: pixels per metre on the body
    } -> (diffuse RGBA, normal RGB, spec RGBA) PIL images
    """
    rng = np.random.default_rng(seed)
    prng = random.Random(seed)
    ppm = spec.get('ppm', 1300)
    dif = np.zeros((S, S, 3)); hgt = np.zeros((S, S)); shine = np.zeros((S, S)); gloss = np.zeros((S, S))

    # body
    x0, y0, x1, y1 = px(BODY); w, h = x1 - x0, y1 - y0
    b = spec['body']; kind = b['kind']; base = hexrgb(b.get('colour', '#808080'))
    sh, gl = 0.35, 0.45
    if kind in ('leather', 'patent', 'print', 'quilt'):
        col, hh = leather(w, h, base, rng, grain=0.6 if kind == 'patent' else 1.0, ppm=ppm)
        if kind == 'patent':
            sh, gl = 0.9, 0.9
        if kind == 'quilt':
            yy, xx = np.mgrid[0:h, 0:w].astype(float)
            ch = ppm * b.get('channel', 0.035)
            q = np.abs(np.sin(xx / ch * math.pi)) ** 0.5
            hh = hh * 0.3 + q * 2.0
            col = col * (0.8 + 0.25 * q[..., None])
        if kind == 'print':
            im = Image.fromarray(col.astype(np.uint8)).convert('RGBA')
            fn, size_m, spacing_m = MOTIFS[b['motif']]
            _scatter(im, fn, ppm, size_m, spacing_m, prng)
            col = np.asarray(im.convert('RGB'), float)
            sh, gl = 0.3, 0.4
    elif kind == 'croc':
        col, hh = croc(w, h, base, rng, ppm); sh, gl = 0.7, 0.75
    elif kind == 'velvet':
        col, hh = velvet(w, h, base, rng, ppm); sh, gl = 0.08, 0.15
    elif kind == 'crochet':
        col, hh = crochet(w, h, b['colours'], rng, ppm, b.get('pattern', 'zigzag')); sh, gl = 0.05, 0.1
    elif kind == 'tartan':
        col = tartan(w, h, base, b['lines'], ppm); hh = value_noise(w, h, 6, rng, 2) * 0.3; sh, gl = 0.1, 0.2
    else:
        raise ValueError(kind)
    dif[y0:y1, x0:x1] = col; hgt[y0:y1, x0:x1] = hh; shine[y0:y1, x0:x1] = sh; gloss[y0:y1, x0:x1] = gl

    # trim: leather with a stitch line down each edge
    x0, y0, x1, y1 = px(TRIM); w, h = x1 - x0, y1 - y0
    col, hh = leather(w, h, hexrgb(spec.get('trim', '#c98a4b')), rng, ppm=ppm)
    for sx in (int(w * 0.12), int(w * 0.88)):
        for y in range(0, h, 10):
            col[y:y + 6, max(0, sx - 1):sx + 1] *= 0.75
            hh[y:y + 6, max(0, sx - 1):sx + 1] -= 0.6
    dif[y0:y1, x0:x1] = col; hgt[y0:y1, x0:x1] = hh; shine[y0:y1, x0:x1] = 0.45; gloss[y0:y1, x0:x1] = 0.55

    # metal
    x0, y0, x1, y1 = px(METAL); w, h = x1 - x0, y1 - y0
    m = {'gold': ('#e8c46a', '#9c7a2c'), 'silver': ('#eceff2', '#8d949b'), 'gunmetal': ('#7a7f86', '#33373c')}[spec.get('metal', 'gold')]
    t = np.linspace(0, 1, w)[None, :, None]
    col = hexrgb(m[0]) * (1 - t) + hexrgb(m[1]) * t
    dif[y0:y1, x0:x1] = np.repeat(col, h, axis=0); hgt[y0:y1, x0:x1] = 0; shine[y0:y1, x0:x1] = 1.0; gloss[y0:y1, x0:x1] = 0.95

    diffuse = Image.fromarray(np.clip(dif, 0, 255).astype(np.uint8)).convert('RGBA')
    normal = Image.fromarray(normal_from_height(hgt, 1.6))
    specm = np.dstack([shine, shine, shine, gloss]) * 255
    specular = Image.fromarray(specm.astype(np.uint8), 'RGBA')
    return diffuse, normal, specular
