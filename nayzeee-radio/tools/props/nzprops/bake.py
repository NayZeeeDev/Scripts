"""
nzprops.bake - per-texel material baking ("Substance in numpy").

For every atlas texel the rasteriser gives the 3D position, normal, chart coordinates and material.
The baker evaluates:
    base colour + 3D grain noise        (no seams: noise lives in 3D space)
    bump patterns -> height             (stipple, brushed, fabric, webbing, foam, rubber, knurl, ribs...)
    decals                              (projected in 3D or placed in chart space, see Decal / ChartDecal)
    ambient occlusion                   (voxel ray-marching against the whole prop, see AOField)
    convex edge highlights              (curvature from the interpolated normals)
and returns GTA-ready images: diffuse (sRGB), normal (DirectX, from height), spec (RGB intensity,
A gloss) plus preview maps for the glTF (metal/rough, OpenGL normal).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from PIL import Image

from .atlas import fill_gutters
from .mesh import normalize
from .paint import DecalCanvas, Mat, fbm3, noise2, noise3


# ---------------------------------------------------------------------------------------------
# decals
# ---------------------------------------------------------------------------------------------
@dataclass
class Decal:
    """A DecalCanvas projected onto the prop along -normal.

    center  3D point at the middle of the canvas
    normal  direction the decal faces (out of the surface)
    up      3D direction of the canvas' top edge
    depth   half thickness of the projection volume (m)
    mats    restrict to these material names (None = every material)
    min_dot texels whose normal is closer than this to perpendicular are skipped
    part    only print on charts of this part id ("" = the body / ordinary geometry, "*" = anything);
            Builder.decal() fills it from the current Builder.part() context
    """

    canvas: DecalCanvas
    center: tuple
    normal: tuple
    up: tuple = (0, 0, 1)
    depth: float = 0.01
    mats: tuple | None = None
    min_dot: float = 0.25
    part: str = ""


@dataclass
class ChartDecal:
    """A DecalCanvas placed in the metric chart coordinates of charts whose tag starts with `tag`.
    (u0, v0) is where the canvas' top-left corner lands; rot in (0, 90, 180, 270)."""

    canvas: DecalCanvas
    tag: str
    u0: float
    v0: float
    rot: int = 0
    repeat_v: float = 0.0     # repeat the canvas every N metres along v (0 = once)
    mats: tuple | None = None
    mirror: bool = False      # flip the canvas horizontally (charts whose u runs the other way)
    part: str = ""            # part id filter, like Decal.part


def _sample(arr, x, y):
    """Bilinear sample arr (H,W[,C]) at float pixel coords (texel centres at i+0.5)."""
    H, W = arr.shape[:2]
    x = x - 0.5
    y = y - 0.5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = (x - x0).astype(np.float32)
    fy = (y - y0).astype(np.float32)
    x1 = np.clip(x0 + 1, 0, W - 1)
    y1 = np.clip(y0 + 1, 0, H - 1)
    x0 = np.clip(x0, 0, W - 1)
    y0 = np.clip(y0, 0, H - 1)
    if arr.ndim == 3:
        fx = fx[:, None]
        fy = fy[:, None]
    a = arr[y0, x0] * (1 - fx) + arr[y0, x1] * fx
    b = arr[y1, x0] * (1 - fx) + arr[y1, x1] * fx
    return a * (1 - fy) + b * fy


def _apply_canvas(L, sel, cv: DecalCanvas, px, py):
    """Blend canvas layers into texel layers L at the selected texels (sel = index array)."""
    inb = (px >= 0) & (py >= 0) & (px <= cv.W) & (py <= cv.H)
    if not inb.any():
        return
    sel = sel[inb]
    px, py = px[inb], py[inb]
    a = _sample(cv.a, px, py)
    if (a > 0.002).any():
        rgb = _sample(cv.rgb, px, py)
        L["albedo"][sel] = L["albedo"][sel] * (1 - a[:, None]) + rgb * a[:, None]
        if "alpha" in L:
            L["alpha"][sel] = L["alpha"][sel] * (1 - a) + a
    hgt = _sample(cv.height, px, py)
    L["height"][sel] += hgt
    sga = _sample(cv.sg_a, px, py)
    if (sga > 0.002).any():
        L["spec"][sel] = L["spec"][sel] * (1 - sga) + _sample(cv.spec, px, py) * sga
        L["gloss"][sel] = L["gloss"][sel] * (1 - sga) + _sample(cv.gloss, px, py) * sga
    met = _sample(cv.metal, px, py)
    L["metal"][sel] = np.maximum(L["metal"][sel], met)


def apply_decal(L, P, N, matname, d: Decal, partname=None):
    c = np.asarray(d.center, np.float64)
    n = normalize(np.asarray(d.normal, np.float64))
    up = np.asarray(d.up, np.float64)
    up = normalize(up - n * np.dot(up, n))
    right = np.cross(up, n)
    rel = P - c
    depth = rel @ n
    ok = (np.abs(depth) <= d.depth) & ((N @ n) >= d.min_dot)
    if d.mats is not None:
        ok &= np.isin(matname, np.asarray(d.mats))
    if partname is not None and d.part != "*":
        ok &= partname == (d.part or "")
    sel = np.nonzero(ok)[0]
    if len(sel) == 0:
        return
    cv = d.canvas
    x = (rel[sel] @ right) / cv.w_m + 0.5
    y = 0.5 - (rel[sel] @ up) / cv.h_m
    _apply_canvas(L, sel, cv, x * cv.W, y * cv.H)


def apply_chart_decal(L, C, tags, matname, d: ChartDecal, partname=None):
    ok = np.char.startswith(tags, d.tag)
    if d.mats is not None:
        ok &= np.isin(matname, np.asarray(d.mats))
    if partname is not None and d.part != "*":
        ok &= partname == (d.part or "")
    sel = np.nonzero(ok)[0]
    if len(sel) == 0:
        return
    cv = d.canvas
    u = C[sel, 0] - d.u0
    v = C[sel, 1] - d.v0
    if d.repeat_v > 0:
        v = np.mod(v, d.repeat_v)
    if d.rot == 0:
        x, y = u, v
    elif d.rot == 90:
        x, y = v, cv.h_m - u
    elif d.rot == 180:
        x, y = cv.w_m - u, cv.h_m - v
    else:
        x, y = cv.w_m - v, u
    if d.mirror:
        x = cv.w_m - x
    _apply_canvas(L, sel, cv, x * cv.ppm, y * cv.ppm)


# ---------------------------------------------------------------------------------------------
# ambient occlusion
# ---------------------------------------------------------------------------------------------
class AOField:
    """Surface occupancy grid of the whole prop + hemisphere ray marching."""

    def __init__(self, tri_pos, max_dist=None, res=112, seed=7):
        tri_pos = np.asarray(tri_pos, np.float64)
        pts = tri_pos.reshape(-1, 3)
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        diag = float(np.linalg.norm(hi - lo))
        self.vs = max(diag / res, 0.0008)
        self.max_dist = max_dist if max_dist is not None else float(np.clip(diag * 0.22, 0.015, 0.30))
        pad = self.max_dist + 3 * self.vs
        self.lo = lo - pad
        dims = np.ceil((hi + pad - self.lo) / self.vs).astype(np.int64) + 1
        self.dims = dims
        self.grid = np.zeros(tuple(dims), dtype=bool)
        rng = np.random.default_rng(seed)
        e1 = tri_pos[:, 1] - tri_pos[:, 0]
        e2 = tri_pos[:, 2] - tri_pos[:, 0]
        area = 0.5 * np.linalg.norm(np.cross(e1, e2), axis=1)
        nsamp = np.clip(np.ceil(area / (self.vs * self.vs) * 3.0).astype(np.int64), 3, 4000)
        tri_idx = np.repeat(np.arange(len(tri_pos)), nsamp)
        r1 = np.sqrt(rng.random(len(tri_idx)))
        r2 = rng.random(len(tri_idx))
        p = tri_pos[tri_idx, 0] * (1 - r1)[:, None] + tri_pos[tri_idx, 1] * (r1 * (1 - r2))[:, None] + tri_pos[tri_idx, 2] * (r1 * r2)[:, None]
        p = np.concatenate([p, tri_pos.reshape(-1, 3)])
        ijk = np.floor((p - self.lo) / self.vs).astype(np.int64)
        ijk = np.clip(ijk, 0, dims - 1)
        self.grid[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = True
        # cosine weighted hemisphere directions (fibonacci)
        nd = 28
        k = np.arange(nd) + 0.5
        r = np.sqrt(k / nd)
        th = k * math.pi * (3 - math.sqrt(5))
        self.dirs = np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(1 - r * r)], axis=1)
        ns = 11
        t = (np.arange(ns) / (ns - 1)) ** 1.6
        self.steps = 1.5 * self.vs + t * (self.max_dist - 1.5 * self.vs)

    def occlusion(self, P, N, chunk=6000):
        P = np.asarray(P, np.float64)
        N = normalize(np.asarray(N, np.float64))
        out = np.ones(len(P), np.float32)
        a = np.where(np.abs(N[:, 0:1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]]))
        T = normalize(np.cross(N, a))
        B = np.cross(N, T)
        D = self.dirs
        falloff = 1.0 - (self.steps / self.max_dist) ** 0.7
        for s in range(0, len(P), chunk):
            e = min(len(P), s + chunk)
            dw = (T[s:e, None, :] * D[None, :, 0:1] + B[s:e, None, :] * D[None, :, 1:2] + N[s:e, None, :] * D[None, :, 2:3])
            base = P[s:e] + N[s:e] * (1.2 * self.vs)
            occ = np.zeros((e - s, len(D)), np.float32)
            hit = np.zeros((e - s, len(D)), bool)
            for si, st in enumerate(self.steps):
                q = base[:, None, :] + dw * st
                ijk = np.floor((q - self.lo) / self.vs).astype(np.int64)
                inb = np.all((ijk >= 0) & (ijk < self.dims), axis=2)
                ijk = np.clip(ijk, 0, self.dims - 1)
                h = self.grid[ijk[..., 0], ijk[..., 1], ijk[..., 2]] & inb & (~hit)
                occ[h] = falloff[si]
                hit |= h
            out[s:e] = 1.0 - occ.mean(axis=1)
        return out


# ---------------------------------------------------------------------------------------------
# material evaluation
# ---------------------------------------------------------------------------------------------
def _bump(m: Mat, P, C, seed):
    """Height (metres) and colour modulation for a bump pattern."""
    amp, sc = m.bump_amp, max(m.bump_scale, 1e-5)
    n = len(P)
    if m.bump == "none" or amp == 0:
        return np.zeros(n, np.float32), np.ones(n, np.float32)
    if m.bump == "stipple":
        h = fbm3(P / sc, 3, seed) + 0.35 * noise3(P / (sc * 0.35), seed + 5)
        return (h * amp).astype(np.float32), (1 + 0.035 * h).astype(np.float32)
    if m.bump == "orange_peel":
        h = noise3(P / sc, seed)
        return (h * amp).astype(np.float32), np.ones(n, np.float32)
    if m.bump == "rubber":
        h = fbm3(P / sc, 2, seed)
        return (h * amp).astype(np.float32), (1 + 0.05 * h).astype(np.float32)
    if m.bump == "brushed":
        h = noise2(C[:, 0] / (sc * 60), C[:, 1] / sc, seed) * 0.7 + noise2(C[:, 0] / (sc * 200), C[:, 1] / (sc * 0.4), seed + 3) * 0.3
        return (h * amp).astype(np.float32), (1 + 0.05 * h).astype(np.float32)
    if m.bump == "fabric":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        warp = np.sin(2 * math.pi * u) * np.sign(np.sin(math.pi * v))
        weft = np.sin(2 * math.pi * v) * np.sign(np.sin(math.pi * u + 1.3))
        h = 0.5 * (np.abs(warp) + np.abs(weft)) - 0.5 + 0.25 * noise3(P / (sc * 3), seed)
        return (h * amp).astype(np.float32), (1 + 0.08 * h).astype(np.float32)
    if m.bump == "webbing":
        v = C[:, 1] / sc
        u = C[:, 0] / (sc * 0.5)
        h = np.abs(np.sin(math.pi * v)) ** 0.7 * 0.8 + 0.2 * np.abs(np.sin(math.pi * u)) + 0.15 * noise3(P / (sc * 2), seed)
        h = h - 0.5
        return (h * amp).astype(np.float32), (1 + 0.10 * h).astype(np.float32)
    if m.bump == "foam":
        nz = noise3(P / sc, seed)
        nz2 = noise3(P / (sc * 0.45), seed + 9)
        pores = np.clip(np.abs(nz) * 2.2 - 1.2, 0, 1) + 0.6 * np.clip(np.abs(nz2) * 2.0 - 1.3, 0, 1)
        h = -pores + 0.2 * noise3(P / (sc * 3), seed + 2)
        return (h * amp).astype(np.float32), (1 - 0.25 * np.clip(pores, 0, 1)).astype(np.float32)
    if m.bump == "eggcrate":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        h = np.sin(2 * math.pi * u) * np.sin(2 * math.pi * v)
        pores = np.clip(np.abs(noise3(P / (sc * 0.08), seed)) * 2.2 - 1.3, 0, 1)
        h = h - 0.15 * pores
        return (h * amp).astype(np.float32), (1 + 0.10 * h - 0.2 * pores).astype(np.float32)
    if m.bump == "pluck":
        # pick-and-pluck foam: grid of fine cuts every bump_scale + foam pores
        u, v = C[:, 0] / sc, C[:, 1] / sc
        fu = np.abs(u - np.round(u))
        fv = np.abs(v - np.round(v))
        cut = np.clip(1 - np.minimum(fu, fv) / 0.045, 0, 1)
        nz = noise3(P / (sc * 0.06), seed)
        pores = np.clip(np.abs(nz) * 2.2 - 1.2, 0, 1)
        h = -cut * 1.0 - pores * 0.25
        return (h * amp).astype(np.float32), (1 - 0.45 * cut - 0.2 * pores).astype(np.float32)
    if m.bump == "knurl":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        h = 0.5 * (np.abs(np.sin(math.pi * (u + v))) + np.abs(np.sin(math.pi * (u - v)))) - 0.5
        return (h * amp).astype(np.float32), (1 + 0.06 * h).astype(np.float32)
    if m.bump == "ribs":
        v = C[:, 1] / sc
        h = np.abs(np.sin(math.pi * v)) - 0.5
        return (h * amp).astype(np.float32), (1 + 0.05 * h).astype(np.float32)
    if m.bump == "ribs_u":
        u = C[:, 0] / sc
        h = np.abs(np.sin(math.pi * u)) - 0.5
        return (h * amp).astype(np.float32), (1 + 0.05 * h).astype(np.float32)
    if m.bump == "leather":
        a = np.abs(noise3(P / sc, seed))
        b = np.abs(noise3(P / (sc * 0.5), seed + 4))
        h = -(np.clip(0.18 - a, 0, 1) * 4 + np.clip(0.12 - b, 0, 1) * 3)
        return (h * amp).astype(np.float32), (1 + 0.6 * h).astype(np.float32)
    if m.bump == "phillips":
        # screw head built around its own axis: chart coords centred on the head (planar lathe caps)
        u, v = C[:, 0] / sc, C[:, 1] / sc
        r = np.sqrt(u * u + v * v)
        dome = np.clip(1 - r * r, 0, 1) * 0.35
        cross = ((np.abs(u) < 0.13) & (np.abs(v) < 0.62)) | ((np.abs(v) < 0.13) & (np.abs(u) < 0.62))
        h = dome - cross * 1.0
        return (h * amp).astype(np.float32), (1 - 0.55 * cross).astype(np.float32)
    if m.bump == "hexsocket":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        a = np.abs(u)
        b2 = np.abs(v)
        hexd = np.maximum(a * 0.866 + b2 * 0.5, b2) < 0.42
        h = -(hexd * 1.0)
        return (h * amp).astype(np.float32), (1 - 0.6 * hexd).astype(np.float32)
    if m.bump == "torx":
        # six-lobe drive recess centred on the head (planar lathe caps, like "phillips")
        u, v = C[:, 0] / sc, C[:, 1] / sc
        r = np.sqrt(u * u + v * v)
        th = np.arctan2(v, u)
        dome = np.clip(1 - r * r, 0, 1) * 0.35
        star = r < (0.40 + 0.11 * np.cos(6 * th))
        h = dome - star * 1.0
        return (h * amp).astype(np.float32), (1 - 0.55 * star).astype(np.float32)
    if m.bump == "diamond":
        # tread plate: raised lozenges alternating +-45 deg on a square lattice
        u, v = C[:, 0] / sc, C[:, 1] / sc
        iu, iv = np.floor(u), np.floor(v)
        fu, fv = u - iu - 0.5, v - iv - 0.5
        par = ((iu + iv) % 2 == 0)
        a = np.where(par, fu + fv, fu - fv) / 1.414
        bb = np.where(par, fu - fv, fu + fv) / 1.414
        d = (a / 0.42) ** 2 + (bb / 0.11) ** 2
        h = np.clip(1 - d, 0, 1) ** 0.5 - 0.15
        return (h * amp).astype(np.float32), (1 + 0.06 * h).astype(np.float32)
    if m.bump == "dimple":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        fu, fv = u - np.round(u), v - np.round(v)
        d = np.sqrt(fu * fu + fv * fv) / 0.32
        h = np.clip(1 - d * d, 0, 1) ** 0.5 - 0.2
        return (h * amp).astype(np.float32), (1 + 0.05 * h).astype(np.float32)
    if m.bump == "perf":
        u, v = C[:, 0] / sc, C[:, 1] / sc
        fu, fv = u - np.round(u), v - np.round(v)
        d = np.sqrt(fu * fu + fv * fv)
        hole = np.clip((0.30 - d) / 0.05, 0, 1)
        h = -hole
        return (h * amp).astype(np.float32), (1 - 0.8 * hole).astype(np.float32)
    if m.bump == "twill":
        # 2x2 twill weave (carbon fibre / heavy webbing)
        u, v = C[:, 0] / sc, C[:, 1] / sc
        k = np.floor(u) + np.floor(v)
        along = np.where((k % 4) < 2, np.sin(np.pi * (u - np.floor(u))), np.sin(np.pi * (v - np.floor(v))))
        h = along - 0.5 + 0.12 * noise3(P / (sc * 4), seed)
        return (h * amp).astype(np.float32), (1 + 0.12 * h).astype(np.float32)
    if m.bump == "cordura":
        # coarse basket weave nylon (bags, pouches)
        u, v = C[:, 0] / sc, C[:, 1] / sc
        cu, cv = np.floor(u * 0.5), np.floor(v * 0.5)
        warp = (cu + cv) % 2 == 0
        h = np.where(warp, np.abs(np.sin(np.pi * u)), np.abs(np.sin(np.pi * v))) - 0.5 + 0.2 * noise3(P / (sc * 3), seed)
        return (h * amp).astype(np.float32), (1 + 0.10 * h).astype(np.float32)
    if m.bump == "crinkle":
        # crumpled metallised film (rescue blanket): ridged creases at three scales + per-facet brightness
        r1 = 1 - np.abs(noise3(P / sc, seed))
        r2 = 1 - np.abs(noise3(P / (sc * 0.43), seed + 3))
        r3 = 1 - np.abs(noise3(P / (sc * 0.19), seed + 6))
        h = r1 ** 4 * 0.6 + r2 ** 4 * 0.3 + r3 ** 4 * 0.15 - 0.25
        facet = noise3(P / (sc * 0.55), seed + 9)
        return (h * amp).astype(np.float32), (1 + 0.14 * facet + 0.05 * (r2 - 0.5)).astype(np.float32)
    if m.bump == "velcro":
        n1 = noise3(P / sc, seed)
        n2 = noise3(P / (sc * 0.4), seed + 3)
        h = np.abs(n1) * 0.6 + np.abs(n2) * 0.6 - 0.5
        return (h * amp).astype(np.float32), (1 + 0.18 * h).astype(np.float32)
    raise ValueError(f"unknown bump pattern {m.bump}")


def _hash2(iu, iv, seed):
    from .paint import _hash
    return _hash(iu.astype(np.int64), iv.astype(np.int64), np.zeros_like(iu, dtype=np.int64), seed)


def scratch_field(C, texel, seed=0):
    """Fine straight scratches laid out in chart space (metres): a few random segments per cell,
    two size octaves. Width follows the texel size so they stay crisp without aliasing."""
    out = np.zeros(len(C), np.float32)
    for cell, dens, sd in ((0.018, 0.4, 0), (0.007, 0.25, 1), (0.045, 0.45, 2)):
        for layer in range(2):
            ofs = 0.5 * layer
            u, v = C[:, 0] / cell + ofs, C[:, 1] / cell + ofs * 0.7
            iu, iv = np.floor(u), np.floor(v)
            fu, fv = u - iu - 0.5, v - iv - 0.5
            s0 = seed * 31 + sd * 7 + layer * 3
            h1, h2, h3, h4 = (_hash2(iu, iv, s0 + k) for k in range(4))
            ang = h1 * np.pi
            ta, tb = np.cos(ang), np.sin(ang)
            along = fu * ta + fv * tb
            across = -fu * tb + fv * ta - h2 * 0.25
            half = 0.18 + 0.27 * (h3 * 0.5 + 0.5)
            present = (h4 * 0.5 + 0.5) < dens
            wid = np.maximum(texel * 0.8, 0.00012) / cell
            line = np.clip(1 - np.abs(across) / wid, 0, 1) * np.clip((half - np.abs(along)) * 6, 0, 1) * present
            out = np.maximum(out, line * (0.55 + 0.45 * (h3 * 0.5 + 0.5)))
    return out


def eval_materials(mats: dict, matname, P, C, seed=11):
    """Base layers for every texel (1D arrays)."""
    n = len(P)
    L = {
        "albedo": np.zeros((n, 3), np.float32),
        "height": np.zeros(n, np.float32),
        "spec": np.zeros(n, np.float32),
        "gloss": np.zeros(n, np.float32),
        "metal": np.zeros(n, np.float32),
        "alpha": np.ones(n, np.float32),
        "edge": np.zeros(n, np.float32),
        "aok": np.zeros(n, np.float32),
        "dirt": np.zeros(n, np.float32),
        "wear": np.zeros(n, np.float32),
        "wear_rgb": np.zeros((n, 3), np.float32),
        "scratch": np.zeros(n, np.float32),
        "smudge": np.zeros(n, np.float32),
        "cavity": np.zeros(n, np.float32),
    }
    for mi, (name, m) in enumerate(mats.items()):
        sel = np.nonzero(matname == name)[0]
        if len(sel) == 0:
            continue
        p = P[sel]
        c = C[sel]
        col = np.asarray(m.color, np.float32)[None, :]
        g = fbm3(p / max(m.grain_scale, 1e-4), 3, seed + mi * 31)
        g2 = noise3(p / max(m.grain_scale * 0.18, 1e-5), seed + mi * 31 + 7)
        mod = (1 + m.grain * (0.75 * g + 0.25 * g2)).astype(np.float32)
        h, cm = _bump(m, p, c, seed + mi * 13)
        alb = col * (mod * cm)[:, None]
        if m.color2 is not None and m.bump in ("fabric", "webbing"):
            t = np.clip(h / max(m.bump_amp, 1e-9) + 0.5, 0, 1)[:, None]
            alb = alb * (1 - t * 0.5) + np.asarray(m.color2, np.float32)[None, :] * mod[:, None] * t * 0.5
        L["albedo"][sel] = alb
        L["height"][sel] = h
        sv = noise3(p / max(m.grain_scale * 0.5, 1e-4), seed + mi * 7 + 1)
        L["spec"][sel] = np.clip(m.spec * (1 + 0.15 * sv), 0, 1)
        L["gloss"][sel] = np.clip(m.gloss * (1 + 0.10 * sv) - (np.clip(-h / max(m.bump_amp, 1e-9), 0, 1) * 0.15 if m.bump == "foam" else 0), 0, 1)
        L["metal"][sel] = m.metal
        L["alpha"][sel] = m.alpha
        L["edge"][sel] = m.edge
        L["aok"][sel] = m.ao
        L["dirt"][sel] = m.dirt
        clear = m.layer == "alpha"
        L["wear"][sel] = (m.edge * (0.12 if clear else 0.6)) if m.wear < 0 else m.wear
        if m.wear_color is not None:
            L["wear_rgb"][sel] = np.asarray(m.wear_color, np.float32)[None, :]
        elif m.metal > 0.5 or m.spec > 0.7:
            L["wear_rgb"][sel] = np.minimum(alb * 1.22 + 22, 255)
        else:
            L["wear_rgb"][sel] = alb + (255.0 - alb) * 0.28
        auto_s = (0.1 if clear else 0.12 + 0.4 * m.gloss) if m.bump not in ("fabric", "webbing", "foam", "pluck", "eggcrate",
                                                                               "velcro", "cordura", "twill", "crinkle") else 0.0
        L["scratch"][sel] = auto_s if m.scratch < 0 else m.scratch
        L["smudge"][sel] = (0.25 + 0.6 * m.gloss if not clear else 0.35) if m.smudge < 0 else m.smudge
        L["cavity"][sel] = m.cavity
    return L


# ---------------------------------------------------------------------------------------------
# full layer bake
# ---------------------------------------------------------------------------------------------
def curvature(Pimg, Nimg, cov, chart):
    """Mean convex curvature (1/m) per texel from neighbouring texels of the same chart."""
    H, W = cov.shape
    k = np.zeros((H, W), np.float32)
    cnt = np.zeros((H, W), np.float32)
    for axis in (0, 1):
        pf = np.roll(Pimg, -1, axis=axis)
        pb = np.roll(Pimg, 1, axis=axis)
        nf = np.roll(Nimg, -1, axis=axis)
        nb = np.roll(Nimg, 1, axis=axis)
        ok = cov & np.roll(cov, -1, axis=axis) & np.roll(cov, 1, axis=axis) & \
            (np.roll(chart, -1, axis=axis) == chart) & (np.roll(chart, 1, axis=axis) == chart)
        dp = pf - pb
        dn = nf - nb
        d2 = np.einsum("hwc,hwc->hw", dp, dp)
        kk = np.einsum("hwc,hwc->hw", dn, dp) / np.maximum(d2, 1e-14)
        k += np.where(ok, kk, 0)
        cnt += ok
    return np.where(cnt > 0, k / np.maximum(cnt, 1), 0)


def height_to_normal(height, texel_m, strength=1.0):
    """DirectX tangent space normal (green = +v = image down) from a height map in metres."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 / texel_m
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 / texel_m
    dx = np.clip(dx * strength, -3, 3)
    dy = np.clip(dy * strength, -3, 3)
    n = np.stack([-dx, -dy, np.ones_like(dx)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def bake(W, H, tid, bary, tri_vidx, V_pos, V_nrm, V_uvm, tri_mat, tri_chart, chart_tags, chart_dens,
         mats: dict, decals, chart_decals, ao: AOField | None, alpha_layer=False, glow_layer=False, chart_parts=None):
    """Bake one atlas layer. Returns dict of PIL images."""
    cov = tid >= 0
    ys, xs = np.nonzero(cov)
    t = tid[ys, xs]
    b = bary[ys, xs].astype(np.float64)
    vi = tri_vidx[t]
    P = (V_pos[vi] * b[:, :, None]).sum(axis=1)
    N = normalize((V_nrm[vi] * b[:, :, None]).sum(axis=1))
    C = (V_uvm[vi] * b[:, :, None]).sum(axis=1)
    matname = np.asarray(tri_mat, dtype=object)[t].astype(str)
    ch = tri_chart[t]
    tags = np.asarray(chart_tags, dtype=object)[ch].astype(str)
    texel = 1.0 / np.asarray(chart_dens)[ch]

    L = eval_materials(mats, matname, P, C)
    partname = None
    if chart_parts is not None:
        partname = np.asarray([p or "" for p in chart_parts], dtype=object)[ch].astype(str)
    for d in decals:
        apply_decal(L, P, N, matname, d, partname)
    for d in chart_decals:
        apply_chart_decal(L, C, tags, matname, d, partname)

    # AO at half resolution of covered texels, broadcast to the full grid
    aov = np.ones(len(P), np.float32)
    if ao is not None and not glow_layer:
        sub = ((ys % 2) == 0) & ((xs % 2) == 0)
        img = np.zeros((H // 2, W // 2), np.float32)
        m = np.zeros((H // 2, W // 2), bool)
        if sub.any():
            occ = ao.occlusion(P[sub], N[sub])
            img[ys[sub] // 2, xs[sub] // 2] = occ
            m[ys[sub] // 2, xs[sub] // 2] = True
        arr = [img]
        fill_gutters(arr, m, dilate=2)
        aov = arr[0][np.minimum(ys // 2, H // 2 - 1), np.minimum(xs // 2, W // 2 - 1)]

    # full-size images
    def blank(c=None):
        return np.zeros((H, W) if c is None else (H, W, c), np.float32)

    Pimg = blank(3)
    Nimg = blank(3)
    Pimg[ys, xs] = P
    Nimg[ys, xs] = N
    chart_img = np.full((H, W), -1, np.int32)
    chart_img[ys, xs] = ch
    curv = curvature(Pimg, Nimg, cov, chart_img)[ys, xs]

    convex = np.clip(curv / 260.0, 0, 1)
    concave = np.clip(-curv / 180.0, 0, 1)
    edge = convex * L["edge"]
    alb = L["albedo"]
    # soft convex highlight (catches the light on bevels)
    alb = alb + edge[:, None] * (255.0 - alb) * 0.10
    # chipped edge wear: convexity broken up by fine + coarse 3D noise
    if not glow_layer:
        n_hi = noise3(P / 0.0021, 101) * 0.6 + noise3(P / 0.0009, 102) * 0.4
        n_lo = fbm3(P / 0.035, 3, 103)
        wear = np.clip(convex * 1.7 - 0.55 + n_hi * 0.55 + n_lo * 0.35, 0, 1) * L["wear"]
        wear = np.clip(wear * 1.6, 0, 1) ** 1.3
        alb = alb * (1 - wear[:, None] * 0.65) + L["wear_rgb"] * wear[:, None] * 0.65
        # fine scratches (lighter, slightly rougher, tiny dent in the height)
        scr = scratch_field(C, texel, seed=7) * L["scratch"] * np.clip(0.0009 / np.maximum(texel, 1e-6), 0.25, 1.0)
        alb = alb + scr[:, None] * (np.maximum(L["wear_rgb"], alb) - alb) * 0.28 + scr[:, None] * 3.0
        L["height"] -= scr * 0.000004
        # handling marks / smudges: large blotches of lower gloss
        smg = np.clip(fbm3(P / 0.045, 3, 107) * 1.7 + 0.05, 0, 1) * np.clip(noise3(P / 0.012, 108) * 0.8 + 0.6, 0, 1) * L["smudge"]
        # crevice grime (AO + concave curvature), patchy
        dmask = np.clip((1 - aov) * 2.0 + concave * 0.8, 0, 1) * np.clip(0.55 + 0.75 * n_lo, 0.1, 1.3)
        dirt = L["dirt"] * dmask
        # dust settling on up-facing surfaces
        dust = L["dirt"] * np.clip((N[:, 2] - 0.55) / 0.45, 0, 1) * np.clip(0.45 + 0.8 * fbm3(P / 0.018, 2, 109), 0, 1) * 0.55
    else:
        wear = scr = smg = dust = np.zeros(len(P), np.float32)
        dirt = L["dirt"] * np.clip((1 - aov) * 2.2, 0, 1)
    aof = 1.0 - L["aok"] * (1.0 - aov) * 0.85
    alb = alb * aof[:, None] * (1 - concave * L["cavity"] * 0.35)[:, None]
    alb = alb * (1 - dirt[:, None] * 0.38) + np.array([66, 57, 46], np.float32)[None, :] * dirt[:, None] * 0.38
    alb = alb * (1 - dust[:, None] * 0.3) + np.array([152, 146, 136], np.float32)[None, :] * dust[:, None] * 0.3
    metalish = np.clip(L["metal"] + (L["spec"] > 0.7), 0, 1)
    spec = L["spec"] * (0.45 + 0.55 * aov) + edge * 0.05 + wear * (0.12 + 0.25 * metalish) - smg * 0.06 * L["spec"]
    spec = spec * (1 - dust * 0.5) - scr * 0.05
    gloss = L["gloss"] * (1 - dirt * 0.5) * (1 - smg * 0.32) * (1 - dust * 0.45) + wear * 0.08 * (1 - metalish) - scr * 0.12
    gloss = np.clip(gloss, 0, 1)
    spec = np.clip(spec, 0, 1)

    diffuse = blank(3)
    diffuse[ys, xs] = alb
    height = blank()
    height[ys, xs] = L["height"]
    specimg = blank()
    specimg[ys, xs] = spec
    glossimg = blank()
    glossimg[ys, xs] = gloss
    metal = blank()
    metal[ys, xs] = L["metal"]
    alpha = blank()
    alpha[ys, xs] = L["alpha"]
    tex = blank()
    tex[ys, xs] = texel
    aoimg = np.ones((H, W), np.float32)
    aoimg[ys, xs] = aov
    arrays = [diffuse, height, specimg, glossimg, metal, alpha, tex, aoimg]
    fill_gutters(arrays, cov, dilate=4)
    diffuse, height, specimg, glossimg, metal, alpha, tex, aoimg = arrays

    nrm = height_to_normal(height, np.maximum(tex, 1e-5))
    n_dx = np.clip((nrm * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    n_gl = n_dx.copy()
    n_gl[..., 1] = 255 - n_gl[..., 1]
    d8 = np.clip(diffuse, 0, 255).astype(np.uint8)
    out = {"coverage": float(cov.mean())}
    if alpha_layer:
        a8 = np.clip(alpha * 255, 0, 255).astype(np.uint8)
        out["diffuse"] = Image.fromarray(np.dstack([d8, a8]), "RGBA")
    else:
        out["diffuse"] = Image.fromarray(d8, "RGB")
    s8 = np.clip(specimg * 255, 0, 255).astype(np.uint8)
    g8 = np.clip(glossimg * 255, 0, 255).astype(np.uint8)
    out["spec"] = Image.fromarray(np.dstack([s8, s8, s8, g8]), "RGBA")
    out["normal_dx"] = Image.fromarray(n_dx, "RGB")
    out["normal_gl"] = Image.fromarray(n_gl, "RGB")
    rough = np.clip(1.0 - glossimg * 0.88, 0.08, 1.0)
    out["mr"] = Image.fromarray(np.dstack([np.full((H, W), 255, np.uint8), (rough * 255).astype(np.uint8), np.clip(metal * 255, 0, 255).astype(np.uint8)]), "RGB")
    out["ao"] = Image.fromarray(np.clip(aoimg * 255, 0, 255).astype(np.uint8), "L")
    return out
