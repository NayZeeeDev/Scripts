"""
Geometry for bagforge: soft "pillow" bodies, swept tubes (handles, piping,
straps), spheres, rings and small hardware. Everything is built in metres,
Z up, Y = front/back, X = left/right, and gets atlas UVs on the way out.
"""
import math

import numpy as np


class Mesh:
    def __init__(self):
        self.p, self.n, self.uv, self.idx = [], [], [], []

    def add(self, m):
        base = len(self.p)
        self.p += m.p; self.n += m.n; self.uv += m.uv
        self.idx += [i + base for i in m.idx]
        return self

    # ---- helpers -------------------------------------------------------
    def arrays(self):
        return (np.array(self.p, float), np.array(self.n, float),
                np.array(self.uv, float), np.array(self.idx, int).reshape(-1, 3))

    def transform(self, R=None, t=(0, 0, 0)):
        R = np.eye(3) if R is None else np.asarray(R, float)
        self.p = [tuple(R @ np.array(p) + np.array(t)) for p in self.p]
        self.n = [tuple(R @ np.array(n)) for n in self.n]
        return self


def rot_z(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot_x(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _grid(P, U, V, closed_u, flip=False):
    """P: (nv, nu, 3) points. Builds tris, smooth normals (seam-welded)."""
    nv, nu, _ = P.shape
    m = Mesh()
    for j in range(nv):
        for i in range(nu):
            m.p.append(tuple(P[j, i])); m.uv.append((U[j, i], V[j, i]))
    for j in range(nv - 1):
        for i in range(nu - 1):
            a = j * nu + i; b = a + 1; c = a + nu; d = c + 1
            if flip:
                m.idx += [a, c, b, b, c, d]
            else:
                m.idx += [a, b, c, b, d, c]
    smooth_normals(m)
    return m


def smooth_normals(m):
    p = np.array(m.p); idx = np.array(m.idx).reshape(-1, 3)
    fn = np.cross(p[idx[:, 1]] - p[idx[:, 0]], p[idx[:, 2]] - p[idx[:, 0]])
    vn = np.zeros_like(p)
    for k in range(3):
        np.add.at(vn, idx[:, k], fn)
    # weld normals of coincident points (uv seams, poles)
    keys = {}
    for i, q in enumerate(np.round(p, 5)):
        keys.setdefault(tuple(q), []).append(i)
    for group in keys.values():
        if len(group) > 1:
            s = vn[group].sum(0)
            vn[group] = s
    ln = np.linalg.norm(vn, axis=1, keepdims=True)
    vn = vn / np.where(ln < 1e-12, 1, ln)
    m.n = [tuple(v) for v in vn]


# ---- 2D sections --------------------------------------------------------

def rounded_rect(w, h, r, n=64, bulge=0.0):
    """Closed CCW outline, centred, with a little outward bulge on the flats."""
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
               (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    per = max(4, n // 4)
    for cx, cy, a0 in corners:
        for k in range(per):
            a = math.radians(a0 + 90 * k / (per - 1))
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts = resample(pts, n)
    if bulge:
        out = []
        for x, y in pts:
            fx = 1 + bulge * (1 - (2 * y / h) ** 2) * 0.5
            fy = 1 + bulge * (1 - (2 * x / w) ** 2) * 0.5
            out.append((x * fx, y * fy))
        pts = out
    return pts


def arch_rect(w, h, rt, rb, n=96):
    """Closed CCW outline, centred: rounded rect with big top corners
    (`rt`) and small bottom ones (`rb`), the classic backpack front."""
    pts = []
    corners = [(w / 2 - rt, h / 2 - rt, rt, 0), (-w / 2 + rt, h / 2 - rt, rt, 90),
               (-w / 2 + rb, -h / 2 + rb, rb, 180), (w / 2 - rb, -h / 2 + rb, rb, 270)]
    for cx, cy, r, a0 in corners:
        for k in range(24):
            a = math.radians(a0 + 90 * k / 23)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return resample(pts, n)


def superellipse(w, h, e=4.0, n=64):
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        pts.append((w / 2 * math.copysign(abs(c) ** (2 / e), c), h / 2 * math.copysign(abs(s) ** (2 / e), s)))
    return pts


def dome(w, h, flat=0.25, n=64):
    """Bowling-bag profile: arched top, flat bottom `flat * h` deep with
    rounded corners, evenly spaced."""
    pts = []
    for k in range(200):                       # arch, right to left
        a = math.pi * k / 200
        pts.append((w / 2 * math.cos(a), h * (math.sin(a) ** 0.85)))
    fb = flat * h
    r = min(fb, w * 0.2)
    for k in range(40):                        # left corner, down and round
        a = math.pi + math.pi / 2 * k / 40
        pts.append((-w / 2 + r + r * math.cos(a), -fb + r + r * math.sin(a)))
    for k in range(40):                        # right corner, round and up
        a = 1.5 * math.pi + math.pi / 2 * k / 40
        pts.append((w / 2 - r + r * math.cos(a), -fb + r + r * math.sin(a)))
    return resample(pts, n)


def heart(w, h, n=96):
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 32 * w, (y + 5) / 30 * h))
    pts.reverse()
    return pts


def polygon(w, h, sides=6, r=0.15, n=72):
    """Rounded regular-ish polygon (hexagon bag)."""
    base = []
    for k in range(sides):
        a = 2 * math.pi * k / sides + math.pi / 2
        base.append((w / 2 * math.cos(a), h / 2 * math.sin(a)))
    pts = []
    per = max(3, n // sides)
    for k in range(sides):
        p0 = np.array(base[k - 1]); p1 = np.array(base[k]); p2 = np.array(base[(k + 1) % sides])
        a = p1 + (p0 - p1) * r; b = p1 + (p2 - p1) * r
        for j in range(per):
            t = j / (per - 1)
            q = (1 - t) ** 2 * a + 2 * (1 - t) * t * p1 + t ** 2 * b
            pts.append(tuple(q))
    return resample(pts, n)


def resample(pts, n):
    P = np.array(pts + [pts[0]], float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    L = cum[-1]
    out = []
    for k in range(n):
        s = L * k / n
        i = np.searchsorted(cum, s, side='right') - 1
        t = (s - cum[i]) / max(seg[i], 1e-9)
        out.append(tuple(P[i] + (P[i + 1] - P[i]) * t))
    return out


def perimeter(pts):
    P = np.array(pts + [pts[0]], float)
    return float(np.linalg.norm(np.diff(P, axis=0), axis=1).sum())


# ---- bodies ---------------------------------------------------------------

def pillow(section, length, k=6.0, nt=40, region=(0, 0, 1, 1), density=None,
           axis='x', taper=None, swell=0.0, cap=0.88):
    """
    Extrude a closed 2D section along `axis` over [-length/2, length/2],
    closing both ends with a superellipse profile (k high = flat ends with
    a rounded rim, k=2 = fully round). `taper(t)` scales the section's first
    coordinate along the length (t in -1..1), `swell` fattens the middle.
    UVs: around the section x along the length, metres * density, offset
    into `region` (u0, v0, u1, v1) of the atlas. Past |t| > `cap` the ends
    are mapped flat (seen face-on) so prints don't pinch into a star.
    """
    sec = list(section)
    ns = len(sec)
    # start the loop (where the texture wraps) underneath, or at the back for
    # upright bags, where the seam won't be seen
    ys = [p[1] for p in sec]
    st = ys.index(max(ys)) if axis == 'z' else ys.index(min(ys))
    sec = sec[st:] + sec[:st]
    L = length / 2
    # length steps bunched near the ends where the profile turns
    ts = []
    for j in range(nt + 1):
        a = -1 + 2 * j / nt
        ts.append(math.copysign(abs(a) ** 0.6, a))
    per = perimeter(sec)
    u0, v0, u1, v1 = region
    dens = min(density or 1e9, (u1 - u0) / per * 0.995, (v1 - v0) / length * 0.995)
    arc = [0.0]
    for i in range(1, ns + 1):
        a = np.array(sec[i - 1]); b = np.array(sec[i % ns])
        arc.append(arc[-1] + float(np.linalg.norm(b - a)))

    P = np.zeros((nt + 1, ns + 1, 3)); U = np.zeros((nt + 1, ns + 1)); V = np.zeros((nt + 1, ns + 1))
    for j, t in enumerate(ts):
        s = (1 - abs(t) ** k) ** (1 / k) if abs(t) < 1 else 0.0
        s *= 1 + swell * (1 - t * t)
        tx = taper(t) if taper else 1.0
        for i in range(ns + 1):
            x, y = sec[i % ns]
            x *= s * tx; y *= s
            z = t * L
            if axis == 'x':
                P[j, i] = (z, x, y)
            elif axis == 'y':
                P[j, i] = (x, z, y)
            else:
                P[j, i] = (x, y, z)
            U[j, i] = u0 + arc[i] * dens
            V[j, i] = v0 + (t + 1) * L * dens
    flip = axis == 'y'
    if not cap or not density:
        return _grid(P, U, V, True, flip=flip)
    # flat UVs for the end caps: the section's own (x, y), scaled the same
    Q = np.zeros((nt + 1, ns + 1, 2))
    for j, t in enumerate(ts):
        s = (1 - abs(t) ** k) ** (1 / k) if abs(t) < 1 else 0.0
        s *= 1 + swell * (1 - t * t)
        tx = taper(t) if taper else 1.0
        for i in range(ns + 1):
            x, y = sec[i % ns]
            Q[j, i] = (x * s * tx, y * s)
    lo = Q.reshape(-1, 2).min(0)
    a = next(j for j, t in enumerate(ts) if t > -cap)
    b = max(j for j, t in enumerate(ts) if t < cap)
    m = Mesh()   # seam rings a-1 and b+1 are shared (duplicated) between pieces
    for rows, flat in ((slice(0, a), True), (slice(a - 1, b + 2), False), (slice(b + 1, nt + 1), True)):
        if rows.stop - rows.start < 2:     # too few rings to need a cap
            continue
        if flat:
            m.add(_grid(P[rows], u0 + (Q[rows, :, 0] - lo[0]) * dens, v0 + (Q[rows, :, 1] - lo[1]) * dens, True, flip=flip))
        else:
            m.add(_grid(P[rows], U[rows], V[rows], True, flip=flip))
    smooth_normals(m)
    return m


def shell_frame(section):
    """How shell() walks a section: starting at the bottom centre, the
    running arc length at each point, and the index where the halves meet."""
    sec = list(section)
    ns = len(sec)
    ymin = min(p[1] for p in sec)
    st = min((i for i in range(ns) if sec[i][1] < ymin + 1e-3), key=lambda i: abs(sec[i][0]))
    sec = sec[st:] + sec[:st]
    arc = [0.0]
    for i in range(1, ns + 1):
        arc.append(arc[-1] + float(np.linalg.norm(np.subtract(sec[i % ns], sec[i - 1]))))
    h = min(range(ns + 1), key=lambda i: abs(arc[i] - arc[-1] / 2))
    return sec, arc, h


def shell(section, depth, k=6.0, nt=30, swell=0.0, cap=0.88, front_uv=None, back_uv=None, band_uv=None):
    """
    A pillow standing upright (section in X/Z, `depth` along Y) whose three
    faces each get their own UVs, so front art isn't repeated on the back:
      front_uv(x, z) / back_uv(x, z)   the -Y / +Y faces, from section coords
      band_uv(half, s, d)              the sides: half 0 = +X side, 1 = -X side,
                                       s metres from the bottom centre, d metres
                                       from the front
    """
    sec, arc, h = shell_frame(section)
    ns = len(sec)
    L = depth / 2
    ts = [math.copysign(abs(a) ** 0.6, a) for a in (-1 + 2 * j / nt for j in range(nt + 1))]

    P = np.zeros((nt + 1, ns + 1, 3)); Q = np.zeros((nt + 1, ns + 1, 2))
    for j, t in enumerate(ts):
        s = (1 - abs(t) ** k) ** (1 / k) if abs(t) < 1 else 0.0
        s *= 1 + swell * (1 - t * t)
        for i in range(ns + 1):
            x, y = sec[i % ns]
            P[j, i] = (x * s, t * L, y * s)
            Q[j, i] = (x * s, y * s)
    a = next(j for j, t in enumerate(ts) if t > -cap)
    b = max(j for j, t in enumerate(ts) if t < cap)

    def uvs(rows, cols, fn):
        U = np.zeros((len(rows), len(cols))); V = np.zeros_like(U)
        for jj, j in enumerate(rows):
            for ii, i in enumerate(cols):
                U[jj, ii], V[jj, ii] = fn(j, i)
        return U, V

    m = Mesh()
    pieces = [
        (range(0, a), range(0, ns + 1), lambda j, i: front_uv(*Q[j, i])),
        (range(b + 1, nt + 1), range(0, ns + 1), lambda j, i: back_uv(*Q[j, i])),
        (range(a - 1, b + 2), range(0, h + 1), lambda j, i: band_uv(0, arc[i], (ts[j] + 1) * L)),
        (range(a - 1, b + 2), range(h, ns + 1), lambda j, i: band_uv(1, arc[i] - arc[h], (ts[j] + 1) * L)),
    ]
    for rows, cols, fn in pieces:
        rows, cols = list(rows), list(cols)
        if len(rows) < 2:
            continue
        U, V = uvs(rows, cols, fn)
        m.add(_grid(P[np.ix_(rows, cols)], U, V, False, flip=True))
    smooth_normals(m)
    return m


# ---- sweeps ---------------------------------------------------------------

def sweep(path, radius, sides=12, region=(0, 0, 1, 1), flat=1.0, closed=False, twist_up=(0, 0, 1), flat_n=1.0):
    """Tube along a polyline; `flat` / `flat_n` < 1 squash it into a strap
    (thin across the binormal / the normal)."""
    path = [np.array(p, float) for p in path]
    n = len(path)
    T = []
    for i in range(n):
        a = path[max(i - 1, 0)]; b = path[min(i + 1, n - 1)]
        if closed:
            a = path[i - 1]; b = path[(i + 1) % n]
        d = b - a; T.append(d / (np.linalg.norm(d) + 1e-12))
    up = np.array(twist_up, float)
    seg = [0.0]
    for i in range(1, n):
        seg.append(seg[-1] + float(np.linalg.norm(path[i] - path[i - 1])))
    total = seg[-1] or 1.0
    u0, v0, u1, v1 = region
    P = np.zeros((n, sides + 1, 3)); U = np.zeros((n, sides + 1)); V = np.zeros((n, sides + 1))
    N0 = np.cross(T[0], up)
    if np.linalg.norm(N0) < 1e-6:
        N0 = np.cross(T[0], [1, 0, 0])
    N0 /= np.linalg.norm(N0)
    N = N0
    for i in range(n):
        if i > 0:  # parallel transport
            N = N - T[i] * np.dot(N, T[i]); N /= (np.linalg.norm(N) + 1e-12)
        B = np.cross(T[i], N)
        for k in range(sides + 1):
            a = 2 * math.pi * k / sides
            off = N * math.cos(a) * radius * flat_n + B * math.sin(a) * radius * flat
            P[i, k] = path[i] + off
            U[i, k] = u0 + (u1 - u0) * k / sides
            V[i, k] = v0 + (v1 - v0) * seg[i] / total
    m = _grid(P, U, V, True)
    if not closed:
        # end caps
        for i, sign in ((0, -1), (n - 1, 1)):
            c = Mesh()
            c.p.append(tuple(path[i])); c.uv.append(((u0 + u1) / 2, v0))
            ring = [tuple(P[i, k]) for k in range(sides)]
            for q in ring:
                c.p.append(q); c.uv.append(((u0 + u1) / 2, v0))
            for k in range(sides):
                a, b = 1 + k, 1 + (k + 1) % sides
                c.idx += [0, b, a] if sign < 0 else [0, a, b]
            smooth_normals(c)
            m.add(c)
    return m


def arc_path(a, b, height, n=40, bow=0.0):
    """Handle arch from a to b rising `height` above them."""
    a, b = np.array(a, float), np.array(b, float)
    out = []
    for k in range(n + 1):
        t = k / n
        p = a + (b - a) * t
        lift = math.sin(math.pi * t) ** 0.9 * height
        p = p + np.array([0, 0, lift]) + np.array([0, bow * math.sin(math.pi * t), 0])
        out.append(p)
    return out


def bezier(points, n=40):
    P = [np.array(p, float) for p in points]
    out = []
    for k in range(n + 1):
        t = k / n
        Q = P[:]
        while len(Q) > 1:
            Q = [Q[i] * (1 - t) + Q[i + 1] * t for i in range(len(Q) - 1)]
        out.append(Q[0])
    return out


def ring_path(radius, n=32):
    return [np.array((radius * math.cos(2 * math.pi * k / n), 0, radius * math.sin(2 * math.pi * k / n))) for k in range(n)]


# ---- small solids ----------------------------------------------------------

def sphere(r, n=14, region=(0, 0, 1, 1), scale=(1, 1, 1)):
    u0, v0, u1, v1 = region
    P = np.zeros((n + 1, 2 * n + 1, 3)); U = np.zeros_like(P[..., 0]); V = np.zeros_like(P[..., 0])
    for j in range(n + 1):
        th = math.pi * j / n
        for i in range(2 * n + 1):
            ph = 2 * math.pi * i / (2 * n)
            P[j, i] = (r * scale[0] * math.sin(th) * math.cos(ph), r * scale[1] * math.sin(th) * math.sin(ph), r * scale[2] * math.cos(th))
            U[j, i] = u0 + (u1 - u0) * i / (2 * n); V[j, i] = v0 + (v1 - v0) * j / n
    return _grid(P, U, V, True, flip=True)


def box(w, d, h, r=0.004, region=(0, 0, 1, 1), density=None):
    """Small rounded box (hardware plates, tags, padlock bodies), centred."""
    return pillow(rounded_rect(w, d, r, n=24), h, k=10, nt=10, region=region, axis='z', density=density)


def torus(R, r, region=(0, 0, 1, 1), sides=10, n=28):
    return sweep(ring_path(R, n) + [ring_path(R, n)[0]], r, sides=sides, region=region)


def disc_studs(points, r, region):
    m = Mesh()
    for p in points:
        s = sphere(r, n=6, region=region, scale=(1, 1, 0.6))
        s.transform(t=p)
        m.add(s)
    return m


# ---- tangents --------------------------------------------------------------

def tangents(P, N, UV, I):
    t = np.zeros_like(P); b = np.zeros_like(P)
    for tri in I:
        i0, i1, i2 = tri
        e1, e2 = P[i1] - P[i0], P[i2] - P[i0]
        du1, dv1 = UV[i1] - UV[i0]; du2, dv2 = UV[i2] - UV[i0]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            continue
        r = 1.0 / det
        sd = (e1 * dv2 - e2 * dv1) * r
        td = (e2 * du1 - e1 * du2) * r
        t[tri] += sd; b[tri] += td
    out = np.zeros((len(P), 4))
    for i in range(len(P)):
        n = N[i]; tt = t[i] - n * np.dot(n, t[i])
        ln = np.linalg.norm(tt)
        if ln < 1e-9:
            a = np.array([1, 0, 0]) if abs(n[0]) < 0.9 else np.array([0, 1, 0])
            tt = np.cross(n, a); ln = np.linalg.norm(tt)
        tt /= ln
        w = -1.0 if np.dot(np.cross(n, tt), b[i]) < 0 else 1.0
        out[i, :3] = tt; out[i, 3] = w
    return out
