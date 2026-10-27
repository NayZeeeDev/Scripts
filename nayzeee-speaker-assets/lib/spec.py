"""Model description returned by every ``models/<name>.py: build(detail)``.

    from lib.spec import ModelSpec, Anchor, LodSettings, Box, Cylinder, Sphere, Capsule

    def build(detail):
        parts = [...]                                   # lib.mesh.Mesh parts, each with a material
        return ModelSpec(
            name="nayzeee_console",
            parts=parts,
            collision=[Box((0, 0, 0.3), (0.3, 0.25, 0.6), "PLASTIC")],
            anchors={"grip": Anchor((0, 0, 0.62), (0, 0, 0), "carry handle centre")},
            lod=LodSettings(high_dist=18, archetype_lod_dist=120),
        )

Anchors are named points for gameplay code (attach offsets, turntable
positions ...), written to out/layout.json in model space: metres, +Z up,
+Y front; ``rot`` is (x, y, z) degrees as AttachEntityToEntity expects.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np

# CBaseArchetypeDef flags (CodeWalker names)
FLAG_STATIC = 32
FLAG_DYNAMIC = 131072
FLAG_USE_AMBIENT_SCALE = 536870912
ARCHETYPE_DYNAMIC = FLAG_DYNAMIC | FLAG_USE_AMBIENT_SCALE        # 537001984 (old ytyp also had 1024 = UV anims for its .ycd)
ARCHETYPE_STATIC = ARCHETYPE_DYNAMIC | FLAG_STATIC

Vec3 = Tuple[float, float, float]


def _v(x) -> np.ndarray:
    return np.asarray(x, dtype=float).reshape(3)


def _r3(v) -> List[float]:
    return [round(float(x), 6) + 0.0 for x in v]


@dataclass
class Anchor:
    """A named point in model space for gameplay code."""
    pos: Vec3
    rot: Vec3 = (0.0, 0.0, 0.0)
    note: str = ""

    def to_json(self) -> dict:
        d = {"pos": _r3(self.pos), "rot": _r3(self.rot)}
        if self.note:
            d["note"] = self.note
        return d


@dataclass
class LodSettings:
    """Distances in metres.

    high_dist          Drawable LodDistHigh: the High model is drawn up to here,
                       then the Medium model (built at ``med_detail``).
    med_dist           Drawable LodDistMed (Medium drawn up to here).
    archetype_lod_dist CBaseArchetypeDef lodDist: the prop fades out beyond this.
    hd_texture_dist    CBaseArchetypeDef hdTextureDist.
    med_detail         detail factor passed to build() for the Medium model.
    """
    high_dist: float = 15.0
    med_dist: float = 9998.0
    archetype_lod_dist: float = 100.0
    hd_texture_dist: float = 5.0
    med_detail: float = 0.35


# --------------------------------------------------------------------------- collision shapes
def _euler(rx, ry, rz) -> np.ndarray:
    def R(axis, d):
        t = math.radians(d)
        c, s = math.cos(t), math.sin(t)
        if axis == 0:
            return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        if axis == 1:
            return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    return R(2, rz) @ R(1, ry) @ R(0, rx)


@dataclass
class Box:
    """Collision box: centre, full size, optional rotation (degrees XYZ)."""
    center: Vec3
    size: Vec3
    material: Optional[str] = None
    rotation: Vec3 = (0.0, 0.0, 0.0)

    @staticmethod
    def from_minmax(lo, hi, material: Optional[str] = None) -> "Box":
        lo, hi = _v(lo), _v(hi)
        return Box(tuple((lo + hi) / 2), tuple(hi - lo), material)

    @property
    def R(self) -> np.ndarray:
        return _euler(*self.rotation)

    def corners(self) -> np.ndarray:
        h = _v(self.size) / 2
        sgn = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float)
        return (sgn * h) @ self.R.T + _v(self.center)

    def poly_vertices(self) -> np.ndarray:
        """The 4 corners GTA's phPrimBox uses: (-,-,-), (+,-,+), (-,+,+), (+,+,-)."""
        h = _v(self.size) / 2
        sgn = np.array([[-1, -1, -1], [1, -1, 1], [-1, 1, 1], [1, 1, -1]], float)
        return (sgn * h) @ self.R.T + _v(self.center)

    def aabb(self):
        c = self.corners()
        return c.min(axis=0), c.max(axis=0)

    @property
    def volume(self) -> float:
        x, y, z = self.size
        return float(x * y * z)

    @property
    def centroid(self) -> np.ndarray:
        return _v(self.center)

    def inertia(self) -> np.ndarray:
        x, y, z = (float(v) for v in self.size)
        I = np.diag([(y * y + z * z) / 12, (x * x + z * z) / 12, (x * x + y * y) / 12])
        return self.R @ I @ self.R.T

    def bounding_points(self):
        return [(p, 0.0) for p in self.corners()]


@dataclass
class Cylinder:
    """Collision cylinder between end points ``p1`` and ``p2`` (any orientation)."""
    p1: Vec3
    p2: Vec3
    radius: float
    material: Optional[str] = None

    @staticmethod
    def vertical(center_xy, z0: float, z1: float, radius: float, material: Optional[str] = None) -> "Cylinder":
        return Cylinder((center_xy[0], center_xy[1], z0), (center_xy[0], center_xy[1], z1), radius, material)

    @property
    def axis(self) -> np.ndarray:
        d = _v(self.p2) - _v(self.p1)
        return d / max(np.linalg.norm(d), 1e-12)

    @property
    def length(self) -> float:
        return float(np.linalg.norm(_v(self.p2) - _v(self.p1)))

    def aabb(self):
        a = self.axis
        ext = self.radius * np.sqrt(np.clip(1 - a * a, 0, 1))
        p = np.vstack([_v(self.p1), _v(self.p2)])
        return p.min(axis=0) - ext, p.max(axis=0) + ext

    @property
    def volume(self) -> float:
        return math.pi * self.radius ** 2 * self.length

    @property
    def centroid(self) -> np.ndarray:
        return (_v(self.p1) + _v(self.p2)) / 2

    def inertia(self) -> np.ndarray:
        a = self.axis[:, None]
        r, L = self.radius, self.length
        return (L * L / 12 + r * r / 4) * (np.eye(3) - a @ a.T) + (r * r / 2) * (a @ a.T)

    def bounding_points(self):
        return [(_v(self.p1), self.radius), (_v(self.p2), self.radius)]


@dataclass
class Sphere:
    center: Vec3
    radius: float
    material: Optional[str] = None

    def aabb(self):
        c = _v(self.center)
        return c - self.radius, c + self.radius

    @property
    def volume(self) -> float:
        return 4.0 / 3.0 * math.pi * self.radius ** 3

    @property
    def centroid(self) -> np.ndarray:
        return _v(self.center)

    def inertia(self) -> np.ndarray:
        return np.eye(3) * 0.4 * self.radius ** 2

    def bounding_points(self):
        return [(_v(self.center), self.radius)]


@dataclass
class Capsule:
    """Capsule whose hemisphere centres are ``p1`` and ``p2``."""
    p1: Vec3
    p2: Vec3
    radius: float
    material: Optional[str] = None

    def aabb(self):
        p = np.vstack([_v(self.p1), _v(self.p2)])
        return p.min(axis=0) - self.radius, p.max(axis=0) + self.radius

    @property
    def length(self) -> float:
        return float(np.linalg.norm(_v(self.p2) - _v(self.p1)))

    @property
    def volume(self) -> float:
        r = self.radius
        return math.pi * r * r * self.length + 4.0 / 3.0 * math.pi * r ** 3

    @property
    def centroid(self) -> np.ndarray:
        return (_v(self.p1) + _v(self.p2)) / 2

    def inertia(self) -> np.ndarray:
        return Cylinder(self.p1, self.p2, self.radius).inertia() if self.length > 1e-9 else \
            np.eye(3) * 0.4 * self.radius ** 2

    def bounding_points(self):
        return [(_v(self.p1), self.radius), (_v(self.p2), self.radius)]


SHAPES = (Box, Cylinder, Sphere, Capsule)


# --------------------------------------------------------------------------- ModelSpec
@dataclass
class ModelSpec:
    """Everything the exporters need to know about one model.

    name        archetype / file name (lowercase).  Must match the module name.
    parts       list of lib.mesh.Mesh, each tagged with a registered material.
    collision   list of Box / Cylinder / Sphere / Capsule (model space). Empty =
                no embedded bounds (only sensible for export=False models).
    anchors     {name: Anchor} for gameplay code (layout.json).
    lod         LodSettings.
    export      False = image-only model (GLB + layout, no ydr / ytyp entry).
    flags       CBaseArchetypeDef flags (ARCHETYPE_DYNAMIC or ARCHETYPE_STATIC).
    description human readable, copied to layout.json.
    meta        extra JSON-serialisable data for layout.json (e.g. dimensions).
    """
    name: str
    parts: list
    collision: list = field(default_factory=list)
    anchors: Dict[str, Anchor] = field(default_factory=dict)
    lod: LodSettings = field(default_factory=LodSettings)
    export: bool = True
    flags: int = ARCHETYPE_DYNAMIC
    description: str = ""
    meta: dict = field(default_factory=dict)

    def problems(self) -> List[str]:
        """Static checks (materials registered, names, shapes) -> list of messages."""
        from . import materials
        out = []
        if self.name != self.name.lower() or " " in self.name:
            out.append(f"{self.name}: name must be lowercase without spaces")
        if not self.parts:
            out.append(f"{self.name}: no parts")
        for p in self.parts:
            if not p.material:
                out.append(f"{self.name}: part {p.name!r} has no material")
                continue
            try:
                materials.get(p.material)
            except KeyError:
                out.append(f"{self.name}: part {p.name!r} uses unknown material {p.material!r}")
            for e in p.check():
                out.append(f"{self.name}: part {p.name!r}: {e}")
        for c in self.collision:
            if not isinstance(c, SHAPES):
                out.append(f"{self.name}: unsupported collision shape {type(c).__name__}")
            mat = getattr(c, "material", None)
            if mat is not None and mat not in materials.COLLISION_MATERIALS:
                out.append(f"{self.name}: unknown collision material {mat!r}")
        if self.export and not self.collision:
            out.append(f"{self.name}: exported model without collision shapes")
        for k, a in self.anchors.items():
            if not isinstance(a, Anchor):
                out.append(f"{self.name}: anchor {k!r} is not an Anchor")
        return out


def collision_mass_properties(shapes):
    """(volume, centre of gravity, per-unit-mass inertia diag about the cg) of a shape list."""
    vols = np.array([max(s.volume, 1e-9) for s in shapes])
    cgs = np.array([s.centroid for s in shapes])
    V = float(vols.sum())
    cg = (vols[:, None] * cgs).sum(axis=0) / V
    I = np.zeros((3, 3))
    for v, c, s in zip(vols, cgs, shapes):
        d = c - cg
        I += v * (s.inertia() + (np.dot(d, d) * np.eye(3) - np.outer(d, d)))
    return V, cg, np.diag(I) / V
