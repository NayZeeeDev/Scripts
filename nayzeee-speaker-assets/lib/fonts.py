"""Lexend font access for textures (Pillow) and 3D lettering (traced text outlines).

The UI font lives in the resource (``nayzeee-speaker/html/fonts/lexend.woff2``,
a variable font, wght 100..900).  ``fontTools`` (+ ``brotli`` for WOFF2) turns
it into static TTF instances cached in ``nayzeee-speaker-assets/cache/fonts``.

    pil_font(48, weight=600)                    -> PIL.ImageFont for drawing
    text_polygons("nayzeee", 0.02, weight=700)  -> [(outer, [holes]), ...] in metres
    text_width("nayzeee", 0.02, weight=700)     -> advance width in metres
"""
from __future__ import annotations

import os
from functools import lru_cache

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_CANDIDATES = [
    os.path.join(ROOT, "fonts", "lexend.woff2"),
    os.path.join(os.path.dirname(ROOT), "nayzeee-speaker", "html", "fonts", "lexend.woff2"),
]
CACHE_DIR = os.path.join(ROOT, "cache", "fonts")


def source_path() -> str:
    for p in FONT_CANDIDATES:
        if os.path.isfile(p):
            return p
    raise FileNotFoundError("lexend.woff2 not found; looked in: " + ", ".join(FONT_CANDIDATES))


@lru_cache(maxsize=None)
def ttf_path(weight: int = 400) -> str:
    """Path of a static Lexend TTF at ``weight`` (100..900), created on first use."""
    weight = int(min(max(weight, 100), 900))
    os.makedirs(CACHE_DIR, exist_ok=True)
    out = os.path.join(CACHE_DIR, f"lexend-{weight}.ttf")
    if os.path.isfile(out):
        return out
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer
    f = TTFont(source_path())
    f.flavor = None
    if "fvar" in f:
        f = instancer.instantiateVariableFont(f, {"wght": weight}, inplace=False)
    tmp = out + ".tmp"
    f.save(tmp)
    os.replace(tmp, out)
    return out


@lru_cache(maxsize=256)
def pil_font(size_px: int, weight: int = 400):
    """Pillow ImageFont for Lexend at ``size_px`` pixels and ``weight``."""
    from PIL import ImageFont
    return ImageFont.truetype(ttf_path(weight), int(size_px))


@lru_cache(maxsize=None)
def _ttfont(weight: int):
    from fontTools.ttLib import TTFont
    return TTFont(ttf_path(weight))


def _marching_squares(f: np.ndarray, iso: float = 0.5):
    """Closed iso-contours of image ``f`` (rows = y down) as lists of (x, y) arrays."""
    H, W = f.shape
    segs = {}

    def key_h(i, j):   # crossing on the horizontal edge (i,j)-(i,j+1)
        return ("h", i, j)

    def key_v(i, j):   # crossing on the vertical edge (i,j)-(i+1,j)
        return ("v", i, j)

    pts = {}

    def point(k):
        if k in pts:
            return pts[k]
        t, i, j = k
        if t == "h":
            a, b = f[i, j], f[i, j + 1]
            u = (iso - a) / (b - a) if b != a else 0.5
            p = (j + u, float(i))
        else:
            a, b = f[i, j], f[i + 1, j]
            u = (iso - a) / (b - a) if b != a else 0.5
            p = (float(j), i + u)
        pts[k] = p
        return p

    inside = f > iso
    tl, tr = inside[:-1, :-1], inside[:-1, 1:]
    br, bl = inside[1:, 1:], inside[1:, :-1]
    case = tl * 8 + tr * 4 + br * 2 + bl * 1
    ii, jj = np.nonzero((case > 0) & (case < 15))
    for i, j in zip(ii.tolist(), jj.tolist()):
        c = int(case[i, j])
        T, R, B, L = key_h(i, j), key_v(i, j + 1), key_h(i + 1, j), key_v(i, j)
        # segments oriented with the inside on the LEFT (image coords, y down)
        table = {1: [(L, B)], 2: [(B, R)], 3: [(L, R)], 4: [(R, T)], 6: [(B, T)], 7: [(L, T)],
                 8: [(T, L)], 9: [(T, B)], 11: [(T, R)], 12: [(R, L)], 13: [(R, B)], 14: [(B, L)]}
        if c in (5, 10):
            centre = (f[i, j] + f[i, j + 1] + f[i + 1, j] + f[i + 1, j + 1]) / 4 > iso
            if c == 5:
                lst = [(L, T), (R, B)] if centre else [(L, B), (R, T)]
            else:
                lst = [(T, R), (B, L)] if centre else [(T, L), (B, R)]
        else:
            lst = table[c]
        for a, b in lst:
            segs[a] = b
    loops = []
    while segs:
        k0, k1 = segs.popitem()
        loop = [k0, k1]
        while loop[-1] in segs:
            loop.append(segs.pop(loop[-1]))
        if loop[-1] == loop[0]:
            loop.pop()
        if len(loop) >= 3:
            loops.append(np.array([point(k) for k in loop]))
    return loops


def _rdp(pts: np.ndarray, tol: float) -> np.ndarray:
    """Ramer-Douglas-Peucker simplification of a closed loop."""
    if len(pts) < 8:
        return pts
    # split the loop at the two farthest-apart points to simplify two open chains
    i0 = 0
    d = np.linalg.norm(pts - pts[i0], axis=1)
    i1 = int(np.argmax(d))

    def simp(chain):
        keep = np.zeros(len(chain), dtype=bool)
        keep[0] = keep[-1] = True
        stack = [(0, len(chain) - 1)]
        while stack:
            a, b = stack.pop()
            if b <= a + 1:
                continue
            p, q = chain[a], chain[b]
            seg = q - p
            L = np.hypot(*seg)
            mid = chain[a + 1:b]
            if L < 1e-12:
                dist = np.linalg.norm(mid - p, axis=1)
            else:
                dist = np.abs(seg[0] * (mid[:, 1] - p[1]) - seg[1] * (mid[:, 0] - p[0])) / L
            k = int(np.argmax(dist))
            if dist[k] > tol:
                m = a + 1 + k
                keep[m] = True
                stack += [(a, m), (m, b)]
        return chain[keep]

    c1 = simp(pts[i0:i1 + 1])
    c2 = simp(np.vstack([pts[i1:], pts[:1]]))
    return np.vstack([c1[:-1], c2[:-1]])


def _inside(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


def _area(c):
    x, y = c[:, 0], c[:, 1]
    return 0.5 * (np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def text_polygons(text: str, height: float, weight: int = 600, tracking: float = 0.0, align: str = "center",
                  quality: int = 160, tolerance: float = 0.35):
    """Outlines of ``text`` scaled so the cap height == ``height`` metres.

    Returns [(outer (N,2) CCW, [hole (M,2) CW, ...]), ...] with the baseline at
    y = 0, ready for ``mesh.extrude``.  The text is rendered by Pillow (correct
    kerning and overlap handling) at ``quality`` px cap height, traced with
    marching squares and simplified to ``tolerance`` px.  ``tracking`` adds
    spacing in metres between letters; ``align`` = 'left'|'center'|'right'.
    """
    from PIL import Image, ImageDraw
    from fontTools.ttLib import TTFont  # noqa: F401  (ensures fontTools is present)
    font_tt = _ttfont(int(weight))
    upm = font_tt["head"].unitsPerEm
    cap = getattr(font_tt["OS/2"], "sCapHeight", 0) or upm * 0.7
    size_px = int(round(quality * upm / cap))
    pf = pil_font(size_px, int(weight))
    px_per_m = quality / height
    track_px = tracking * px_per_m
    # layout glyph by glyph only when tracking is requested (keeps kerning otherwise)
    asc, desc = pf.getmetrics()
    pad = int(size_px * 0.25) + 4
    if track_px:
        widths = [pf.getlength(ch) for ch in text]
        total = sum(widths) + track_px * max(len(text) - 1, 0)
    else:
        total = pf.getlength(text)
    Wd = int(total + 2 * pad)
    Ht = int(asc + desc + 2 * pad)
    img = Image.new("L", (Wd, Ht), 0)
    d = ImageDraw.Draw(img)
    base_y = pad + asc
    if track_px:
        x = pad
        for ch, w in zip(text, widths):
            d.text((x, base_y), ch, font=pf, fill=255, anchor="ls")
            x += w + track_px
    else:
        d.text((pad, base_y), text, font=pf, fill=255, anchor="ls")
    f = np.asarray(img, dtype=float) / 255.0
    loops = _marching_squares(f, 0.5)
    loops = [_rdp(l, tolerance) for l in loops]
    loops = [l for l in loops if len(l) >= 3 and abs(_area(l)) > 1.0]
    # pixels -> metres (y up, baseline at 0)
    conv = [np.column_stack([(l[:, 0] - pad) / px_per_m, (base_y - l[:, 1]) / px_per_m]) for l in loops]
    depth = []
    for i, c in enumerate(conv):
        dpt = 0
        for j, o in enumerate(conv):
            if i != j and abs(_area(o)) > abs(_area(c)) and _inside(c[0], o):
                dpt += 1
        depth.append(dpt)
    outers = [i for i, dp in enumerate(depth) if dp % 2 == 0]
    groups = []
    for oi in outers:
        o = conv[oi]
        o = o if _area(o) > 0 else o[::-1]
        holes = []
        for hi, dp in enumerate(depth):
            if dp == depth[oi] + 1 and _inside(conv[hi][0], conv[oi]):
                h = conv[hi]
                holes.append(h if _area(h) < 0 else h[::-1])
        groups.append((o.copy(), [h.copy() for h in holes]))
    width = total / px_per_m
    dx = {"left": 0.0, "center": -width / 2, "right": -width}[align]
    return [(o + [dx, 0.0], [h + [dx, 0.0] for h in hs]) for o, hs in groups]


def text_width(text: str, height: float, weight: int = 600, tracking: float = 0.0) -> float:
    """Advance width in metres of ``text`` at cap height ``height``."""
    font = _ttfont(int(weight))
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    cap = getattr(font["OS/2"], "sCapHeight", 0) or upm * 0.7
    s = height / cap
    w = sum(font["hmtx"][cmap.get(ord(c), ".notdef")][0] * s for c in text)
    return w + tracking * max(len(text) - 1, 0)
