"""
Turn a worn pair of shoes (ped space, standing) into a boxed pair and put the
origin at the bottom centre.

  lay="flat"  sneakers: both shoes upright along X, heel-to-toe (a real shoe box)
  lay="side"  heels and boots: both lying on their side, one flipped so the foot
              of one nests against the shaft of the other (a real boot box)
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


def _rot_y(p, deg):
    r = np.radians(deg)
    c, s = np.cos(r), np.sin(r)
    out = p.copy()
    out[:, 0] = p[:, 0] * c + p[:, 2] * s
    out[:, 2] = -p[:, 0] * s + p[:, 2] * c
    return out


def _sub(pos, nrm, uv, tris):
    used, inv = np.unique(tris.ravel(), return_inverse=True)
    return pos[used].copy(), nrm[used].copy(), uv[used].copy(), inv.astype(np.int64)


def _surface_points(p, i):
    """Vertices plus triangle centres and edge midpoints, so big low-poly faces still count."""
    t = p[i.reshape(-1, 3)]
    return np.concatenate([p, t.mean(1), (t[:, 0] + t[:, 1]) / 2, (t[:, 1] + t[:, 2]) / 2, (t[:, 2] + t[:, 0]) / 2])


def box_layout(pos, nrm, uv, idx, lay="flat", gap=0.004, slice_w=0.004):
    """Returns pos, nrm, uv, idx of the arranged pair plus its size (x, y, z)."""
    left, right = split_pair(pos, idx)
    parts = []
    for k, tris in enumerate((left, right)):
        p, n, t, i = _sub(pos, nrm, uv, tris)
        if lay == "side":
            # height (Z) -> X, the outer side faces up; the second shoe is turned end for end
            sign = -1.0 if k == 0 else 1.0
            p, n = _rot_y(p, 90.0 * sign), _rot_y(n, 90.0 * sign)
            if k == 1:
                p, n = _rot_z(p, 180.0), _rot_z(n, 180.0)
            p[:, 2] -= p[:, 2].min()                            # both resting on the floor
        else:
            # ped forward is +Y; one shoe toe -> +X, the other toe -> -X
            deg = -90.0 if k == 0 else 90.0
            p, n = _rot_z(p, deg), _rot_z(n, deg)
        p[:, 0] -= (p[:, 0].min() + p[:, 0].max()) / 2          # centre along the length
        parts.append([p, n, t, i])

    # slide shoe B along -Y until it clears shoe A in every slice along X. For side-laid
    # pairs also try offsetting B along X, so a foot can tuck in beside the other's opening.
    pa = _surface_points(parts[0][0], parts[0][3])
    pb0 = _surface_points(parts[1][0], parts[1][3])

    def clearance(pb):
        x0 = min(pa[:, 0].min(), pb[:, 0].min())
        x1 = max(pa[:, 0].max(), pb[:, 0].max())
        need = -np.inf
        for xs in np.arange(x0, x1, slice_w):
            a = pa[(pa[:, 0] >= xs - slice_w) & (pa[:, 0] < xs + 2 * slice_w)]
            b = pb[(pb[:, 0] >= xs - slice_w) & (pb[:, 0] < xs + 2 * slice_w)]
            if len(a) and len(b):
                need = max(need, b[:, 1].max() - a[:, 1].min())
        return need

    best = (np.inf, 0.0, 0.0)
    shifts = np.arange(-0.15, 0.1501, 0.01) if lay == "side" else [0.0]
    for dx in shifts:
        pb = pb0 + [dx, 0.0, 0.0]
        need = clearance(pb)
        if not np.isfinite(need):
            continue
        pb = pb - [0.0, need + gap, 0.0]
        allp = np.concatenate([pa, pb])
        ext = allp.max(0) - allp.min(0)
        score = ext[0] * ext[1] + 0.5 * max(ext[0], ext[1]) ** 2   # small and not too long
        if score < best[0]:
            best = (score, dx, need)
    _, dx, need = best
    parts[1][0][:, 0] += dx
    parts[1][0][:, 1] -= need + gap

    pos2 = np.concatenate([parts[0][0], parts[1][0]])
    nrm2 = np.concatenate([parts[0][1], parts[1][1]])
    uv2 = np.concatenate([parts[0][2], parts[1][2]])
    idx2 = np.concatenate([parts[0][3], parts[1][3] + len(parts[0][0])])
    lo, hi = pos2.min(axis=0), pos2.max(axis=0)
    pos2 -= [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]
    return pos2, nrm2, uv2, idx2, hi - lo
