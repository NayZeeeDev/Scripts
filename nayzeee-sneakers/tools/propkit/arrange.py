"""
Turn a worn pair of shoes (ped space, standing) into a boxed pair:
split left/right, lay them along X heel-to-toe like a real shoe box, and
put the origin at the bottom centre.
"""

import numpy as np


def split_pair(pos, idx):
    """Triangle lists for the -X shoe and the +X shoe (by triangle centroid)."""
    tris = idx.reshape(-1, 3)
    cx = pos[tris].mean(axis=1)[:, 0]
    mid = (pos[:, 0].min() + pos[:, 0].max()) / 2
    return tris[cx < mid], tris[cx >= mid]


def _rot_z(p, deg):
    r = np.radians(deg)
    c, s = np.cos(r), np.sin(r)
    out = p.copy()
    out[:, 0] = p[:, 0] * c - p[:, 1] * s
    out[:, 1] = p[:, 0] * s + p[:, 1] * c
    return out


def _sub(pos, nrm, uv, tris):
    used, inv = np.unique(tris.ravel(), return_inverse=True)
    return pos[used].copy(), nrm[used].copy(), uv[used].copy(), inv.astype(np.int64)


def box_layout(pos, nrm, uv, idx, gap=0.004, slice_w=0.004):
    """Returns pos, nrm, uv, idx of the arranged pair plus its size (x, y, z)."""
    left, right = split_pair(pos, idx)
    parts = []
    # ped forward is +Y; one shoe toe -> +X, the other toe -> -X
    for tris, deg in ((left, -90.0), (right, 90.0)):
        p, n, t, i = _sub(pos, nrm, uv, tris)
        p, n = _rot_z(p, deg), _rot_z(n, deg)
        p[:, 0] -= (p[:, 0].min() + p[:, 0].max()) / 2      # centre along the length
        parts.append([p, n, t, i])

    # slide shoe B along -Y until it clears shoe A in every 4 mm slice
    (pa, *_), (pb, *_) = parts
    x0 = min(pa[:, 0].min(), pb[:, 0].min())
    x1 = max(pa[:, 0].max(), pb[:, 0].max())
    need = -np.inf
    for xs in np.arange(x0, x1, slice_w):
        a = pa[(pa[:, 0] >= xs) & (pa[:, 0] < xs + slice_w)]
        b = pb[(pb[:, 0] >= xs) & (pb[:, 0] < xs + slice_w)]
        if len(a) and len(b):
            need = max(need, b[:, 1].max() - a[:, 1].min())
    parts[1][0][:, 1] -= need + gap

    pos2 = np.concatenate([parts[0][0], parts[1][0]])
    nrm2 = np.concatenate([parts[0][1], parts[1][1]])
    uv2 = np.concatenate([parts[0][2], parts[1][2]])
    idx2 = np.concatenate([parts[0][3], parts[1][3] + len(parts[0][0])])
    lo, hi = pos2.min(axis=0), pos2.max(axis=0)
    pos2 -= [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]
    return pos2, nrm2, uv2, idx2, hi - lo
