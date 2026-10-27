"""
nzprops.mesh - geometry for procedural GTA V props.

Everything is built from *charts*: a chart is a small triangle mesh with its own 2D metric
parametrisation (``uvm``, metres along the surface). Charts are later packed into a texture
atlas automatically (nzprops.atlas), so prop code never deals with UV layouts.

Coordinate system: GTA V - metres, +X right, +Y forward, +Z up. Front faces are counter
clockwise seen from outside; every primitive fixes its winding against its normals, so the
order in which you list points never flips a face.

Primitives (all return a ``Geo``):
    box            box with optional rounded / bevelled edges (cube-sphere rounding)
    lathe          surface of revolution from a (r, z) profile (cylinders, knobs, caps, cones)
    cylinder       convenience lathe with bevelled caps
    capsule, sphere, torus
    sweep          any 2D profile swept along a 3D path (tubes, straps, rails, cables)
    tube           circle profile sweep
    extrude        2D polygon extruded along +Z with optional rounded bevel
    plane          single quad (optionally with fixed UVs for screens)

Path / profile helpers: circle, rect_profile, rrect, ellipse, polyline_fillet, catmull,
arc_points, bezier.

``Geo`` supports translate / rotate / scale / mirror / merge (``+``) and material assignment.
"""
from __future__ import annotations

import math
from typing import Iterable

import numpy as np

EPS = 1e-9


# ---------------------------------------------------------------------------------------------
# small math helpers
# ---------------------------------------------------------------------------------------------
def vec(*a) -> np.ndarray:
    if len(a) == 1:
        return np.asarray(a[0], dtype=np.float64)
    return np.asarray(a, dtype=np.float64)


def normalize(v, axis=-1):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.where(n < 1e-15, 1.0, n)


def rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def euler(rx=0.0, ry=0.0, rz=0.0):
    """Rotation matrix applying X first, then Y, then Z (degrees, extrinsic)."""
    return rot_z(rz) @ rot_y(ry) @ rot_x(rx)


def axis_angle(axis, deg):
    axis = normalize(vec(axis))
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = axis
    C = 1 - c
    return np.array([
        [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, c + z * z * C],
    ], dtype=np.float64)


def look_basis(forward, up=(0, 0, 1)):
    """Orthonormal (right, up, forward) basis with forward = +Y of the returned matrix columns."""
    f = normalize(vec(forward))
    u = vec(up)
    if abs(float(np.dot(f, normalize(u)))) > 0.999:
        u = vec(1, 0, 0) if abs(f[0]) < 0.9 else vec(0, 1, 0)
    r = normalize(np.cross(f, u))
    u = normalize(np.cross(r, f))
    return np.stack([r, f, u], axis=1)  # columns: X=right, Y=forward, Z=up


# ---------------------------------------------------------------------------------------------
# chart & geo containers
# ---------------------------------------------------------------------------------------------
class Chart:
    """One UV island. pos/nrm (n,3), uvm (n,2) metric surface coordinates, tri (m,3).

    part  id of the pressable part this chart belongs to (None = the body / a normal prop); set by
          Builder.part() - decals only print on charts of their own part
    lod   'hm' (high + medium model, default), 'h' (high only: detail dropped at distance) or 'm'
          (medium only: a cheaper stand-in)
    """

    __slots__ = ("pos", "nrm", "uvm", "tri", "mat", "density", "tag", "fixed_uv", "part", "lod")

    def __init__(self, pos, nrm, uvm, tri, mat, density=1.0, tag="", fixed_uv=None, part=None, lod="hm"):
        self.pos = np.asarray(pos, dtype=np.float64).reshape(-1, 3)
        self.nrm = normalize(np.asarray(nrm, dtype=np.float64).reshape(-1, 3))
        self.uvm = np.asarray(uvm, dtype=np.float64).reshape(-1, 2)
        self.tri = np.asarray(tri, dtype=np.int64).reshape(-1, 3)
        self.mat = mat
        self.density = float(density)
        self.tag = tag
        self.fixed_uv = None if fixed_uv is None else np.asarray(fixed_uv, dtype=np.float64).reshape(-1, 2)
        self.part = part
        self.lod = lod

    def copy(self):
        return Chart(self.pos.copy(), self.nrm.copy(), self.uvm.copy(), self.tri.copy(), self.mat,
                     self.density, self.tag, None if self.fixed_uv is None else self.fixed_uv.copy(), self.part, self.lod)

    def clean(self):
        """Drop degenerate triangles and fix winding so every face points along its normals."""
        if len(self.tri) == 0:
            return self
        p = self.pos[self.tri]
        cr = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
        area2 = np.linalg.norm(cr, axis=1)
        keep = area2 > 1e-14
        n = self.nrm[self.tri].sum(axis=1)
        flip = (np.einsum("ij,ij->i", cr, n) < 0) & keep
        tri = self.tri.copy()
        tri[flip] = tri[flip][:, [0, 2, 1]]
        self.tri = tri[keep]
        return self

    def area(self):
        p = self.pos[self.tri]
        return float(np.linalg.norm(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]), axis=1).sum() * 0.5)


class Geo:
    """A list of charts with in-place transform helpers (all return self for chaining)."""

    def __init__(self, charts: Iterable[Chart] | None = None):
        self.charts: list[Chart] = [c for c in (charts or []) if c is not None and len(c.tri)]

    # composition --------------------------------------------------------------------------
    def __add__(self, other: "Geo"):
        return Geo([c.copy() for c in self.charts] + [c.copy() for c in other.charts])

    def __iadd__(self, other: "Geo"):
        self.charts.extend(c.copy() for c in other.charts)
        return self

    def copy(self):
        return Geo([c.copy() for c in self.charts])

    @staticmethod
    def merge(items: Iterable["Geo"]):
        g = Geo()
        for it in items:
            g += it
        return g

    # transforms ---------------------------------------------------------------------------
    def transform(self, m3, t=(0, 0, 0)):
        m3 = np.asarray(m3, dtype=np.float64)
        t = vec(t)
        nm = np.linalg.inv(m3).T
        det = np.linalg.det(m3)
        for c in self.charts:
            c.pos = c.pos @ m3.T + t
            c.nrm = normalize(c.nrm @ nm.T)
            if det < 0:
                c.tri = c.tri[:, [0, 2, 1]]
        return self

    def translate(self, x, y=None, z=None):
        if y is None:
            x, y, z = x
        for c in self.charts:
            c.pos = c.pos + vec(x, y, z)
        return self

    def rotate(self, rx=0.0, ry=0.0, rz=0.0, origin=(0, 0, 0)):
        o = vec(origin)
        self.translate(-o)
        self.transform(euler(rx, ry, rz))
        return self.translate(o)

    def rotate_axis(self, axis, deg, origin=(0, 0, 0)):
        o = vec(origin)
        self.translate(-o)
        self.transform(axis_angle(axis, deg))
        return self.translate(o)

    def scale(self, sx, sy=None, sz=None):
        if sy is None:
            sy = sz = sx
        m = np.diag([sx, sy, sz]).astype(np.float64)
        self.transform(m)
        g = (abs(sx * sy * sz)) ** (1.0 / 3.0)
        for c in self.charts:
            c.uvm = c.uvm * g
        return self

    def mirror(self, axis="x"):
        s = {"x": (-1, 1, 1), "y": (1, -1, 1), "z": (1, 1, -1)}[axis]
        self.transform(np.diag(s).astype(np.float64))
        for c in self.charts:
            c.uvm = c.uvm * vec(-1, 1)
        return self

    # attributes ---------------------------------------------------------------------------
    def set_mat(self, mat, only=None):
        for c in self.charts:
            if only is None or c.mat == only:
                c.mat = mat
        return self

    def set_density(self, d):
        for c in self.charts:
            c.density = d
        return self

    def set_tag(self, tag):
        for c in self.charts:
            c.tag = tag
        return self

    def set_part(self, part):
        """Assign every chart to a pressable part id (None = body). Builder.part() does this for you."""
        for c in self.charts:
            c.part = part
        return self

    def set_lod(self, lod):
        """'hm' both LODs (default), 'h' high only (fine detail), 'm' medium only (cheap stand-in)."""
        if lod not in ("hm", "h", "m"):
            raise ValueError(f"lod must be 'hm', 'h' or 'm', got {lod!r}")
        for c in self.charts:
            c.lod = lod
        return self

    def flip(self):
        """Turn the surface inside out (interiors of boxes, cavities)."""
        for c in self.charts:
            c.nrm = -c.nrm
            c.tri = c.tri[:, [0, 2, 1]]
            c.uvm = c.uvm * vec(-1, 1)
        return self

    def deform(self, fn, eps=1e-5):
        """Move every vertex through fn(P (n,3)) -> (n,3). Normals follow exactly through the
        numerical Jacobian (n' = J^-T n), so smooth surfaces stay smooth across chart seams."""
        for c in self.charts:
            p = c.pos
            q = fn(p)
            J = np.zeros((len(p), 3, 3))
            for k in range(3):
                d = np.zeros(3)
                d[k] = eps
                J[:, :, k] = (fn(p + d) - fn(p - d)) / (2 * eps)
            JT = np.transpose(J, (0, 2, 1))
            det = np.linalg.det(J)
            ok = np.abs(det) > 1e-14
            n = c.nrm.copy()
            if ok.any():
                n[ok] = np.linalg.solve(JT[ok], c.nrm[ok][:, :, None])[:, :, 0]
            c.nrm = normalize(n)
            if np.any(det[ok] < 0):
                c.tri = c.tri[:, [0, 2, 1]]
            c.pos = q
        return self

    def taper(self, z0, z1, s0, s1, cx=0.0, cy=0.0):
        """Scale X/Y linearly from s0 at z0 to s1 at z1 (around cx, cy)."""
        def fn(p):
            t = (p[:, 2] - z0) / (z1 - z0)
            s = s0 + (s1 - s0) * t
            q = p.copy()
            q[:, 0] = cx + (p[:, 0] - cx) * s
            q[:, 1] = cy + (p[:, 1] - cy) * s
            return q
        return self.deform(fn)

    def bbox(self):
        if not self.charts:
            return vec(0, 0, 0), vec(0, 0, 0)
        p = np.concatenate([c.pos for c in self.charts])
        return p.min(axis=0), p.max(axis=0)

    def tri_count(self):
        return sum(len(c.tri) for c in self.charts)

    def vert_count(self):
        return sum(len(c.pos) for c in self.charts)


# ---------------------------------------------------------------------------------------------
# grid helper
# ---------------------------------------------------------------------------------------------
def grid_tris(nu, nv, wrap_u=False):
    """Triangles of an nu x nv vertex grid (index = j*nu + i)."""
    tris = []
    cu = nu if wrap_u else nu - 1
    for j in range(nv - 1):
        for i in range(cu):
            i1 = (i + 1) % nu
            a, b, c, d = j * nu + i, j * nu + i1, (j + 1) * nu + i1, (j + 1) * nu + i
            tris.append((a, b, c))
            tris.append((a, c, d))
    return np.asarray(tris, dtype=np.int64).reshape(-1, 3)


# ---------------------------------------------------------------------------------------------
# box (rounded / bevelled)
# ---------------------------------------------------------------------------------------------
_FACES = {
    "+x": ((1, 0, 0), (0, 1, 0), (0, 0, -1)),
    "-x": ((-1, 0, 0), (0, -1, 0), (0, 0, -1)),
    "+y": ((0, 1, 0), (-1, 0, 0), (0, 0, -1)),
    "-y": ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
    "+z": ((0, 0, 1), (1, 0, 0), (0, -1, 0)),
    "-z": ((0, 0, -1), (-1, 0, 0), (0, -1, 0)),
}


def _axis_samples(h, r, n):
    if r <= 1e-9:
        return np.array([-h, h]), np.array([-h, h])
    inner = h - r
    th = np.linspace(0.0, math.pi / 4, n + 1)
    ap = inner + r * np.tan(th)
    al = inner + r * th
    if inner > 1e-9:
        return np.concatenate([-ap[::-1], ap]), np.concatenate([-al[::-1], al])
    return np.concatenate([-ap[::-1], ap[1:]]), np.concatenate([-al[::-1], al[1:]])


def box(size, mat, r=0.0, seg=2, center=(0, 0, 0), faces="+x -x +y -y +z -z", face_mat=None,
        density=1.0, face_density=None, tag="", rz=None):
    """Axis aligned box of `size` (sx, sy, sz) centred on `center`.

    r      edge radius (0 = sharp). seg = arc steps per 45 deg (1 = chamfer look, 2-3 = round).
    rz     optional different radius for edges parallel to the XY plane is not supported by the
           cube-sphere mapping; pass r for a uniform rounding.
    faces  which faces to emit, e.g. "+x -x +y -y +z" (skip hidden ones).
    face_mat / face_density: dicts {"+z": "label_mat"} to override per face.
    """
    H = np.asarray(size, dtype=np.float64) / 2.0
    r = float(min(r, H.min() * 0.999))
    inner = H - r
    g = Geo()
    for key in faces.split():
        n, U, V = (vec(a) for a in _FACES[key])
        ku = int(np.argmax(np.abs(U)))
        kv = int(np.argmax(np.abs(V)))
        kn = int(np.argmax(np.abs(n)))
        su, cu = _axis_samples(H[ku], r, seg)
        sv, cv = _axis_samples(H[kv], r, seg)
        nu, nv = len(su), len(sv)
        P = np.zeros((nv, nu, 3))
        P[:, :, kn] = n[kn] * H[kn]
        P[:, :, ku] = (U[ku] * su)[None, :]
        P[:, :, kv] = (V[kv] * sv)[:, None]
        P = P.reshape(-1, 3)
        if r > 1e-9:
            C = np.clip(P, -inner, inner)
            D = P - C
            L = np.linalg.norm(D, axis=1, keepdims=True)
            Nn = D / np.maximum(L, 1e-15)
            P = C + r * Nn
        else:
            Nn = np.tile(n, (len(P), 1))
        UV = np.zeros((nv, nu, 2))
        UV[:, :, 0] = cu[None, :]
        UV[:, :, 1] = cv[:, None]
        m = (face_mat or {}).get(key, mat)
        d = (face_density or {}).get(key, density)
        ch = Chart(P + vec(center), Nn, UV.reshape(-1, 2), grid_tris(nu, nv), m, d, f"{tag}{key}" if tag else key)
        g.charts.append(ch.clean())
    return g


# ---------------------------------------------------------------------------------------------
# lathe (surface of revolution around +Z)
# ---------------------------------------------------------------------------------------------
def _profile_runs(pts2, smooth_angle, sharp=None, closed=False):
    """Split a 2D polyline into smooth runs. Returns list of (indices, vertex normals) where
    normals are 2D outward normals (dy, -dx) averaged inside runs."""
    pts2 = np.asarray(pts2, dtype=np.float64)
    n = len(pts2)
    segs = (np.roll(pts2, -1, axis=0) - pts2) if closed else (pts2[1:] - pts2[:-1])
    lens = np.linalg.norm(segs, axis=1)
    sn = np.stack([segs[:, 1], -segs[:, 0]], axis=1) / np.maximum(lens, 1e-15)[:, None]
    nseg = len(segs)
    sharp_set = set(sharp or [])
    cos_lim = math.cos(math.radians(smooth_angle))

    def is_sharp(i):  # vertex i between seg i-1 and seg i
        if i in sharp_set:
            return True
        if not closed and (i == 0 or i == n - 1):
            return False
        a = sn[(i - 1) % nseg]
        b = sn[i % nseg]
        return float(np.dot(a, b)) < cos_lim

    if closed:
        sharp_idx = [i for i in range(n) if is_sharp(i)]
        if not sharp_idx:
            idx = list(range(n)) + [0]
            normals = []
            for k, i in enumerate(idx):
                a, b = sn[(i - 1) % nseg], sn[i % nseg]
                normals.append(normalize(a + b))
            return [(idx, np.asarray(normals), True)]
        runs = []
        for k, s in enumerate(sharp_idx):
            e = sharp_idx[(k + 1) % len(sharp_idx)]
            idx = [s]
            i = s
            while True:
                i = (i + 1) % n
                idx.append(i)
                if i == e:
                    break
            normals = []
            for kk, i in enumerate(idx):
                if kk == 0:
                    normals.append(sn[i % nseg])
                elif kk == len(idx) - 1:
                    normals.append(sn[(i - 1) % nseg])
                else:
                    normals.append(normalize(sn[(i - 1) % nseg] + sn[i % nseg]))
            runs.append((idx, np.asarray(normals), False))
        return runs
    runs = []
    start = 0
    for i in range(1, n):
        if i == n - 1 or is_sharp(i):
            idx = list(range(start, i + 1))
            normals = []
            for kk, j in enumerate(idx):
                if kk == 0:
                    normals.append(sn[j] if j < nseg else sn[-1])
                elif kk == len(idx) - 1:
                    normals.append(sn[j - 1])
                else:
                    normals.append(normalize(sn[j - 1] + sn[j]))
            runs.append((idx, np.asarray(normals), False))
            start = i
    return runs


def lathe(profile, mat, segs=32, sweep=360.0, start=0.0, smooth_angle=35.0, sharp=None,
          density=1.0, tag="", planar_caps=True):
    """Revolve a (r, z) profile around +Z. List the profile bottom -> top with the outside on the
    right hand side when walking it (e.g. (0,0) -> (R,0) -> (R,H) -> (0,H) for a closed cylinder).
    Vertices whose turning angle exceeds `smooth_angle` (or listed in `sharp`) get hard edges."""
    prof = np.asarray(profile, dtype=np.float64)
    full = abs(sweep - 360.0) < 1e-6
    phis = np.radians(start + np.linspace(0.0, sweep, segs + 1))
    g = Geo()
    for ri, (idx, n2, _) in enumerate(_profile_runs(prof, smooth_angle, sharp)):
        pr = prof[idx]
        if len(pr) < 2:
            continue
        nr = len(pr)
        cph, sph = np.cos(phis), np.sin(phis)
        P = np.zeros((nr, segs + 1, 3))
        N = np.zeros((nr, segs + 1, 3))
        P[:, :, 0] = pr[:, 0:1] * cph[None, :]
        P[:, :, 1] = pr[:, 0:1] * sph[None, :]
        P[:, :, 2] = pr[:, 1:2]
        N[:, :, 0] = n2[:, 0:1] * cph[None, :]
        N[:, :, 1] = n2[:, 0:1] * sph[None, :]
        N[:, :, 2] = n2[:, 1:2]
        planar = planar_caps and np.all(np.abs(n2[:, 1]) > 0.985)
        UV = np.zeros((nr, segs + 1, 2))
        if planar:
            sgn = 1.0 if n2[:, 1].mean() > 0 else -1.0
            UV[:, :, 0] = P[:, :, 0] * sgn
            UV[:, :, 1] = -P[:, :, 1]
        else:
            seglen = np.linalg.norm(np.diff(pr, axis=0), axis=1)
            s = np.concatenate([[0.0], np.cumsum(seglen)])
            rref = max(float(pr[:, 0].max()), 1e-4)
            UV[:, :, 0] = (phis - phis[0])[None, :] * rref
            UV[:, :, 1] = -s[:, None]
        tris = grid_tris(segs + 1, nr)
        ch = Chart(P.reshape(-1, 3), N.reshape(-1, 3), UV.reshape(-1, 2), tris, mat, density,
                   f"{tag}:{ri}" if tag else f"lathe:{ri}")
        g.charts.append(ch.clean())
    _ = full
    return g


def cylinder(radius, height, mat, segs=32, bevel=0.0, bevel_seg=2, z0=0.0, caps=(True, True),
             density=1.0, tag="", r_top=None):
    """Vertical cylinder from z0 to z0+height (optionally tapered to r_top) with rounded bevels."""
    rt = radius if r_top is None else r_top
    pts = []
    b = min(bevel, radius * 0.45, rt * 0.45, height * 0.45)
    if caps[0]:
        pts.append((0.0, z0))
        if b > 0:
            for k in range(bevel_seg + 1):
                a = (math.pi / 2) * k / bevel_seg
                pts.append((radius - b + b * math.sin(a), z0 + b - b * math.cos(a)))
        else:
            pts.append((radius, z0))
    else:
        pts.append((radius, z0))
    if caps[1]:
        if b > 0:
            for k in range(bevel_seg + 1):
                a = (math.pi / 2) * k / bevel_seg
                pts.append((rt - b + b * math.cos(a), z0 + height - b + b * math.sin(a)))
        else:
            pts.append((rt, z0 + height))
        pts.append((0.0, z0 + height))
    else:
        pts.append((rt, z0 + height))
    clean = [pts[0]]
    for p in pts[1:]:
        if abs(p[0] - clean[-1][0]) > 1e-9 or abs(p[1] - clean[-1][1]) > 1e-9:
            clean.append(p)
    return lathe(clean, mat, segs=segs, density=density, tag=tag)


def sphere(radius, mat, segs=24, rings=12, density=1.0, tag=""):
    pts = [(radius * math.sin(math.pi * k / rings), -radius * math.cos(math.pi * k / rings)) for k in range(rings + 1)]
    pts[0] = (0.0, -radius)
    pts[-1] = (0.0, radius)
    return lathe(pts, mat, segs=segs, smooth_angle=89, density=density, tag=tag, planar_caps=False)


def capsule(radius, length, mat, segs=20, rings=6, density=1.0, tag=""):
    """Capsule along +Z from 0 to length (length includes the hemispheres)."""
    half = max(length / 2 - radius, 0.0)
    pts = []
    for k in range(rings + 1):
        a = -math.pi / 2 + (math.pi / 2) * k / rings
        pts.append((radius * math.cos(a), radius + radius * math.sin(a)))
    for k in range(rings + 1):
        a = (math.pi / 2) * k / rings
        pts.append((radius * math.cos(a), radius + 2 * half + radius * math.sin(a)))
    pts[0] = (0.0, 0.0)
    pts[-1] = (0.0, 2 * half + 2 * radius)
    clean = [pts[0]]
    for p in pts[1:]:
        if abs(p[0] - clean[-1][0]) > 1e-9 or abs(p[1] - clean[-1][1]) > 1e-9:
            clean.append(p)
    return lathe(clean, mat, segs=segs, smooth_angle=89, density=density, tag=tag, planar_caps=False)


# ---------------------------------------------------------------------------------------------
# 2D profiles & paths
# ---------------------------------------------------------------------------------------------
def circle(r, n=16, start=0.0):
    a = np.radians(start) + np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.stack([r * np.cos(a), r * np.sin(a)], axis=1)


def ellipse(rx, ry, n=24):
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.stack([rx * np.cos(a), ry * np.sin(a)], axis=1)


def rrect(w, h, r, n=4):
    """CCW rounded rectangle centred at the origin (n points per corner)."""
    r = min(r, w / 2 - 1e-6, h / 2 - 1e-6)
    if r <= 1e-6:
        return np.array([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], dtype=np.float64)
    pts = []
    corners = [(w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)]
    for cx, cy, a0 in corners:
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.asarray(pts, dtype=np.float64)


def rect_profile(w, h, r=0.0, n=3):
    return rrect(w, h, r, n)


def chamfer_poly(w, h, c):
    """CCW rectangle with all four corners cut by c."""
    return np.array([(-w / 2 + c, -h / 2), (w / 2 - c, -h / 2), (w / 2, -h / 2 + c), (w / 2, h / 2 - c),
                     (w / 2 - c, h / 2), (-w / 2 + c, h / 2), (-w / 2, h / 2 - c), (-w / 2, -h / 2 + c)], dtype=np.float64)


def arc_points(center, radius, a0, a1, n, plane="xy"):
    a = np.radians(np.linspace(a0, a1, n))
    c = vec(center)
    pts = np.zeros((n, 3))
    i, j = {"xy": (0, 1), "xz": (0, 2), "yz": (1, 2)}[plane]
    pts[:] = c
    pts[:, i] += radius * np.cos(a)
    pts[:, j] += radius * np.sin(a)
    return pts


def bezier(p0, p1, p2, p3, n=16):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = (vec(p) for p in (p0, p1, p2, p3))
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + (t ** 3) * p3


def catmull(points, n=8, closed=False):
    """Centripetal-free uniform Catmull-Rom subdivision of a 3D polyline."""
    P = np.asarray(points, dtype=np.float64)
    if closed:
        ext = np.concatenate([P[-1:], P, P[:2]])
        segs = len(P)
    else:
        ext = np.concatenate([2 * P[:1] - P[1:2], P, 2 * P[-1:] - P[-2:-1]])
        segs = len(P) - 1
    out = []
    for i in range(segs):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(P[-1])
    return np.asarray(out)


def polyline_fillet(points, radius, n=6):
    """Round the inner corners of a 3D polyline with circular arcs of `radius`."""
    P = np.asarray(points, dtype=np.float64)
    if len(P) < 3 or radius <= 0:
        return P
    out = [P[0]]
    for i in range(1, len(P) - 1):
        a, b, c = P[i - 1], P[i], P[i + 1]
        d1 = normalize(a - b)
        d2 = normalize(c - b)
        cosang = float(np.clip(np.dot(d1, d2), -1, 1))
        ang = math.acos(cosang)
        if ang > math.pi - 1e-3 or ang < 1e-3:
            out.append(b)
            continue
        t = radius / math.tan(ang / 2)
        t = min(t, np.linalg.norm(a - b) * 0.49, np.linalg.norm(c - b) * 0.49)
        rr = t * math.tan(ang / 2)
        p1 = b + d1 * t
        p2 = b + d2 * t
        bis = normalize(d1 + d2)
        ctr = b + bis * (rr / math.sin(ang / 2))
        v1 = p1 - ctr
        v2 = p2 - ctr
        axis = normalize(np.cross(v1, v2))
        total = math.acos(float(np.clip(np.dot(normalize(v1), normalize(v2)), -1, 1)))
        for k in range(n + 1):
            out.append(ctr + axis_angle(axis, math.degrees(total * k / n)) @ v1)
    out.append(P[-1])
    res = [out[0]]
    for p in out[1:]:
        if np.linalg.norm(p - res[-1]) > 1e-7:
            res.append(p)
    return np.asarray(res)


def resample(points, step):
    """Resample a polyline at ~uniform spacing (keeps end points)."""
    P = np.asarray(points, dtype=np.float64)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(math.ceil(s[-1] / step)) + 1)
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, P[:, k]) for k in range(3)], axis=1)


# ---------------------------------------------------------------------------------------------
# polygon helpers (2D)
# ---------------------------------------------------------------------------------------------
def poly_area(poly):
    p = np.asarray(poly)
    return 0.5 * float(np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1]))


def ensure_ccw(poly):
    p = np.asarray(poly, dtype=np.float64)
    return p if poly_area(p) > 0 else p[::-1].copy()


def offset_poly(poly, d):
    """Offset a CCW polygon inward by d (negative = outward) with mitred corners."""
    p = np.asarray(poly, dtype=np.float64)
    e = np.roll(p, -1, axis=0) - p
    en = normalize(np.stack([e[:, 1], -e[:, 0]], axis=1))  # outward normals of edges
    n_prev = np.roll(en, 1, axis=0)
    m = n_prev + en
    denom = 1.0 + np.einsum("ij,ij->i", n_prev, en)
    m = m / np.maximum(denom, 0.2)[:, None]
    return p - m * d


def triangulate(poly):
    """Ear clipping for a simple CCW polygon -> (k,3) index array."""
    p = np.asarray(poly, dtype=np.float64)
    n = len(p)
    if n < 3:
        return np.zeros((0, 3), dtype=np.int64)
    idx = list(range(n))
    if poly_area(p) < 0:
        idx.reverse()
    tris = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(pt, a, b, c):
        return cross(a, b, pt) >= -1e-12 and cross(b, c, pt) >= -1e-12 and cross(c, a, pt) >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        m = len(idx)
        for k in range(m):
            i0, i1, i2 = idx[(k - 1) % m], idx[k], idx[(k + 1) % m]
            a, b, c = p[i0], p[i1], p[i2]
            if cross(a, b, c) <= 1e-14:
                continue
            ok = True
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                if inside(p[j], a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(k)
                found = True
                break
        if not found:
            # degenerate remainder: fan it
            for k in range(1, len(idx) - 1):
                tris.append((idx[0], idx[k], idx[k + 1]))
            idx = []
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return np.asarray(tris, dtype=np.int64).reshape(-1, 3)


# ---------------------------------------------------------------------------------------------
# planar polygon / plane
# ---------------------------------------------------------------------------------------------
def poly_cap(poly, z, mat, up=True, density=1.0, tag=""):
    p = ensure_ccw(poly)
    n = len(p)
    P = np.zeros((n, 3))
    P[:, :2] = p
    P[:, 2] = z
    N = np.tile(vec(0, 0, 1 if up else -1), (n, 1))
    UV = np.stack([p[:, 0] if up else -p[:, 0], -p[:, 1]], axis=1)
    return Geo([Chart(P, N, UV, triangulate(p), mat, density, tag or ("cap+" if up else "cap-")).clean()])


def plane(sx, sy, mat, density=1.0, tag="", fixed_uv=False, two_sided=False):
    """Quad in the XY plane facing +Z, centred at the origin. With fixed_uv the UVs cover 0..1
    exactly (top-left of the texture at -X,+Y) - used for screens that a DUI replaces."""
    P = np.array([(-sx / 2, sy / 2, 0), (sx / 2, sy / 2, 0), (sx / 2, -sy / 2, 0), (-sx / 2, -sy / 2, 0)], dtype=np.float64)
    N = np.tile(vec(0, 0, 1), (4, 1))
    UVm = np.array([(-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)])
    tri = np.array([(0, 2, 1), (0, 3, 2)])
    fu = np.array([(0, 0), (1, 0), (1, 1), (0, 1)], dtype=np.float64) if fixed_uv else None
    g = Geo([Chart(P, N, UVm, tri, mat, density, tag or "plane", fu).clean()])
    if two_sided:
        back = Chart(P.copy(), -N, UVm * vec(-1, 1), tri[:, [0, 2, 1]], mat, density, (tag or "plane") + ":back",
                     None if fu is None else fu.copy())
        g.charts.append(back.clean())
    return g


def quad(center, right, up, w, h, mat, density=1.0, tag="", fixed_uv=False):
    """Oriented quad: spans `right` (width w) and `up` (height h) around `center`; it faces
    right x up. With fixed_uv the texture's top-left corner sits at (-right, +up) - i.e. the image
    reads correctly for a viewer looking at the front of the quad. Use it for screens/labels."""
    c, r, u = vec(center), normalize(vec(right)), normalize(vec(up))
    n = normalize(np.cross(r, u))
    P = np.array([c - r * w / 2 + u * h / 2, c + r * w / 2 + u * h / 2, c + r * w / 2 - u * h / 2, c - r * w / 2 - u * h / 2])
    N = np.tile(n, (4, 1))
    UVm = np.array([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)])
    tri = np.array([(0, 2, 1), (0, 3, 2)])
    fu = np.array([(0, 0), (1, 0), (1, 1), (0, 1)], dtype=np.float64) if fixed_uv else None
    return Geo([Chart(P, N, UVm, tri, mat, density, tag or "quad", fu).clean()])


# ---------------------------------------------------------------------------------------------
# extrude
# ---------------------------------------------------------------------------------------------
def subdivide_poly(poly, max_seg):
    """Insert points along the edges of a closed 2D polygon so no edge is longer than max_seg
    (the original corners are kept)."""
    p = np.asarray(poly, dtype=np.float64)
    out = []
    for i in range(len(p)):
        a, b2 = p[i], p[(i + 1) % len(p)]
        k = max(1, int(math.ceil(float(np.linalg.norm(b2 - a)) / max_seg)))
        for j in range(k):
            out.append(a + (b2 - a) * (j / k))
    return np.asarray(out)


def extrude(poly, depth, mat, bevel=0.0, bevel_seg=2, z0=0.0, caps=(True, True), smooth_angle=30.0,
            density=1.0, tag="", cap_mat=None, side_mat=None, mid_rings=0, max_seg=None):
    """Extrude a 2D polygon (any winding) from z0 to z0+depth, optional rounded bevel on both
    rims. Sharp outline corners (turn > smooth_angle) get split normals.

    mid_rings  extra vertex rings on the straight wall between the bevels and max_seg extra points
               along long outline edges - only needed when the result is deformed afterwards
               (Geo.deform: a domed front face, a bulged housing). Caps keep the plain outline."""
    p = ensure_ccw(poly)
    cap_poly = p
    if max_seg:
        p = subdivide_poly(p, max_seg)
    n = len(p)
    b = float(min(bevel, depth * 0.45))
    # profile rings (inset, z, n_out, n_z): bottom bevel, top bevel
    rings = []
    if b > 0 and caps[0]:
        for k in range(bevel_seg + 1):
            a = (math.pi / 2) * k / bevel_seg
            rings.append((b * (1 - math.sin(a)), z0 + b * (1 - math.cos(a)), math.sin(a), -math.cos(a)))
    else:
        rings.append((0.0, z0, 1.0, 0.0))
    if mid_rings > 0:
        za = rings[-1][1]
        zb = z0 + depth - (b if (b > 0 and caps[1]) else 0.0)
        for k in range(1, mid_rings + 1):
            rings.append((0.0, za + (zb - za) * k / (mid_rings + 1), 1.0, 0.0))
    if b > 0 and caps[1]:
        for k in range(bevel_seg + 1):
            a = (math.pi / 2) * k / bevel_seg
            rings.append((b * (1 - math.cos(a)), z0 + depth - b + b * math.sin(a), math.cos(a), math.sin(a)))
    else:
        rings.append((0.0, z0 + depth, 1.0, 0.0))
    # outline columns with split normals at sharp corners
    e = np.roll(p, -1, axis=0) - p
    elen = np.linalg.norm(e, axis=1)
    en = normalize(np.stack([e[:, 1], -e[:, 0]], axis=1))
    cos_lim = math.cos(math.radians(smooth_angle))
    cols = []  # (vertex index, 2D normal, perimeter coordinate)
    perim = np.concatenate([[0.0], np.cumsum(elen)])
    for i in range(n + 1):
        vi = i % n
        prev_n = en[(vi - 1) % n]
        next_n = en[vi]
        if float(np.dot(prev_n, next_n)) < cos_lim:
            if i > 0:
                cols.append((vi, prev_n, perim[i]))
            if i < n:
                cols.append((vi, next_n, perim[i]))
        else:
            cols.append((vi, normalize(prev_n + next_n), perim[i]))
    ncol = len(cols)
    insets = sorted(set(r[0] for r in rings))
    offs = {d: offset_poly(p, d) for d in insets}
    P = np.zeros((len(rings), ncol, 3))
    N = np.zeros((len(rings), ncol, 3))
    UV = np.zeros((len(rings), ncol, 2))
    s_prof = np.concatenate([[0.0], np.cumsum([math.hypot(rings[k + 1][0] - rings[k][0], rings[k + 1][1] - rings[k][1]) for k in range(len(rings) - 1)])])
    for ri, (ins, z, no, nz) in enumerate(rings):
        op = offs[ins]
        for ci, (vi, n2, per) in enumerate(cols):
            P[ri, ci, :2] = op[vi]
            P[ri, ci, 2] = z
            N[ri, ci] = normalize(vec(n2[0] * no, n2[1] * no, nz))
            UV[ri, ci] = (per, -s_prof[ri])
    g = Geo()
    tris = grid_tris(ncol, len(rings))
    g.charts.append(Chart(P.reshape(-1, 3), N.reshape(-1, 3), UV.reshape(-1, 2), tris, side_mat or mat, density,
                          (tag + ":side") if tag else "extrude:side").clean())
    if cap_poly is not p:
        offs = {d: offset_poly(cap_poly, d) for d in insets}
    if caps[0]:
        g += poly_cap(offs[rings[0][0]], rings[0][1], cap_mat or mat, up=False, density=density, tag=(tag + ":bot") if tag else "extrude:bot")
    if caps[1]:
        g += poly_cap(offs[rings[-1][0]], rings[-1][1], cap_mat or mat, up=True, density=density, tag=(tag + ":top") if tag else "extrude:top")
    return g


# ---------------------------------------------------------------------------------------------
# sweep
# ---------------------------------------------------------------------------------------------
def path_frames(path, closed=False, up=None, side=None):
    """Rotation-minimising frames along a polyline. Returns (T, S, U) arrays (m,3):
    tangent, side (= T x U) and up. `up` hints the initial U, `side` the initial S (profile x).
    For closed paths the residual twist is spread evenly."""
    P = np.asarray(path, dtype=np.float64)
    m = len(P)
    if closed:
        T = normalize(np.roll(P, -1, axis=0) - np.roll(P, 1, axis=0))
    else:
        T = np.zeros_like(P)
        T[1:-1] = P[2:] - P[:-2]
        T[0] = P[1] - P[0]
        T[-1] = P[-1] - P[-2]
        T = normalize(T)
    u0 = vec(0, 0, 1) if up is None else normalize(vec(up))
    if side is not None:
        u0 = normalize(np.cross(normalize(vec(side)), T[0]))
    if abs(float(np.dot(u0, T[0]))) > 0.98:
        u0 = vec(1, 0, 0) if abs(T[0][0]) < 0.9 else vec(0, 1, 0)
    U = np.zeros_like(P)
    U[0] = normalize(u0 - T[0] * np.dot(u0, T[0]))
    for i in range(1, m):
        u = U[i - 1]
        # rotate previous up by the rotation that takes T[i-1] to T[i]
        ax = np.cross(T[i - 1], T[i])
        sa = np.linalg.norm(ax)
        if sa > 1e-10:
            ang = math.degrees(math.atan2(sa, float(np.dot(T[i - 1], T[i]))))
            u = axis_angle(ax / sa, ang) @ u
        u = normalize(u - T[i] * np.dot(u, T[i]))
        U[i] = u
    if closed:
        # transport once more to the start and measure the twist
        ax = np.cross(T[-1], T[0])
        sa = np.linalg.norm(ax)
        u = U[-1]
        if sa > 1e-10:
            u = axis_angle(ax / sa, math.degrees(math.atan2(sa, float(np.dot(T[-1], T[0]))))) @ u
        u = normalize(u - T[0] * np.dot(u, T[0]))
        twist = math.degrees(math.atan2(float(np.dot(np.cross(u, U[0]), T[0])), float(np.dot(u, U[0]))))
        for i in range(m):
            U[i] = axis_angle(T[i], twist * i / m) @ U[i]
    S = normalize(np.cross(T, U))
    return T, S, U


def sweep(profile, path, mat, closed_path=False, closed_profile=True, caps=True, up=None, scale=None,
          smooth_angle=40.0, density=1.0, split=0.45, tag="", twist=0.0, side=None):
    """Sweep a 2D profile (x -> frame side, y -> frame up) along a 3D path.

    profile        (k,2) polygon/polyline. Closed profiles should be CCW.
    path           (m,3) points (use catmull / polyline_fillet / resample for smooth curves).
    up / side      hint for the initial frame: profile y follows `up`, or profile x follows `side`.
    scale          optional per-path-point scale factors (taper): (m,) or (m,2) for separate
                   profile x / y scaling (e.g. a collar band that is taller at the front).
    twist          extra twist in degrees distributed along the path.
    split          max chart length along the path in metres (charts are split at rings).
    Each smooth run of the profile becomes its own chart tagged '<tag>:<run>' - e.g. a strap
    profile rect gives runs 0..3 so prints can target the top face only.
    """
    prof = np.asarray(profile, dtype=np.float64)
    if closed_profile:
        prof = ensure_ccw(prof)
    P = np.asarray(path, dtype=np.float64)
    m = len(P)
    T, S, U = path_frames(P, closed_path, up, side)
    if twist:
        for i in range(m):
            a = twist * i / max(m - 1, 1)
            S[i] = axis_angle(T[i], a) @ S[i]
            U[i] = axis_angle(T[i], a) @ U[i]
    sc = np.ones((m, 2)) if scale is None else np.asarray(scale, dtype=np.float64)
    if sc.ndim == 1:
        sc = np.stack([sc, sc], axis=1)
    if closed_path:
        P = np.concatenate([P, P[:1]])
        T = np.concatenate([T, T[:1]])
        S = np.concatenate([S, S[:1]])
        U = np.concatenate([U, U[:1]])
        sc = np.concatenate([sc, sc[:1]], axis=0)
        m += 1
    seglen = np.linalg.norm(np.diff(P, axis=0), axis=1)
    sl = np.concatenate([[0.0], np.cumsum(seglen)])
    # split points
    cuts = [0]
    last = 0.0
    for i in range(1, m):
        if sl[i] - last >= split and i < m - 1:
            cuts.append(i)
            last = sl[i]
    cuts.append(m - 1)
    runs = _profile_runs(prof, smooth_angle, None, closed_profile)
    g = Geo()
    for ri, (idx, n2, _) in enumerate(runs):
        pr = prof[idx]
        k = len(pr)
        plen = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pr, axis=0), axis=1))])
        for ci in range(len(cuts) - 1):
            a, b = cuts[ci], cuts[ci + 1]
            rows = range(a, b + 1)
            nr = len(rows)
            Pp = np.zeros((nr, k, 3))
            Nn = np.zeros((nr, k, 3))
            UV = np.zeros((nr, k, 2))
            for rr, i in enumerate(rows):
                Pp[rr] = P[i] + pr[:, 0:1] * sc[i, 0] * S[i] + pr[:, 1:2] * sc[i, 1] * U[i]
                Nn[rr] = n2[:, 0:1] / sc[i, 0] * S[i] + n2[:, 1:2] / sc[i, 1] * U[i]
                UV[rr, :, 0] = plen * float(np.sqrt(sc[i, 0] * sc[i, 1]))
                UV[rr, :, 1] = sl[i]
            ch = Chart(Pp.reshape(-1, 3), Nn.reshape(-1, 3), UV.reshape(-1, 2), grid_tris(k, nr), mat, density,
                       f"{tag}:{ri}" if tag else f"sweep:{ri}")
            g.charts.append(ch.clean())
    if caps and closed_profile and not closed_path:
        tri = triangulate(prof)
        for end, i, sgn in (("a", 0, -1.0), ("b", m - 1, 1.0)):
            Pc = P[i] + prof[:, 0:1] * sc[i, 0] * S[i] + prof[:, 1:2] * sc[i, 1] * U[i]
            Nc = np.tile(T[i] * sgn, (len(prof), 1))
            UVc = np.stack([prof[:, 0] * sgn * sc[i, 0], -prof[:, 1] * sc[i, 1]], axis=1)
            g.charts.append(Chart(Pc, Nc, UVc, tri, mat, density, f"{tag}:cap{end}" if tag else f"sweep:cap{end}").clean())
    return g


def tube(path, radius, mat, segs=12, closed_path=False, caps=True, density=1.0, split=0.45, tag="", up=None, scale=None, side=None):
    return sweep(circle(radius, segs), path, mat, closed_path=closed_path, caps=caps, density=density,
                 split=split, tag=tag, up=up, scale=scale, smooth_angle=60, side=side)


def torus(R, r, mat, segs=32, tube_segs=12, density=1.0, tag=""):
    path = arc_points((0, 0, 0), R, 0, 360, segs + 1)[:-1]
    return sweep(circle(r, tube_segs), path, mat, closed_path=True, density=density, tag=tag, smooth_angle=60, up=(0, 0, 1))


# ---------------------------------------------------------------------------------------------
# soft shapes
# ---------------------------------------------------------------------------------------------
def pillow(w, h, t, mat, nx=18, nz=22, seam=0.0, power=3.0, density=1.0, tag="pillow", zmax=None, inset=0.0):
    """Flat bag / cushion in the XZ plane (width w along X, height h along Z, centred at the
    origin), thickness t along Y at the centre falling off towards the welded edges.
    seam  width of a flat welded border (two-sided strip) around the edge.
    zmax  clip the body at this Z (fill level of a liquid) and close it with a flat top.
    Returns front (+Y) and back (-Y) charts (+ top cap when clipped, + seam strip)."""
    hw, hh = w / 2 - inset, h / 2 - inset

    def thick(x, z):
        a = np.clip(1 - np.abs(x / hw) ** power, 0, 1)
        b = np.clip(1 - np.abs(z / hh) ** power, 0, 1)
        return (t / 2) * np.sqrt(a * b)

    xs = np.sin(np.linspace(-np.pi / 2, np.pi / 2, nx)) * hw
    ztop = hh if zmax is None else min(zmax, hh)
    zs_full = np.sin(np.linspace(-np.pi / 2, np.pi / 2, nz)) * hh
    zs = zs_full[zs_full < ztop - 1e-6]
    zs = np.concatenate([zs, [ztop]])
    g = Geo()
    X, Z = np.meshgrid(xs, zs)
    for side in (1, -1):
        Y = side * thick(X, Z)
        P = np.stack([X, Y, Z], axis=-1).reshape(-1, 3)
        # normals from the analytic gradient of the thickness field
        e = 1e-5
        dtx = (thick(X + e, Z) - thick(X - e, Z)) / (2 * e)
        dtz = (thick(X, Z + e) - thick(X, Z - e)) / (2 * e)
        N = np.stack([-dtx, np.full_like(X, float(side)), -dtz], axis=-1).reshape(-1, 3)
        UV = np.stack([-X * side, -Z], axis=-1).reshape(-1, 2)
        ch = Chart(P, N, UV, grid_tris(len(xs), len(zs)), mat, density, f"{tag}:{'front' if side > 0 else 'back'}")
        g.charts.append(ch.clean())
    if zmax is not None and ztop < hh:
        xx = xs
        tt = thick(xx, np.full_like(xx, ztop))
        P = np.concatenate([np.stack([xx, tt, np.full_like(xx, ztop)], axis=1), np.stack([xx, -tt, np.full_like(xx, ztop)], axis=1)])
        N = np.tile(vec(0, 0, 1), (len(P), 1))
        UV = np.stack([P[:, 0], -P[:, 1]], axis=1)
        n = len(xx)
        tri = []
        for i in range(n - 1):
            tri += [(i, i + 1, n + i + 1), (i, n + i + 1, n + i)]
        g.charts.append(Chart(P, N, UV, np.array(tri), mat, density, f"{tag}:level").clean())
    if seam > 0:
        outer = rrect(w + 2 * seam, h + 2 * seam, seam * 1.2, 3)
        inner = rrect(w, h, seam * 0.3, 3)
        # resample both loops to the same count for a clean strip
        def res_loop(lp, n):
            lp = np.concatenate([lp, lp[:1]])
            d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(lp, axis=0), axis=1))])
            tt_ = np.linspace(0, d[-1], n, endpoint=False)
            return np.stack([np.interp(tt_, d, lp[:, 0]), np.interp(tt_, d, lp[:, 1])], axis=1)
        n = 96
        lo = res_loop(outer, n)
        li = res_loop(inner, n)
        for side in (1, -1):
            P = np.concatenate([np.stack([lo[:, 0], np.full(n, side * 0.0004), lo[:, 1]], axis=1),
                                np.stack([li[:, 0], np.full(n, side * 0.0004), li[:, 1]], axis=1)])
            N = np.tile(vec(0, side, 0), (2 * n, 1))
            UV = np.stack([P[:, 0] * side, -P[:, 2]], axis=1)
            tri = []
            for i in range(n):
                j = (i + 1) % n
                tri += [(i, j, n + j), (i, n + j, n + i)]
            g.charts.append(Chart(P, N, UV, np.array(tri), mat, density, f"{tag}:seam").clean())
    return g


def slab_with_holes(x0, x1, y0, y1, z, holes, mat, density=1.0, tag="slab"):
    """Horizontal +Z facing rectangle with axis aligned rectangular holes (x0, x1, y0, y1) cut out
    - e.g. the top of a pick-and-pluck foam insert."""
    xs = sorted({x0, x1, *[h[0] for h in holes], *[h[1] for h in holes]})
    ys = sorted({y0, y1, *[h[2] for h in holes], *[h[3] for h in holes]})
    xs = [x for x in xs if x0 <= x <= x1]
    ys = [y for y in ys if y0 <= y <= y1]
    P, tri = [], []
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx, cy = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
            if any(h[0] <= cx <= h[1] and h[2] <= cy <= h[3] for h in holes):
                continue
            b = len(P)
            P += [(xs[i], ys[j], z), (xs[i + 1], ys[j], z), (xs[i + 1], ys[j + 1], z), (xs[i], ys[j + 1], z)]
            tri += [(b, b + 1, b + 2), (b, b + 2, b + 3)]
    P = np.asarray(P, dtype=np.float64)
    N = np.tile(vec(0, 0, 1), (len(P), 1))
    UV = np.stack([P[:, 0], -P[:, 1]], axis=1)
    return Geo([Chart(P, N, UV, np.asarray(tri), mat, density, tag).clean()])


def pocket(x0, x1, y0, y1, z_top, depth, mat, density=1.0, tag="pocket"):
    """Inside walls + floor of a rectangular cut-out going down from z_top."""
    w, d = x1 - x0, y1 - y0
    g = box((w, d, depth), mat, r=0.0, center=((x0 + x1) / 2, (y0 + y1) / 2, z_top - depth / 2),
            faces="+x -x +y -y -z", density=density, tag=tag)
    return g.flip()


# ---------------------------------------------------------------------------------------------
# rounded outlines, helices, lofts and plates with wells (added for the radio kit)
# ---------------------------------------------------------------------------------------------
def fillet_poly(poly, r, n=4):
    """Round every corner of a closed 2D polygon with radius r (n segments per corner). Corners whose
    neighbouring edges are too short get the largest radius that fits."""
    p = ensure_ccw(poly)
    m = len(p)
    out = []
    for i in range(m):
        a, b, c = p[i - 1], p[i], p[(i + 1) % m]
        d1, d2 = a - b, c - b
        l1, l2 = float(np.linalg.norm(d1)), float(np.linalg.norm(d2))
        if l1 < 1e-12 or l2 < 1e-12 or r <= 0:
            out.append(b)
            continue
        d1, d2 = d1 / l1, d2 / l2
        ang = math.acos(float(np.clip(np.dot(d1, d2), -1, 1)))
        if ang > math.pi - 1e-4:
            out.append(b)
            continue
        t = r / math.tan(ang / 2)
        t = min(t, l1 * 0.5, l2 * 0.5)
        rr = t * math.tan(ang / 2)
        p1, p2 = b + d1 * t, b + d2 * t
        bis = d1 + d2
        bis = bis / max(float(np.linalg.norm(bis)), 1e-12)
        ctr = b + bis * (rr / math.sin(ang / 2))
        a0 = math.atan2(p1[1] - ctr[1], p1[0] - ctr[0])
        a1 = math.atan2(p2[1] - ctr[1], p2[0] - ctr[0])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(n + 1):
            aa = a0 + da * k / n
            out.append(ctr + rr * np.array([math.cos(aa), math.sin(aa)]))
    res = [out[0]]
    for q in out[1:]:
        if np.linalg.norm(q - res[-1]) > 1e-9:
            res.append(q)
    if np.linalg.norm(res[0] - res[-1]) < 1e-9:
        res.pop()
    return np.asarray(res)


def chamfer_fillet_rect(w, h, c, r=0.0, n=3):
    """CCW rectangle w x h whose four corners are cut by a 45 degree chamfer c, every resulting
    corner filleted with radius r - the classic moulded radio / instrument housing plan."""
    p = chamfer_poly(w, h, c) if c > 1e-9 else rrect(w, h, 0.0)
    return fillet_poly(p, r, n) if r > 0 else p


def helix(base, axis, radius, pitch, turns, n_per_turn=24, side=None, phase=0.0):
    """Points of a helix starting at `base` winding around `axis` (coil springs, gooseneck bases)."""
    ax = normalize(vec(axis))
    ref = vec(side) if side is not None else (vec(1, 0, 0) if abs(ax[0]) < 0.9 else vec(0, 1, 0))
    e1 = normalize(ref - ax * float(np.dot(ref, ax)))
    e2 = np.cross(ax, e1)
    n = max(4, int(round(turns * n_per_turn))) + 1
    t = np.linspace(0, turns, n)
    a = 2 * math.pi * t + math.radians(phase)
    return vec(base)[None, :] + ax[None, :] * (pitch * t)[:, None] + radius * (np.cos(a)[:, None] * e1 + np.sin(a)[:, None] * e2)


def loft(loop_a, loop_b, mat, normals_a=None, normals_b=None, closed=True, density=1.0, tag="loft"):
    """Strip between two 3D loops with the same point count (a ring, a chamfer, a lip). Normals are
    computed from the strip unless given per loop."""
    A, B = np.asarray(loop_a, np.float64), np.asarray(loop_b, np.float64)
    k = len(A)
    if closed:
        A, B = np.concatenate([A, A[:1]]), np.concatenate([B, B[:1]])
        if normals_a is not None:
            normals_a = np.concatenate([normals_a, normals_a[:1]])
        if normals_b is not None:
            normals_b = np.concatenate([normals_b, normals_b[:1]])
        k += 1
    P = np.concatenate([A, B])
    if normals_a is None or normals_b is None:
        t = np.gradient(A, axis=0)
        s = B - A
        nn = normalize(np.cross(t, s))
        N = np.concatenate([nn, nn])
    else:
        N = np.concatenate([normals_a, normals_b])
    seg = np.linalg.norm(np.diff(A, axis=0), axis=1)
    u = np.concatenate([[0.0], np.cumsum(seg)])
    hgt = float(np.mean(np.linalg.norm(B - A, axis=1)))
    UV = np.concatenate([np.stack([u, np.zeros(k)], 1), np.stack([u, np.full(k, -hgt)], 1)])
    tri = []
    for i in range(k - 1):
        tri += [(i, i + 1, k + i + 1), (i, k + i + 1, k + i)]
    return Geo([Chart(P, N, UV, np.asarray(tri), mat, density, tag).clean()])


def _rrect_n(w, h, r, n):
    """rrect that always returns 4 * (n + 1) points (sharp corners repeat their point) so two
    outlines with different radii can be lofted point by point."""
    if r > 1e-7:
        return rrect(w, h, r, n)
    pts = []
    for cx, cy in ((w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2), (-w / 2, -h / 2)):
        pts += [(cx, cy)] * (n + 1)
    return np.asarray(pts, dtype=np.float64)


def well_plate(w, h, t, holes, mat, depth=None, floor_mat=None, wall_mat=None, bevel=0.0004, hole_bevel=0.0003,
               corner_n=4, density=1.0, tag="plate", floor=True, outer_r=0.0, outer_n=2):
    """A flat plate w x h (centred on the origin, bottom at z = 0, top face at z = t, facing +Z) with
    rounded-rectangle openings that fall into wells - key wells, knob sockets, PTT pockets, grille holes.

    holes  [(cx, cy, hw, hh, r) or (cx, cy, hw, hh, r, depth) or (cx, cy, hw, hh, r, depth, corner_n)]:
           centre, half extents and corner radius of each opening (r = min(hw, hh) makes a round hole);
           depth None = the default; corner_n overrides the arc steps of that opening (a big round well
           needs more than a key well). Holes must not overlap and must stay inside the plate (minus the
           rim bevel).
    depth  default well depth (default t: the floor sits on the plate's bottom plane)
    outer_r  corner radius of the plate outline in plan (outer_n arc steps per corner); 0 = square corners
           (the default). The four corner cells of the top grid become fans that follow the rounded rim -
           no opening may reach into a corner cell closer than the radius.
    The top face is one chart (grid partition around the holes + corner fans, no slivers); every well
    gets a 45 degree top chamfer (hole_bevel), inward facing walls and an optional floor. The plate's
    vertical corners are square in plan (its top rim is bevelled) - sink it into a housing face or
    keep it small (keypad surrounds, bezels) - or give it outer_r."""
    depth = t if depth is None else depth
    wall_mat = wall_mat or mat
    floor_mat = floor_mat or wall_mat
    bv = float(min(bevel, t * 0.45))
    g = Geo()
    # outer wall + rounded top rim (the cap is replaced by the holed grid below)
    outer_r = float(min(max(outer_r, 0.0), w / 2 - 1e-6, h / 2 - 1e-6))
    outline = rrect(w, h, outer_r, outer_n) if outer_r > bv + 1e-6 else rrect(w, h, 0.0)
    rim = extrude(outline, t, mat, bevel=bv, bevel_seg=2, caps=(False, True), density=density, tag=tag + ":rim",
                  smooth_angle=50)
    rim.charts = [c for c in rim.charts if not c.tag.endswith(":top")]
    g += rim
    X0, X1, Y0, Y1 = -w / 2 + bv, w / 2 - bv, -h / 2 + bv, h / 2 - bv
    hb = max(0.0, float(hole_bevel))
    boxes = []
    for hole in holes:
        cx, cy, hw, hh, r = hole[:5]
        r = min(r, hw, hh)
        ohw, ohh, orr = hw + hb, hh + hb, r + hb
        x0, x1, y0, y1 = cx - ohw, cx + ohw, cy - ohh, cy + ohh
        if x0 < X0 - 1e-9 or x1 > X1 + 1e-9 or y0 < Y0 - 1e-9 or y1 > Y1 + 1e-9:
            raise ValueError(f"well_plate: hole at ({cx:.4f}, {cy:.4f}) leaves the plate")
        dep_h = hole[5] if len(hole) > 5 and hole[5] is not None else depth
        boxes.append((x0, x1, y0, y1, cx, cy, hw, hh, r, ohw, ohh, orr, dep_h, int(hole[6]) if len(hole) > 6 else corner_n))
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b2 = boxes[i], boxes[j]
            if a[0] < b2[1] - 1e-9 and b2[0] < a[1] - 1e-9 and a[2] < b2[3] - 1e-9 and b2[2] < a[3] - 1e-9:
                raise ValueError("well_plate: holes overlap (including their top chamfer)")
    xs = sorted({X0, X1, *[bx[0] for bx in boxes], *[bx[1] for bx in boxes]})
    ys = sorted({Y0, Y1, *[bx[2] for bx in boxes], *[bx[3] for bx in boxes]})
    P, tri = [], []

    def quad_(a, b2, c, d):
        base = len(P)
        P.extend([a, b2, c, d])
        tri.extend([(base, base + 1, base + 2), (base, base + 2, base + 3)])

    # rounded plan corners: the rim's top edge (outline inset by the bevel) bounds the four corner cells
    arcs = {}
    if len(outline) > 4:
        top = offset_poly(outline, bv)
        per = outer_n + 1
        rc = outer_r - bv
        for k, key in enumerate(((1, 0), (1, 1), (0, 1), (0, 0))):      # rrect corner order: +x-y, +x+y, -x+y, -x-y
            arcs[key] = (top[k * per:(k + 1) * per], rc)
    ni, nj = len(xs) - 1, len(ys) - 1
    for i in range(ni):
        for j in range(nj):
            cx_, cy_ = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
            hole_cell = any(bx[0] <= cx_ <= bx[1] and bx[2] <= cy_ <= bx[3] for bx in boxes)
            key = (1 if i == ni - 1 else 0 if i == 0 else None, 1 if j == nj - 1 else 0 if j == 0 else None)
            if arcs and key in arcs:
                if hole_cell:
                    raise ValueError("well_plate: an opening reaches into a rounded plate corner (outer_r)")
                arc, rc = arcs[key]
                qx = xs[i] if key[0] == 1 else xs[i + 1]        # the cell corner facing the plate centre
                qy = ys[j] if key[1] == 1 else ys[j + 1]
                if xs[i + 1] - xs[i] < rc - 1e-9 or ys[j + 1] - ys[j] < rc - 1e-9:
                    raise ValueError("well_plate: outer_r is larger than a corner cell (an opening is too close to a corner)")
                # convex corner cell walked CCW: edge point -> arc -> edge point, fanned from the inner corner
                if key == (1, 0):
                    ring = [(qx, ys[j])] + [tuple(a) for a in arc] + [(xs[i + 1], qy)]
                elif key == (1, 1):
                    ring = [(xs[i + 1], qy)] + [tuple(a) for a in arc] + [(qx, ys[j + 1])]
                elif key == (0, 1):
                    ring = [(qx, ys[j + 1])] + [tuple(a) for a in arc] + [(xs[i], qy)]
                else:
                    ring = [(xs[i], qy)] + [tuple(a) for a in arc] + [(qx, ys[j])]
                for q in range(len(ring) - 1):
                    a, b2 = ring[q], ring[q + 1]
                    if abs((a[0] - qx) * (b2[1] - qy) - (a[1] - qy) * (b2[0] - qx)) < 1e-14:
                        continue
                    base = len(P)
                    P.extend([(qx, qy, t), (a[0], a[1], t), (b2[0], b2[1], t)])
                    tri.append((base, base + 1, base + 2))
                continue
            if hole_cell:
                continue
            quad_((xs[i], ys[j], t), (xs[i + 1], ys[j], t), (xs[i + 1], ys[j + 1], t), (xs[i], ys[j + 1], t))
    for (x0, x1, y0, y1, cx, cy, hw, hh, r, ohw, ohh, orr, dep, cn) in boxes:
        loop = _rrect_n(2 * ohw, 2 * ohh, orr, cn) + np.array([cx, cy])
        # the rrect loop has 4 corner arcs of corner_n + 1 points (CCW from the -y side of the +x edge)
        corners = [(x1, y0), (x1, y1), (x0, y1), (x0, y0)]
        per = cn + 1
        if orr > 1e-9:
            for k in range(4):
                arc = loop[k * per:(k + 1) * per]
                cxy = corners[k]
                for q in range(per - 1):
                    base = len(P)
                    P.extend([(cxy[0], cxy[1], t), (arc[q][0], arc[q][1], t), (arc[q + 1][0], arc[q + 1][1], t)])
                    tri.append((base, base + 1, base + 2))
        # chamfer ring (top rim of the opening)
        inner = _rrect_n(2 * hw, 2 * hh, r, cn) + np.array([cx, cy])
        if hb > 1e-9:
            A = np.concatenate([loop, np.full((len(loop), 1), t)], axis=1)
            B = np.concatenate([inner, np.full((len(inner), 1), t - hb)], axis=1)
            g += loft(A, B, wall_mat, density=density, tag=tag + ":chamfer")
        inner = rrect(2 * hw, 2 * hh, r, cn) + np.array([cx, cy])
        ztop = t - hb if hb > 1e-9 else t
        dep_wall = max(dep - (t - ztop), 1e-5)
        walls = extrude(inner, dep_wall, wall_mat, bevel=0.0, caps=(False, False), z0=ztop - dep_wall, density=density,
                        tag=tag + ":well", smooth_angle=50).flip()
        g += walls
        if floor:
            g += poly_cap(inner, ztop - dep_wall, floor_mat, up=True, density=density, tag=tag + ":floor")
    if P:
        P = np.asarray(P, np.float64)
        N = np.tile(vec(0, 0, 1), (len(P), 1))
        UV = np.stack([P[:, 0], -P[:, 1]], axis=1)
        g.charts.append(Chart(P, N, UV, np.asarray(tri), mat, density, tag + ":top").clean())
    return g


def rr_lathe(w, h, r, profile, mat, n=4, density=1.0, tag="rrl", top_split=0.7, top_fn=None, close=False):
    """A 'lathe' around +Z whose cross-section is a rounded rectangle instead of a circle.

    profile  [(inset, z), ...] from the outside bottom to the top centre: ring k is the w x h rounded
             rectangle (corner radius r) offset inward by inset_k (its corner radius shrinks with it).
             Example key cap: [(0, 0), (0, t - b), (b * 0.3, t - b * 0.3), (b, t), (min(w, h) / 2, t + dome)]
    Vertex normals are averaged over the surface (smooth everywhere - give every crease a small bevel).
    The rings whose profile faces up (normal z > top_split) form a separate top chart with planar UVs,
    so legends / prints on the top get an even texel density. Used for key caps, rocker buttons, bosses.
    top_fn(x, y) -> (z, dz/dx, dz/dy) replaces the height of the top rings with a smooth surface (a
    pillow dome) and gives them exact normals - without it the shrinking rounded rectangles meet in
    creases along the diagonals (a hip roof). close=True ends the profile on a real ring and closes the
    top with a fan to the centre (avoid profiles that shrink to a line: sliver triangles leave texture seams)."""
    prof = [(float(a), float(z)) for a, z in profile]
    rings = []
    for ins, z in prof:
        ww, hh = max(w - 2 * ins, 1e-6), max(h - 2 * ins, 1e-6)
        rr = max(min(r - ins, ww / 2 - 1e-7, hh / 2 - 1e-7), 0.0)
        loop = _rrect_n(ww, hh, rr, n) if rr > 1e-7 else _rrect_n(ww, hh, 0.0, n)
        rings.append(np.concatenate([loop, np.full((len(loop), 1), z)], axis=1))
    P = np.stack(rings)                    # (K, M, 3)
    K, M = P.shape[0], P.shape[1]
    ks_fn = None
    if top_fn is not None:
        ks_fn = K - 1
        while ks_fn > 0 and (prof[ks_fn][0] - prof[ks_fn - 1][0]) / (math.hypot(prof[ks_fn][0] - prof[ks_fn - 1][0], prof[ks_fn][1] - prof[ks_fn - 1][1]) or 1) > top_split:
            ks_fn -= 1
        for k in range(ks_fn + 1, K):
            z, _, _ = top_fn(P[k, :, 0], P[k, :, 1])
            P[k, :, 2] = z
    acc = np.zeros_like(P)
    for k in range(K - 1):
        a = P[k]
        b = np.roll(P[k], -1, axis=0)
        c = np.roll(P[k + 1], -1, axis=0)
        d = P[k + 1]
        fn = np.cross(c - a, d - b)
        for arr, sh in ((acc[k], 0), (acc[k + 1], 0)):
            _ = arr, sh
        acc[k] += fn
        acc[k] += np.roll(fn, 1, axis=0)
        acc[k + 1] += fn
        acc[k + 1] += np.roll(fn, 1, axis=0)
    N = normalize(acc)
    # orientation: the first ring must face away from the axis
    ref = P[0, :, :2] - P[0, :, :2].mean(axis=0)
    if float(np.sum(np.einsum("ij,ij->i", N[0, :, :2], ref))) < 0:
        N = -N
    bad = np.linalg.norm(acc, axis=2) < 1e-20
    N[bad] = np.array([0.0, 0.0, 1.0])
    if ks_fn is not None:
        for k in range(ks_fn + 1, K):
            _, gx, gy = top_fn(P[k, :, 0], P[k, :, 1])
            N[k] = normalize(np.stack([-np.asarray(gx, float) * np.ones(M), -np.asarray(gy, float) * np.ones(M), np.ones(M)], axis=1))
    # split rings into side / top runs
    seg_up = []
    for k in range(K - 1):
        dd, dz = prof[k + 1][0] - prof[k][0], prof[k + 1][1] - prof[k][1]
        L = math.hypot(dd, dz) or 1.0
        seg_up.append(dd / L)
    ks = K - 1
    while ks > 0 and seg_up[ks - 1] > top_split:
        ks -= 1
    g = Geo()
    Pw = np.concatenate([P, P[:, :1]], axis=1)
    Nw = np.concatenate([N, N[:, :1]], axis=1)

    def chart(k0, k1, planar, ctag, close=False):
        if k1 - k0 < 1 and not close:
            return
        Pp, Nn = Pw[k0:k1 + 1], Nw[k0:k1 + 1]
        nr = k1 - k0 + 1
        if planar:
            UV = np.stack([Pp[:, :, 0], -Pp[:, :, 1]], axis=-1)
        else:
            seg = np.linalg.norm(np.diff(Pp, axis=1), axis=2)
            u = np.concatenate([np.zeros((nr, 1)), np.cumsum(seg, axis=1)], axis=1)
            pl = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(Pp[:, 0, :], axis=0), axis=1))])
            UV = np.stack([u, np.repeat(-pl[:, None], M + 1, axis=1)], axis=-1)
        pos, nrm, uvm = Pp.reshape(-1, 3), Nn.reshape(-1, 3), UV.reshape(-1, 2)
        tri = grid_tris(M + 1, nr)
        if close:
            # fan from the last ring to the centre (no degenerate sliver rings at the middle)
            last = Pp[-1, :M]
            cz = float(last[:, 2].mean())
            cn = np.array([0.0, 0.0, 1.0])
            if top_fn is not None:
                cz, gx, gy = top_fn(np.zeros(1), np.zeros(1))
                cz = float(np.asarray(cz).reshape(-1)[0])
                cn = normalize(np.array([-float(np.asarray(gx).reshape(-1)[0]), -float(np.asarray(gy).reshape(-1)[0]), 1.0]))
            ci = len(pos)
            pos = np.concatenate([pos, [[0.0, 0.0, cz]]])
            nrm = np.concatenate([nrm, [cn]])
            uvm = np.concatenate([uvm, [[0.0, 0.0]]])
            base = (nr - 1) * (M + 1)
            fan = np.array([(base + i, base + i + 1, ci) for i in range(M)])
            tri = np.concatenate([tri, fan]) if len(tri) else fan
        ch = Chart(pos, nrm, uvm, tri, mat, density, ctag)
        g.charts.append(ch.clean())

    chart(0, ks, False, tag + ":side")
    chart(ks, K - 1, True, tag + ":top", close=close)
    return g


def split_by_normal(geo: "Geo", suffix=True, cap_dot=None):
    """Split every chart into up to six charts by the dominant axis of each triangle's normal (+x -x +y
    -y +z -z), duplicating the shared vertices. A wrapped side wall (extrude / housing) then packs as four
    rectangles and each face can get its own texel density (tags get ':+y' etc.).
    cap_dot: when set, a triangle joins the +z / -z chart only if its normalised |n_z| >= cap_dot; every
    other triangle goes to the dominant of +-x / +-y - the 45 degree rim bevels of an extrude then stay
    whole with their side wall instead of alternating between the wall and the cap chart (sawtooth)."""
    out = Geo()
    keys = ["+x", "-x", "+y", "-y", "+z", "-z"]
    for c in geo.charts:
        p = c.pos[c.tri]
        fn = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
        fn = fn + c.nrm[c.tri].sum(axis=1) * 1e-12
        ax = np.argmax(np.abs(fn), axis=1)
        if cap_dot is not None:
            nz = np.abs(fn[:, 2]) / np.maximum(np.linalg.norm(fn, axis=1), 1e-30)
            side = nz < cap_dot
            ax = np.where(side, np.argmax(np.abs(fn[:, :2]), axis=1), 2)
        sg = np.sign(fn[np.arange(len(fn)), ax])
        cls = ax * 2 + (sg < 0)
        for k in np.unique(cls):
            sel = c.tri[cls == k]
            used = np.unique(sel.reshape(-1))
            remap = np.full(len(c.pos), -1, np.int64)
            remap[used] = np.arange(len(used))
            ch = Chart(c.pos[used], c.nrm[used], c.uvm[used], remap[sel], c.mat, c.density,
                       f"{c.tag}:{keys[int(k)]}" if suffix else c.tag, None if c.fixed_uv is None else c.fixed_uv[used], c.part, c.lod)
            out.charts.append(ch)
    return out
