"""High quality salon props (normal_spec: diffuse + normal + specular maps), no branding.

Hand tools run along +Y with the grip at the origin; tubs, cans and bottles stand on z = 0 along +Z.
Head pieces (wig cap, clips, pins) are built for the head bone: like hairkit's hair, model axes
(x right, y forward, z up) measured from SKEL_Head.

    python3 build.py <out>     builds these with the rest (build.py imports PROPS from here)
"""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from mesh import Part, merge, lathe, loft_y, box, rot, height_to_normal, write_dds, ydr_xml_hq, archetype_xml, render

TEAL = (8, 175, 162)


def _b():
    import build
    return build


# ── geometry helpers ────────────────────────────────────────────────────────────────────────────

def sweep(path, radius, segs, uv, caps=True, flat=1.0):
    """A tube along a 3D polyline. radius: number or list per point. flat < 1 squashes it (ribbons, wire)."""
    path = np.asarray(path, dtype=np.float64)
    n = len(path)
    rad = np.full(n, radius, dtype=np.float64) if np.isscalar(radius) else np.asarray(radius, dtype=np.float64)
    T = np.gradient(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-12
    # parallel transport frames
    ref = np.array([0.0, 0.0, 1.0]) if abs(T[0][2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    Nn = np.cross(T[0], ref); Nn /= np.linalg.norm(Nn)
    frames = []
    for i in range(n):
        if i > 0:
            Nn = Nn - T[i] * np.dot(Nn, T[i]); Nn /= np.linalg.norm(Nn) + 1e-12
        B = np.cross(T[i], Nn)
        frames.append((Nn.copy(), B))
    u0, v0, u1, v1 = uv
    P, Nm, UV, Tr = [], [], [], []
    L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    L = L / max(L[-1], 1e-9)
    for i in range(n):
        Nv, Bv = frames[i]
        for k in range(segs + 1):
            a = 2 * math.pi * k / segs
            d = Nv * math.cos(a) + Bv * math.sin(a) * flat
            P.append(path[i] + d * rad[i])
            nn = Nv * math.cos(a) + Bv * math.sin(a) / max(flat, 1e-3)
            Nm.append(nn / (np.linalg.norm(nn) + 1e-12))
            UV.append((u0 + (u1 - u0) * k / segs, v0 + (v1 - v0) * L[i]))
    for i in range(n - 1):
        for k in range(segs):
            a, b_, c, d = i * (segs + 1) + k, i * (segs + 1) + k + 1, (i + 1) * (segs + 1) + k, (i + 1) * (segs + 1) + k + 1
            Tr += [(a, c, b_), (b_, c, d)]
    parts = [Part(np.array(P), np.array(Nm), np.array(UV), np.array(Tr))]
    if caps:
        for end, sgn in ((0, -1), (n - 1, 1)):
            c = path[end]; nn = T[end] * sgn
            base = len(P)
            cp = [c] + [P[end * (segs + 1) + k] for k in range(segs)]
            cn = [nn] * len(cp)
            cuv = [((u0 + u1) / 2, v0 if end == 0 else v1)] * len(cp)
            ct = [(0, k + 1, (k + 1) % segs + 1) if sgn > 0 else (0, (k + 1) % segs + 1, k + 1) for k in range(segs)]
            parts.append(Part(np.array(cp), np.array(cn), np.array(cuv), np.array(ct)))
    return merge(parts)


def rbar(y0, y1, w0, w1, h0, h1, uv, n=5.0, segs=28, steps=8, cz=0.0, caps=True, bow=0.0):
    """A rounded-rectangle bar along Y from (w0,h0) to (w1,h1): handles, arms, plates."""
    secs = []
    for i in range(steps + 1):
        t = i / steps
        secs.append((y0 + (y1 - y0) * t, w0 + (w1 - w0) * t, h0 + (h1 - h0) * t, n, 0.0, cz + bow * math.sin(t * math.pi)))
    return loft_y(secs, segs, uv, caps=[(0, uv), (1, uv)] if caps else None)


def disk(r, z, uv, segs=48, up=True):
    """A flat round lid / bottom with planar UVs (print reads flat on it)."""
    u0, v0, u1, v1 = uv
    P = [(0.0, 0.0, z)] + [(r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z) for k in range(segs)]
    UV = [((u0 + u1) / 2, (v0 + v1) / 2)] + [(u0 + (u1 - u0) * (0.5 + 0.5 * math.cos(2 * math.pi * k / segs)),
                                            v0 + (v1 - v0) * (0.5 - 0.5 * math.sin(2 * math.pi * k / segs))) for k in range(segs)]
    nz = 1.0 if up else -1.0
    T = [(0, k + 1, (k + 1) % segs + 1) if up else (0, (k + 1) % segs + 1, k + 1) for k in range(segs)]
    return Part(np.array(P), np.array([(0, 0, nz)] * len(P)), np.array(UV), np.array(T))


def ball(r, uv, segs=20, rings=10, at=(0, 0, 0)):
    prof = [(0.0, -r)] + [(r * math.sin(math.pi * k / rings), -r * math.cos(math.pi * k / rings)) for k in range(1, rings)] + [(0.0, r)]
    return lathe(prof, segs, uv).transformed(t=at)


# ── materials: one 1024 atlas per prop, with matching normal + specular maps ─────────────────────

class Atlas:
    """Regions of a 1024 texture: diffuse colour, a height map (for the normal map) and specular."""

    def __init__(self, size=1024):
        self.S = size
        self.d = np.zeros((size, size, 3)); self.h = np.full((size, size), 0.5); self.s = np.zeros((size, size))
        self.slots = []
        self.img = None

    def region(self, u0, v0, u1, v1, rgb, spec, kind='plain', amp=6.0, seed=1, scale=1.0):
        S = self.S
        x0, y0, x1, y1 = int(u0 * S), int(v0 * S), int(u1 * S), int(v1 * S)
        w, h = x1 - x0, y1 - y0
        rng = np.random.default_rng(seed)
        noise = rng.normal(0, 1, (h, w))
        noise = np.asarray(Image.fromarray(np.uint8(np.clip(128 + noise * 40, 0, 255))).filter(ImageFilter.GaussianBlur(1.0)), np.float64) / 128 - 1
        col = np.ones((h, w, 3)) * np.array(rgb, np.float64) + noise[..., None] * amp
        ht = 0.5 + noise * 0.04
        yy, xx = np.mgrid[0:h, 0:w]
        if kind == 'knurl':          # soft-touch grip: a diamond knurl
            k = (np.sin(xx / (3.0 * scale) + yy / (3.0 * scale)) * np.sin(xx / (3.0 * scale) - yy / (3.0 * scale)))
            ht = 0.5 + 0.35 * np.sign(k) * np.abs(k) ** 0.5
            col *= (0.92 + 0.08 * (ht[..., None] - 0.5) * 2)
        elif kind == 'brushed':      # brushed metal: streaks along u
            streak = np.repeat(rng.normal(0, 1, (h, 1)), w, axis=1)
            streak = np.asarray(Image.fromarray(np.uint8(np.clip(128 + streak * 50, 0, 255))).filter(ImageFilter.GaussianBlur((6, 0))), np.float64) / 128 - 1
            col += streak[..., None] * 9
            ht = 0.5 + streak * 0.06
        elif kind == 'ribs':         # ridged lids / grip rings along v
            r = np.sin(yy / (2.2 * scale) * math.pi)
            ht = 0.5 + 0.45 * r
            col *= (0.9 + 0.1 * (r[..., None] * 0.5 + 0.5))
        elif kind == 'mesh':         # a wig cap's net
            g = (np.abs(np.sin(xx / (5.0 * scale) * math.pi)) < 0.22) | (np.abs(np.sin(yy / (5.0 * scale) * math.pi)) < 0.22)
            ht = np.where(g, 0.85, 0.25)
            col = np.where(g[..., None], col * 1.15, col * 0.72)
        elif kind == 'ceramic':
            col += noise[..., None] * 4
            ht = 0.5 + noise * 0.015
        elif kind == 'hair':         # pre-stretched hair: strands along v
            cols = np.convolve(rng.random(w), np.ones(3) / 3, mode='same')
            k = np.clip(0.6 * cols[None, :] + 0.4 * rng.random((h, w)) * 0.3, 0, 1)
            col = np.array(rgb, np.float64) * (0.55 + 0.75 * k[..., None])
            ht = 0.5 + (k - 0.5) * 0.8
        self.d[y0:y1, x0:x1] = col
        self.h[y0:y1, x0:x1] = ht
        self.s[y0:y1, x0:x1] = spec * (0.9 + 0.1 * (ht - 0.5) * 2)
        return (u0, v0, u1, v1)

    def text(self, rect, lines, flip=False, align='mm'):
        """Print text into the diffuse (and a touch into the height map, like ink). rect in u/v (v = image rows)."""
        b = _b()
        S = self.S
        u0, v0, u1, v1 = rect
        pw, ph = int((u1 - u0) * S), int((v1 - v0) * S)
        panel = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
        d = ImageDraw.Draw(panel)
        total = sum(sz * 1.3 for _, sz, _, _ in lines)
        y = (ph - total) / 2
        for txt, sz, rgb, wt in lines:
            d.text((pw / 2, y + sz * 0.65), txt, font=b.font(int(sz), wt), fill=rgb + (255,), anchor='mm')
            y += sz * 1.3
        if flip:
            panel = panel.transpose(Image.FLIP_TOP_BOTTOM)
        a = np.asarray(panel, np.float64) / 255.0
        x0, y0 = int(u0 * S), int(v0 * S)
        reg = self.d[y0:y0 + ph, x0:x0 + pw]
        reg[:] = reg * (1 - a[..., 3:4]) + a[..., :3] * 255 * a[..., 3:4]
        self.h[y0:y0 + ph, x0:x0 + pw] += a[..., 3] * 0.04
        self.s[y0:y0 + ph, x0:x0 + pw] *= (1 - 0.4 * a[..., 3])

    def band(self, rect, rgb, spec=None):
        S = self.S
        u0, v0, u1, v1 = rect
        self.d[int(v0 * S):int(v1 * S), int(u0 * S):int(u1 * S)] = rgb
        if spec is not None:
            self.s[int(v0 * S):int(v1 * S), int(u0 * S):int(u1 * S)] = spec

    def ao(self, rect, edge=0.08, strength=0.35):
        """Darken the ends of a lathe region along v (where parts meet)."""
        S = self.S
        u0, v0, u1, v1 = rect
        y0, y1 = int(v0 * S), int(v1 * S)
        n = y1 - y0
        t = np.linspace(0, 1, n)
        k = 1 - strength * (np.clip(1 - t / edge, 0, 1) ** 2 + np.clip(1 - (1 - t) / edge, 0, 1) ** 2)
        self.d[y0:y1, int(u0 * S):int(u1 * S)] *= k[:, None, None]

    def images(self):
        d = Image.fromarray(np.uint8(np.clip(self.d, 0, 255)))
        nrm = height_to_normal(self.h, 3.0)
        sp = Image.fromarray(np.uint8(np.clip(self.s * 255, 0, 255))).convert('RGB')
        return d, nrm, sp


def save_hq(out, name, part, atlas, lod=30.0, spec_mult=1.0, falloff=60.0):
    import os
    d, n, s = atlas.images()
    tex = {}
    for kind, img in (('diffuse', d), ('normal', n), ('spec', s)):
        tn = f'{name}_{kind[0]}'
        mips = write_dds(img, os.path.join(out, tn + '.dds'))
        tex[kind] = (tn, img.size[0], img.size[1], mips)
    with open(os.path.join(out, name + '.ydr.xml'), 'w') as fh:
        fh.write(ydr_xml_hq(name, part, tex, spec_mult=spec_mult, falloff=falloff))
    d.save(os.path.join(out, name + '_d.png'))
    shots = [render(part, d, 360, yaw=a, pitch=p) for a, p in ((35, 20), (215, 15), (110, 60))]
    sheet = Image.new('RGB', (360 * 3, 360))
    for i, sh in enumerate(shots):
        sheet.paste(sh, (360 * i, 0))
    sheet.save(os.path.join(out, name + '_preview.png'))
    print('%-16s verts=%6d tris=%6d (hq)' % (name, len(part.P), len(part.T)))
    return archetype_xml(name, part, lod)


# ═════════════════════════════════════════════════════════════════════════════════════
# HAND TOOLS

def comb():
    A = Atlas()
    body = A.region(0.0, 0.0, 0.5, 1.0, (17, 17, 19), 0.45, 'plain', 4, seed=11)
    tail = A.region(0.5, 0.0, 1.0, 0.5, (196, 200, 205), 0.95, 'brushed', 8, seed=12)
    ferr = A.region(0.5, 0.5, 1.0, 1.0, (40, 42, 46), 0.55, 'ribs', 4, seed=13, scale=1.5)
    A.text((0.05, 0.4, 0.45, 0.6), [('ANTI-STATIC', 34, (110, 114, 120), 600)])
    spine = rbar(0.0, 0.112, 0.0062, 0.0058, 0.0016, 0.0013, body, n=4.0, segs=24, steps=6, cz=0.0)
    spine = spine.transformed(t=(0.0035, 0, 0))
    teeth = []
    for i in range(30):
        y = 0.004 + i * 0.0035
        L = 0.0105 if i % 2 == 0 else 0.0095
        path = [(-0.0025 - L * t, y + 0.0007, 0.0) for t in np.linspace(0, 1, 6)]
        teeth.append(sweep(path, [0.00072, 0.0007, 0.00066, 0.0006, 0.0005, 0.0003], 6, body, flat=0.75))
    tpath = [(0.0035, -0.004 - 0.1 * t, 0.0) for t in np.linspace(0, 1, 18)]
    tr = [0.0011 - 0.0007 * t ** 1.4 for t in np.linspace(0, 1, 18)]
    tailp = sweep(tpath, tr, 12, tail)
    collar = lathe([(0.0016, -0.0035), (0.0021, -0.003), (0.0021, 0.002), (0.0016, 0.0025)], 16, ferr).transformed(R=rot('x', -90), t=(0.0035, 0.0, 0.0))
    return ('nz_sty_comb', merge([spine, tailp, collar] + teeth), A, 25.0)


def brush():
    A = Atlas()
    shell = A.region(0.0, 0.0, 0.5, 0.6, (14, 15, 17), 0.5, 'plain', 4, seed=21)
    grip = A.region(0.0, 0.6, 0.5, 1.0, (22, 23, 25), 0.15, 'knurl', 5, seed=22)
    pad = A.region(0.5, 0.0, 1.0, 0.5, (36, 38, 42), 0.2, 'plain', 4, seed=23)
    pins = A.region(0.5, 0.5, 0.75, 1.0, (170, 172, 176), 0.8, 'plain', 4, seed=24)
    tips = A.region(0.75, 0.5, 1.0, 1.0, TEAL, 0.6, 'plain', 4, seed=25)
    A.text((0.05, 0.15, 0.45, 0.45), [('PROFESSIONAL', 30, (120, 124, 130), 600), ('DETANGLING', 24, (90, 94, 100), 500)])
    handle = merge([rbar(-0.115, -0.04, 0.0105, 0.0125, 0.0085, 0.0095, grip, n=3.2, segs=28, steps=8),
                    rbar(-0.04, 0.0, 0.0125, 0.0105, 0.0095, 0.0082, shell, n=3.2, segs=28, steps=6)])
    secs = []
    for i in range(20):
        a = i / 19
        y = 0.0 + a * 0.115
        w = 0.0105 + 0.026 * math.sin(min(1, a * 1.5) * math.pi / 2) - 0.012 * max(0, a - 0.82) / 0.18
        secs.append((y, w, 0.0085 - 0.0015 * a, 2.6, 0, -0.0005))
    head = loft_y(secs, 40, shell, caps=[(1, shell)])
    cushion = rbar(0.012, 0.104, 0.027, 0.027, 0.0012, 0.0012, pad, n=3.0, segs=32, steps=4, cz=0.0078)
    bristles = []
    for r in range(11):
        for c in range(7):
            x = -0.0225 + c * 0.0075 + (0.0037 if r % 2 else 0)
            if abs(x) > 0.025:
                continue
            y = 0.016 + r * 0.0079
            bristles.append(sweep([(x, y, 0.0085), (x, y, 0.0175)], 0.00055, 6, pins, caps=False))
            bristles.append(ball(0.0011, tips, segs=8, rings=5, at=(x, y, 0.0182)))
    return ('nz_sty_brush', merge([handle, head, cushion] + bristles), A, 30.0)


def edge_brush():
    A = Atlas()
    body = A.region(0.0, 0.0, 0.5, 1.0, (16, 16, 18), 0.45, 'plain', 4, seed=31)
    hair = A.region(0.5, 0.0, 1.0, 0.5, (58, 42, 30), 0.1, 'hair', 6, seed=32)
    grip = A.region(0.5, 0.5, 1.0, 1.0, (28, 28, 30), 0.15, 'knurl', 4, seed=33, scale=0.6)
    handle = merge([rbar(-0.07, -0.02, 0.0034, 0.0042, 0.0028, 0.0032, grip, n=3.0, segs=20),
                    rbar(-0.02, 0.03, 0.0042, 0.0036, 0.0032, 0.003, body, n=3.0, segs=20)])
    block = rbar(0.022, 0.04, 0.0042, 0.0042, 0.0028, 0.0028, body, n=4.0, segs=20, cz=0.0035)
    tufts = []
    for r in range(4):
        for c in range(3):
            x, y = -0.0025 + c * 0.0025, 0.0245 + r * 0.0042
            for k in range(5):
                ox, oy = (k % 3 - 1) * 0.0004, (k // 3 - 0.5) * 0.0004
                tufts.append(sweep([(x + ox, y + oy, 0.006), (x + ox * 2, y + oy * 2, 0.0135)], 0.00028, 4, hair, caps=False))
    comb = []
    for i in range(14):
        y = -0.068 + i * 0.0032
        comb.append(sweep([(-0.0034 - 0.0075 * t, y, 0.0) for t in np.linspace(0, 1, 4)], [0.0005, 0.00045, 0.0004, 0.00025], 5, body, flat=0.7))
    return ('nz_sty_edge', merge([handle, block] + tufts + comb), A, 20.0)


def needle():
    A = Atlas()
    steel = A.region(0.0, 0.0, 0.5, 1.0, (205, 210, 216), 0.95, 'brushed', 6, seed=41)
    thread = A.region(0.5, 0.0, 1.0, 1.0, (40, 30, 26), 0.1, 'ribs', 6, seed=42, scale=0.5)
    R = 0.021
    arc = [(R * math.cos(a), 0.0, R * math.sin(a)) for a in np.linspace(math.radians(-15), math.radians(195), 40)]
    arc = [(x + R, y, z) for x, y, z in arc]
    rr = [0.0009 if t < 0.85 else 0.0009 * max(0.0, 1 - (t - 0.85) / 0.15) ** 0.6 + 0.00005 for t in np.linspace(0, 1, 40)]
    shaft = sweep(arc, rr, 10, steel, flat=0.85)
    eye = lathe([(0.0014, -0.0005), (0.0022, -0.0005), (0.0022, 0.0005), (0.0014, 0.0005), (0.0014, -0.0005)], 14, steel)
    eye = eye.transformed(R=rot('x', 90), t=arc[0])
    th = [arc[0]] + [(arc[0][0] - 0.004 * t + 0.003 * math.sin(t * 5), -0.02 * t, arc[0][2] - 0.03 * t + 0.004 * math.sin(t * 7)) for t in np.linspace(0.05, 1, 22)]
    thr = sweep(th, 0.00045, 6, thread)
    return ('nz_sty_needle', merge([shaft, eye, thr]).transformed(R=rot('x', 90)), A, 15.0)


def hook():
    A = Atlas()
    alu = A.region(0.0, 0.0, 0.5, 1.0, (180, 70, 140), 0.85, 'brushed', 6, seed=51)
    grip = A.region(0.5, 0.0, 1.0, 1.0, (24, 24, 26), 0.12, 'knurl', 4, seed=52)
    shaft = sweep([(0, -0.07 + 0.15 * t, 0) for t in np.linspace(0, 1, 10)], 0.0018, 14, alu)
    tipc = [(0.0, 0.08 + 0.003 * math.sin(a), -0.0025 + 0.0025 * math.cos(a)) for a in np.linspace(0, math.pi * 1.25, 14)]
    tip = sweep(tipc, [0.0013 - 0.0005 * t for t in np.linspace(0, 1, 14)], 10, alu)
    latch = sweep([(0.0, 0.062 + 0.018 * t, -0.0024 + 0.0004 * t) for t in np.linspace(0, 1, 6)], 0.0006, 8, alu, flat=0.5)
    hinge = ball(0.0011, alu, segs=10, rings=6, at=(0.0, 0.061, -0.0022))
    g = rbar(-0.065, 0.0, 0.0052, 0.0048, 0.0052, 0.0048, grip, n=2.0, segs=24, steps=6)
    return ('nz_sty_hook', merge([shaft, tip, latch, hinge, g]), A, 15.0)


def flat_iron():
    A = Atlas()
    shell = A.region(0.0, 0.0, 0.5, 0.7, (18, 19, 21), 0.6, 'plain', 4, seed=61)
    grip = A.region(0.0, 0.7, 0.5, 1.0, (24, 25, 27), 0.15, 'knurl', 4, seed=62)
    plate = A.region(0.5, 0.0, 1.0, 0.4, (226, 216, 198), 0.7, 'ceramic', 4, seed=63)
    metal = A.region(0.5, 0.4, 1.0, 0.7, (170, 172, 176), 0.9, 'brushed', 6, seed=64)
    disp = A.region(0.5, 0.7, 1.0, 1.0, (8, 10, 12), 0.9, 'plain', 2, seed=65)
    A.text((0.55, 0.75, 0.95, 0.95), [('450°F', 60, (95, 225, 210), 700)])
    A.text((0.05, 0.25, 0.45, 0.45), [('TITANIUM PRO', 30, (150, 154, 160), 600)])
    arms = []
    for s in (1, -1):
        a = merge([
            rbar(-0.11, -0.02, 0.0105, 0.0125, 0.0058, 0.0066, grip, n=3.4, segs=28, steps=8),
            rbar(-0.02, 0.165, 0.0125, 0.0128, 0.0066, 0.0058, shell, n=3.4, segs=28, steps=12),
            rbar(0.04, 0.162, 0.0108, 0.0108, 0.0012, 0.0012, plate, n=6.0, segs=24, steps=4, cz=-s * 0.0064),
            rbar(0.036, 0.166, 0.0118, 0.0118, 0.0008, 0.0008, metal, n=6.0, segs=24, steps=3, cz=-s * 0.0058),
        ])
        if s > 0:
            a = merge([a, rbar(-0.005, 0.02, 0.0062, 0.0062, 0.0004, 0.0004, disp, n=6, segs=16, steps=2, cz=0.0068)])
        arms.append(a.transformed(R=rot('x', 2.5 * s), t=(0, 0, s * 0.0078)))
    hinge = lathe([(0.0, -0.016), (0.0072, -0.016), (0.0078, -0.012), (0.0078, 0.012), (0.0072, 0.016), (0.0, 0.016)], 24, metal).transformed(R=rot('y', 90), t=(0, -0.112, 0))
    swivel = lathe([(0.0, 0.0), (0.0045, 0.0), (0.0048, 0.01), (0.003, 0.018), (0.0026, 0.03)], 18, shell).transformed(R=rot('x', 90), t=(0, -0.112, 0))
    cord = sweep([(0, -0.142 - 0.05 * t, -0.012 * t * t) for t in np.linspace(0, 1, 10)], 0.0024, 10, shell)
    return ('nz_sty_iron', merge(arms + [hinge, swivel, cord]), A, 30.0)


def wand():
    A = Atlas()
    shell = A.region(0.0, 0.0, 0.5, 0.6, (18, 19, 21), 0.6, 'plain', 4, seed=71)
    grip = A.region(0.0, 0.6, 0.5, 1.0, (24, 25, 27), 0.15, 'knurl', 4, seed=72)
    barrel = A.region(0.5, 0.0, 1.0, 0.7, (192, 140, 100), 0.9, 'brushed', 7, seed=73)
    tip = A.region(0.5, 0.7, 1.0, 1.0, (20, 20, 22), 0.2, 'ribs', 3, seed=74, scale=0.8)
    A.text((0.05, 0.2, 0.45, 0.4), [('CERAMIC 1"', 32, (150, 154, 160), 600)])
    handle = lathe([(0.0, -0.115), (0.008, -0.115), (0.0115, -0.105), (0.0128, -0.06), (0.0132, -0.02), (0.0124, 0.0), (0.0, 0.0)], 32, grip)
    collar = lathe([(0.0124, 0.0), (0.0135, 0.002), (0.0135, 0.012), (0.0112, 0.016), (0.0, 0.016)], 32, shell)
    br = lathe([(0.0108, 0.016), (0.0106, 0.06), (0.0098, 0.12), (0.0092, 0.168), (0.0, 0.168)], 40, barrel)
    cool = lathe([(0.0092, 0.168), (0.0088, 0.172), (0.0078, 0.182), (0.005, 0.188), (0.0, 0.189)], 24, tip)
    stand = sweep([(0.0, 0.004 + 0.012 * t, -0.0135 - 0.006 * math.sin(t * math.pi)) for t in np.linspace(0, 1, 8)], 0.0011, 8, shell)
    part = merge([handle, collar, br, cool, stand]).transformed(R=rot('x', -90))
    return ('nz_sty_wand', part, A, 30.0)


def dryer():
    A = Atlas()
    shell = A.region(0.0, 0.0, 0.5, 0.7, (16, 17, 19), 0.65, 'plain', 4, seed=81)
    grip = A.region(0.0, 0.7, 0.5, 1.0, (24, 25, 27), 0.15, 'knurl', 4, seed=82)
    vent = A.region(0.5, 0.0, 1.0, 0.4, (30, 31, 34), 0.3, 'mesh', 4, seed=83, scale=0.6)
    accent = A.region(0.5, 0.4, 1.0, 0.7, TEAL, 0.7, 'plain', 4, seed=84)
    metal = A.region(0.5, 0.7, 1.0, 1.0, (170, 172, 176), 0.9, 'brushed', 6, seed=85)
    A.text((0.05, 0.25, 0.45, 0.45), [('2200W', 40, (150, 154, 160), 700), ('IONIC', 26, (110, 114, 120), 600)], flip=True)
    body = lathe([(0.0, -0.085), (0.028, -0.085), (0.034, -0.078), (0.037, -0.06), (0.038, 0.0), (0.035, 0.045),
                  (0.028, 0.075), (0.024, 0.09), (0.0, 0.09)], 48, shell).transformed(R=rot('y', 90), t=(0, 0.05, 0))
    grille = lathe([(0.0, -0.0865), (0.03, -0.0865), (0.03, -0.0855), (0.0, -0.0855)], 40, vent).transformed(R=rot('y', 90), t=(0, 0.05, 0))
    ring = lathe([(0.0305, -0.087), (0.034, -0.087), (0.035, -0.08), (0.0305, -0.08)], 40, accent).transformed(R=rot('y', 90), t=(0, 0.05, 0))
    # concentrator nozzle: round to flat
    secs = []
    for i in range(10):
        t = i / 9
        secs.append((0.09 + 0.045 * t, 0.024 - 0.002 * t, 0.024 - 0.015 * t, 2.0 + 3 * t, 0, 0))
    noz = loft_y(secs, 32, metal, caps=[(1, vent)]).transformed(R=rot('z', -90), t=(0, 0.05, 0))
    handle = merge([rbar(-0.11, -0.01, 0.0135, 0.016, 0.017, 0.019, grip, n=2.6, segs=28, steps=8),
                    rbar(-0.01, 0.03, 0.016, 0.019, 0.019, 0.022, shell, n=2.6, segs=28, steps=4)]).transformed(R=rot('z', 8))
    sw1 = rbar(-0.05, -0.034, 0.0035, 0.0035, 0.0018, 0.0018, accent, n=4, segs=12, steps=2, cz=0.0)
    sw1 = sw1.transformed(t=(0, 0, 0.0185))
    sw2 = sw1.transformed(t=(0, 0.02, 0))
    cord = sweep([(0.0, -0.11 - 0.06 * t, 0.01 * math.sin(t * 3)) for t in np.linspace(0, 1, 12)], 0.0028, 10, shell)
    return ('nz_sty_dryer', merge([body, grille, ring, noz, handle, sw1, sw2, cord]), A, 35.0)


# ═════════════════════════════════════════════════════════════════════════════════════
# PRODUCTS (stand on z = 0)

def tub(name='nz_sty_gel', body=(64, 150, 214), lid=(14, 15, 17), title='BRAIDING GEL', sub='Maximum Hold · 16 oz', r=0.036, h=0.044, ink=(255, 255, 255)):
    A = Atlas()
    bd = A.region(0.0, 0.0, 1.0, 0.6, body, 0.7, 'plain', 5, seed=91)
    lb = A.region(0.0, 0.6, 1.0, 0.75, lid, 0.55, 'ribs', 3, seed=92, scale=1.2)
    lt = A.region(0.0, 0.75, 0.5, 1.0, lid, 0.55, 'plain', 3, seed=93)
    bt = A.region(0.5, 0.75, 1.0, 1.0, tuple(int(c * 0.8) for c in body), 0.5, 'plain', 3, seed=94)
    for uc in (0.25, 0.75):
        A.text((uc - 0.22, 0.12, uc + 0.22, 0.48), [(title, 50, ink, 800), (sub, 28, tuple(int(c * 0.9) for c in ink), 500)], flip=True)
    A.text((0.04, 0.78, 0.46, 0.97), [('16 OZ', 40, (90, 94, 100), 700)])
    A.ao(bd, 0.06, 0.3)
    wall = lathe([(r * 0.97, 0.0015), (r, 0.005), (r, h * 0.8), (r * 0.985, h * 0.83)], 64, bd)
    bottom = disk(r * 0.97, 0.0015, bt, up=False)
    side = lathe([(r * 1.012, h * 0.8), (r * 1.03, h * 0.82), (r * 1.03, h * 0.98), (r * 1.012, h)], 64, lb)
    edge = lathe([(r * 1.012, h), (r * 0.96, h * 1.012)], 64, lb)
    top = disk(r * 0.96, h * 1.012, lt)
    return (name, merge([wall, bottom, side, edge, top]), A, 25.0)


def gel():
    return tub()


def tin():
    A = Atlas()
    bd = A.region(0.0, 0.0, 1.0, 0.45, (216, 168, 70), 0.85, 'plain', 5, seed=95)
    lid = A.region(0.0, 0.45, 0.5, 1.0, (210, 160, 62), 0.85, 'plain', 5, seed=96)
    bt = A.region(0.5, 0.45, 1.0, 1.0, (170, 130, 50), 0.6, 'plain', 4, seed=97)
    for uc in (0.25, 0.75):
        A.text((uc - 0.22, 0.04, uc + 0.22, 0.42), [('EDGE CONTROL', 44, (20, 16, 10), 800), ('extra hold', 26, (60, 44, 20), 500)], flip=True)
    # the lid's print, embossed (into the height map too)
    A.text((0.04, 0.55, 0.46, 0.9), [('EDGE', 64, (120, 86, 24), 800), ('CONTROL', 46, (120, 86, 24), 800), ('24H HOLD', 26, (140, 100, 30), 600)])
    r, h = 0.033, 0.021
    can = lathe([(r * 0.96, 0.0012), (r, 0.003), (r, h * 0.82)], 64, bd)
    bottom = disk(r * 0.96, 0.0012, bt, up=False)
    rim = lathe([(r * 1.01, h * 0.8), (r * 1.025, h * 0.85), (r * 1.025, h * 0.97), (r * 1.01, h), (r * 0.95, h * 1.03)], 64, bd)
    top = disk(r * 0.95, h * 1.03, lid)
    return ('nz_sty_tin', merge([can, bottom, rim, top]), A, 25.0)


def can(name='nz_sty_mousse', band=(226, 86, 150), title='FOAM MOUSSE', sub='wrap & set'):
    A = Atlas()
    bd = A.region(0.0, 0.0, 1.0, 0.72, (238, 239, 240), 0.8, 'plain', 4, seed=101)
    A.band((0.0, 0.18, 1.0, 0.5), band, 0.6)
    tp = A.region(0.0, 0.72, 1.0, 0.86, (190, 194, 198), 0.95, 'brushed', 5, seed=102)
    ac = A.region(0.0, 0.86, 1.0, 1.0, (18, 18, 20), 0.5, 'plain', 3, seed=103)
    for uc in (0.25, 0.75):
        A.text((uc - 0.22, 0.2, uc + 0.22, 0.48), [(title, 40, (255, 255, 255), 800), (sub, 24, (255, 236, 244), 500)], flip=True)
    A.ao(bd, 0.04, 0.25)
    body = lathe([(0.0, 0.0), (0.02, 0.0), (0.0235, 0.003), (0.024, 0.008), (0.024, 0.118)], 56, bd)
    dome = lathe([(0.024, 0.118), (0.0215, 0.128), (0.0165, 0.134), (0.011, 0.137), (0.011, 0.139), (0.0, 0.14)], 56, tp)
    act = lathe([(0.0, 0.139), (0.0095, 0.139), (0.0102, 0.142), (0.0102, 0.151), (0.0085, 0.156), (0.0, 0.157)], 32, ac)
    spout = sweep([(0.0, 0.0, 0.152), (0.008, 0.0, 0.153), (0.016, 0.0, 0.151)], [0.0032, 0.0028, 0.0024], 12, ac)
    return (name, merge([body, dome, act, spout]), A, 25.0)


def mousse():
    return can()


def spray(name='nz_sty_spray', liquid=(232, 240, 242), band=TEAL, title='SHINE SPRAY', sub='gloss finish'):
    A = Atlas()
    bd = A.region(0.0, 0.0, 1.0, 0.66, liquid, 0.85, 'plain', 4, seed=111)
    A.band((0.0, 0.2, 1.0, 0.5), band, 0.6)
    hd = A.region(0.0, 0.66, 1.0, 1.0, (20, 20, 22), 0.5, 'plain', 3, seed=112)
    for uc in (0.25, 0.75):
        A.text((uc - 0.22, 0.22, uc + 0.22, 0.48), [(title, 40, (255, 255, 255), 800), (sub, 24, (236, 248, 246), 500)], flip=True)
    A.ao(bd, 0.04, 0.25)
    body = lathe([(0.0, 0.0), (0.019, 0.0), (0.0218, 0.004), (0.022, 0.012), (0.022, 0.096), (0.019, 0.108),
                  (0.012, 0.116), (0.0095, 0.12), (0.0095, 0.126)], 56, bd)
    collar = lathe([(0.0105, 0.124), (0.0115, 0.126), (0.0115, 0.136), (0.0105, 0.138)], 40, hd)
    # trigger sprayer: shroud, nozzle, trigger
    shroud = rbar(-0.013, 0.026, 0.0085, 0.006, 0.0105, 0.0075, hd, n=3.0, segs=24, steps=6).transformed(t=(0, 0, 0.146))
    noz = lathe([(0.0, 0.0), (0.0045, 0.0), (0.0045, 0.006), (0.003, 0.008), (0.0, 0.008)], 16, hd).transformed(R=rot('x', -90), t=(0, 0.026, 0.147))
    trig = sweep([(0.0, 0.012, 0.142), (0.0, 0.016, 0.13), (0.0, 0.014, 0.118)], [0.0042, 0.004, 0.0035], 12, hd, flat=0.55)
    tube = sweep([(0.0, 0.0, 0.124), (0.0, 0.0, 0.006)], 0.0012, 8, bd, caps=False)
    return (name, merge([body, collar, shroud, noz, trig, tube]), A, 25.0)


def heat():
    return spray('nz_sty_heat', (246, 240, 236), (214, 64, 64), 'HEAT PROTECT', 'up to 450°F')


def moist():
    return spray('nz_sty_moist', (240, 244, 248), (96, 150, 210), 'MOISTURIZER', 'leave-in')


def pack(name='nz_sty_pack', hair=(190, 140, 82), title='PRE-STRETCHED', sub='BRAIDING HAIR · 26"'):
    A = Atlas()
    hr = A.region(0.0, 0.0, 0.75, 1.0, hair, 0.25, 'hair', 0, seed=121)
    pb = A.region(0.75, 0.0, 1.0, 1.0, (244, 245, 246), 0.3, 'plain', 3, seed=122)
    A.band((0.75, 0.0, 1.0, 0.12), TEAL, 0.5)
    A.text((0.76, 0.15, 0.99, 0.85), [(title, 22, (24, 24, 26), 800), (sub, 16, (60, 60, 64), 600)])
    # a folded hank: several flat strand bundles with tapered ends, side by side
    parts = []
    for k in range(5):
        off = (k - 2) * 0.0055
        pts, rr = [], []
        for t in np.linspace(0, 1, 26):
            y = -0.16 + 0.32 * t
            pts.append((off + 0.0012 * math.sin(t * 9 + k), y, 0.0009 * math.sin(t * 13 + k * 2)))
            taper = min(1.0, t / 0.08, (1 - t) / 0.08)
            rr.append(0.0034 * (0.25 + 0.75 * taper))
        parts.append(sweep(pts, rr, 12, hr, flat=0.55))
    band = rbar(-0.035, 0.035, 0.0175, 0.0175, 0.0042, 0.0042, pb, n=4.5, segs=28, steps=4)
    return (name, merge(parts + [band]), A, 25.0)


# ═════════════════════════════════════════════════════════════════════════════════════
# HEAD PIECES (model axes from SKEL_Head, like hairkit's hair)

# SKEL_Head's freemode rest pose (rows, columns = the bone's axes in the model) and the model's facing:
# GTA's ped models face -Y, so the head frame used below (x right, y face, z up) turns round first
HEAD_REST = np.array([[-0.000001, 0.000026, 1.0], [0.008806, -0.999961, 0.000026], [0.999961, 0.008806, 0.000001]])
TO_MODEL = np.diag([-1.0, -1.0, 1.0])


def to_bone(part):
    """A piece built in the head frame -> the head bone's own space (attach at 0 / 0)."""
    M = HEAD_REST.T @ TO_MODEL
    return Part(part.P @ M.T, part.N @ M.T, part.UV, part.T)


HEAD_C = (0.0, 0.015, 0.055)          # the head centre from the bone (client/salon.lua CENTRE)
HEAD_R = (0.098, 0.116, 0.126)        # the scalp (a touch inside the cutting ellipsoid, which sits on the hair)


def hair_el(az):
    a = abs(((az + 180) % 360) - 180)
    HL = [(0, 36), (45, 24), (75, 6), (95, -10), (135, -26), (180, -36)]
    for (a0, e0), (a1, e1) in zip(HL, HL[1:]):
        if a <= a1:
            return e0 + (e1 - e0) * (a - a0) / (a1 - a0)
    return -36


def cap_on():
    """The mesh wig cap, fitted over the cornrows: a dome from the crown down to the hairline, elastic edge."""
    A = Atlas()
    net = A.region(0.0, 0.0, 1.0, 0.85, (34, 26, 22), 0.2, 'mesh', 6, seed=131, scale=0.9)
    edge = A.region(0.0, 0.85, 1.0, 1.0, (22, 18, 16), 0.15, 'ribs', 3, seed=132, scale=0.5)
    rings, segs = 22, 64
    P, N, UV, T = [], [], [], []
    for i in range(rings + 1):
        t = i / rings
        for j in range(segs + 1):
            az = 360.0 * j / segs
            el0 = hair_el(az) - 3.0
            el = 90.0 - (90.0 - el0) * t
            e, a = math.radians(el), math.radians(az)
            u = np.array([math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)])
            k = 1.035   # over the cornrows
            p = np.array(HEAD_C) + u * np.array(HEAD_R) * k
            n = u / np.array(HEAD_R); n = n / np.linalg.norm(n)
            P.append(p); N.append(n); UV.append((j / segs, 0.85 * t))
    for i in range(rings):
        for j in range(segs):
            a, b_, c, d = i * (segs + 1) + j, i * (segs + 1) + j + 1, (i + 1) * (segs + 1) + j, (i + 1) * (segs + 1) + j + 1
            T += [(a, b_, c), (b_, d, c)]
    dome = Part(np.array(P), np.array(N), np.array(UV), np.array(T))
    # the elastic band round the edge
    ep = []
    for j in range(segs + 1):
        az = 360.0 * j / segs
        e, a = math.radians(hair_el(az) - 3.0), math.radians(az)
        u = np.array([math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)])
        ep.append(np.array(HEAD_C) + u * np.array(HEAD_R) * 1.045)
    band = sweep(ep, 0.0028, 8, edge, caps=False, flat=0.5)
    return ('nz_sty_capon', to_bone(merge([dome, dome.flipped(0.0006), band])), A, 30.0)


def clip():
    """A duckbill sectioning clip (lies on the head, jaws along +Y)."""
    A = Atlas()
    met = A.region(0.0, 0.0, 0.6, 1.0, (190, 194, 200), 0.95, 'brushed', 6, seed=141)
    tab = A.region(0.6, 0.0, 1.0, 1.0, TEAL, 0.5, 'ribs', 3, seed=142, scale=0.6)
    jaws = []
    for s in (1, -1):
        jaws.append(rbar(-0.006, 0.072, 0.0035, 0.0018, 0.0006, 0.0005, met, n=4.0, segs=14, steps=10, cz=s * 0.0012, bow=s * 0.0008))
    spring = sweep([(0.0, 0.0, 0.0), (0.0, -0.004, 0.003), (0.0, -0.006, 0.0)], 0.0007, 8, met)
    tabs = [rbar(-0.022, -0.006, 0.004, 0.0035, 0.0012, 0.0012, tab, n=3.0, segs=14, steps=3, cz=s * 0.004) for s in (1, -1)]
    return ('nz_sty_clip', merge(jaws + [spring] + tabs), A, 15.0)


def pin():
    """A bobby pin: one straight leg, one wavy."""
    A = Atlas()
    m = A.region(0.0, 0.0, 1.0, 1.0, (24, 22, 22), 0.6, 'plain', 3, seed=151)
    a = [(0.0012 * math.sin(t * 25), 0.05 * t, 0.0) for t in np.linspace(0, 1, 40)]
    b_ = [(0.003, 0.048 * t, 0.0) for t in np.linspace(0, 1, 8)]
    bend = [(0.0015 + 0.0015 * math.cos(x), -0.0015 * math.sin(x), 0.0) for x in np.linspace(math.pi, 2 * math.pi, 8)]
    wire = sweep(list(reversed(a)) + bend[1:-1] + b_, 0.00045, 6, m, flat=0.6)
    tips = [ball(0.0007, m, 8, 5, at=a[-1]), ball(0.0007, m, 8, 5, at=b_[-1])]
    return ('nz_sty_pin', merge([wire] + tips), A, 10.0)


PROPS = [comb, brush, edge_brush, needle, hook, flat_iron, wand, dryer, gel, tin, mousse, spray, heat, moist, pack, cap_on, clip, pin]
