"""
nzprops.atlas - automatic UV atlas: chart packing, triangle rasterisation, gutter filling.

pack_charts(charts, size, pad)   finds the highest texel density (px/m) at which every chart fits
                                 a size x size atlas (skyline bottom-left packer, 90 deg rotation)
chart_uvs(chart, placement)      final 0..1 UVs (DirectX convention, v down) for a packed chart
rasterize(tri_px, W, H)          per-texel triangle id + barycentrics (vectorised in size buckets)
fill_gutters(arrays, mask)       dilate charts by a few texels, then push-pull fill the rest so
                                 mip maps never bleed black into the charts
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np


@dataclass
class Placement:
    x: int
    y: int
    w: int          # placed width in px (incl. padding)
    h: int
    rot: bool       # True = chart rotated 90 degrees
    dens: float     # px per metre for this chart
    umin: float
    vmin: float
    umax: float
    vmax: float
    pad: int


class _Skyline:
    def __init__(self, W, H):
        self.W, self.H = W, H
        self.nodes = [[0, 0, W]]

    def _fit(self, i, w, h):
        x = self.nodes[i][0]
        if x + w > self.W:
            return -1
        left = w
        y = self.nodes[i][1]
        j = i
        while left > 0:
            if j >= len(self.nodes):
                return -1
            y = max(y, self.nodes[j][1])
            if y + h > self.H:
                return -1
            left -= self.nodes[j][2]
            j += 1
        return y

    def _place(self, i, x, y, w, h):
        self.nodes.insert(i, [x, y + h, w])
        k = i + 1
        while k < len(self.nodes):
            prev = self.nodes[k - 1]
            node = self.nodes[k]
            if node[0] < prev[0] + prev[2]:
                shrink = prev[0] + prev[2] - node[0]
                node[0] += shrink
                node[2] -= shrink
                if node[2] <= 0:
                    self.nodes.pop(k)
                    continue
                break
            break
        k = 0
        while k < len(self.nodes) - 1:
            if self.nodes[k][1] == self.nodes[k + 1][1]:
                self.nodes[k][2] += self.nodes[k + 1][2]
                self.nodes.pop(k + 1)
            else:
                k += 1

    def insert(self, w, h, allow_rot=True):
        best = None
        for rot in ((False, True) if allow_rot and w != h else (False,)):
            ww, hh = (h, w) if rot else (w, h)
            for i in range(len(self.nodes)):
                y = self._fit(i, ww, hh)
                if y < 0:
                    continue
                key = (y + hh, self.nodes[i][0])
                if best is None or key < best[0]:
                    best = (key, i, self.nodes[i][0], y, ww, hh, rot)
        if best is None:
            return None
        _, i, x, y, ww, hh, rot = best
        self._place(i, x, y, ww, hh)
        return x, y, rot


def _chart_extent(ch):
    u = ch.uvm[:, 0]
    v = ch.uvm[:, 1]
    return float(u.min()), float(v.min()), float(u.max()), float(v.max())


def _try_pack(charts, W, H, dens, pad, max_frac=0.98):
    items = []
    for ci, ch in enumerate(charts):
        umin, vmin, umax, vmax = _chart_extent(ch)
        d = dens * ch.density
        cw, chh = (umax - umin) * d, (vmax - vmin) * d
        # very long charts are scaled down individually so they still fit the atlas
        lim = (min(W, H) * max_frac) - 2 * pad - 2
        big = max(cw, chh)
        if big > lim:
            d *= lim / big
            cw, chh = (umax - umin) * d, (vmax - vmin) * d
        w = int(math.ceil(cw)) + 2 * pad + 1
        h = int(math.ceil(chh)) + 2 * pad + 1
        items.append((ci, w, h, d, umin, vmin, umax, vmax))
    order = sorted(items, key=lambda it: (-max(it[1], it[2]), -it[1] * it[2]))
    sk = _Skyline(W, H)
    out = [None] * len(charts)
    for ci, w, h, d, umin, vmin, umax, vmax in order:
        r = sk.insert(w, h)
        if r is None:
            return None
        x, y, rot = r
        ww, hh = (h, w) if rot else (w, h)
        out[ci] = Placement(x, y, ww, hh, rot, d, umin, vmin, umax, vmax, pad)
    return out


def pack_charts(charts, W, H=None, pad=4, max_density=9000.0, min_density=20.0):
    """Binary-search the largest uniform density (px/m, times each chart's own multiplier) that
    packs. Returns (density, placements)."""
    H = H or W
    area = sum(max(c.area(), 1e-8) * c.density ** 2 for c in charts)
    guess = math.sqrt(0.62 * W * H / max(area, 1e-8))
    lo, hi = min_density, min(max_density, guess * 2.5)
    best = None
    if _try_pack(charts, W, H, lo, pad) is None:
        raise RuntimeError(f"charts do not fit a {W}x{H} atlas even at {lo} px/m")
    for _ in range(18):
        mid = (lo + hi) / 2
        res = _try_pack(charts, W, H, mid, pad)
        if res is not None:
            best = (mid, res)
            lo = mid
        else:
            hi = mid
        if hi - lo < max(1.0, lo * 0.01):
            break
    if best is None:
        best = (lo, _try_pack(charts, W, H, lo, pad))
    return best


def chart_px(ch, pl: Placement):
    """Pixel coordinates (float) of every chart vertex in the atlas."""
    u = ch.uvm[:, 0]
    v = ch.uvm[:, 1]
    o = pl.pad + 0.5
    if not pl.rot:
        px = pl.x + o + (u - pl.umin) * pl.dens
        py = pl.y + o + (v - pl.vmin) * pl.dens
    else:
        px = pl.x + o + (pl.vmax - v) * pl.dens
        py = pl.y + o + (u - pl.umin) * pl.dens
    return np.stack([px, py], axis=1)


def chart_uvs(ch, pl: Placement, W, H):
    p = chart_px(ch, pl)
    return np.stack([p[:, 0] / W, p[:, 1] / H], axis=1)


# ---------------------------------------------------------------------------------------------
# rasterisation
# ---------------------------------------------------------------------------------------------
def rasterize(tri_px, W, H):
    """tri_px (T,3,2) pixel coordinates. Returns tid (H,W) int32 (-1 = empty) and bary (H,W,3)."""
    T = len(tri_px)
    tid = np.full((H, W), -1, np.int32)
    bary = np.zeros((H, W, 3), np.float32)
    if T == 0:
        return tid, bary
    a, b, c = tri_px[:, 0], tri_px[:, 1], tri_px[:, 2]
    area = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    valid = np.abs(area) > 1e-10
    mn = np.floor(tri_px.min(axis=1) - 0.5).astype(np.int64)
    mx = np.ceil(tri_px.max(axis=1) - 0.5).astype(np.int64)
    mn = np.clip(mn, 0, [W - 1, H - 1])
    mx = np.clip(mx, 0, [W - 1, H - 1])
    span = np.maximum(mx - mn + 1, 1).max(axis=1)
    done = ~valid
    sizes = [2, 4, 8, 16, 32]
    for S in sizes:
        sel = np.nonzero((~done) & (span <= S))[0]
        if len(sel) == 0:
            continue
        done[sel] = True
        for chunk in np.array_split(sel, max(1, len(sel) * S * S // 400000 + 1)):
            _raster_bucket(chunk, S, tri_px, area, mn, W, H, tid, bary)
    rest = np.nonzero(~done)[0]
    for t in rest:
        sx = mx[t, 0] - mn[t, 0] + 1
        sy = mx[t, 1] - mn[t, 1] + 1
        xs = np.arange(mn[t, 0], mn[t, 0] + sx)
        ys = np.arange(mn[t, 1], mn[t, 1] + sy)
        X, Y = np.meshgrid(xs + 0.5, ys + 0.5)
        w0, w1, w2, inside = _edge(tri_px[t], area[t], X, Y)
        yy, xx = np.nonzero(inside)
        gx, gy = xs[xx], ys[yy]
        tid[gy, gx] = t
        bary[gy, gx, 0] = w0[yy, xx]
        bary[gy, gx, 1] = w1[yy, xx]
        bary[gy, gx, 2] = w2[yy, xx]
    return tid, bary


def _edge(tp, ar, X, Y):
    a, b, c = tp[0], tp[1], tp[2]
    w0 = ((b[0] - X) * (c[1] - Y) - (b[1] - Y) * (c[0] - X)) / ar
    w1 = ((c[0] - X) * (a[1] - Y) - (c[1] - Y) * (a[0] - X)) / ar
    w2 = 1.0 - w0 - w1
    eps = -1e-5
    inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    return w0, w1, w2, inside


def _raster_bucket(sel, S, tri_px, area, mn, W, H, tid, bary):
    n = len(sel)
    ox = np.arange(S)
    gx = mn[sel, 0][:, None, None] + ox[None, None, :]
    gy = mn[sel, 1][:, None, None] + ox[None, :, None]
    gx = np.broadcast_to(gx, (n, S, S))
    gy = np.broadcast_to(gy, (n, S, S))
    X = gx + 0.5
    Y = gy + 0.5
    tp = tri_px[sel]
    ar = area[sel][:, None, None]
    a = tp[:, 0][:, None, None, :]
    b = tp[:, 1][:, None, None, :]
    c = tp[:, 2][:, None, None, :]
    w0 = ((b[..., 0] - X) * (c[..., 1] - Y) - (b[..., 1] - Y) * (c[..., 0] - X)) / ar
    w1 = ((c[..., 0] - X) * (a[..., 1] - Y) - (c[..., 1] - Y) * (a[..., 0] - X)) / ar
    w2 = 1.0 - w0 - w1
    eps = -1e-5
    inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps) & (gx < W) & (gy < H)
    k, yy, xx = np.nonzero(inside)
    px, py = gx[k, yy, xx], gy[k, yy, xx]
    tid[py, px] = sel[k]
    bary[py, px, 0] = w0[k, yy, xx]
    bary[py, px, 1] = w1[k, yy, xx]
    bary[py, px, 2] = w2[k, yy, xx]


# ---------------------------------------------------------------------------------------------
# gutter filling
# ---------------------------------------------------------------------------------------------
def _dilate_once(arrs, mask):
    acc = [np.zeros_like(a, dtype=np.float32) for a in arrs]
    cnt = np.zeros(mask.shape, np.float32)
    m = mask.astype(np.float32)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        ms = np.roll(np.roll(m, dy, axis=0), dx, axis=1)
        cnt += ms
        for k, a in enumerate(arrs):
            sa = np.roll(np.roll(a, dy, axis=0), dx, axis=1)
            acc[k] += sa * (ms if a.ndim == 2 else ms[..., None])
    grow = (~mask) & (cnt > 0)
    for k, a in enumerate(arrs):
        if a.ndim == 2:
            a[grow] = acc[k][grow] / cnt[grow]
        else:
            a[grow] = acc[k][grow] / cnt[grow][:, None]
    return mask | grow


def _pushpull(a, mask):
    """Fill a[~mask] from a coarse-to-fine pyramid of the masked average."""
    H, W = mask.shape
    chans = a.shape[2] if a.ndim == 3 else 1
    A = (a.reshape(H, W, chans) * mask[..., None]).astype(np.float64)
    M = mask.astype(np.float64)
    levels = []
    while A.shape[0] > 1 and A.shape[1] > 1 and A.shape[0] % 2 == 0 and A.shape[1] % 2 == 0:
        levels.append((A, M))
        h, w = A.shape[0] // 2, A.shape[1] // 2
        A = A.reshape(h, 2, w, 2, chans).sum(axis=(1, 3))
        M = M.reshape(h, 2, w, 2).sum(axis=(1, 3))
    cur = np.where(M[..., None] > 0, A / np.maximum(M, 1e-12)[..., None], 0.0)
    for A, M in reversed(levels):
        up = np.repeat(np.repeat(cur, 2, axis=0), 2, axis=1)
        own = A / np.maximum(M, 1e-12)[..., None]
        cur = np.where(M[..., None] > 0, own, up)
    out = cur.reshape(a.shape).astype(a.dtype)
    res = a.copy()
    res[~mask] = out[~mask]
    return res


def fill_gutters(arrays, mask, dilate=4):
    """In-place: grow every array `dilate` texels out of the charts, then fill the rest."""
    m = mask.copy()
    for _ in range(dilate):
        m = _dilate_once(arrays, m)
    for k, a in enumerate(arrays):
        arrays[k][...] = _pushpull(a, m)
    return m
