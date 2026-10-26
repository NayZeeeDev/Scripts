"""Procedural mesh toolkit for the nayzeee prop pipeline.

Conventions (shared by every model, the exporters and the image renderer)
-------------------------------------------------------------------------
* Units are metres.
* Axes follow GTA: +Z is up, +Y is the model FRONT, +X is the viewer's LEFT
  when the viewer faces the front (viewer's right = -X).
* Triangles are counter-clockwise when seen from outside (outward normal =
  (b - a) x (c - a)). GTA, glTF and Blender all use this winding.
* UVs: (u, v) with v = 0 at the TOP row of the texture image (DirectX / GTA /
  glTF convention). Planar helpers orient images "upright as seen from outside".
* Tangents are float4: xyz = direction of +u on the surface, w = handedness so
  that cross(N, T) * w points to "image up" (-dP/dv). This is the Blender /
  glTF / Sollumz convention, so the same tangents work for GTA and glTF.
* Vertex colours are RGBA floats 0..1 (exported as 0..255). GTA reads R as
  natural ambient, G as artificial ambient; keep them at 1 unless baking AO.

Level of detail
---------------
Every primitive takes "nominal" segment counts that are multiplied by the
current global detail factor (see ``detail()`` / ``seg()``).  build.py calls a
model's ``build(detail)`` once at detail 1.0 (High LOD) and once at about 0.35
(Medium LOD), so the same model code produces both LODs.

A model is simply a list of ``Mesh`` parts; each part carries the material
name it is drawn with.  Use ``merge``/``group_by_material`` to combine parts.
"""
from __future__ import annotations

import math
from contextlib import contextmanager
from typing import Iterable

import numpy as np

__all__ = [
    # detail
    "get_detail", "detail", "seg",
    # math helpers
    "rotation_matrix", "euler_matrix", "translation_matrix", "scale_matrix", "compose",
    # mesh
    "Mesh", "merge", "group_by_material", "parts_bounds", "parts_tri_count",
    "array_linear", "array_radial", "array_grid",
    # primitives
    "box", "rounded_box", "bevel_box", "plane", "lathe", "cylinder", "tube", "cone",
    "disc", "uv_sphere", "hemisphere", "capsule", "torus", "extrude", "sweep",
    # profile / path / section helpers
    "arc_profile", "circle_section", "ellipse_section", "rounded_rect_section",
    "bezier_path", "polyline_path", "arc_path", "catmull_rom_path",
    # 2d shapes
    "circle_2d", "ellipse_2d", "rounded_rect_2d", "chamfer_rect_2d", "regular_polygon_2d",
    "mark_2d", "polygon_area_2d", "ensure_ccw_2d", "triangulate_polygon",
]

EPS = 1e-12

# --------------------------------------------------------------------------- detail
_DETAIL_STACK = [1.0]


def get_detail() -> float:
    """Current global detail factor (1.0 = High LOD, ~0.35 = Medium LOD)."""
    return _DETAIL_STACK[-1]


@contextmanager
def detail(level: float):
    """Context manager that sets the global detail factor for primitives.

    >>> with detail(0.35):
    ...     m = cylinder(0.1, 0.2, segments=48)   # -> 17 segments
    """
    _DETAIL_STACK.append(float(level))
    try:
        yield float(level)
    finally:
        _DETAIL_STACK.pop()


def seg(n: float, minimum: int = 3, even: bool = False, multiple: int = 1) -> int:
    """Scale a nominal segment count by the current detail factor.

    ``minimum`` clamps the result, ``even`` forces an even count and
    ``multiple`` rounds up to a multiple (e.g. 4 so a circle keeps vertices on
    its axes).
    """
    v = max(int(minimum), int(round(float(n) * get_detail())))
    if multiple > 1:
        v = int(math.ceil(v / multiple) * multiple)
    if even and v % 2:
        v += 1
    return max(int(minimum), v)


# --------------------------------------------------------------------------- vector / matrix helpers
def _vec3(x, y=None, z=None) -> np.ndarray:
    if y is None and z is None:
        a = np.asarray(x, dtype=float).reshape(-1)
        if a.size == 1:
            return np.array([a[0], a[0], a[0]], dtype=float)
        return a[:3].astype(float)
    return np.array([float(x), float(y if y is not None else 0.0), float(z if z is not None else 0.0)])


def _normalize(v: np.ndarray, axis: int = -1) -> np.ndarray:
    n = np.linalg.norm(v, axis=axis, keepdims=True)
    return v / np.maximum(n, EPS)


_AXES = {"x": np.array([1.0, 0, 0]), "y": np.array([0, 1.0, 0]), "z": np.array([0, 0, 1.0]),
         "-x": np.array([-1.0, 0, 0]), "-y": np.array([0, -1.0, 0]), "-z": np.array([0, 0, -1.0]),
         "+x": np.array([1.0, 0, 0]), "+y": np.array([0, 1.0, 0]), "+z": np.array([0, 0, 1.0])}


def _axis(a) -> np.ndarray:
    if isinstance(a, str):
        return _AXES[a.lower()].copy()
    return _normalize(np.asarray(a, dtype=float).reshape(3))


def rotation_matrix(axis, degrees: float) -> np.ndarray:
    """3x3 right-handed rotation about ``axis`` ('x','y','z' or a vector)."""
    k = _axis(axis)
    t = math.radians(degrees)
    c, s = math.cos(t), math.sin(t)
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + s * K + (1 - c) * (K @ K)


def euler_matrix(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> np.ndarray:
    """3x3 rotation applying X, then Y, then Z (degrees, extrinsic)."""
    return rotation_matrix("z", rz) @ rotation_matrix("y", ry) @ rotation_matrix("x", rx)


def translation_matrix(x, y=None, z=None) -> np.ndarray:
    m = np.eye(4)
    m[:3, 3] = _vec3(x, y, z)
    return m


def scale_matrix(sx, sy=None, sz=None) -> np.ndarray:
    if sy is None and sz is None:
        s = _vec3(sx)
    else:
        s = _vec3(sx, sy, sz)
    m = np.eye(4)
    m[0, 0], m[1, 1], m[2, 2] = s
    return m


def compose(*mats) -> np.ndarray:
    """Compose 3x3/4x4 matrices; the LAST one is applied first (like math)."""
    out = np.eye(4)
    for m in mats:
        m = np.asarray(m, dtype=float)
        if m.shape == (3, 3):
            m4 = np.eye(4)
            m4[:3, :3] = m
            m = m4
        out = out @ m
    return out


# --------------------------------------------------------------------------- Mesh
class Mesh:
    """Indexed triangle mesh tagged with a material name.

    Attributes (numpy arrays, one row per vertex unless noted):
      positions (N,3) float, normals (N,3) float, uvs (N,2) float,
      colors (N,4) float 0..1, tangents (N,4) float or None (computed lazily),
      indices (M,3) int (triangles), material str, name str.

    Transform helpers return NEW meshes, so expressions chain:
        knob = cylinder(0.012, 0.01).translate(0.1, 0.2, 0.3).with_material("brushed_aluminium")
    """

    __slots__ = ("positions", "normals", "uvs", "colors", "tangents", "indices", "material", "name", "uv_tile")

    def __init__(self, positions, indices, normals=None, uvs=None, colors=None, tangents=None,
                 material: str | None = None, name: str | None = None, crease: float = 30.0,
                 uv_tile: float | None = None):
        self.positions = np.array(positions, dtype=float).reshape(-1, 3)
        self.indices = np.array(indices, dtype=np.int64).reshape(-1, 3)
        n = len(self.positions)
        self.uvs = np.zeros((n, 2)) if uvs is None else np.asarray(uvs, dtype=float).reshape(n, 2).copy()
        if colors is None:
            self.colors = np.ones((n, 4))
        else:
            c = np.asarray(colors, dtype=float)
            if c.ndim == 1:
                c = np.broadcast_to(c.reshape(1, -1)[:, :4], (n, 4))
            self.colors = np.array(c, dtype=float).reshape(n, 4)
        self.tangents = None if tangents is None else np.asarray(tangents, dtype=float).reshape(n, 4).copy()
        self.material = material
        self.name = name
        # metres per texture repeat the UVs were generated with (None = fitted / radial UVs)
        self.uv_tile = uv_tile
        if normals is None:
            self.normals = np.zeros((n, 3))
            if n and len(self.indices):
                self._recompute_normals_inplace(crease)
        else:
            self.normals = _normalize(np.asarray(normals, dtype=float).reshape(n, 3))

    # ----------------------------------------------------------------- basics
    def copy(self) -> "Mesh":
        return Mesh(self.positions.copy(), self.indices.copy(), self.normals.copy(), self.uvs.copy(),
                    self.colors.copy(), None if self.tangents is None else self.tangents.copy(),
                    self.material, self.name, uv_tile=self.uv_tile)

    def _with(self, **kw) -> "Mesh":
        m = self.copy()
        for k, v in kw.items():
            setattr(m, k, v)
        return m

    @property
    def vertex_count(self) -> int:
        return int(len(self.positions))

    @property
    def tri_count(self) -> int:
        return int(len(self.indices))

    def __repr__(self) -> str:
        return f"<Mesh {self.name or ''} mat={self.material} verts={self.vertex_count} tris={self.tri_count}>"

    def with_material(self, material: str, rescale_uvs: bool = True) -> "Mesh":
        """Return a copy drawn with ``material`` (a name from lib.materials).

        Texel-density UVs (from primitives, uv_box/uv_planar/uv_cylindrical) are
        rescaled to the new material's ``tile`` so textures keep their real-world
        size; fitted/radial UVs (uv_fit, uv_radial, plane) are left untouched.
        """
        m = self._with(material=material)
        if rescale_uvs and self.uv_tile:
            new_tile = m._tile(None)
            if abs(new_tile - self.uv_tile) > 1e-12:
                m.uvs = m.uvs * (self.uv_tile / new_tile)
                m.uv_tile = new_tile
        return m

    def named(self, name: str) -> "Mesh":
        return self._with(name=name)

    def paint(self, rgba) -> "Mesh":
        """Set every vertex colour (RGBA 0..1, or 0..255 ints if any value > 1)."""
        c = np.asarray(rgba, dtype=float).reshape(-1)
        if c.size == 3:
            c = np.append(c, 1.0)
        if c.max() > 1.0:
            c = c / 255.0
        return self._with(colors=np.tile(c, (self.vertex_count, 1)))

    # ----------------------------------------------------------------- transforms
    def transform(self, m) -> "Mesh":
        """Apply a 3x3 or 4x4 matrix. Mirroring matrices flip the winding."""
        m = np.asarray(m, dtype=float)
        if m.shape == (3, 3):
            lin, t = m, np.zeros(3)
        else:
            lin, t = m[:3, :3], m[:3, 3]
        pos = self.positions @ lin.T + t
        det = float(np.linalg.det(lin))
        inv_t = np.linalg.inv(lin).T if abs(det) > EPS else lin
        nrm = _normalize(self.normals @ inv_t.T)
        tan = None
        if self.tangents is not None:
            txyz = _normalize(self.tangents[:, :3] @ lin.T)
            w = self.tangents[:, 3:4] * (-1.0 if det < 0 else 1.0)
            tan = np.hstack([txyz, w])
        idx = self.indices[:, ::-1].copy() if det < 0 else self.indices.copy()
        return Mesh(pos, idx, nrm, self.uvs.copy(), self.colors.copy(), tan, self.material, self.name,
                    uv_tile=self.uv_tile)

    def translate(self, x, y=None, z=None) -> "Mesh":
        return self.transform(translation_matrix(x, y, z))

    def scale(self, sx, sy=None, sz=None, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        o = _vec3(origin)
        return self.transform(compose(translation_matrix(o), scale_matrix(sx, sy, sz), translation_matrix(-o)))

    def rotate(self, axis, degrees: float, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        o = _vec3(origin)
        return self.transform(compose(translation_matrix(o), rotation_matrix(axis, degrees), translation_matrix(-o)))

    def rotate_x(self, degrees: float, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        return self.rotate("x", degrees, origin)

    def rotate_y(self, degrees: float, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        return self.rotate("y", degrees, origin)

    def rotate_z(self, degrees: float, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        return self.rotate("z", degrees, origin)

    def mirror(self, axis: str = "x", about: float = 0.0) -> "Mesh":
        """Mirror across the plane ``axis = about`` (winding is fixed automatically)."""
        i = "xyz".index(axis.lower().strip("+-"))
        s = np.ones(3)
        s[i] = -1.0
        o = np.zeros(3)
        o[i] = about
        return self.transform(compose(translation_matrix(o), scale_matrix(s), translation_matrix(-o)))

    def orient(self, facing="+y", origin=(0.0, 0.0, 0.0)) -> "Mesh":
        """Turn a flat design authored in the XY plane (x = right, y = up, extruded
        toward +Z) so it faces ``facing`` ('+y' front, '-y' back, '+x', '-x', '+z' top,
        '-z' bottom or a vector), upright and readable for a viewer looking at that
        face, then move it to ``origin``.  Same frame as the planar UV helpers.

            M.extrude(panel_outline, 0.006, holes=cutouts).orient("+y", (0, 0.09, 0.2))
        """
        n = _axis(facing)
        U, V = self._face_frame(n)
        R = np.column_stack([U, -V, n])
        return self.transform(compose(translation_matrix(origin), R))

    def flip(self) -> "Mesh":
        """Reverse winding and normals (turns a surface inside out)."""
        tan = None
        if self.tangents is not None:
            tan = self.tangents.copy()
            tan[:, 3] *= -1
        return Mesh(self.positions.copy(), self.indices[:, ::-1].copy(), -self.normals, self.uvs.copy(),
                    self.colors.copy(), tan, self.material, self.name, uv_tile=self.uv_tile)

    def double_sided(self) -> "Mesh":
        """Return the mesh plus a flipped copy (for thin cards/sheets)."""
        return merge([self, self.flip()])

    # ----------------------------------------------------------------- normals / tangents
    def recompute_normals(self, crease: float = 30.0) -> "Mesh":
        """Return a copy with auto-smoothed normals.

        Corners whose faces meet at less than ``crease`` degrees are smoothed
        (angle-weighted); sharper edges get split vertices.
        """
        m = self.copy()
        m._recompute_normals_inplace(crease)
        return m

    def _recompute_normals_inplace(self, crease: float) -> None:
        P, F = self.positions, self.indices
        if len(F) == 0:
            return
        key = np.round(P / 1e-7).astype(np.int64)
        _, pid = np.unique(key, axis=0, return_inverse=True)
        pid = pid.reshape(-1)
        v0, v1, v2 = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
        fn = _normalize(np.cross(v1 - v0, v2 - v0))
        fn[~np.isfinite(fn).all(axis=1)] = 0.0

        def corner_angle(a, b, c):
            u = _normalize(b - a)
            v = _normalize(c - a)
            return np.arccos(np.clip(np.einsum("ij,ij->i", u, v), -1.0, 1.0))

        ang = np.stack([corner_angle(v0, v1, v2), corner_angle(v1, v2, v0), corner_angle(v2, v0, v1)], axis=1)
        C = F.size
        c_face = np.repeat(np.arange(len(F)), 3)
        c_vid = F.reshape(-1)
        c_pid = pid[c_vid]
        c_w = ang.reshape(-1)
        c_fn = fn[c_face]
        cos_c = math.cos(math.radians(crease))

        order = np.argsort(c_pid, kind="stable")
        sp = c_pid[order]
        starts = np.flatnonzero(np.r_[True, sp[1:] != sp[:-1]])
        ends = np.r_[starts[1:], len(sp)]
        sizes = ends - starts
        out = np.zeros((C, 3))
        for k in np.unique(sizes):
            gs = starts[sizes == k]
            grp = order[gs[:, None] + np.arange(k)[None, :]]          # (G,k) corner ids
            n = c_fn[grp]                                             # (G,k,3)
            w = c_w[grp]                                              # (G,k)
            dots = np.einsum("gid,gjd->gij", n, n)                    # (G,k,k)
            mask = (dots >= cos_c).astype(float)
            acc = np.einsum("gij,gj,gjd->gid", mask, w, n)
            # fall back to plain smooth average when everything is degenerate
            smooth = np.einsum("gj,gjd->gd", w, n)[:, None, :].repeat(k, axis=1)
            bad = np.linalg.norm(acc, axis=2) < 1e-9
            acc[bad] = smooth[bad]
            out[grp.reshape(-1)] = acc.reshape(-1, 3)
        bad = np.linalg.norm(out, axis=1) < 1e-12
        out[bad] = [0.0, 0.0, 1.0]
        cn = _normalize(out)
        # split vertices whose corners received different normals
        q = np.round(cn * 2048.0).astype(np.int64)
        keys = np.column_stack([c_vid, q])
        uniq, first, inv = np.unique(keys, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        src = c_vid[first]
        self.positions = P[src]
        self.uvs = self.uvs[src]
        self.colors = self.colors[src]
        self.tangents = None
        self.normals = cn[first]
        self.indices = inv.reshape(-1, 3).astype(np.int64)

    def compute_tangents(self) -> "Mesh":
        """Compute MikkTSpace-style per-vertex tangents in place (returns self)."""
        P, N, UV, F = self.positions, self.normals, self.uvs, self.indices
        n = len(P)
        T = np.zeros((n, 3))
        B = np.zeros((n, 3))
        if len(F):
            p0, p1, p2 = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
            t0, t1, t2 = UV[F[:, 0]], UV[F[:, 1]], UV[F[:, 2]]
            e1, e2 = p1 - p0, p2 - p0
            d1, d2 = t1 - t0, t2 - t0
            r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
            ok = np.abs(r) > 1e-14
            rs = np.where(ok, 1.0 / np.where(ok, r, 1.0), 0.0)
            ft = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * rs[:, None]   # dP/du
            fb = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * rs[:, None]   # dP/dv
            ft = _normalize(ft)
            fb = _normalize(fb)
            ft[~ok] = 0
            fb[~ok] = 0

            def corner_angle(a, b, c):
                u = _normalize(b - a)
                v = _normalize(c - a)
                return np.arccos(np.clip(np.einsum("ij,ij->i", u, v), -1.0, 1.0))

            angs = [corner_angle(p0, p1, p2), corner_angle(p1, p2, p0), corner_angle(p2, p0, p1)]
            for c in range(3):
                np.add.at(T, F[:, c], ft * angs[c][:, None])
                np.add.at(B, F[:, c], fb * angs[c][:, None])
        # Gram-Schmidt against the normal
        t = T - N * np.einsum("ij,ij->i", N, T)[:, None]
        ln = np.linalg.norm(t, axis=1)
        bad = ln < 1e-9
        if bad.any():
            # fallback: any vector perpendicular to N
            ref = np.where(np.abs(N[bad, 2:3]) < 0.9, np.array([[0, 0, 1.0]]), np.array([[1.0, 0, 0]]))
            t[bad] = np.cross(ref, N[bad])
            ln[bad] = np.linalg.norm(t[bad], axis=1)
        t = t / np.maximum(ln, EPS)[:, None]
        w = np.sign(np.einsum("ij,ij->i", np.cross(N, t), -B))
        w[w == 0] = 1.0
        self.tangents = np.hstack([t, w[:, None]])
        return self

    def ensure_tangents(self) -> np.ndarray:
        if self.tangents is None:
            self.compute_tangents()
        return self.tangents

    def fix_winding(self) -> "Mesh":
        """Flip any triangle whose geometric normal opposes its vertex normals (in place)."""
        P, F = self.positions, self.indices
        if len(F) == 0:
            return self
        gn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
        vn = self.normals[F[:, 0]] + self.normals[F[:, 1]] + self.normals[F[:, 2]]
        flip = np.einsum("ij,ij->i", gn, vn) < 0
        if flip.any():
            self.indices[flip] = self.indices[flip][:, ::-1]
        return self

    # ----------------------------------------------------------------- cleanup
    def weld(self, tol: float = 1e-6) -> "Mesh":
        """Merge vertices that are identical in position/normal/uv/colour."""
        key = np.hstack([np.round(self.positions / tol), np.round(self.normals * 1e4),
                         np.round(self.uvs / 1e-6), np.round(self.colors * 255)]).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        return Mesh(self.positions[first], inv.reshape(-1)[self.indices], self.normals[first], self.uvs[first],
                    self.colors[first], None if self.tangents is None else self.tangents[first],
                    self.material, self.name, uv_tile=self.uv_tile)

    def remove_degenerate(self, area_eps: float = 1e-14) -> "Mesh":
        P, F = self.positions, self.indices
        a = np.linalg.norm(np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]]), axis=1)
        keep = a > area_eps
        return self._with(indices=F[keep].copy()).compact()

    def compact(self) -> "Mesh":
        """Drop vertices that no triangle references."""
        used = np.zeros(self.vertex_count, dtype=bool)
        used[self.indices.reshape(-1)] = True
        remap = -np.ones(self.vertex_count, dtype=np.int64)
        remap[used] = np.arange(int(used.sum()))
        return Mesh(self.positions[used], remap[self.indices], self.normals[used], self.uvs[used],
                    self.colors[used], None if self.tangents is None else self.tangents[used],
                    self.material, self.name, uv_tile=self.uv_tile)

    # ----------------------------------------------------------------- UV helpers
    def _tile(self, tile):
        if tile is not None:
            return float(tile)
        if self.material:
            try:
                from . import materials as _mats
                return float(_mats.get(self.material).tile)
            except Exception:
                pass
        return 0.25

    @staticmethod
    def _face_frame(n: np.ndarray):
        """(U, V) image axes for a planar projection seen from outside along ``n``."""
        n = _normalize(np.asarray(n, dtype=float))
        if abs(n[2]) > 0.7071:
            up = np.array([0.0, -1.0, 0.0]) if n[2] > 0 else np.array([0.0, 1.0, 0.0])
        else:
            up = np.array([0.0, 0.0, 1.0])
        U = _normalize(np.cross(up, n))
        V = -_normalize(up - n * np.dot(up, n))
        return U, V

    def uv_planar(self, axis="+y", tile=None, origin=(0.0, 0.0, 0.0), rotate: float = 0.0) -> "Mesh":
        """Project UVs along ``axis`` (the direction the textured side faces).

        One texture repeat covers ``tile`` metres (default: the material's tile).
        Images appear upright when the face is seen from outside.
        """
        tile = self._tile(tile)
        U, V = self._face_frame(_axis(axis))
        p = self.positions - _vec3(origin)
        uv = np.column_stack([p @ U, p @ V]) / tile
        if rotate:
            uv = _rot2(uv, rotate)
        return self._with(uvs=uv, uv_tile=tile)

    def uv_fit(self, rect=(0.0, 0.0, 1.0, 1.0), axis="+y", bounds=None, keep_aspect: bool = False) -> "Mesh":
        """Planar-project along ``axis`` and stretch the projected bounds onto ``rect``.

        ``rect`` = (u0, v0, u1, v1) in UV space (v0 = top of the image). Use it
        for labels, atlas entries and decals.  ``bounds`` = ((umin, vmin),
        (umax, vmax)) in projected metres overrides the automatic bounds.
        """
        U, V = self._face_frame(_axis(axis))
        p = self.positions
        pu, pv = p @ U, p @ V
        if bounds is None:
            lo = np.array([pu.min(), pv.min()])
            hi = np.array([pu.max(), pv.max()])
        else:
            lo, hi = np.asarray(bounds[0], float), np.asarray(bounds[1], float)
        size = np.maximum(hi - lo, EPS)
        if keep_aspect:
            s = size.max()
            c = (lo + hi) / 2
            lo, size = c - s / 2, np.array([s, s])
        u0, v0, u1, v1 = rect
        u = u0 + (pu - lo[0]) / size[0] * (u1 - u0)
        v = v0 + (pv - lo[1]) / size[1] * (v1 - v0)
        return self._with(uvs=np.column_stack([u, v]), uv_tile=None)

    def uv_radial(self, radius: float, center=(0.0, 0.0, 0.0), axis="+z", rect=(0.0, 0.0, 1.0, 1.0)) -> "Mesh":
        """Map a disc of ``radius`` around ``center`` (seen along ``axis``) onto ``rect``.

        Used for records, labels and radially brushed knob tops.
        """
        U, V = self._face_frame(_axis(axis))
        p = self.positions - _vec3(center)
        pu, pv = p @ U, p @ V
        u0, v0, u1, v1 = rect
        u = u0 + (pu / (2 * radius) + 0.5) * (u1 - u0)
        v = v0 + (pv / (2 * radius) + 0.5) * (v1 - v0)
        return self._with(uvs=np.column_stack([u, v]), uv_tile=None)

    def uv_box(self, tile=None, origin=(0.0, 0.0, 0.0)) -> "Mesh":
        """Box (tri-planar) projection chosen per triangle; splits vertices on seams."""
        tile = self._tile(tile)
        P, F = self.positions - _vec3(origin), self.indices
        if len(F) == 0:
            return self.copy()
        fn = np.cross(self.positions[F[:, 1]] - self.positions[F[:, 0]],
                      self.positions[F[:, 2]] - self.positions[F[:, 0]])
        fn += (self.normals[F[:, 0]] + self.normals[F[:, 1]] + self.normals[F[:, 2]]) * 1e-9
        dom = np.argmax(np.abs(fn), axis=1)
        sgn = np.sign(fn[np.arange(len(F)), dom])
        sgn[sgn == 0] = 1
        face_key = dom * 2 + (sgn > 0)
        c_vid = F.reshape(-1)
        c_key = np.repeat(face_key, 3)
        keys = np.column_stack([c_vid, c_key])
        uniq, first, inv = np.unique(keys, axis=0, return_index=True, return_inverse=True)
        src = c_vid[first]
        fk = c_key[first]
        new_uv = np.zeros((len(src), 2))
        for k in range(6):
            sel = fk == k
            if not sel.any():
                continue
            n = np.zeros(3)
            n[k // 2] = 1.0 if (k % 2) else -1.0
            U, V = self._face_frame(n)
            pp = P[src[sel]]
            new_uv[sel] = np.column_stack([pp @ U, pp @ V]) / tile
        return Mesh(self.positions[src], inv.reshape(-1, 3), self.normals[src], new_uv, self.colors[src],
                    None, self.material, self.name, uv_tile=tile)

    def uv_cylindrical(self, axis="z", tile=None, center=(0.0, 0.0, 0.0), radius=None) -> "Mesh":
        """Cylindrical unwrap around ``axis``: u = arc length, v = -height (upright)."""
        tile = self._tile(tile)
        a = _axis(axis)
        ref = np.array([1.0, 0, 0]) if abs(a[0]) < 0.9 else np.array([0, 1.0, 0])
        e1 = _normalize(ref - a * np.dot(ref, a))
        e2 = np.cross(a, e1)
        p = self.positions - _vec3(center)
        x, y, h = p @ e1, p @ e2, p @ a
        ang = np.arctan2(y, x)
        R = float(radius) if radius else max(float(np.sqrt(x * x + y * y).max()), 1e-6)
        F = self.indices
        # split triangles that straddle the -pi/pi seam
        angc = ang[F]
        straddle = (angc.max(axis=1) - angc.min(axis=1)) > math.pi
        u = ang.copy()
        c_vid = F.reshape(-1)
        c_shift = np.zeros(F.size, dtype=np.int64)
        if straddle.any():
            sel = np.repeat(straddle, 3) & (ang[c_vid] < 0)
            c_shift[sel] = 1
        keys = np.column_stack([c_vid, c_shift])
        uniq, first, inv = np.unique(keys, axis=0, return_index=True, return_inverse=True)
        src = c_vid[first]
        uu = u[src] + c_shift[first] * 2 * math.pi
        uv = np.column_stack([uu * R / tile, -h[src] / tile])
        return Mesh(self.positions[src], inv.reshape(-1, 3), self.normals[src], uv, self.colors[src], None,
                    self.material, self.name, uv_tile=tile)

    def uv_transform(self, scale=(1.0, 1.0), offset=(0.0, 0.0), rotate: float = 0.0) -> "Mesh":
        """uv' = rotate(uv * scale) + offset."""
        uv = self.uvs * np.asarray(scale, float).reshape(1, 2)
        if rotate:
            uv = _rot2(uv, rotate)
        return self._with(uvs=uv + np.asarray(offset, float).reshape(1, 2), uv_tile=None)

    # ----------------------------------------------------------------- measurements
    def bbox(self):
        """(min xyz, max xyz) as numpy arrays."""
        if self.vertex_count == 0:
            return np.zeros(3), np.zeros(3)
        return self.positions.min(axis=0), self.positions.max(axis=0)

    def bounding_sphere(self):
        """(center, radius): bbox centre and the farthest vertex distance."""
        lo, hi = self.bbox()
        c = (lo + hi) / 2
        r = float(np.linalg.norm(self.positions - c, axis=1).max()) if self.vertex_count else 0.0
        return c, r

    def area(self) -> float:
        P, F = self.positions, self.indices
        return float(np.linalg.norm(np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]]), axis=1).sum() / 2)

    def check(self) -> list[str]:
        """Return a list of problems (empty when the mesh is clean)."""
        errs = []
        for nm in ("positions", "normals", "uvs", "colors"):
            if not np.isfinite(getattr(self, nm)).all():
                errs.append(f"{nm} contain NaN/inf")
        if len(self.indices) and (self.indices.min() < 0 or self.indices.max() >= self.vertex_count):
            errs.append("index out of range")
        if self.tangents is not None and not np.isfinite(self.tangents).all():
            errs.append("tangents contain NaN/inf")
        return errs


def _rot2(uv: np.ndarray, degrees: float) -> np.ndarray:
    t = math.radians(degrees)
    c, s = math.cos(t), math.sin(t)
    return uv @ np.array([[c, s], [-s, c]])


# --------------------------------------------------------------------------- combining
def merge(meshes: Iterable[Mesh], material: str | None = None, name: str | None = None) -> Mesh:
    """Concatenate meshes. All must share one material unless ``material`` is given."""
    meshes = [m for m in meshes if m is not None and m.vertex_count > 0]
    if not meshes:
        return Mesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64), np.zeros((0, 3)), material=material,
                    name=name)
    mats = {m.material for m in meshes}
    if material is None:
        if len(mats) > 1:
            raise ValueError(f"merge(): parts use different materials {sorted(map(str, mats))}; "
                             f"use group_by_material() or pass material=")
        material = meshes[0].material
    offs = np.cumsum([0] + [m.vertex_count for m in meshes[:-1]])
    tans = None
    if all(m.tangents is not None for m in meshes):
        tans = np.vstack([m.tangents for m in meshes])
    tiles = {m.uv_tile for m in meshes}
    return Mesh(np.vstack([m.positions for m in meshes]),
                np.vstack([m.indices + o for m, o in zip(meshes, offs)]),
                np.vstack([m.normals for m in meshes]),
                np.vstack([m.uvs for m in meshes]),
                np.vstack([m.colors for m in meshes]),
                tans, material, name or meshes[0].name, uv_tile=tiles.pop() if len(tiles) == 1 else None)


def group_by_material(parts: Iterable[Mesh]) -> dict:
    """{material: merged Mesh} in first-seen order (parts without material -> KeyError)."""
    groups: dict = {}
    for p in parts:
        if p is None or p.vertex_count == 0:
            continue
        if not p.material:
            raise KeyError(f"part {p.name!r} has no material")
        groups.setdefault(p.material, []).append(p)
    return {k: merge(v) for k, v in groups.items()}


def parts_bounds(parts: Iterable[Mesh]):
    """(bbmin, bbmax, sphere_centre, sphere_radius) over all parts."""
    ps = [p.positions for p in parts if p is not None and p.vertex_count]
    if not ps:
        z = np.zeros(3)
        return z, z, z, 0.0
    P = np.vstack(ps)
    lo, hi = P.min(axis=0), P.max(axis=0)
    c = (lo + hi) / 2
    return lo, hi, c, float(np.linalg.norm(P - c, axis=1).max())


def parts_tri_count(parts: Iterable[Mesh]) -> int:
    return int(sum(p.tri_count for p in parts if p is not None))


def array_linear(mesh: Mesh, count: int, step) -> Mesh:
    """``count`` copies, each offset by ``step`` (xyz) from the previous."""
    st = _vec3(step)
    return merge([mesh.translate(st * i) for i in range(int(count))])


def array_radial(mesh: Mesh, count: int, axis="z", center=(0.0, 0.0, 0.0), angle: float = 360.0,
                 start: float = 0.0) -> Mesh:
    """``count`` copies rotated around ``axis`` through ``center``.

    For a full 360 degrees the copies are evenly spaced without duplicating the
    first one; for partial arcs the first and last copy sit on the arc ends.
    """
    count = int(count)
    if count <= 0:
        return merge([])
    full = abs(angle) >= 359.999
    stepa = angle / count if full else (angle / max(count - 1, 1))
    return merge([mesh.rotate(axis, start + stepa * i, origin=center) for i in range(count)])


def array_grid(mesh: Mesh, counts=(2, 2), spacing=(0.1, 0.1), axes: str = "xy", centered: bool = True) -> Mesh:
    """2D grid of copies in the plane spanned by ``axes`` (e.g. 'xz' for a front panel)."""
    a0, a1 = "xyz".index(axes[0]), "xyz".index(axes[1])
    nx, ny = int(counts[0]), int(counts[1])
    out = []
    for i in range(nx):
        for j in range(ny):
            off = np.zeros(3)
            off[a0] = (i - (nx - 1) / 2 if centered else i) * spacing[0]
            off[a1] = (j - (ny - 1) / 2 if centered else j) * spacing[1]
            out.append(mesh.translate(off))
    return merge(out)


# --------------------------------------------------------------------------- simple primitives
def box(size, center=(0.0, 0.0, 0.0), tile: float | None = None, material: str | None = None) -> Mesh:
    """Sharp-edged box of ``size`` (sx, sy, sz) centred on ``center``."""
    return rounded_box(size, 0.0, 1, center=center, tile=tile, material=material)


def plane(width: float, height: float, center=(0.0, 0.0, 0.0), facing="+z", segments=(1, 1),
          rect=(0.0, 0.0, 1.0, 1.0), material: str | None = None) -> Mesh:
    """Flat rectangle facing ``facing`` with UVs fitted to ``rect`` (0..1 by default).

    ``width`` runs along the image's u axis, ``height`` along v.  Ideal for
    labels, screens, decals and sleeve covers.  The image is upright for a
    viewer looking at that face (top faces: read from the model front).
    ``facing="design"`` builds it in design space instead (XY plane, image
    right = +x, image up = +y, normal +z) for use with ``Mesh.orient``.
    """
    if isinstance(facing, str) and facing == "design":
        n, U, V = np.array([0, 0, 1.0]), np.array([1.0, 0, 0]), np.array([0, -1.0, 0])
    else:
        n = _axis(facing)
        U, V = Mesh._face_frame(n)
    nu, nv = max(1, int(segments[0])), max(1, int(segments[1]))
    su = np.linspace(-0.5, 0.5, nu + 1) * width
    sv = np.linspace(-0.5, 0.5, nv + 1) * height
    gu, gv = np.meshgrid(su, sv, indexing="xy")
    pos = gu.reshape(-1, 1) * U + gv.reshape(-1, 1) * V + _vec3(center)
    u0, v0, u1, v1 = rect
    uv = np.column_stack([u0 + (gu.reshape(-1) / width + 0.5) * (u1 - u0),
                          v0 + (gv.reshape(-1) / height + 0.5) * (v1 - v0)])
    idx = []
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            idx += [(a, a + 1, a + nu + 2), (a, a + nu + 2, a + nu + 1)]
    m = Mesh(pos, idx, np.tile(n, (len(pos), 1)), uv, material=material, name="plane")
    return m.fix_winding()


def rounded_box(size, radius=0.01, segments: int = 4, center=(0.0, 0.0, 0.0), profile: str = "round",
                tile: float | None = None, material: str | None = None) -> Mesh:
    """Box with rounded (or chamfered) edges and corners.

    size     : (sx, sy, sz) full dimensions.
    radius   : one value or per-axis (rx, ry, rz) rounding depth; 0 on an axis
               keeps those faces flat/sharp (e.g. (r, r, 0) = rounded-rect prism).
    segments : nominal segments per 90 degree edge (scaled by the detail factor).
    profile  : 'round' or 'chamfer' (flat 45 degree bevel).
    UVs are box-projected per face (texel density ``tile`` metres per repeat).
    """
    h = np.asarray(size, dtype=float).reshape(3) / 2.0
    r = np.broadcast_to(np.asarray(radius, dtype=float).reshape(-1), (3,)).astype(float).copy()
    r = np.clip(r, 0.0, h)
    inner = h - r
    chamfer = profile == "chamfer"
    k = 1 if chamfer else max(1, int(math.ceil(seg(segments, 2) / 2)))
    if tile is None:
        tile = Mesh(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3)), material=material)._tile(None)

    def axis_coords(a):
        if r[a] <= 1e-9:
            return np.array([-h[a], h[a]]), np.array([-h[a], h[a]])
        th = np.linspace(0.0, math.pi / 4, k + 1)[1:]
        band = inner[a] + r[a] * np.tan(th)
        band_u = inner[a] + r[a] * th
        mid = np.array([-inner[a], inner[a]]) if inner[a] > 1e-9 else np.array([0.0])
        pc = np.concatenate([-band[::-1], mid, band])
        uc = np.concatenate([-band_u[::-1], mid, band_u])
        return pc, uc

    coords = [axis_coords(a) for a in range(3)]
    all_pos, all_nrm, all_uv, all_idx = [], [], [], []
    base = 0
    for a in range(3):
        b, c = [i for i in range(3) if i != a]
        for s in (1.0, -1.0):
            pb, ub = coords[b]
            pc_, uc_ = coords[c]
            gb, gc = np.meshgrid(pb, pc_, indexing="ij")
            gub, guc = np.meshgrid(ub, uc_, indexing="ij")
            nb_, nc_ = gb.shape
            P = np.zeros((nb_ * nc_, 3))
            P[:, a] = s * h[a]
            P[:, b] = gb.reshape(-1)
            P[:, c] = gc.reshape(-1)
            ip = np.clip(P, -inner, inner)
            d = P - ip
            rs = np.where(r > 1e-9, r, 1.0)
            q = np.where(r > 1e-9, d / rs, 0.0)
            nq = np.abs(q).sum(axis=1) if chamfer else np.linalg.norm(q, axis=1)
            if r[a] > 1e-9:
                # face is part of the rounded surface: project onto it
                on = nq > 1e-12
                qn = np.where(on[:, None], q / np.maximum(nq, EPS)[:, None], q)
            else:
                # flat face (rounded-rect outline): square-to-disc map of the corner
                # region keeps grid points distinct and puts the border on the arc
                on = np.zeros(len(q), dtype=bool)
                ninf = np.abs(q).max(axis=1)
                fac = np.where(nq > 1e-12, ninf / np.maximum(nq, EPS), 1.0)
                qn = q * fac[:, None]
            pos = ip + qn * r
            fnrm = np.zeros(3)
            fnrm[a] = s
            if chamfer:
                g = np.where((r > 1e-9) & (np.abs(qn) > 1e-9), np.sign(qn) / rs, 0.0)
            else:
                g = np.where(r > 1e-9, qn / rs, 0.0)
            nrm = _normalize(g)
            use_face = (~on) | (np.linalg.norm(g, axis=1) < 1e-12)
            nrm[use_face] = fnrm
            unrolled = np.zeros_like(P)
            unrolled[:, b] = gub.reshape(-1)
            unrolled[:, c] = guc.reshape(-1)
            U, V = Mesh._face_frame(fnrm)
            uv = np.column_stack([unrolled @ U, unrolled @ V]) / float(tile)
            idx = []
            for i in range(nb_ - 1):
                for j in range(nc_ - 1):
                    v00 = base + i * nc_ + j
                    v01, v10, v11 = v00 + 1, v00 + nc_, v00 + nc_ + 1
                    idx += [(v00, v10, v11), (v00, v11, v01)]
            all_pos.append(pos)
            all_nrm.append(nrm)
            all_uv.append(uv)
            all_idx.extend(idx)
            base += len(pos)
    m = Mesh(np.vstack(all_pos) + _vec3(center), np.array(all_idx), np.vstack(all_nrm), np.vstack(all_uv),
             material=material, name="rounded_box", uv_tile=float(tile))
    m = m.remove_degenerate(1e-16)
    m.fix_winding()
    if chamfer:
        m = m.recompute_normals(20.0)
    return m


def bevel_box(size, bevel=0.004, center=(0.0, 0.0, 0.0), tile: float | None = None,
              material: str | None = None) -> Mesh:
    """Box with flat 45 degree chamfered edges of depth ``bevel``."""
    return rounded_box(size, bevel, 1, center=center, profile="chamfer", tile=tile, material=material)


# --------------------------------------------------------------------------- lathe & friends
def arc_profile(center, radius: float, a0: float, a1: float, n: int = 4, concave: bool = False):
    """Points on an arc in the (r, z) plane with analytic normals.

    Angles in degrees, measured from +r towards +z.  Returns a list of
    (r, z, nr, nz) tuples suitable for ``lathe`` profiles; ``concave`` flips
    the normals (for inside fillets).  ``n`` is scaled by the detail factor.
    """
    n = seg(n, 1)
    out = []
    for t in np.linspace(math.radians(a0), math.radians(a1), n + 1):
        c, s = math.cos(t), math.sin(t)
        nr, nz = (-c, -s) if concave else (c, s)
        out.append((center[0] + radius * c, center[1] + radius * s, nr, nz))
    return out


def _parse_profile(profile):
    pts, nrm = [], []
    for p in profile:
        p = tuple(float(x) for x in p)
        pts.append(p[:2])
        nrm.append(p[2:4] if len(p) >= 4 else (np.nan, np.nan))
    return np.array(pts, dtype=float), np.array(nrm, dtype=float)


def lathe(profile, segments: int = 32, sweep: float = 360.0, start: float = 0.0, crease: float = 40.0,
          closed: bool = False, tile: float | None = None, material: str | None = None,
          name: str = "lathe") -> Mesh:
    """Revolve a 2D profile around the Z axis.

    profile : sequence of (r, z) or (r, z, nr, nz) points.  Walk the profile
              with the solid on your LEFT (i.e. bottom-to-top along the outside:
              (0,0) -> (R,0) -> (R,H) -> (0,H) makes a capped cylinder).  Points
              with r == 0 close the surface on the axis.  Optional (nr, nz) give
              an explicit vertex normal (use ``arc_profile`` for fillets);
              otherwise corners sharper than ``crease`` degrees are split.
    segments: nominal segments around (scaled by detail).
    sweep/start: partial revolutions in degrees (start at +X, CCW seen from +Z).
    closed  : connect the last profile point back to the first (tubes, torus).
    UVs     : u = arc length around at the largest radius, v = -profile length,
              both divided by ``tile`` (lathe unwrap; images stay upright).
    """
    pts, enrm = _parse_profile(profile)
    if closed:
        if np.linalg.norm(pts[0] - pts[-1]) > 1e-9:
            pts = np.vstack([pts, pts[:1]])
            enrm = np.vstack([enrm, enrm[:1]])
        else:
            enrm[-1] = enrm[0]
    keep = [0]
    for i in range(1, len(pts)):
        if np.linalg.norm(pts[i] - pts[keep[-1]]) > 1e-9:
            keep.append(i)
        elif not np.isnan(enrm[i]).any():
            enrm[keep[-1]] = enrm[i]
    pts, enrm = pts[keep], enrm[keep]
    if len(pts) < 2:
        raise ValueError("lathe(): profile needs at least two distinct points")
    pts[:, 0] = np.maximum(pts[:, 0], 0.0)
    K = len(pts)
    S = K - 1
    dvec = pts[1:] - pts[:-1]
    slen = np.linalg.norm(dvec, axis=1)
    sn = _normalize(np.column_stack([dvec[:, 1], -dvec[:, 0]]))
    cum = np.concatenate([[0.0], np.cumsum(slen)])
    cos_c = math.cos(math.radians(crease))

    ring_pt, ring_n, ring_v = [], [], []
    seg_start = [None] * S
    seg_end = [None] * S

    def add_ring(k, n2):
        ring_pt.append(pts[k])
        ring_n.append(_normalize(np.asarray(n2, dtype=float)))
        ring_v.append(cum[k])
        return len(ring_pt) - 1

    for k in range(K):
        prev_s = k - 1 if k > 0 else (S - 1 if closed else None)
        next_s = k if k < S else (0 if closed else None)
        if not np.isnan(enrm[k]).any():
            ri = add_ring(k, enrm[k])
            r_prev = r_next = ri
        else:
            na = sn[prev_s] if prev_s is not None else None
            nb = sn[next_s] if next_s is not None else None
            if na is None:
                r_prev = r_next = add_ring(k, nb)
            elif nb is None:
                r_prev = r_next = add_ring(k, na)
            elif float(np.dot(na, nb)) >= cos_c:
                r_prev = r_next = add_ring(k, na + nb)
            else:
                r_prev = add_ring(k, na)
                r_next = add_ring(k, nb)
        if k > 0:
            seg_end[k - 1] = r_prev
        if k < S:
            seg_start[k] = r_next

    nseg = seg(segments, 3)
    full = abs(sweep) >= 359.999
    th = np.radians(start + np.linspace(0.0, sweep, nseg + 1))
    ncol = nseg + 1
    R_ref = max(float(pts[:, 0].max()), 1e-6)
    if tile is None:
        tile = Mesh(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3)), material=material)._tile(None)
    ct, st = np.cos(th), np.sin(th)
    nr = len(ring_pt)
    rp = np.array(ring_pt)
    rn = np.array(ring_n)
    rv = np.array(ring_v)
    pos = np.zeros((nr, ncol, 3))
    nrm = np.zeros((nr, ncol, 3))
    pos[:, :, 0] = rp[:, 0:1] * ct[None, :]
    pos[:, :, 1] = rp[:, 0:1] * st[None, :]
    pos[:, :, 2] = rp[:, 1:2]
    nrm[:, :, 0] = rn[:, 0:1] * ct[None, :]
    nrm[:, :, 1] = rn[:, 0:1] * st[None, :]
    nrm[:, :, 2] = rn[:, 1:2]
    uv = np.zeros((nr, ncol, 2))
    uv[:, :, 0] = (np.radians(np.linspace(0.0, sweep, ncol)) * R_ref / tile)[None, :]
    uv[:, :, 1] = (-rv / tile)[:, None]
    idx = []
    j = np.arange(nseg)
    for s in range(S):
        A, B = seg_start[s], seg_end[s]
        a0, a1 = A * ncol + j, A * ncol + j + 1
        b0, b1 = B * ncol + j, B * ncol + j + 1
        rA, rB = rp[A, 0], rp[B, 0]
        if rA <= 1e-9 and rB <= 1e-9:
            continue
        if rA <= 1e-9:
            idx.append(np.column_stack([a0, b1, b0]))
        elif rB <= 1e-9:
            idx.append(np.column_stack([a0, a1, b1]))
        else:
            idx.append(np.column_stack([a0, a1, b1]))
            idx.append(np.column_stack([a0, b1, b0]))
    F = np.vstack(idx) if idx else np.zeros((0, 3), dtype=np.int64)
    m = Mesh(pos.reshape(-1, 3), F, nrm.reshape(-1, 3), uv.reshape(-1, 2), material=material, name=name,
             uv_tile=float(tile))
    m.fix_winding()
    return m.compact()


def cylinder(radius: float, height: float, segments: int = 32, bevel: float = 0.0, bevel_segments: int = 3,
             top: bool = True, bottom: bool = True, sweep: float = 360.0, start: float = 0.0,
             center: bool = False, tile: float | None = None, material: str | None = None) -> Mesh:
    """Z-axis cylinder from z=0 to z=height (or centred on z=0 with center=True).

    ``bevel`` rounds both cap edges with ``bevel_segments`` arc steps; ``top`` /
    ``bottom`` = False leaves that end open.
    """
    R, H = float(radius), float(height)
    b = min(max(float(bevel), 0.0), R * 0.999, H / 2 * 0.999)
    prof = []
    if b > 0:
        if bottom:
            prof.append((0.0, 0.0, 0.0, -1.0))
        prof += arc_profile((R - b, b), b, -90, 0, bevel_segments) if bottom else [(R, 0.0)]
        prof += arc_profile((R - b, H - b), b, 0, 90, bevel_segments) if top else [(R, H)]
        if top:
            prof.append((0.0, H, 0.0, 1.0))
    else:
        if bottom:
            prof.append((0.0, 0.0))
        prof += [(R, 0.0), (R, H)]
        if top:
            prof.append((0.0, H))
    m = lathe(prof, segments, sweep, start, tile=tile, material=material, name="cylinder")
    return m.translate(0, 0, -H / 2) if center else m


def tube(r_outer: float, r_inner: float, height: float, segments: int = 32, bevel: float = 0.0,
         bevel_segments: int = 2, sweep: float = 360.0, start: float = 0.0, center: bool = False,
         tile: float | None = None, material: str | None = None) -> Mesh:
    """Hollow cylinder (ring/collar) from z=0 to ``height`` with optional rounded edges."""
    ro, ri, H = float(r_outer), float(r_inner), float(height)
    b = min(max(float(bevel), 0.0), (ro - ri) / 2 * 0.999, H / 2 * 0.999)
    if b > 0:
        prof = [(ri + b, 0.0, 0.0, -1.0)]
        prof += arc_profile((ro - b, b), b, -90, 0, bevel_segments)
        prof += arc_profile((ro - b, H - b), b, 0, 90, bevel_segments)
        prof += arc_profile((ri + b, H - b), b, 90, 180, bevel_segments)
        prof += arc_profile((ri + b, b), b, 180, 270, bevel_segments)
    else:
        prof = [(ri, 0.0), (ro, 0.0), (ro, H), (ri, H)]
    m = lathe(prof, segments, sweep, start, closed=True, tile=tile, material=material, name="tube")
    return m.translate(0, 0, -H / 2) if center else m


def cone(r_bottom: float, r_top: float, height: float, segments: int = 32, top: bool = True,
         bottom: bool = True, tile: float | None = None, material: str | None = None) -> Mesh:
    """Frustum / cone along +Z (r_top = 0 for a pointed cone)."""
    prof = []
    if bottom:
        prof.append((0.0, 0.0))
    prof += [(r_bottom, 0.0), (r_top, height)]
    if top and r_top > 0:
        prof.append((0.0, height))
    return lathe(prof, segments, tile=tile, material=material, name="cone")


def disc(radius: float, inner_radius: float = 0.0, segments: int = 48, facing: str = "+z",
         tile: float | None = None, material: str | None = None) -> Mesh:
    """Flat disc (or annulus) at z=0 facing +Z (or -Z).  UVs: radial unwrap;
    call ``.uv_radial(radius)`` for a 0..1 label-style mapping."""
    m = lathe([(radius, 0.0), (inner_radius, 0.0)], segments, tile=tile, material=material, name="disc")
    if facing.startswith("-"):
        m = m.flip()
    return m


def uv_sphere(radius: float, segments: int = 32, rings: int = 16, center=(0.0, 0.0, 0.0),
              tile: float | None = None, material: str | None = None) -> Mesh:
    """UV sphere; ``rings`` latitude bands (scaled by detail)."""
    n = seg(rings, 4)
    prof = []
    for t in np.linspace(-90.0, 90.0, n + 1):
        c, s = math.cos(math.radians(t)), math.sin(math.radians(t))
        prof.append((radius * c if abs(c) > 1e-9 else 0.0, radius * s, c, s))
    return lathe(prof, segments, tile=tile, material=material, name="sphere").translate(center)


def hemisphere(radius: float, segments: int = 32, rings: int = 8, cap: bool = True,
               tile: float | None = None, material: str | None = None) -> Mesh:
    """Upper half sphere sitting on z=0 (optionally closed with a flat base)."""
    n = seg(rings, 2)
    prof = [(0.0, 0.0, 0.0, -1.0), (radius, 0.0)] if cap else []
    for t in np.linspace(0.0, 90.0, n + 1):
        c, s = math.cos(math.radians(t)), math.sin(math.radians(t))
        prof.append((radius * c if abs(c) > 1e-9 else 0.0, radius * s, c, s))
    return lathe(prof, segments, tile=tile, material=material, name="hemisphere")


def capsule(radius: float, length: float, segments: int = 24, rings: int = 6, tile: float | None = None,
            material: str | None = None) -> Mesh:
    """Z-axis capsule; ``length`` is the cylindrical part, base hemisphere starts at z=0."""
    n = seg(rings, 2)
    prof = []
    for t in np.linspace(-90.0, 0.0, n + 1):
        c, s = math.cos(math.radians(t)), math.sin(math.radians(t))
        prof.append((radius * c if abs(c) > 1e-9 else 0.0, radius + radius * s, c, s))
    for t in np.linspace(0.0, 90.0, n + 1):
        c, s = math.cos(math.radians(t)), math.sin(math.radians(t))
        prof.append((radius * c if abs(c) > 1e-9 else 0.0, radius + length + radius * s, c, s))
    return lathe(prof, segments, tile=tile, material=material, name="capsule")


def torus(major: float, minor: float, segments: int = 48, sides: int = 16, sweep: float = 360.0,
          start: float = 0.0, tile: float | None = None, material: str | None = None) -> Mesh:
    """Torus around Z at z=0 (``sweep`` < 360 gives an open arc, e.g. handles)."""
    n = seg(sides, 4)
    prof = []
    for t in np.linspace(-90.0, 270.0, n + 1)[:-1]:
        c, s = math.cos(math.radians(t)), math.sin(math.radians(t))
        prof.append((major + minor * c, minor * s, c, s))
    return lathe(prof, segments, sweep, start, closed=True, tile=tile, material=material, name="torus")


# --------------------------------------------------------------------------- 2D shapes
def polygon_area_2d(pts) -> float:
    p = np.asarray(pts, dtype=float)
    x, y = p[:, 0], p[:, 1]
    return float(0.5 * (np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))


def ensure_ccw_2d(pts) -> np.ndarray:
    p = np.asarray(pts, dtype=float)
    return p if polygon_area_2d(p) >= 0 else p[::-1].copy()


def circle_2d(radius: float, n: int = 48, center=(0.0, 0.0), start: float = 0.0) -> np.ndarray:
    """CCW circle outline (``n`` scaled by detail, multiple of 4)."""
    n = seg(n, 6, multiple=4)
    t = np.radians(start) + np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.column_stack([center[0] + radius * np.cos(t), center[1] + radius * np.sin(t)])


def ellipse_2d(rx: float, ry: float, n: int = 48, center=(0.0, 0.0)) -> np.ndarray:
    n = seg(n, 6, multiple=4)
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.column_stack([center[0] + rx * np.cos(t), center[1] + ry * np.sin(t)])


def regular_polygon_2d(radius: float, sides: int, center=(0.0, 0.0), start: float = 90.0) -> np.ndarray:
    t = np.radians(start) + np.linspace(0, 2 * math.pi, int(sides), endpoint=False)
    return np.column_stack([center[0] + radius * np.cos(t), center[1] + radius * np.sin(t)])


def rounded_rect_2d(width: float, height: float, radius: float, segments: int = 6,
                    center=(0.0, 0.0), radii=None) -> np.ndarray:
    """CCW rounded rectangle.  ``radii`` = (bottom-left, bottom-right, top-right,
    top-left) overrides ``radius`` per corner (0 = sharp)."""
    w, h = width / 2.0, height / 2.0
    rr = list(radii) if radii is not None else [radius] * 4
    rr = [min(max(float(x), 0.0), w, h) for x in rr]
    n = seg(segments, 1)
    corners = [((-w, -h), 180.0), ((w, -h), 270.0), ((w, h), 0.0), ((-w, h), 90.0)]
    out = []
    for ci, ((cx, cy), a0) in enumerate(corners):
        r = rr[ci]
        if r <= 1e-9:
            out.append((cx, cy))
            continue
        ccx = cx - math.copysign(r, cx)
        ccy = cy - math.copysign(r, cy)
        for t in np.linspace(a0, a0 + 90.0, n + 1):
            out.append((ccx + r * math.cos(math.radians(t)), ccy + r * math.sin(math.radians(t))))
    p = np.array(out) + np.asarray(center, float)
    return _dedupe_2d(p)


def chamfer_rect_2d(width: float, height: float, chamfer: float, center=(0.0, 0.0), corners=(1, 1, 1, 1)) -> np.ndarray:
    """CCW rectangle with 45 degree corner cuts; ``corners`` toggles (bl, br, tr, tl)."""
    w, h, c = width / 2.0, height / 2.0, float(chamfer)
    pts = []
    spec = [((-w, -h), (0, c), (c, 0)), ((w, -h), (-c, 0), (0, c)), ((w, h), (0, -c), (-c, 0)),
            ((-w, h), (c, 0), (0, -c))]
    for on, ((x, y), d0, d1) in zip(corners, spec):
        if on and c > 0:
            pts += [(x + d0[0], y + d0[1]), (x + d1[0], y + d1[1])]
        else:
            pts.append((x, y))
    return _dedupe_2d(np.array(pts) + np.asarray(center, float))


def mark_2d(size: float = 1.0, segments: int = 6, center=(0.0, 0.0)):
    """The nayzeee "mark" logo outline: (outline, bar).

    A rounded square (radius 20% of size) whose bottom-right corner is cut
    from (100%, 56%) to (56%, 100%), plus the black bar (22%..78% wide,
    22%..44% from the top) -- both as CCW (x, y) polygons, y up, centred.
    """
    S = float(size)
    r = 0.2 * S
    n = seg(segments, 2)
    # CSS coordinates (y down) -> convert to y-up later
    pts = []

    def arc(cx, cy, a0, a1):
        for t in np.linspace(math.radians(a0), math.radians(a1), n + 1):
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))

    # walk clockwise in CSS space == counter-clockwise once y is flipped
    arc(r, r, 180, 270)                 # top-left
    arc(S - r, r, 270, 360)             # top-right
    pts.append((S, 0.56 * S))
    pts.append((0.56 * S, S))
    arc(r, S - r, 90, 180)              # bottom-left
    css = _dedupe_2d(np.array(pts))
    outline = np.column_stack([css[:, 0] - S / 2, S / 2 - css[:, 1]])
    outline = ensure_ccw_2d(outline) + np.asarray(center, float)
    br = 0.0333 * S
    bar = rounded_rect_2d(0.56 * S, 0.22 * S, br, 2, center=(0.0, S / 2 - 0.33 * S))
    return outline, bar + np.asarray(center, float)


def _dedupe_2d(p: np.ndarray, tol: float = 1e-9) -> np.ndarray:
    keep = [0]
    for i in range(1, len(p)):
        if np.linalg.norm(p[i] - p[keep[-1]]) > tol:
            keep.append(i)
    if len(keep) > 1 and np.linalg.norm(p[keep[-1]] - p[keep[0]]) <= tol:
        keep.pop()
    return p[keep]


# --------------------------------------------------------------------------- triangulation
def _point_in_poly(pt, poly) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xi > x:
                inside = not inside
    return inside


def triangulate_polygon(outer, holes=()):
    """Ear-clipping triangulation of a simple polygon with optional holes.

    Returns (points (K,2), triangles (T,3)) where triangles are CCW.
    """
    outer = ensure_ccw_2d(_dedupe_2d(np.asarray(outer, dtype=float)))
    hl = [ensure_ccw_2d(_dedupe_2d(np.asarray(h, dtype=float)))[::-1] for h in holes if len(h) >= 3]
    pts = [outer] + hl
    P = np.vstack(pts)
    offs = np.cumsum([0] + [len(p) for p in pts])
    poly = list(range(len(outer)))
    order = sorted(range(len(hl)), key=lambda i: -hl[i][:, 0].max())
    for hi in order:
        hidx = list(range(offs[hi + 1], offs[hi + 2]))
        hp = P[hidx]
        m = int(np.argmax(hp[:, 0] + hp[:, 1] * 1e-9))
        M = P[hidx[m]]
        best_k, best_x = None, math.inf
        n = len(poly)
        for i in range(n):
            a, b = P[poly[i]], P[poly[(i + 1) % n]]
            if (a[1] - M[1]) * (b[1] - M[1]) > 0:
                continue
            if abs(a[1] - b[1]) < 1e-15:
                if a[1] == M[1] and max(a[0], b[0]) >= M[0]:
                    x = min(xx for xx in (a[0], b[0]) if xx >= M[0])
                    k = i if a[0] == x else (i + 1) % n
                    if x < best_x:
                        best_x, best_k = x, k
                continue
            t = (M[1] - a[1]) / (b[1] - a[1])
            x = a[0] + t * (b[0] - a[0])
            if x >= M[0] - 1e-12 and x < best_x:
                best_x = x
                best_k = i if a[0] > b[0] else (i + 1) % n
        if best_k is None:
            continue
        # check reflex vertices inside triangle (M, I, Pk); pick the one with smallest angle
        I = np.array([best_x, M[1]])
        Pk = P[poly[best_k]]
        cand = best_k
        n = len(poly)
        tri = (M, I, Pk)
        best_ang = math.inf
        for i in range(n):
            q = P[poly[i]]
            if poly[i] == poly[best_k]:
                continue
            a, b, c = P[poly[i - 1]], q, P[poly[(i + 1) % n]]
            if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) >= 0:
                continue  # convex
            if _pt_in_tri(q, *tri):
                ang = abs(math.atan2(q[1] - M[1], q[0] - M[0]))
                if ang < best_ang:
                    best_ang, cand = ang, i
        ring = hidx[m:] + hidx[:m] + [hidx[m]]
        poly = poly[:cand + 1] + ring + poly[cand:]
    tris = _earclip(P, poly)
    return P, np.array(tris, dtype=np.int64).reshape(-1, 3)


def _pt_in_tri(p, a, b, c) -> bool:
    d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
    d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
    d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)


def _earclip(P: np.ndarray, poly: list) -> list:
    idx = list(poly)
    tris = []
    guard = 0
    i = 0
    while len(idx) > 3 and guard < 100000:
        guard += 1
        n = len(idx)
        arr = P[idx]
        clipped = False
        for step in range(n):
            k = (i + step) % n
            ia, ib, ic = idx[(k - 1) % n], idx[k], idx[(k + 1) % n]
            a, b, c = P[ia], P[ib], P[ic]
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if abs(cr) < 1e-18:
                # collinear / duplicate: drop the middle vertex without a triangle
                if np.linalg.norm(a - b) < 1e-12 or np.linalg.norm(b - c) < 1e-12 or \
                        np.dot(b - a, c - b) > 0:
                    del idx[k]
                    i = k % len(idx)
                    clipped = True
                    break
                continue
            if cr < 0:
                continue
            # any other vertex inside the candidate ear?
            mask = np.ones(n, dtype=bool)
            for kk in ((k - 1) % n, k, (k + 1) % n):
                mask[kk] = False
            q = arr[mask]
            if len(q):
                same = (np.all(np.isclose(q, a, atol=1e-12), axis=1) | np.all(np.isclose(q, b, atol=1e-12), axis=1)
                        | np.all(np.isclose(q, c, atol=1e-12), axis=1))
                q = q[~same]
            if len(q):
                d1 = (q[:, 0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (q[:, 1] - b[1])
                d2 = (q[:, 0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (q[:, 1] - c[1])
                d3 = (q[:, 0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (q[:, 1] - a[1])
                inside = ~(((d1 < 0) | (d2 < 0) | (d3 < 0)) & ((d1 > 0) | (d2 > 0) | (d3 > 0)))
                if inside.any():
                    continue
            tris.append((ia, ib, ic))
            del idx[k]
            i = k % len(idx)
            clipped = True
            break
        if not clipped:
            # numerically awkward polygon: clip the most convex vertex anyway
            best, bk = -math.inf, 0
            for k in range(n):
                a, b, c = P[idx[(k - 1) % n]], P[idx[k]], P[idx[(k + 1) % n]]
                cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
                if cr > best:
                    best, bk = cr, k
            if best > 0:
                tris.append((idx[(bk - 1) % n], idx[bk], idx[(bk + 1) % n]))
            del idx[bk]
            i = bk % max(len(idx), 1)
    if len(idx) == 3:
        a, b, c = P[idx[0]], P[idx[1]], P[idx[2]]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) > 1e-18:
            tris.append(tuple(idx))
    return tris


# --------------------------------------------------------------------------- extrude
def _offset_contour(c: np.ndarray, d: float, max_miter: float = 3.0) -> np.ndarray:
    """Offset a closed contour by ``d`` to the LEFT of its direction (miter joins)."""
    if abs(d) < 1e-15:
        return c.copy()
    prev = np.roll(c, 1, axis=0)
    nxt = np.roll(c, -1, axis=0)
    e0 = _normalize(c - prev)
    e1 = _normalize(nxt - c)
    n0 = np.column_stack([-e0[:, 1], e0[:, 0]])
    n1 = np.column_stack([-e1[:, 1], e1[:, 0]])
    bis = n0 + n1
    bl = np.linalg.norm(bis, axis=1)
    bis = np.where(bl[:, None] > 1e-9, bis / np.maximum(bl, EPS)[:, None], n1)
    cosh = np.einsum("ij,ij->i", bis, n1)
    scale = 1.0 / np.maximum(cosh, 1.0 / max_miter)
    return c + bis * (d * scale)[:, None]


def extrude(outline, depth: float, holes=(), bevel: float = 0.0, bevel_segments: int = 1, z0: float = 0.0,
            crease: float = 35.0, cap_top: bool = True, cap_bottom: bool = True, bevel_bottom: bool = True,
            tile: float | None = None, material: str | None = None) -> Mesh:
    """Extrude a 2D polygon (x, y) along +Z from ``z0`` to ``z0 + depth``.

    outline : (N,2) outer contour (any orientation).
    holes   : list of (M,2) hole contours (e.g. driver cut-outs).
    bevel   : rounded (bevel_segments >= 2) or chamfered (1) edge size at the
              top (and bottom when ``bevel_bottom``).
    Contour corners sharper than ``crease`` degrees get hard normals.
    UVs: caps planar (top seen from +Z), walls = (contour length, -z) / tile.
    Typical use: plates, buttons, logo badges, raised lettering (see lib.fonts).
    """
    if tile is None:
        tile = Mesh(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3)), material=material)._tile(None)
    outer = ensure_ccw_2d(_dedupe_2d(np.asarray(outline, dtype=float)))
    hl = [ensure_ccw_2d(_dedupe_2d(np.asarray(h, dtype=float)))[::-1] for h in holes]
    contours = [outer] + hl  # solid always on the left of every contour
    H = float(depth)
    b = min(max(float(bevel), 0.0), H / (2.0 if bevel_bottom else 1.0) * 0.999)
    nb = 1 if b <= 0 else seg(bevel_segments, 1)
    # ring list: (inset, z, normal_horizontal_weight, normal_up_weight)
    rings = []
    if b > 0 and bevel_bottom:
        for t in np.linspace(0.0, 90.0, nb + 1):
            tr = math.radians(t)
            rings.append((b * (1 - math.sin(tr)), z0 + b * (1 - math.cos(tr)), math.sin(tr), -math.cos(tr)))
    else:
        rings.append((0.0, z0, 1.0, 0.0))
    if b > 0:
        for t in np.linspace(90.0, 0.0, nb + 1):
            tr = math.radians(t)
            rings.append((b * (1 - math.sin(tr)), z0 + H - b * (1 - math.cos(tr)), math.sin(tr), math.cos(tr)))
    else:
        rings.append((0.0, z0 + H, 1.0, 0.0))
    cos_c = math.cos(math.radians(crease))
    all_pos, all_nrm, all_uv, all_idx = [], [], [], []
    base = 0
    for c in contours:
        n = len(c)
        e = np.roll(c, -1, axis=0) - c                 # edge i: c[i] -> c[i+1]
        el = np.linalg.norm(e, axis=1)
        en = _normalize(np.column_stack([e[:, 1], -e[:, 0]]))   # outward (right) normals
        prev_n = np.roll(en, 1, axis=0)                # edge entering vertex i
        smooth = np.einsum("ij,ij->i", prev_n, en) >= cos_c
        # vertex slots: one per smooth vertex, two per sharp vertex
        slot_in, slot_out, slot_vtx, slot_n = [], [], [], []
        for i in range(n):
            if smooth[i]:
                s = len(slot_vtx)
                slot_vtx.append(i)
                slot_n.append(_normalize(prev_n[i] + en[i]))
                slot_in.append(s)
                slot_out.append(s)
            else:
                s = len(slot_vtx)
                slot_vtx += [i, i]
                slot_n += [prev_n[i], en[i]]
                slot_in.append(s)
                slot_out.append(s + 1)
        slot_vtx = np.array(slot_vtx)
        slot_n = np.array(slot_n)
        ns = len(slot_vtx)
        cum = np.concatenate([[0.0], np.cumsum(el)])
        slot_u = cum[slot_vtx]
        # the "out" slot of vertex 0 starts the wall at u=0; the closing edge needs u=total
        for ri_, (inset, z, wh, wu) in enumerate(rings):
            cc = _offset_contour(c, inset)
            p2 = cc[slot_vtx]
            pos = np.column_stack([p2, np.full(ns, z)])
            nrm = _normalize(np.column_stack([slot_n * wh, np.full(ns, wu)]))
            all_pos.append(pos)
            all_nrm.append(nrm)
            all_uv.append(np.column_stack([slot_u / tile, np.full(ns, -z / tile)]))
        # extra copy of vertex-0 slots for the UV seam of the closing edge
        seam_base = base + ns * len(rings)
        for ri_, (inset, z, wh, wu) in enumerate(rings):
            cc = _offset_contour(c, inset)
            s_in = slot_in[0]
            pos = np.array([[cc[0, 0], cc[0, 1], z]])
            nrm = _normalize(np.column_stack([slot_n[s_in:s_in + 1] * wh, [[wu]]]))
            all_pos.append(pos)
            all_nrm.append(nrm)
            all_uv.append(np.array([[cum[-1] / tile, -z / tile]]))
        for ri_ in range(len(rings) - 1):
            r0 = base + ri_ * ns
            r1 = base + (ri_ + 1) * ns
            for i in range(n):
                j = (i + 1) % n
                a0 = r0 + slot_out[i]
                a1 = r1 + slot_out[i]
                if j == 0:
                    b0 = seam_base + ri_
                    b1 = seam_base + ri_ + 1
                else:
                    b0 = r0 + slot_in[j]
                    b1 = r1 + slot_in[j]
                all_idx += [(a0, b0, b1), (a0, b1, a1)]
        base = seam_base + len(rings)
    # caps
    top_inset, top_z = rings[-1][0], rings[-1][1]
    bot_inset, bot_z = rings[0][0], rings[0][1]
    cap_specs = []
    if cap_top:
        cap_specs.append((top_inset, top_z, 1.0))
    if cap_bottom:
        cap_specs.append((bot_inset, bot_z, -1.0))
    for inset, z, sgn in cap_specs:
        oc = _offset_contour(contours[0], inset)
        hc = [_offset_contour(h, inset) for h in contours[1:]]
        P2, T = triangulate_polygon(oc, [h[::-1] for h in hc])
        pos = np.column_stack([P2, np.full(len(P2), z)])
        nrm = np.tile([0.0, 0.0, sgn], (len(P2), 1))
        U, V = Mesh._face_frame(np.array([0.0, 0.0, sgn]))
        uv = np.column_stack([pos @ U, pos @ V]) / tile
        all_pos.append(pos)
        all_nrm.append(nrm)
        all_uv.append(uv)
        all_idx += [tuple(t + base) for t in T]
        base += len(P2)
    m = Mesh(np.vstack(all_pos), np.array(all_idx, dtype=np.int64).reshape(-1, 3), np.vstack(all_nrm),
             np.vstack(all_uv), material=material, name="extrude", uv_tile=float(tile))
    m.fix_winding()
    return m.remove_degenerate(1e-18)


# --------------------------------------------------------------------------- sweep
def circle_section(radius: float, n: int = 12) -> np.ndarray:
    """CCW circular cross-section for ``sweep`` (n scaled by detail)."""
    n = seg(n, 4, multiple=2)
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.column_stack([radius * np.cos(t), radius * np.sin(t)])


def ellipse_section(rx: float, ry: float, n: int = 12) -> np.ndarray:
    n = seg(n, 4, multiple=2)
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.column_stack([rx * np.cos(t), ry * np.sin(t)])


def rounded_rect_section(width: float, height: float, radius: float, n_corner: int = 3) -> np.ndarray:
    """CCW rounded-rectangle cross-section (width along the frame normal)."""
    return rounded_rect_2d(width, height, radius, n_corner)


def bezier_path(p0, p1, p2, p3, n: int = 16) -> np.ndarray:
    """Cubic Bezier polyline (n segments, scaled by detail), roughly arc-length spaced."""
    n = seg(n, 2)
    P = np.array([_vec3(p0), _vec3(p1), _vec3(p2), _vec3(p3)])
    t = np.linspace(0, 1, 8 * n + 1)[:, None]
    dense = ((1 - t) ** 3) * P[0] + 3 * ((1 - t) ** 2) * t * P[1] + 3 * (1 - t) * t * t * P[2] + t ** 3 * P[3]
    L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
    target = np.linspace(0, L[-1], n + 1)
    return np.column_stack([np.interp(target, L, dense[:, k]) for k in range(3)])


def catmull_rom_path(points, n_per_segment: int = 6) -> np.ndarray:
    """Smooth path through ``points`` (centripetal-ish uniform Catmull-Rom)."""
    P = np.array([_vec3(p) for p in points])
    n = seg(n_per_segment, 1)
    ext = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return np.array(out)


def polyline_path(points, radius: float = 0.0, segments: int = 6) -> np.ndarray:
    """Polyline through ``points`` with corners rounded by fillets of ``radius``."""
    P = np.array([_vec3(p) for p in points])
    if radius <= 0 or len(P) < 3:
        return P
    n = seg(segments, 1)
    out = [P[0]]
    for i in range(1, len(P) - 1):
        a, b, c = P[i - 1], P[i], P[i + 1]
        d0, d1 = _normalize(b - a), _normalize(c - b)
        cosang = float(np.clip(np.dot(-d0, d1), -1, 1))
        theta = math.acos(cosang)            # interior angle
        if theta > math.pi - 1e-4 or theta < 1e-4:
            out.append(b)
            continue
        t = radius / math.tan(theta / 2)
        t = min(t, np.linalg.norm(b - a) * 0.5, np.linalg.norm(c - b) * 0.5)
        s, e = b - d0 * t, b + d1 * t
        for k in range(n + 1):
            u = k / n
            q = (1 - u) ** 2 * s + 2 * (1 - u) * u * b + u * u * e   # quadratic approx of the fillet
            out.append(q)
    out.append(P[-1])
    return _dedupe_path(np.array(out))


def arc_path(center, radius: float, start: float, end: float, n: int = 16, plane: str = "xz") -> np.ndarray:
    """Circular arc in ``plane`` ('xy', 'xz', 'yz'), angles in degrees from the first axis."""
    n = seg(n, 2)
    a0, a1 = "xyz".index(plane[0]), "xyz".index(plane[1])
    t = np.radians(np.linspace(start, end, n + 1))
    P = np.tile(_vec3(center), (n + 1, 1))
    P[:, a0] += radius * np.cos(t)
    P[:, a1] += radius * np.sin(t)
    return P


def _dedupe_path(P: np.ndarray) -> np.ndarray:
    keep = [0]
    for i in range(1, len(P)):
        if np.linalg.norm(P[i] - P[keep[-1]]) > 1e-9:
            keep.append(i)
    return P[keep]


def sweep(section, path, closed: bool = False, caps: bool = True, crease: float = 40.0, up=None,
          twist: float = 0.0, scale_end: float = 1.0, tile: float | None = None,
          material: str | None = None) -> Mesh:
    """Sweep a closed 2D ``section`` along a 3D ``path`` (handles, cables, tonearm tubes).

    section : (n,2) CCW cross-section (circle_section / rounded_rect_section ...).
              Section x maps to the frame normal, y to the binormal.
    path    : (m,3) points (bezier_path / polyline_path / arc_path ...).
    closed  : the path is a loop (no caps).
    up      : hint for the initial frame normal (default world Z or X).
    twist   : extra rotation of the section from start to end (degrees).
    scale_end: section scale at the end of the path (linear taper).
    Frames are rotation-minimising (double reflection), so tubes do not twist.
    """
    if tile is None:
        tile = Mesh(np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3)), material=material)._tile(None)
    S = ensure_ccw_2d(_dedupe_2d(np.asarray(section, dtype=float)))
    X = _dedupe_path(np.asarray(path, dtype=float))
    if closed and np.linalg.norm(X[0] - X[-1]) < 1e-9:
        X = X[:-1]
    m = len(X)
    if m < 2:
        raise ValueError("sweep(): path needs 2+ points")
    if closed:
        T = _normalize(np.roll(X, -1, axis=0) - np.roll(X, 1, axis=0))
    else:
        T = np.zeros_like(X)
        T[1:-1] = _normalize(X[2:] - X[:-2])
        T[0] = _normalize(X[1] - X[0])
        T[-1] = _normalize(X[-1] - X[-2])
    hint = _axis(up) if up is not None else np.array([0.0, 0.0, 1.0])
    if abs(np.dot(hint, T[0])) > 0.95:
        hint = np.array([1.0, 0.0, 0.0]) if abs(T[0][0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    Nf = np.zeros_like(X)
    Nf[0] = _normalize(hint - T[0] * np.dot(hint, T[0]))
    for i in range(m - 1):
        v1 = X[i + 1] - X[i]
        c1 = float(np.dot(v1, v1))
        if c1 < 1e-20:
            Nf[i + 1] = Nf[i]
            continue
        rL = Nf[i] - (2 / c1) * np.dot(v1, Nf[i]) * v1
        tL = T[i] - (2 / c1) * np.dot(v1, T[i]) * v1
        v2 = T[i + 1] - tL
        c2 = float(np.dot(v2, v2))
        Nf[i + 1] = rL - (2 / c2) * np.dot(v2, rL) * v2 if c2 > 1e-20 else rL
        Nf[i + 1] = _normalize(Nf[i + 1] - T[i + 1] * np.dot(Nf[i + 1], T[i + 1]))
    Bf = np.cross(T, Nf)
    L = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(X, axis=0), axis=1))])
    if closed:
        L = np.append(L, L[-1] + np.linalg.norm(X[0] - X[-1]))
    frac = L[:m] / max(L[-1], EPS)
    tw = np.radians(twist) * frac
    if closed:
        # distribute the frame mismatch at the seam
        n_end = Nf[-1]
        v1 = X[0] - X[-1]
        c1 = float(np.dot(v1, v1))
        rL = n_end - (2 / c1) * np.dot(v1, n_end) * v1
        tL = T[-1] - (2 / c1) * np.dot(v1, T[-1]) * v1
        v2 = T[0] - tL
        c2 = float(np.dot(v2, v2))
        n_wrap = rL - (2 / c2) * np.dot(v2, rL) * v2 if c2 > 1e-20 else rL
        ang = math.atan2(np.dot(np.cross(n_wrap, Nf[0]), T[0]), np.dot(n_wrap, Nf[0]))
        tw = tw + ang * frac
    scl = 1.0 + (scale_end - 1.0) * frac
    # section normals with crease split
    ns = len(S)
    e = np.roll(S, -1, axis=0) - S
    el = np.linalg.norm(e, axis=1)
    en = _normalize(np.column_stack([e[:, 1], -e[:, 0]]))
    prev_n = np.roll(en, 1, axis=0)
    cos_c = math.cos(math.radians(crease))
    smooth = np.einsum("ij,ij->i", prev_n, en) >= cos_c
    slot_vtx, slot_n, slot_in, slot_out = [], [], [], []
    for i in range(ns):
        s = len(slot_vtx)
        if smooth[i]:
            slot_vtx.append(i)
            slot_n.append(_normalize(prev_n[i] + en[i]))
            slot_in.append(s)
            slot_out.append(s)
        else:
            slot_vtx += [i, i]
            slot_n += [prev_n[i], en[i]]
            slot_in.append(s)
            slot_out.append(s + 1)
    slot_vtx = np.array(slot_vtx)
    slot_n = np.array(slot_n)
    cum = np.concatenate([[0.0], np.cumsum(el)])
    k = len(slot_vtx)
    rows = m + 1 if closed else m
    pos = np.zeros((rows, k + 1, 3))
    nrm = np.zeros((rows, k + 1, 3))
    uv = np.zeros((rows, k + 1, 2))
    for r in range(rows):
        i = r % m                      # the closing row of a loop reuses frame 0
        c, s_ = math.cos(tw[i]), math.sin(tw[i])
        Ni = c * Nf[i] + s_ * Bf[i]
        Bi = -s_ * Nf[i] + c * Bf[i]
        sc = scl[i] if r < m else scl[0]
        sp = S[slot_vtx] * sc
        sn2 = slot_n
        P3 = X[i] + sp[:, 0:1] * Ni + sp[:, 1:2] * Bi
        N3 = _normalize(sn2[:, 0:1] * Ni + sn2[:, 1:2] * Bi)
        s0 = slot_in[0]
        pos[r, :k] = P3
        nrm[r, :k] = N3
        pos[r, k] = X[i] + S[0, 0] * sc * Ni + S[0, 1] * sc * Bi
        nrm[r, k] = _normalize(slot_n[s0, 0] * Ni + slot_n[s0, 1] * Bi)
        uv[r, :k, 0] = cum[slot_vtx] / tile
        uv[r, k, 0] = cum[-1] / tile
        uv[r, :, 1] = -L[r] / tile
    idx = []
    for r in range(rows - 1):
        for i in range(ns):
            j = (i + 1) % ns
            a0 = r * (k + 1) + slot_out[i]
            a1 = (r + 1) * (k + 1) + slot_out[i]
            b0 = r * (k + 1) + (k if j == 0 else slot_in[j])
            b1 = (r + 1) * (k + 1) + (k if j == 0 else slot_in[j])
            idx += [(a0, b0, b1), (a0, b1, a1)]
    parts = [Mesh(pos.reshape(-1, 3), idx, nrm.reshape(-1, 3), uv.reshape(-1, 2), material=material,
                  name="sweep", uv_tile=float(tile)).fix_winding()]
    if caps and not closed:
        P2, Tt = triangulate_polygon(S)
        for i_end, sgn in ((0, -1.0), (m - 1, 1.0)):
            c, s_ = math.cos(tw[i_end]), math.sin(tw[i_end])
            Ni = c * Nf[i_end] + s_ * Bf[i_end]
            Bi = -s_ * Nf[i_end] + c * Bf[i_end]
            sp = P2 * scl[i_end]
            P3 = X[i_end] + sp[:, 0:1] * Ni + sp[:, 1:2] * Bi
            nn = np.tile(T[i_end] * sgn, (len(P3), 1))
            cap = Mesh(P3, Tt, nn, sp / tile, material=material, name="sweep_cap", uv_tile=float(tile))
            parts.append(cap.fix_winding())
    return merge(parts)
