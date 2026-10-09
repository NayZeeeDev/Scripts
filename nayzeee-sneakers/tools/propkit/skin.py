"""
Clean a clothing mesh for use as a prop: drop the wearer's skin (open-toe heels,
sandals) and anything mapped to transparent texels (cut out on the worn shoe,
but a prop would draw it solid). Triangles are classified by the texture under them.
"""

import colorsys

import numpy as np


def is_skin(rgb):
    r, g, b = [c / 255.0 for c in rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return (h <= 40 / 360 or h >= 350 / 360) and 0.22 <= s <= 0.7 and v >= 0.3 and r > g > b and (r - b) > 0.12


def components(pos, tris):
    """Connected pieces of the mesh (vertices welded by position)."""
    key = {tuple(np.round(p, 5)): i for i, p in enumerate(pos)}
    weld = np.array([key[tuple(np.round(p, 5))] for p in pos])
    parent = list(range(len(pos)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b, c in weld[tris]:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    return np.array([find(weld[t[0]]) for t in tris])


def strip_skin(pos, nrm, uv, idx, texture, samples=4, piece_ratio=0.35, skin=True, alpha=True):
    """texture: RGBA numpy array (reference colourway). Returns the mesh without skin triangles.
    Whole mesh pieces that are mostly skin go too, so no stray bits of foot are left behind."""
    h, w = texture.shape[:2]
    tris = idx.reshape(-1, 3)
    keep = np.ones(len(tris), bool)
    for t, (a, b, c) in enumerate(tris):
        votes = 0
        pts = [(uv[a] + uv[b] + uv[c]) / 3, (uv[a] * 2 + uv[b] + uv[c]) / 4,
               (uv[a] + uv[b] * 2 + uv[c]) / 4, (uv[a] + uv[b] + uv[c] * 2) / 4][:samples]
        for u, v in pts:
            px = texture[min(h - 1, int((v % 1.0) * h)), min(w - 1, int((u % 1.0) * w))]
            # transparent texels are cut out on the worn shoe; a prop would draw them solid
            votes += (skin and is_skin(px)) or (alpha and px[3] < 128)
        keep[t] = votes * 2 < len(pts)
    comp = components(pos, tris)
    for cid in np.unique(comp):
        sel = comp == cid
        if (~keep[sel]).mean() >= piece_ratio:
            keep[sel] = False
    kept = tris[keep]
    used, inv = np.unique(kept.ravel(), return_inverse=True)
    return pos[used], nrm[used], uv[used], inv.astype(np.int64), int((~keep).sum())


def resolve_overlaps(pos, nrm, uv, idx, texture, keep_rule, xy=0.008, dz=0.004):
    """Two surfaces stacked a millimetre apart flicker (z-fighting). Where an upward-facing
    triangle sits on top of one whose texel passes keep_rule(rgba), drop the other one."""
    h, w = texture.shape[:2]
    tris = idx.reshape(-1, 3)
    p = pos[tris]
    fn = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    cu = uv[tris].mean(1)
    px = texture[np.minimum(h - 1, (cu[:, 1] % 1 * h).astype(int)), np.minimum(w - 1, (cu[:, 0] % 1 * w).astype(int))]
    good = np.array([keep_rule(c) for c in px])
    up = fn[:, 2] > 0.5
    c = p.mean(1)
    ref = c[up & good]
    drop = np.zeros(len(tris), bool)
    for t in np.nonzero(up & ~good)[0]:
        d = ref - c[t]
        if np.any((np.abs(d[:, 2]) < dz) & (np.hypot(d[:, 0], d[:, 1]) < xy)):
            drop[t] = True
    kept = tris[~drop]
    used, inv = np.unique(kept.ravel(), return_inverse=True)
    return pos[used], nrm[used], uv[used], inv.astype(np.int64), int(drop.sum())
