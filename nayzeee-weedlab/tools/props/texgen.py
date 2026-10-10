"""
Procedural textures for the nayzeee-weedlab props.

Every material gets a diffuse (_d), a normal map (_n) and a specular map (_s). Tiling
materials are made from periodic (FFT filtered) noise, so they repeat without seams.
Labels and panels are painted with Pillow.

    python texgen.py <out dir>

Writes:
    <out>/png/<name>.png                 previews / Blender renders
    <out>/ytd/nzw_weedlab/<name>.dds     DXT1 / DXT5 with a full mip chain (CodeWalker reads these)
    <out>/textures.json                  name -> { format, alpha }
"""
import io
import json
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out")
PNG = os.path.join(OUT, "png")
DDS = os.path.join(OUT, "ytd", "nzw_weedlab")
os.makedirs(PNG, exist_ok=True)
os.makedirs(DDS, exist_ok=True)

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIRS = [os.path.join(HERE, "fonts"), "/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/crosextra"]
MANIFEST = {}


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    print("WARN font missing:", name)
    return ImageFont.load_default()


BOLD = "DejaVuSans-Bold.ttf"
REG = "DejaVuSans.ttf"
COND = "Carlito-Bold.ttf"

# ─────────────────────────── noise ───────────────────────────
RNG = np.random.default_rng(1337)


def pnoise(n, beta=2.0, seed=None, aniso=(1.0, 1.0)):
    """Periodic 1/f^beta noise (tiles perfectly). aniso stretches frequencies on (x, y)."""
    rng = np.random.default_rng(seed) if seed is not None else RNG
    white = rng.standard_normal((n, n))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    f = f / k ** (beta / 2.0)
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def band(n, lo, hi, seed=None):
    """Periodic band-limited noise between frequencies lo..hi (cycles per tile)."""
    rng = np.random.default_rng(seed) if seed is not None else RNG
    f = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    k = np.sqrt(fx * fx + fy * fy)
    f[(k < lo) | (k > hi)] = 0
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def voronoi(n, count, seed=0):
    """Periodic voronoi: (distance to nearest, distance to second, cell id)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2)) * n
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    d1 = np.full((n, n), 1e9, np.float32)
    d2 = np.full((n, n), 1e9, np.float32)
    cid = np.zeros((n, n), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, n - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        cid = np.where(closer, i, cid)
        d1 = np.where(closer, d, d1)
    return d1, d2, cid


def dots(n, count, rmin, rmax, seed=0):
    """Periodic soft dots mask 0..1."""
    rng = np.random.default_rng(seed)
    m = np.zeros((n, n), np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    for _ in range(count):
        px, py, r = rng.random() * n, rng.random() * n, rmin + rng.random() * (rmax - rmin)
        x0, x1 = int(px - r - 2), int(px + r + 3)
        y0, y1 = int(py - r - 2), int(py + r + 3)
        for yy0 in range(y0, y1):
            for xx0 in range(x0, x1):
                d = math.hypot(xx0 - px, yy0 - py)
                if d < r + 1:
                    v = max(0.0, min(1.0, r + 0.5 - d))
                    m[yy0 % n, xx0 % n] = max(m[yy0 % n, xx0 % n], v)
    return m


def strands(n, count, length, seed=0, width=1.0):
    """Short curly strands (pistils / hairs) as a 0..1 mask."""
    rng = np.random.default_rng(seed)
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.random() * n, rng.random() * n
        a = rng.random() * math.tau
        pts = [(x, y)]
        L = length * (0.5 + rng.random())
        for _ in range(6):
            a += (rng.random() - 0.5) * 1.4
            x += math.cos(a) * L / 6
            y += math.sin(a) * L / 6
            pts.append((x, y))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                d.line([(p[0] + ox, p[1] + oy) for p in pts], fill=255, width=max(1, int(width)))
    return np.asarray(img, np.float32) / 255.0


def lerp(a, b, t):
    a, b = np.asarray(a, np.float32), np.asarray(b, np.float32)
    t = np.asarray(t, np.float32)[..., None] if np.ndim(t) == 2 else t
    return a + (b - a) * t


def rgb(h, c0, c1):
    return np.clip(lerp(c0, c1, h), 0, 255)


def normal_from_height(h, strength=2.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx, ny, nz = -dx / l, dy / l, nz / l
    return np.stack([(nx * 0.5 + 0.5) * 255, (ny * 0.5 + 0.5) * 255, (nz * 0.5 + 0.5) * 255], -1)


def flat_normal(n=8):
    return np.full((n, n, 3), (128, 128, 255), np.float32)


# ─────────────────────────── output ───────────────────────────
def _dds_level(img, fmt):
    b = io.BytesIO()
    img.save(b, "DDS", pixel_format=fmt)
    return b.getvalue()[128:]


def write_dds(path, img, fmt):
    """DXT1 (RGB) or DXT5 (RGBA) with every mip level down to 4x4."""
    mode = "RGBA" if fmt == "DXT5" else "RGB"
    img = img.convert(mode)
    w, h = img.size
    levels, cur = [], img
    while True:
        levels.append(_dds_level(cur, fmt))
        if cur.size[0] <= 4 or cur.size[1] <= 4:
            break
        cur = cur.resize((max(4, cur.size[0] // 2), max(4, cur.size[1] // 2)), Image.LANCZOS)
    block = 8 if fmt == "DXT1" else 16
    header = struct.pack(
        "<4sIIIIIII44sII4sIIIIIIIIII",
        b"DDS ", 124, 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000, h, w, max(1, w // 4) * max(1, h // 4) * block, 0, len(levels),
        b"\0" * 44,
        32, 0x4, fmt.encode(), 0, 0, 0, 0, 0,
        0x1000 | 0x8 | 0x400000, 0, 0, 0, 0,
    )
    with open(path, "wb") as f:
        f.write(header + b"".join(levels))


def save(name, arr, alpha=None):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    if alpha is not None:
        al = np.clip(alpha, 0, 255).astype(np.uint8)
        img = Image.fromarray(np.dstack([a, al]), "RGBA")
        fmt = "DXT5"
    else:
        img = Image.fromarray(a, "RGB")
        fmt = "DXT1"
    img.save(os.path.join(PNG, name + ".png"))
    write_dds(os.path.join(DDS, name + ".dds"), img, fmt)
    MANIFEST[name] = {"format": "D3DFMT_" + fmt, "alpha": alpha is not None, "size": img.size}


def material(name, diffuse, height=None, spec=1.0, strength=2.0, alpha=None):
    """spec: float 0..1 or array; height drives the normal map."""
    save(name + "_d", diffuse, alpha)
    save(name + "_n", normal_from_height(height, strength) if height is not None else flat_normal(8))
    s = np.asarray(spec, np.float32)
    if s.ndim == 0:
        s = np.full((8, 8), float(s), np.float32)
    elif s.shape[0] > 256:
        s = s[::2, ::2]
    save(name + "_s", np.repeat((np.clip(s, 0, 1) * 255)[..., None], 3, -1))


N = 512

# ─────────────────────────── metals ───────────────────────────
def m_steel_brushed():
    streak = pnoise(N, 1.4, 11, aniso=(0.02, 1.0))
    fine = band(N, 60, 220, 12)
    blot = pnoise(N, 3.0, 13)
    h = streak * 0.7 + fine * 0.3
    base = 168 + (h - 0.5) * 34 + (blot - 0.5) * 18
    col = np.stack([base * 0.98, base * 1.0, base * 1.03], -1)
    material("nzw_steel", col, h, 0.55 + streak * 0.35, 1.2)


def m_powder(name, c, spec=0.32, seed=20, wear_amt=0.6):
    peel = band(N, 70, 200, seed)
    blot = pnoise(N, 2.6, seed + 1) * 0.5 + 0.25
    wear = (pnoise(N, 2.2, seed + 2) > 0.9).astype(np.float32) * wear_amt
    base = np.array(c, np.float32)
    col = base[None, None, :] * (0.92 + peel[..., None] * 0.12 + (blot[..., None] - 0.5) * 0.10)
    col = col + wear[..., None] * 18
    material(name, col, peel * 0.6 + blot * 0.4, spec * (0.8 + peel * 0.4), 1.6)


def m_galv():
    d1, d2, cid = voronoi(N, 70, 31)
    shade = (cid * 0.6180339 % 1.0)
    edge = np.clip((d2 - d1) / 3.0, 0, 1)
    noise = pnoise(N, 2.2, 32)
    base = 152 + (shade - 0.5) * 14 + (noise - 0.5) * 14 - (1 - edge) * 6
    col = np.stack([base * 0.97, base, base * 1.02], -1)
    material("nzw_galv", col, shade * 0.4 + edge * 0.3, 0.45 + shade * 0.3, 1.0)


def m_alu_dark():
    streak = pnoise(N, 1.4, 41, aniso=(0.03, 1.0))
    base = 52 + (streak - 0.5) * 12
    col = np.stack([base, base * 1.02, base * 1.06], -1)
    material("nzw_alu", col, streak, 0.5, 0.8)


def m_reflector():
    d1, d2, _ = voronoi(N, 140, 51)
    dimple = np.clip(d1 / 22.0, 0, 1)
    base = 205 + (dimple - 0.5) * 40
    col = np.stack([base, base, base * 1.01], -1)
    material("nzw_reflector", col, dimple, 0.95, 4.0)


def m_chrome():
    n = pnoise(N, 1.2, 61, aniso=(0.04, 1.0))
    base = 214 + (n - 0.5) * 16
    material("nzw_chrome", np.stack([base, base, base * 1.02], -1), None, 0.95)


# ─────────────────────────── soft goods ───────────────────────────
def m_fabric(name, c, seed=70):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    per = N / 128.0  # 128 threads per tile
    wx = np.sin(xx / per * math.pi) ** 2
    wy = np.sin(yy / per * math.pi) ** 2
    checker = ((np.floor(xx / per) + np.floor(yy / per)) % 2)
    weave = np.where(checker > 0, wx, wy)
    slub = pnoise(N, 2.0, seed)
    h = weave * 0.7 + slub * 0.3
    base = np.array(c, np.float32)
    col = base[None, None, :] * (0.78 + weave[..., None] * 0.3 + (slub[..., None] - 0.5) * 0.18)
    material(name, col, h, 0.08 + weave * 0.06, 2.2)


def m_mylar():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    k = 2 * math.pi / N * 12
    diamond = np.abs(np.sin((xx + yy) * k * 0.5)) * np.abs(np.sin((xx - yy) * k * 0.5))
    crinkle = pnoise(N, 1.8, 81)
    h = diamond * 0.6 + crinkle * 0.4
    base = 196 + (h - 0.5) * 70
    col = np.stack([base, base * 1.01, base * 1.03], -1)
    material("nzw_mylar", col, h, 0.85 + h * 0.15, 3.0)


def m_plastic(name, c, spec=0.4, rough=0.05, seed=90):
    g = band(N, 90, 240, seed)
    blot = pnoise(N, 2.8, seed + 1)
    base = np.array(c, np.float32)
    col = base[None, None, :] * (0.96 + g[..., None] * 0.05 + (blot[..., None] - 0.5) * 0.06)
    material(name, col, g * rough * 10, spec, 0.6)


def m_rubber():
    g = band(N, 60, 200, 101)
    col = np.full((N, N, 3), 20, np.float32) + (g[..., None] - 0.5) * 8
    material("nzw_rubber", col, g, 0.05, 1.5)


def m_wood():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    warp = pnoise(N, 2.6, 111) * 60 + pnoise(N, 1.6, 112, aniso=(0.05, 1.0)) * 10
    rings = (np.sin((yy + warp) / N * math.pi * 2 * 22) * 0.5 + 0.5) ** 2.5
    fibre = pnoise(N, 1.2, 113, aniso=(0.02, 1.0))
    h = rings * 0.5 + fibre * 0.5
    col = rgb(h, (150, 105, 62), (214, 176, 124))
    material("nzw_wood", col, h, 0.12 + rings * 0.06, 1.4)


def m_twine():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    twist = np.sin((xx * 0.6 + yy) / N * math.pi * 2 * 40) * 0.5 + 0.5
    fuzz = band(N, 100, 250, 121)
    h = twist * 0.7 + fuzz * 0.3
    material("nzw_twine", rgb(h, (178, 160, 122), (226, 212, 176)), h, 0.06, 2.0)


# ─────────────────────────── grow ───────────────────────────
def m_soil():
    d1, d2, cid = voronoi(N, 420, 131)
    clump = np.clip(d1 / 9.0, 0, 1)
    shade = (cid * 0.381966 % 1.0)
    big = pnoise(N, 2.6, 132)
    perlite = dots(N, 160, 1.6, 4.0, 133)
    bark = (band(N, 20, 60, 134) > 0.72).astype(np.float32)
    h = (1 - clump) * 0.6 + big * 0.3 + perlite * 0.6
    col = rgb(shade * 0.6 + big * 0.4, (34, 24, 17), (78, 56, 38))
    col = lerp(col, (96, 62, 36), bark * 0.5)
    col = lerp(col, (226, 224, 214), perlite)
    material("nzw_soil", col, h, 0.12 + perlite * 0.2, 4.0)


def m_bud(name, calyx_lo, calyx_hi, pistil, seed):
    d1, d2, cid = voronoi(N, 260, seed)
    cell = np.clip(d1 / 14.0, 0, 1)
    shade = (cid * 0.6180339 % 1.0)
    leaf = pnoise(N, 2.2, seed + 1)
    hairs = strands(N, 420, 26, seed + 2, 2)
    frost = dots(N, 2600, 0.6, 1.5, seed + 3)
    h = (1 - cell) * 0.7 + leaf * 0.3
    col = rgb(shade * 0.5 + leaf * 0.5 - cell * 0.2, calyx_lo, calyx_hi)
    col = lerp(col, pistil, np.clip(hairs, 0, 1) * 0.9)
    col = lerp(col, (236, 240, 232), frost * 0.75)
    material(name, col, h + hairs * 0.3 + frost * 0.2, 0.18 + frost * 0.5, 3.0)


def m_leaf():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    vein = np.abs(np.sin((xx + yy * 0.3) / N * math.pi * 2 * 6))
    n = pnoise(N, 2.2, 141)
    h = (1 - vein) * 0.3 + n * 0.7
    material("nzw_leaf", rgb(n * 0.7 + vein * 0.3, (36, 70, 28), (88, 132, 52)), h, 0.2, 1.4)


def m_compressed():
    """pressed weed for the brick"""
    fine = band(N, 80, 250, 151)
    n = pnoise(N, 2.0, 152)
    hairs = strands(N, 700, 10, 153, 1)
    h = fine * 0.6 + n * 0.4
    col = rgb(h, (60, 70, 34), (112, 122, 56))
    col = lerp(col, (176, 104, 44), hairs * 0.6)
    material("nzw_compressed", col, h, 0.25, 2.0)


def m_seed():
    n = pnoise(N, 1.6, 161, aniso=(0.25, 1.0))
    tiger = (np.sin(np.mgrid[0:N, 0:N][1] / N * math.pi * 2 * 18 + n * 8) > 0.3).astype(np.float32)
    col = rgb(n, (88, 66, 46), (150, 122, 92))
    col = lerp(col, (48, 34, 24), tiger * 0.7)
    material("nzw_seed", col, n * 0.5 + tiger * 0.3, 0.35, 1.0)


# ─────────────────────────── packaging ───────────────────────────
def m_glass():
    n = pnoise(N, 3.0, 171)
    col = np.stack([200 + n * 20, 222 + n * 16, 222 + n * 16], -1)
    alpha = 46 + n * 20
    material("nzw_glass", col, None, 0.95, alpha=alpha)


def m_bagplastic():
    n = pnoise(N, 2.0, 181)
    wr = band(N, 6, 24, 182)
    col = np.full((N, N, 3), 236, np.float32) + (n[..., None] - 0.5) * 12
    alpha = 34 + wr * 40
    material("nzw_bag", col, None, 0.8 + wr * 0.2, alpha=alpha)


def m_cling():
    n = band(N, 4, 30, 191)
    col = np.full((N, N, 3), 240, np.float32)
    material("nzw_cling", col, None, 0.9, alpha=40 + n * 60)


def m_tape():
    n = pnoise(N, 2.0, 201)
    stretch = pnoise(N, 1.4, 202, aniso=(1.0, 0.05))
    col = rgb(n * 0.5 + stretch * 0.5, (140, 96, 44), (190, 140, 74))
    material("nzw_tape", col, stretch, 0.75, 0.8)


def m_cutmat():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cell = N / 25.0  # tile = 25 cm, 1 cm grid
    fx, fy = (xx % cell), (yy % cell)
    minor = ((fx < 1.4) | (fy < 1.4)).astype(np.float32)
    major = (((xx % (cell * 5)) < 2.2) | ((yy % (cell * 5)) < 2.2)).astype(np.float32)
    n = pnoise(N, 2.4, 211)
    cuts = strands(N, 30, 120, 212, 1) * 0.5
    col = rgb(n, (22, 84, 64), (34, 104, 80))
    col = lerp(col, (182, 214, 196), np.clip(minor * 0.45 + major * 0.75, 0, 1))
    col = lerp(col, (16, 60, 46), cuts)
    material("nzw_cutmat", col, n * 0.4 + cuts, 0.12, 1.2)


# ─────────────────────────── lights ───────────────────────────
def m_led(name, pcb, led_colors, seed, pitch=16):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cx, cy = (xx % pitch) - pitch / 2, (yy % pitch) - pitch / 2
    r = np.sqrt(cx * cx + cy * cy)
    led = np.clip(1.0 - (r - 3.2) / 1.5, 0, 1)
    pick = ((np.floor(xx / pitch) * 7 + np.floor(yy / pitch) * 13) % len(led_colors)).astype(int)
    lc = np.array(led_colors, np.float32)[pick]
    trace = ((np.abs(cy) < 0.7) & (np.abs(cx) > 5)).astype(np.float32) * 0.4
    base = np.array(pcb, np.float32)[None, None, :] * (0.9 + pnoise(N, 2.4, seed)[..., None] * 0.2)
    base = base + trace[..., None] * 30
    col = base * (1 - led[..., None]) + lc * led[..., None]
    save(name + "_d", col)


def m_halogen_glow():
    yy, xx = np.mgrid[0:256, 0:256].astype(np.float32)
    g = np.exp(-((yy - 128) / 70) ** 2)
    col = np.stack([255 * np.ones_like(g), 200 + g * 55, 120 + g * 120], -1)
    save("nzw_halogen_glow_d", col)


def m_solid(name, c, spec=0.3):
    col = np.full((32, 32, 3), c, np.float32)
    material(name, col, None, spec)


# ─────────────────────────── labels (non-tiling) ───────────────────────────
def label_canvas(w, h, bg):
    img = Image.new("RGB", (w, h), bg)
    return img, ImageDraw.Draw(img)


def centered(d, w, y, text, f, fill):
    tw = d.textlength(text, font=f)
    d.text(((w - tw) / 2, y), text, font=f, fill=fill)


def leaf_icon(d, cx, cy, s, fill):
    """seven-blade leaf"""
    for i, (ang, ln) in enumerate([(-90, 1.0), (-55, 0.82), (-125, 0.82), (-25, 0.6), (-155, 0.6), (10, 0.38), (-190, 0.38)]):
        a = math.radians(ang)
        tip = (cx + math.cos(a) * s * ln, cy + math.sin(a) * s * ln)
        side = math.radians(ang + 90)
        w = s * 0.12 * ln
        pts = [(cx, cy), (cx + math.cos(a) * s * ln * 0.5 + math.cos(side) * w, cy + math.sin(a) * s * ln * 0.5 + math.sin(side) * w), tip,
               (cx + math.cos(a) * s * ln * 0.5 - math.cos(side) * w, cy + math.sin(a) * s * ln * 0.5 - math.sin(side) * w)]
        d.polygon(pts, fill=fill)
    d.line([(cx, cy), (cx, cy + s * 0.35)], fill=fill, width=max(2, int(s * 0.05)))


def grunge(img, amount=0.08, seed=0):
    a = np.asarray(img, np.float32)
    n = pnoise(max(a.shape[0], a.shape[1]), 2.2, seed)[: a.shape[0], : a.shape[1]]
    a = a * (1 - amount + n[..., None] * amount * 2)
    return np.clip(a, 0, 255)


def label_soilbag():
    w, h = 512, 512
    img, d = label_canvas(w, h, (28, 22, 18))
    d.rectangle([0, 0, w, 120], fill=(46, 120, 52))
    d.rectangle([0, 112, w, 120], fill=(232, 196, 64))
    centered(d, w, 22, "GREENROOT", font(BOLD, 56), (250, 250, 240))
    centered(d, w, 84, "PREMIUM POTTING MIX", font(BOLD, 22), (232, 196, 64))
    leaf_icon(d, w / 2, 270, 110, (82, 168, 70))
    centered(d, w, 360, "ORGANIC  ·  PERLITE  ·  COCO", font(REG, 20), (220, 210, 190))
    d.rounded_rectangle([140, 400, 372, 470], 10, fill=(232, 196, 64))
    centered(d, w, 410, "25 L", font(BOLD, 44), (28, 22, 18))
    save("nzw_lbl_soil_d", grunge(img, 0.1, 301))


def label_bottle(name, title, sub, bg, accent, ink, note):
    w, h = 512, 256
    img, d = label_canvas(w, h, bg)
    d.rectangle([0, 0, w, 10], fill=accent)
    d.rectangle([0, h - 10, w, h], fill=accent)
    d.text((24, 26), title, font=font(BOLD, 54), fill=ink)
    d.text((26, 92), sub, font=font(BOLD, 20), fill=accent)
    d.multiline_text((26, 128), note, font=font(REG, 15), fill=ink, spacing=4)
    leaf_icon(d, 430, 140, 70, accent)
    d.rectangle([380, 196, 492, 230], outline=ink, width=2)
    d.text((392, 202), "1 L / 33.8oz", font=font(REG, 14), fill=ink)
    save(name + "_d", grunge(img, 0.06, hash(name) % 1000))


def label_led_brand(name, text, sub, bg, fg):
    w, h = 256, 64
    img, d = label_canvas(w, h, bg)
    d.text((12, 6), text, font=font(BOLD, 30), fill=fg)
    d.text((14, 40), sub, font=font(REG, 13), fill=(160, 166, 170))
    save(name + "_d", np.asarray(img, np.float32))


def panel_mixer():
    w, h = 512, 256
    img, d = label_canvas(w, h, (36, 40, 44))
    d.rounded_rectangle([14, 14, w - 14, h - 14], 12, outline=(80, 86, 92), width=3)
    d.rounded_rectangle([34, 40, 250, 120], 6, fill=(10, 18, 14))
    d.text((48, 52), "MIX  00:06", font=font("DejaVuSansMono-Bold.ttf", 34), fill=(70, 230, 140))
    d.text((48, 96), "RPM 240   LOAD OK", font=font("DejaVuSansMono.ttf", 14), fill=(60, 170, 110))
    for i, (c, t) in enumerate([((40, 190, 90), "START"), ((210, 50, 50), "STOP")]):
        cx = 330 + i * 100
        d.ellipse([cx - 34, 46, cx + 34, 114], fill=(20, 20, 22))
        d.ellipse([cx - 28, 52, cx + 28, 108], fill=c)
        centered_x = cx - d.textlength(t, font=font(BOLD, 16)) / 2
        d.text((centered_x, 122), t, font=font(BOLD, 16), fill=(220, 224, 226))
    d.text((34, 170), "NZ INDUSTRIAL  ·  MX-200 MIXING UNIT", font=font(BOLD, 18), fill=(200, 204, 206))
    d.text((34, 200), "Keep hands clear of the bowl while running", font=font(REG, 14), fill=(150, 156, 160))
    save("nzw_panel_mixer_d", np.asarray(img, np.float32))


def panel_press():
    w, h = 512, 256
    img, d = label_canvas(w, h, (230, 190, 30))
    stripe = 40
    for x in range(-h, w + h, stripe * 2):
        d.polygon([(x, 0), (x + stripe, 0), (x + stripe - h, h), (x - h, h)], fill=(22, 22, 22))
    d.rectangle([40, 60, w - 40, h - 60], fill=(230, 190, 30))
    d.rectangle([44, 64, w - 44, h - 64], outline=(22, 22, 22), width=4)
    centered(d, w, 82, "DANGER", font(BOLD, 52), (22, 22, 22))
    centered(d, w, 142, "CRUSH HAZARD · 20 TON", font(BOLD, 20), (22, 22, 22))
    save("nzw_panel_press_d", grunge(img, 0.12, 411))


def label_brick():
    w, h = 256, 128
    img, d = label_canvas(w, h, (178, 132, 70))
    d.text((20, 18), "NZ", font=font(BOLD, 64), fill=(24, 24, 24))
    d.text((128, 30), "1 KG", font=font(BOLD, 30), fill=(24, 24, 24))
    d.line([(128, 74), (232, 74)], fill=(24, 24, 24), width=4)
    save("nzw_lbl_brick_d", grunge(img, 0.15, 421))


def label_tent():
    w, h = 512, 128
    img, d = label_canvas(w, h, (24, 26, 25))
    d.polygon([(26, 30), (82, 30), (82, 66), (64, 84), (26, 84)], fill=(8, 175, 162))
    d.rectangle([38, 44, 70, 54], fill=(0, 0, 0))
    d.text((100, 26), "NAYZEEE GROW", font=font(BOLD, 40), fill=(240, 242, 242))
    d.text((102, 76), "HYDRO TENT  80 x 80 x 160", font=font(REG, 18), fill=(8, 175, 162))
    save("nzw_lbl_tent_d", grunge(img, 0.06, 431))


def label_jar():
    w, h = 256, 128
    img, d = label_canvas(w, h, (244, 240, 230))
    d.rectangle([0, 0, w, 22], fill=(8, 175, 162))
    centered(d, w, 34, "PREMIUM", font(BOLD, 30), (24, 26, 25))
    centered(d, w, 76, "INDOOR · HAND TRIMMED", font(REG, 13), (80, 84, 86))
    save("nzw_lbl_jar_d", grunge(img, 0.05, 441))


def label_seedvial():
    w, h = 256, 128
    img, d = label_canvas(w, h, (250, 250, 246))
    d.rectangle([0, 0, 12, h], fill=(46, 120, 52))
    d.text((24, 16), "FEMINIZED", font=font(BOLD, 26), fill=(30, 30, 30))
    d.text((24, 52), "x3 SEEDS", font=font(BOLD, 22), fill=(46, 120, 52))
    d.text((24, 86), "Lot 0194 · Benson", font=font(REG, 14), fill=(110, 110, 110))
    save("nzw_lbl_seeds_d", np.asarray(img, np.float32))


def write_manifest():
    with open(os.path.join(OUT, "textures.json"), "w") as f:
        json.dump(MANIFEST, f, indent=1)


if __name__ == "__main__":
    m_steel_brushed()
    m_powder("nzw_black", (30, 31, 33), 0.3, 20)
    m_powder("nzw_red", (150, 24, 22), 0.4, 24)
    m_powder("nzw_white", (226, 228, 228), 0.35, 28, 0.0)
    m_powder("nzw_teal", (8, 150, 140), 0.4, 33)
    m_galv()
    m_alu_dark()
    m_reflector()
    m_chrome()
    m_fabric("nzw_fabric", (27, 28, 28), 70)
    m_fabric("nzw_fabric_teal", (10, 160, 148), 75)
    m_mylar()
    m_plastic("nzw_pblack", (26, 27, 28), 0.35, 0.06, 90)
    m_plastic("nzw_pwhite", (232, 233, 230), 0.4, 0.04, 92)
    m_plastic("nzw_pgreen", (40, 150, 70), 0.45, 0.04, 94)
    m_plastic("nzw_porange", (230, 110, 24), 0.45, 0.04, 96)
    m_plastic("nzw_pblue", (40, 96, 200), 0.45, 0.04, 98)
    m_rubber()
    m_wood()
    m_twine()
    m_soil()
    m_bud("nzw_bud_green", (46, 86, 32), (122, 168, 70), (206, 110, 40), 500)
    m_bud("nzw_bud_purple", (52, 34, 70), (128, 92, 150), (226, 136, 52), 510)
    m_bud("nzw_bud_lime", (92, 140, 34), (178, 214, 86), (232, 150, 60), 520)
    m_bud("nzw_bud_golden", (110, 104, 40), (196, 180, 92), (196, 84, 30), 530)
    m_leaf()
    m_compressed()
    m_seed()
    m_glass()
    m_bagplastic()
    m_cling()
    m_tape()
    m_cutmat()
    m_led("nzw_led_purple", (22, 24, 26), [(255, 40, 120), (255, 60, 90), (120, 70, 255), (255, 50, 140)], 600)
    m_led("nzw_led_white", (232, 232, 226), [(255, 236, 200), (255, 226, 180), (255, 120, 90), (255, 240, 214)], 610, 22)
    m_halogen_glow()
    m_solid("nzw_btn_green", (40, 190, 90), 0.6)
    m_solid("nzw_btn_red", (210, 40, 40), 0.6)
    m_solid("nzw_brass", (184, 148, 70), 0.8)
    m_solid("nzw_dark", (12, 12, 13), 0.1)
    label_soilbag()
    label_bottle("nzw_lbl_pgr", "PGR-X", "PLANT GROWTH REGULATOR", (238, 236, 228), (196, 60, 40), (30, 30, 30),
                 "Boosts yield. Shake well.\nMay lower bud quality.\nKeep out of reach of kids.")
    label_bottle("nzw_lbl_speed", "RAPID-GRO", "SPEED GROWTH FORMULA", (24, 26, 30), (240, 196, 40), (240, 240, 236),
                 "+50% growth instantly.\nFor fast cycles only.\nQuality may suffer.")
    label_bottle("nzw_lbl_fert", "GROWMAX", "LIQUID FERTILIZER 4-4-4", (232, 244, 232), (46, 140, 64), (20, 40, 24),
                 "Spray on leaves and soil.\nRaises bud quality.\nUse once per plant.")
    label_led_brand("nzw_lbl_led", "SPECTRA-X", "PURPLE SERIES 400W", (20, 22, 24), (190, 90, 255))
    label_led_brand("nzw_lbl_fullspec", "SOLARIS PRO", "FULL SPECTRUM 650W", (234, 234, 230), (200, 150, 40))
    label_led_brand("nzw_lbl_halogen", "HALO 250", "METAL HALIDE / HPS", (40, 42, 44), (240, 170, 40))
    panel_mixer()
    panel_press()
    label_brick()
    label_tent()
    label_jar()
    label_seedvial()
    write_manifest()
    print("textures:", len(MANIFEST))
