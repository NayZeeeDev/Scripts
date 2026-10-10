"""
Builds every nayzeee-weedlab prop with Blender (the `bpy` module) + Sollumz, headless.

    BLENDER_USER_SCRIPTS=<dir with addons/sollumz> python build_props.py <build dir>

<build dir> must already hold the textures from texgen.py (png/ + ytd/ + textures.json).
Writes CodeWalker XML for every drawable to <build dir>/xml/, the shared texture
dictionary nzw_weedlab.ytd.xml, bounds.json (for make_ytyp.py) and weedlab_props.blend.

Units are metres, Z up, every prop's working side faces -Y (towards the player).
Moving parts are separate drawables whose origin sits on their pivot:
    nzw_packstation_hatch   hinge at the back edge, rotate on X (negative = open)
    nzw_brickpress_plate    top of the ram, slides on -Z
    nzw_brickpress_lever    pivot of the pump handle, rotate on X
    nzw_mixstation_bowl     centre of the bowl's base, spins on Z
"""
import json
import math
import os
import random
import sys

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector, noise

BUILD = os.path.abspath(sys.argv[-1])
XML = os.path.join(BUILD, "xml")
os.makedirs(XML, exist_ok=True)
TEX = json.load(open(os.path.join(BUILD, "textures.json")))

bpy.ops.preferences.addon_enable(module="sollumz")
from sollumz.sollumz_properties import SollumType  # noqa: E402
from sollumz.tools.blenderhelper import create_blender_object, create_empty_object  # noqa: E402
from sollumz.tools.boundhelper import apply_flag_preset  # noqa: E402
from sollumz.tools.drawablehelper import convert_obj_to_model  # noqa: E402
from sollumz.tools.meshhelper import create_box, mesh_add_missing_color_attrs, mesh_add_missing_uv_maps  # noqa: E402
from sollumz.ybn.collision_materials import create_collision_material_from_index  # noqa: E402
from sollumz.ydr.shader_materials import create_shader  # noqa: E402

TAU = math.tau
random.seed(4242)

# ─────────────────────────── materials ───────────────────────────
# name -> (shader, texture base, params). Texture base 'x' uses x_d / x_n / x_s.
MAT = {
    "steel":       ("normal_spec.sps", "nzw_steel", dict(spec=0.9, falloff=60, bump=0.6)),
    "black":       ("normal_spec.sps", "nzw_black", dict(spec=0.35, falloff=30, bump=0.5)),
    "red":         ("normal_spec.sps", "nzw_red", dict(spec=0.45, falloff=30, bump=0.5)),
    "white":       ("normal_spec.sps", "nzw_white", dict(spec=0.35, falloff=30, bump=0.4)),
    "teal":        ("normal_spec.sps", "nzw_teal", dict(spec=0.4, falloff=30, bump=0.4)),
    "galv":        ("normal_spec.sps", "nzw_galv", dict(spec=0.6, falloff=40, bump=0.4)),
    "alu":         ("normal_spec.sps", "nzw_alu", dict(spec=0.6, falloff=50, bump=0.4)),
    "reflector":   ("normal_spec.sps", "nzw_reflector", dict(spec=1.0, falloff=90, bump=1.0)),
    "chrome":      ("normal_spec.sps", "nzw_chrome", dict(spec=1.0, falloff=120, bump=0.2)),
    "fabric":      ("normal_spec.sps", "nzw_fabric", dict(spec=0.08, falloff=8, bump=1.0)),
    "fabric_teal": ("normal_spec.sps", "nzw_fabric_teal", dict(spec=0.1, falloff=8, bump=1.0)),
    "mylar":       ("normal_spec.sps", "nzw_mylar", dict(spec=1.0, falloff=70, bump=1.0)),
    "pblack":      ("normal_spec.sps", "nzw_pblack", dict(spec=0.4, falloff=40, bump=0.3)),
    "pwhite":      ("normal_spec.sps", "nzw_pwhite", dict(spec=0.45, falloff=40, bump=0.3)),
    "pgreen":      ("normal_spec.sps", "nzw_pgreen", dict(spec=0.5, falloff=40, bump=0.3)),
    "porange":     ("normal_spec.sps", "nzw_porange", dict(spec=0.5, falloff=40, bump=0.3)),
    "pblue":       ("normal_spec.sps", "nzw_pblue", dict(spec=0.5, falloff=40, bump=0.3)),
    "rubber":      ("normal_spec.sps", "nzw_rubber", dict(spec=0.05, falloff=5, bump=0.6)),
    "wood":        ("normal_spec.sps", "nzw_wood", dict(spec=0.15, falloff=12, bump=0.8)),
    "twine":       ("normal_spec.sps", "nzw_twine", dict(spec=0.05, falloff=5, bump=1.0)),
    "soil":        ("normal_spec.sps", "nzw_soil", dict(spec=0.2, falloff=10, bump=1.4)),
    "bud_green":   ("normal_spec.sps", "nzw_bud_green", dict(spec=0.5, falloff=20, bump=1.2)),
    "bud_purple":  ("normal_spec.sps", "nzw_bud_purple", dict(spec=0.5, falloff=20, bump=1.2)),
    "bud_lime":    ("normal_spec.sps", "nzw_bud_lime", dict(spec=0.5, falloff=20, bump=1.2)),
    "bud_golden":  ("normal_spec.sps", "nzw_bud_golden", dict(spec=0.5, falloff=20, bump=1.2)),
    "leaf":        ("normal_spec.sps", "nzw_leaf", dict(spec=0.25, falloff=15, bump=0.8)),
    "compressed":  ("normal_spec.sps", "nzw_compressed", dict(spec=0.3, falloff=15, bump=1.0)),
    "seed":        ("normal_spec.sps", "nzw_seed", dict(spec=0.4, falloff=30, bump=0.6)),
    "tape":        ("normal_spec.sps", "nzw_tape", dict(spec=0.8, falloff=60, bump=0.3)),
    "cutmat":      ("normal_spec.sps", "nzw_cutmat", dict(spec=0.15, falloff=10, bump=0.4)),
    "btn_green":   ("normal_spec.sps", "nzw_btn_green", dict(spec=0.6, falloff=40, bump=0.0)),
    "btn_red":     ("normal_spec.sps", "nzw_btn_red", dict(spec=0.6, falloff=40, bump=0.0)),
    "brass":       ("normal_spec.sps", "nzw_brass", dict(spec=0.8, falloff=60, bump=0.0)),
    "dark":        ("normal_spec.sps", "nzw_dark", dict(spec=0.1, falloff=5, bump=0.0)),
    # alpha
    "glass":       ("glass_spec.sps", "nzw_glass", dict(spec=1.0, falloff=120)),
    "bag":         ("spec_alpha.sps", "nzw_bag", dict(spec=0.8, falloff=60)),
    "cling":       ("spec_alpha.sps", "nzw_cling", dict(spec=0.9, falloff=80)),
    # emissive
    "led_purple":  ("emissivestrong.sps", "nzw_led_purple", dict(emissive=6.0)),
    "led_white":   ("emissivestrong.sps", "nzw_led_white", dict(emissive=5.0)),
    "halogen":     ("emissivestrong.sps", "nzw_halogen_glow", dict(emissive=8.0)),
    # labels (diffuse only: default.sps)
    "lbl_soil":    ("default.sps", "nzw_lbl_soil", {}),
    "lbl_pgr":     ("default.sps", "nzw_lbl_pgr", {}),
    "lbl_speed":   ("default.sps", "nzw_lbl_speed", {}),
    "lbl_fert":    ("default.sps", "nzw_lbl_fert", {}),
    "lbl_led":     ("default.sps", "nzw_lbl_led", {}),
    "lbl_fullspec": ("default.sps", "nzw_lbl_fullspec", {}),
    "lbl_halogen": ("default.sps", "nzw_lbl_halogen", {}),
    "lbl_brick":   ("default.sps", "nzw_lbl_brick", {}),
    "lbl_tent":    ("default.sps", "nzw_lbl_tent", {}),
    "lbl_jar":     ("default.sps", "nzw_lbl_jar", {}),
    "lbl_seeds":   ("default.sps", "nzw_lbl_seeds", {}),
    "panel_mixer": ("default.sps", "nzw_panel_mixer", {}),
    "panel_press": ("default.sps", "nzw_panel_press", {}),
}

_images = {}
_mats = {}


def image(texname):
    if texname not in _images:
        img = bpy.data.images.load(os.path.join(BUILD, "png", texname + ".png"), check_existing=True)
        # Sollumz names a texture after its file name
        img.filepath = "//" + texname + ".dds"
        _images[texname] = img
    return _images[texname]


def set_param(mat, name, value):
    node = mat.node_tree.nodes.get(name)
    if node is not None:
        node.set(0, float(value))


def material(key):
    if key in _mats:
        return _mats[key]
    shader, base, p = MAT[key]
    mat = create_shader(shader)
    mat.name = "nzw_" + key
    nodes = mat.node_tree.nodes
    for sampler, suffix in (("DiffuseSampler", "_d"), ("BumpSampler", "_n"), ("SpecSampler", "_s")):
        node = nodes.get(sampler)
        if node is None:
            continue
        name = base + suffix
        if name not in TEX:
            raise SystemExit(f"missing texture {name}")
        node.image = image(name)
        node.texture_properties.embedded = False
    if "spec" in p:
        set_param(mat, "specularIntensityMult", p["spec"])
        set_param(mat, "specularFalloffMult", p["falloff"])
    if "bump" in p:
        set_param(mat, "bumpiness", p["bump"])
    if "emissive" in p:
        set_param(mat, "emissiveMultiplier", p["emissive"])
    _mats[key] = mat
    return mat


# ─────────────────────────── geometry ───────────────────────────
class Model:
    """Collects primitives (each built in its own bmesh) into one mesh with several materials."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.bm.loops.layers.uv.new("UVMap")
        self.mats = []

    def mi(self, key):
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    # every primitive goes through here
    def _add(self, bm, key, smooth, uv="box", scale=0.5, sharp_angle=35.0):
        uvl = bm.loops.layers.uv.verify()
        idx = self.mi(key)
        bm.normal_update()
        for f in bm.faces:
            f.material_index = idx
            f.smooth = smooth
            if uv == "box":
                n = f.normal
                ax = max(range(3), key=lambda i: abs(n[i]))
                for lp in f.loops:
                    c = lp.vert.co
                    if ax == 0:
                        u, v = c.y * (1 if n.x > 0 else -1), c.z
                    elif ax == 1:
                        u, v = c.x * (-1 if n.y > 0 else 1), c.z
                    else:
                        u, v = c.x, c.y
                    lp[uvl].uv = (u / scale, v / scale)
        if smooth:
            for e in bm.edges:
                if len(e.link_faces) == 2:
                    a = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0)
                    e.smooth = a < math.radians(sharp_angle)
        tmp = bpy.data.meshes.new("tmp")
        bm.to_mesh(tmp)
        bm.free()
        self.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)

    # ── boxes ──
    def box(self, mn, mx, key, bevel=0.0, scale=0.5, segs=2):
        bm = bmesh.new()
        (x0, y0, z0), (x1, y1, z1) = mn, mx
        size = Vector((x1 - x0, y1 - y0, z1 - z0))
        mat = Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)) @ Matrix.Diagonal(size.to_4d())
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=segs, affect="EDGES", profile=0.5)
        self._add(bm, key, bevel > 0, "box", scale)

    def beam(self, p0, p1, w, h, key, up=(0, 0, 1), scale=0.5, bevel=0.003):
        """square tube between two points"""
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        L = d.length
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((w, h, L, 1.0)))
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, w * 0.4, h * 0.4), segments=1, affect="EDGES", profile=0.5)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)
        self._add(bm, key, bool(bevel), "box", scale)

    # ── round things ──
    def lathe(self, prof, key, segs=32, c=(0, 0, 0), a0=0.0, a1=TAU, label=False, scale=0.3, cap_bottom=False, cap_top=False, smooth=True):
        """surface of revolution around Z. prof = [(r, z), ...] bottom to top."""
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.verify()
        full = abs((a1 - a0) - TAU) < 1e-6
        n_ang = segs if full else segs + 1
        rings = []
        for r, z in prof:
            ring = []
            for i in range(n_ang):
                a = a0 + (a1 - a0) * i / segs
                ring.append(bm.verts.new((c[0] + math.cos(a) * r, c[1] + math.sin(a) * r, c[2] + z)))
            rings.append(ring)
        # arc length along the profile for v
        acc = [0.0]
        for k in range(1, len(prof)):
            acc.append(acc[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
        rmax = max(p[0] for p in prof)
        for k in range(len(prof) - 1):
            for i in range(segs):
                j = (i + 1) % n_ang if full else i + 1
                f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
                for lp, (ii, kk) in zip(f.loops, ((i, k), (i + 1, k), (i + 1, k + 1), (i, k + 1))):
                    if label:
                        u = ii / segs
                        v = (prof[kk][1] - prof[0][1]) / max(1e-6, prof[-1][1] - prof[0][1])
                    else:
                        u = (ii / segs) * (a1 - a0) * rmax / scale
                        v = acc[kk] / scale
                    lp[uvl].uv = (u, v)
        for cap, ring, flip in ((cap_bottom, rings[0], True), (cap_top, rings[-1], False)):
            if cap and full:
                f = bm.faces.new(list(reversed(ring)) if flip else ring)
                for lp in f.loops:
                    lp[uvl].uv = ((lp.vert.co.x - c[0]) / scale + 0.5, (lp.vert.co.y - c[1]) / scale + 0.5)
        self._add(bm, key, smooth, uv=None, scale=scale, sharp_angle=40.0)

    def cyl(self, c, r, h, key, segs=24, r2=None, caps=True, axis="z", scale=0.3, smooth=True):
        """closed cylinder / cone along an axis, base at c"""
        r2 = r if r2 is None else r2
        prof = [(r, 0.0), (r2, h)]
        if caps:
            prof = [(0.0001, 0.0), (r, 0.0)] + [(r2, h), (0.0001, h)]
        bm_model = Model("tmp")
        bm_model.lathe(prof, key, segs, (0, 0, 0), scale=scale, smooth=smooth)
        rot = {"z": Matrix.Identity(4), "x": Matrix.Rotation(math.radians(90), 4, "Y"), "y": Matrix.Rotation(math.radians(-90), 4, "X")}[axis]
        bm = bm_model.bm
        bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts)
        self._merge(bm_model)

    def rod(self, p0, p1, r, key, segs=10, scale=0.3):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        m = Model("tmp")
        m.lathe([(r, 0.0), (r, d.length)], key, segs, scale=scale)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(m.bm, matrix=Matrix.Translation(p0) @ rot, verts=m.bm.verts)
        self._merge(m)

    def torus(self, c, R, r, key, segs=24, rsegs=8, axis="z", arc=TAU):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.verify()
        full = abs(arc - TAU) < 1e-6
        na = segs if full else segs + 1
        grid = []
        for i in range(na):
            a = arc * i / segs
            ring = []
            for j in range(rsegs):
                b = TAU * j / rsegs
                p = Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
                ring.append(bm.verts.new(p))
            grid.append(ring)
        for i in range(segs):
            ii = (i + 1) % na if full else i + 1
            for j in range(rsegs):
                jj = (j + 1) % rsegs
                f = bm.faces.new((grid[i][j], grid[ii][j], grid[ii][jj], grid[i][jj]))
                for lp, (u, v) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                    lp[uvl].uv = (u / segs * 4, v / rsegs)
        rot = {"z": Matrix.Identity(4), "x": Matrix.Rotation(math.radians(90), 4, "Y"), "y": Matrix.Rotation(math.radians(90), 4, "X")}[axis]
        bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot, verts=bm.verts)
        self._add(bm, key, True, uv=None)

    def blob(self, c, r, key, subdiv=2, rough=0.25, squash=(1, 1, 1), seed=0, scale=0.05):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
        off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
        for v in bm.verts:
            n = noise.noise(v.co * (6.0 / r) * 0.12 + off)
            v.co = v.co * (1.0 + n * rough)
            v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2]))
        bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
        self._add(bm, key, True, "box", scale, sharp_angle=80.0)

    def quad(self, pts, key, uvs=((0, 0), (1, 0), (1, 1), (0, 1)), double=False):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.verify()
        vs = [bm.verts.new(p) for p in pts]
        f = bm.faces.new(vs)
        for lp, uv in zip(f.loops, uvs):
            lp[uvl].uv = uv
        if double:
            vs2 = [bm.verts.new(p) for p in pts]
            f2 = bm.faces.new(list(reversed(vs2)))
            for lp, uv in zip(f2.loops, list(reversed(uvs))):
                lp[uvl].uv = uv
        self._add(bm, key, False, uv=None)

    def label_band(self, c, r, z0, z1, a0, a1, key, segs=16):
        """a printed label wrapped around a cylinder (UV 0..1)"""
        self.lathe([(r, z0), (r, z1)], key, segs, c, a0, a1, label=True, smooth=True)

    def _merge(self, other):
        # re-add another Model's geometry keeping material names
        remap = {i: self.mi(k) for i, k in enumerate(other.mats)}
        for f in other.bm.faces:
            f.material_index = remap[f.material_index]
        tmp = bpy.data.meshes.new("tmp")
        other.bm.to_mesh(tmp)
        other.bm.free()
        self.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)

    def finish(self):
        mesh = bpy.data.meshes.new(self.name + "_mesh")
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for key in self.mats:
            mesh.materials.append(material(key))
        obj = bpy.data.objects.new(self.name + "_model", mesh)
        bpy.context.collection.objects.link(obj)
        return obj


ROOTS = []
BOUNDS = {}


def drawable(m, boxes=None, lod=100.0):
    obj = m.finish()
    mesh_add_missing_uv_maps(obj.data)
    mesh_add_missing_color_attrs(obj.data)
    root = create_empty_object(SollumType.DRAWABLE, m.name)
    convert_obj_to_model(obj)
    obj.parent = root
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for v in obj.data.vertices:
        lo = Vector(map(min, lo, v.co))
        hi = Vector(map(max, hi, v.co))
    if boxes is None:
        boxes = [(tuple(lo), tuple(hi))]
    if boxes:
        comp = create_empty_object(SollumType.BOUND_COMPOSITE, m.name + "_col")
        comp.parent = root
        cmat = create_collision_material_from_index(0)
        for (mn, mx) in boxes:
            b = create_blender_object(SollumType.BOUND_BOX)
            size = Vector(mx) - Vector(mn)
            size = Vector((max(size.x, 0.004), max(size.y, 0.004), max(size.z, 0.004)))
            create_box(b.data, 1, Matrix.Diagonal(size))
            b.data.materials.append(cmat)
            b.location = (Vector(mn) + Vector(mx)) * 0.5
            b.parent = comp
            apply_flag_preset(b, "General (Default)")
    ROOTS.append(root)
    BOUNDS[m.name] = {"min": [round(c, 4) for c in lo], "max": [round(c, 4) for c in hi], "lod": lod}
    return root


# ═══════════════════════════ PROPS ═══════════════════════════

# ── pot + soil ─────────────────────────────────────────────
POT_TOP = 0.30


def pot():
    m = Model("nzw_pot")
    outer = [(0.115, 0.0), (0.12, 0.012), (0.15, POT_TOP - 0.02), (0.158, POT_TOP - 0.018), (0.158, POT_TOP), (0.148, POT_TOP + 0.004)]
    inner = [(0.14, POT_TOP), (0.135, POT_TOP - 0.02), (0.11, 0.03), (0.0001, 0.03)]
    m.lathe(outer + inner, "pblack", 40, scale=0.25, cap_bottom=True)
    for z in (0.08, 0.15, 0.22):  # moulded ribs
        r = 0.12 + (0.15 - 0.12) * (z / (POT_TOP - 0.02))
        m.torus((0, 0, z), r, 0.004, "pblack", 40, 6)
    for i in range(4):  # feet
        a = i * TAU / 4 + TAU / 8
        m.box((math.cos(a) * 0.09 - 0.015, math.sin(a) * 0.09 - 0.015, -0.006), (math.cos(a) * 0.09 + 0.015, math.sin(a) * 0.09 + 0.015, 0.002), "rubber")
    return drawable(m, [((-0.158, -0.158, 0), (0.158, 0.158, POT_TOP))], 60)


def soil():
    """soil surface (spawned into pots / the tent pot), origin at its bottom"""
    m = Model("nzw_soil")
    prof = [(0.0001, 0.0), (0.142, 0.0), (0.142, 0.012)]
    for k in range(1, 7):
        r = 0.142 * (1 - k / 7)
        prof.append((max(0.0001, r), 0.012 + 0.018 * math.sin(k / 7 * math.pi / 2)))
    m.lathe(prof, "soil", 40, scale=0.12)
    # a few clumps and perlite bits on top
    for i in range(14):
        a, r = random.random() * TAU, random.random() * 0.11
        z = 0.012 + 0.018 * math.cos(r / 0.142 * math.pi / 2)
        m.blob((math.cos(a) * r, math.sin(a) * r, z), 0.008 + random.random() * 0.008, "soil", 1, 0.4, (1, 1, 0.7), i, 0.12)
    return drawable(m, [], 40)


# ── grow tent ─────────────────────────────────────────────
TENT_W, TENT_H = 0.40, 1.60
TENT_POT_TOP = 0.26


def grow_tent():
    m = Model("nzw_growtent")
    W, H, T = TENT_W, TENT_H, 0.012
    # walls: fabric out, mylar in (two thin shells)
    for (mn, mx, inner_face) in (
        ((-W, W - T, 0), (W, W, H), "-y"),            # back
        ((-W, -W, 0), (-W + T, W, H), "+x"),           # left
        ((W - T, -W, 0), (W, W, H), "-x"),             # right
        ((-W, -W, H - T), (W, W, H), "-z"),            # roof
    ):
        m.box(mn, mx, "fabric", 0.004, 0.5)
        # mylar lining just inside
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        eps = 0.002
        a, b, z0, z1 = W - T, W - T, 0.02, H - T
        if inner_face == "-y":
            y = W - T - eps
            m.quad([(-a, y, z0), (a, y, z0), (a, y, z1), (-a, y, z1)], "mylar", ((0, 0), (2, 0), (2, 4), (0, 4)))
        elif inner_face == "+x":
            x = -W + T + eps
            m.quad([(x, -b, z0), (x, b, z0), (x, b, z1), (x, -b, z1)], "mylar", ((0, 0), (2, 0), (2, 4), (0, 4)))
        elif inner_face == "-x":
            x = W - T - eps
            m.quad([(x, b, z0), (x, -b, z0), (x, -b, z1), (x, b, z1)], "mylar", ((0, 0), (2, 0), (2, 4), (0, 4)))
        else:
            z = H - T - eps
            m.quad([(-a, -b, z), (-a, b, z), (a, b, z), (a, -b, z)], "mylar", ((0, 0), (0, 2), (2, 2), (2, 0)))
    # floor tray
    m.box((-W + T, -W + T, 0), (W - T, W - T, 0.02), "mylar", 0.0, 0.5)
    # front: header band with the brand, two side strips and a sill, door rolled up above
    m.box((-W, -W, 1.36), (W, -W + T, H), "fabric", 0.004)
    m.quad([(-0.3, -W - 0.0015, 1.43), (0.3, -W - 0.0015, 1.43), (0.3, -W - 0.0015, 1.55), (-0.3, -W - 0.0015, 1.55)], "lbl_tent")
    m.box((-W, -W, 0), (-0.29, -W + T, 1.36), "fabric", 0.004)
    m.box((0.29, -W, 0), (W, -W + T, 1.36), "fabric", 0.004)
    m.box((-0.29, -W, 0), (0.29, -W + T, 0.1), "fabric", 0.004)
    # rolled door + straps
    m.cyl((-0.29, -W - 0.04, 1.31), 0.04, 0.58, "fabric", 20, axis="x", scale=0.2)
    for x in (-0.18, 0.18):
        m.box((x - 0.012, -W - 0.086, 1.27), (x + 0.012, -W - 0.004, 1.36), "fabric_teal", 0.002)
    # teal zipper trims around the door and on every edge
    t = 0.012
    m.box((-0.296, -W - 0.004, 0.1), (-0.284, -W, 1.36), "fabric_teal")
    m.box((0.284, -W - 0.004, 0.1), (0.296, -W, 1.36), "fabric_teal")
    m.box((-0.296, -W - 0.004, 0.094), (0.296, -W, 0.106), "fabric_teal")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W - t / 2), sy * (W - t / 2)
            m.box((x - t / 2 - 0.003, y - t / 2 - 0.003, 0), (x + t / 2 + 0.003, y + t / 2 + 0.003, H + 0.003), "fabric_teal", 0.003)
    for s in (-1, 1):
        m.box((-W - 0.003, s * (W - t / 2) - t / 2 - 0.003, H - t), (W + 0.003, s * (W - t / 2) + t / 2 + 0.003, H + 0.003), "fabric_teal", 0.003)
        m.box((s * (W - t / 2) - t / 2 - 0.003, -W - 0.003, H - t), (s * (W - t / 2) + t / 2 + 0.003, W + 0.003, H + 0.003), "fabric_teal", 0.003)
    # side vent with mesh + duct port on the left
    m.box((W, 0.05, 0.22), (W + 0.004, 0.28, 0.42), "dark")
    m.cyl((-W - 0.05, 0.12, 1.3), 0.075, 0.05, "fabric", 24, axis="x", caps=False)
    m.torus((-W - 0.05, 0.12, 1.3), 0.075, 0.008, "fabric_teal", 24, 6, axis="x")
    # built-in LED panel (hangs from the roof) with an emissive underside
    m.box((-0.24, -0.16, 1.47), (0.24, 0.16, 1.51), "alu", 0.004)
    m.quad([(-0.22, 0.14, 1.469), (0.22, 0.14, 1.469), (0.22, -0.14, 1.469), (-0.22, -0.14, 1.469)], "led_white", ((0, 0), (1.6, 0), (1.6, 1), (0, 1)))
    for x in (-0.2, 0.2):
        for y in (-0.13, 0.13):
            m.rod((x, y, 1.51), (x * 0.6, y * 0.6, H - T), 0.0015, "steel", 6)
    # built-in fabric pot
    m.lathe([(0.15, 0.02), (0.16, 0.05), (0.165, TENT_POT_TOP - 0.01), (0.168, TENT_POT_TOP + 0.01), (0.155, TENT_POT_TOP + 0.012),
             (0.15, TENT_POT_TOP - 0.005), (0.14, 0.04), (0.0001, 0.04)], "fabric", 40, scale=0.3)
    m.torus((0, 0, TENT_POT_TOP + 0.004), 0.163, 0.007, "fabric_teal", 40, 6)
    for a in (0, math.pi):  # handles
        m.box((math.cos(a) * 0.168 - 0.005, -0.03, TENT_POT_TOP - 0.06), (math.cos(a) * 0.168 + 0.005, 0.03, TENT_POT_TOP - 0.02), "fabric_teal")
    walls = [((-W, W - T, 0), (W, W, H)), ((-W, -W, 0), (-W + T, W, H)), ((W - T, -W, 0), (W, W, H)), ((-W, -W, H - T), (W, W, H)),
             ((-W, -W, 1.36), (W, -W + T, H)), ((-0.17, -0.17, 0), (0.17, 0.17, TENT_POT_TOP))]
    return drawable(m, walls, 120)


# ── suspension rack ─────────────────────────────────────────────
RACK_W, RACK_D, RACK_H = 0.78, 0.36, 2.25
RACK_HANG = (0.0, 0.0, 1.86)   # where a light's hook goes (light origin)


def suspension_rack():
    m = Model("nzw_suspension_rack")
    W, D, H, s = RACK_W, RACK_D, RACK_H, 0.035
    for sx in (-1, 1):
        x = sx * W
        # A-frame legs
        for sy in (-1, 1):
            m.beam((x, sy * D, 0.03), (x, sy * 0.03, H - 0.04), s, s, "galv")
            m.box((x - 0.04, sy * D - 0.06, 0), (x + 0.04, sy * D + 0.06, 0.03), "rubber", 0.006)
        m.beam((x, -D * 0.62, 0.62), (x, D * 0.62, 0.62), s * 0.8, s * 0.8, "galv")
        # top joint plate
        m.box((x - 0.045, -0.07, H - 0.1), (x + 0.045, 0.07, H), "black", 0.006)
        for z in (0.62, H - 0.05):
            for sy in (-1, 1):
                m.cyl((x - 0.02, sy * (D * 0.62 if z < 1 else 0.04), z), 0.007, 0.04, "chrome", 10, axis="x")
    # top crossbar + a second rail for ratchet hangers
    m.beam((-W - 0.04, 0, H - 0.02), (W + 0.04, 0, H - 0.02), 0.05, 0.05, "galv")
    m.beam((-W + 0.05, 0, H - 0.09), (W - 0.05, 0, H - 0.09), 0.03, 0.03, "black")
    # ratchet hangers down to the light hook
    for x in (-0.18, 0.18):
        m.rod((x, 0, H - 0.1), (x * 0.35, 0, RACK_HANG[2] + 0.06), 0.0025, "black", 6)
        m.box((x * 0.6 - 0.012, -0.008, RACK_HANG[2] + 0.14), (x * 0.6 + 0.012, 0.008, RACK_HANG[2] + 0.2), "black", 0.003)
    m.torus((0, 0, RACK_HANG[2] + 0.05), 0.02, 0.003, "chrome", 16, 6, axis="y")
    boxes = []
    for sx in (-1, 1):
        boxes.append(((sx * W - 0.03, -D, 0), (sx * W + 0.03, D, H)))
    boxes.append(((-W - 0.04, -0.03, H - 0.12), (W + 0.04, 0.03, H)))
    return drawable(m, boxes, 120)


# ── grow lights (origin = hook point, everything hangs below) ─────────────────
def hang_wires(m, pts, top=(0, 0, 0)):
    for p in pts:
        m.rod(top, p, 0.0012, "steel", 5)
    m.torus((0, 0, -0.01), 0.012, 0.0025, "chrome", 12, 6, axis="y")


def light_halogen():
    m = Model("nzw_light_halogen")
    top = -0.32
    # parabolic hood: outer powder coat, inner hammered reflector
    outer = [(0.03, top), (0.12, top - 0.02), (0.2, top - 0.06), (0.25, top - 0.12), (0.27, top - 0.17), (0.272, top - 0.18)]
    m.lathe(list(reversed(outer)), "black", 40, scale=0.4)
    inner = [(r - 0.005, z - 0.008) for r, z in outer[:-1]] + [(0.267, top - 0.18)]
    m.lathe(inner, "reflector", 40, scale=0.2)
    m.torus((0, 0, top - 0.18), 0.271, 0.005, "steel", 40, 6)
    # socket + bulb (emissive)
    m.cyl((0, 0, top - 0.06), 0.03, 0.06, "pwhite", 16)
    m.lathe(list(reversed([(0.0001, top - 0.06), (0.03, top - 0.08), (0.034, top - 0.13), (0.026, top - 0.17), (0.0001, top - 0.18)])), "halogen", 24, scale=0.05)
    # ballast box on top with the brand plate
    m.box((-0.11, -0.07, top + 0.0), (0.11, 0.07, top + 0.1), "black", 0.008)
    m.quad([(-0.08, -0.0705, top + 0.025), (0.08, -0.0705, top + 0.025), (0.08, -0.0705, top + 0.075), (-0.08, -0.0705, top + 0.075)], "lbl_halogen")
    for x in (-0.09, 0.09):
        m.cyl((x, -0.08, top + 0.06), 0.008, 0.012, "rubber", 10, axis="y")
    m.rod((0.11, 0, top + 0.05), (0.2, 0.0, top + 0.14), 0.005, "rubber", 8)
    hang_wires(m, [(-0.09, -0.05, top + 0.1), (0.09, -0.05, top + 0.1), (-0.09, 0.05, top + 0.1), (0.09, 0.05, top + 0.1)])
    return drawable(m, [((-0.272, -0.272, top - 0.18), (0.272, 0.272, top + 0.1))], 100)


def light_led():
    m = Model("nzw_light_led")
    top = -0.34
    W, D, Hh = 0.32, 0.17, 0.065
    m.box((-W, -D, top - Hh), (W, D, top), "alu", 0.01, 0.3)
    # heat sink fins on top
    for k in range(13):
        x = -W + 0.04 + k * (2 * W - 0.08) / 12
        m.box((x - 0.003, -D + 0.02, top), (x + 0.003, D - 0.02, top + 0.025), "alu", 0.0)
    # two fans
    for x in (-0.16, 0.16):
        m.cyl((x, 0, top + 0.025), 0.06, 0.012, "black", 24)
        m.torus((x, 0, top + 0.037), 0.055, 0.003, "chrome", 24, 6)
        m.cyl((x, 0, top + 0.037), 0.016, 0.004, "lbl_led", 16)
    # emissive LED array (purple)
    m.quad([(-W + 0.015, D - 0.015, top - Hh - 0.0015), (W - 0.015, D - 0.015, top - Hh - 0.0015), (W - 0.015, -D + 0.015, top - Hh - 0.0015), (-W + 0.015, -D + 0.015, top - Hh - 0.0015)],
           "led_purple", ((0, 0), (3.2, 0), (3.2, 1.6), (0, 1.6)))
    # brand plate on the front edge
    m.quad([(-0.12, -D - 0.0015, top - Hh + 0.012), (0.12, -D - 0.0015, top - Hh + 0.012), (0.12, -D - 0.0015, top - 0.012), (-0.12, -D - 0.0015, top - 0.012)], "lbl_led")
    m.rod((W, 0, top - 0.03), (W + 0.12, 0, top + 0.12), 0.005, "rubber", 8)
    hang_wires(m, [(-W + 0.02, -D + 0.02, top), (W - 0.02, -D + 0.02, top), (-W + 0.02, D - 0.02, top), (W - 0.02, D - 0.02, top)])
    return drawable(m, [((-W, -D, top - Hh), (W, D, top + 0.04))], 100)


def light_fullspec():
    m = Model("nzw_light_fullspec")
    top = -0.32
    L, n = 0.5, 6
    # side rails
    for x in (-L, L):
        m.box((x - 0.018, -0.3, top - 0.03), (x + 0.018, 0.3, top), "alu", 0.004)
    # LED bars
    for k in range(n):
        y = -0.27 + k * 0.54 / (n - 1)
        m.box((-L + 0.02, y - 0.022, top - 0.028), (L - 0.02, y + 0.022, top - 0.004), "white", 0.004, 0.3)
        m.quad([(-L + 0.03, y + 0.018, top - 0.0295), (L - 0.03, y + 0.018, top - 0.0295), (L - 0.03, y - 0.018, top - 0.0295), (-L + 0.03, y - 0.018, top - 0.0295)],
               "led_white", ((0, 0), (5.0, 0), (5.0, 0.35), (0, 0.35)))
    # centre driver with the gold brand
    m.box((-0.13, -0.07, top), (0.13, 0.07, top + 0.06), "white", 0.008)
    m.quad([(-0.11, -0.0705, top + 0.012), (0.11, -0.0705, top + 0.012), (0.11, -0.0705, top + 0.05), (-0.11, -0.0705, top + 0.05)], "lbl_fullspec")
    m.box((-0.135, -0.075, top + 0.0), (0.135, 0.075, top + 0.004), "brass")
    m.cyl((0.1, -0.08, top + 0.03), 0.01, 0.012, "btn_green", 12, axis="y")
    m.rod((0.13, 0, top + 0.03), (0.24, 0, top + 0.14), 0.005, "rubber", 8)
    hang_wires(m, [(-L, -0.28, top), (L, -0.28, top), (-L, 0.28, top), (L, 0.28, top)])
    return drawable(m, [((-L - 0.02, -0.3, top - 0.03), (L + 0.02, 0.3, top + 0.06))], 100)


# ── drying rack ─────────────────────────────────────────────
DRY_W, DRY_D, DRY_H = 0.62, 0.24, 1.78
DRY_LINES = (1.68, 1.36, 1.04)


def drying_rack():
    m = Model("nzw_dryrack")
    W, D, H = DRY_W, DRY_D, DRY_H
    for sx in (-1, 1):
        x = sx * W
        for sy in (-1, 1):
            m.box((x - 0.025, sy * D - 0.025, 0.05), (x + 0.025, sy * D + 0.025, H), "wood", 0.004, 0.4)
        m.box((x - 0.035, -D - 0.08, 0), (x + 0.035, D + 0.08, 0.06), "wood", 0.006, 0.4)   # foot
        m.box((x - 0.022, -D, 0.42), (x + 0.022, D, 0.47), "wood", 0.004, 0.4)               # low brace
        m.box((x - 0.03, -D - 0.025, H - 0.05), (x + 0.03, D + 0.025, H), "wood", 0.004, 0.4)  # top cap
    for sy in (-1, 1):
        m.box((-W, sy * D - 0.02, H - 0.06), (W, sy * D + 0.02, H - 0.01), "wood", 0.004, 0.4)
    m.box((-W, -0.02, 0.42), (W, 0.02, 0.47), "wood", 0.004, 0.4)
    # bottom shelf slats
    for k in range(5):
        y = -D + 0.03 + k * (2 * D - 0.06) / 4
        m.box((-W + 0.03, y - 0.025, 0.47), (W - 0.03, y + 0.025, 0.485), "wood", 0.002, 0.4)
    # twine lines (front + back) with wooden pegs
    for z in DRY_LINES:
        for y in (-D + 0.005, D - 0.005):
            m.rod((-W, y, z), (W, y, z - 0.012), 0.0025, "twine", 6)
            m.cyl((-W - 0.004, y, z), 0.008, 0.012, "steel", 8, axis="x")
            m.cyl((W - 0.008, y, z - 0.012), 0.008, 0.012, "steel", 8, axis="x")
        for k in range(5):
            x = -W + 0.12 + k * (2 * W - 0.24) / 4
            for y in (-D + 0.005,):
                m.box((x - 0.005, y - 0.006, z - 0.05), (x + 0.005, y + 0.006, z + 0.012), "wood", 0.002, 0.1)
    boxes = [((sx * W - 0.03, -D - 0.08, 0), (sx * W + 0.03, D + 0.08, H)) for sx in (-1, 1)] + [((-W, -D, 0.42), (W, D, 0.485))]
    return drawable(m, boxes, 100)


def dry_anchors():
    out = []
    for z in DRY_LINES:
        for k in range(5):
            x = -DRY_W + 0.12 + k * (2 * DRY_W - 0.24) / 4
            out.append((round(x, 3), round(-DRY_D + 0.005, 3), round(z - 0.05, 3)))
    return out


# ── packaging station ─────────────────────────────────────────────
PK_W, PK_D, PK_TOP = 0.75, 0.36, 0.92
TRAY = (-0.52, -0.02)          # centre of the product tray (left)
MAT_C = (-0.04, -0.06)         # centre of the work mat (middle)
HATCH = (0.5, -0.03)           # centre of the hatch opening (right)
HATCH_W, HATCH_D, HATCH_H = 0.17, 0.2, 0.16


def pack_station():
    m = Model("nzw_packstation")
    W, D, Z = PK_W, PK_D, PK_TOP
    # table top + steel frame
    m.box((-W, -D, Z - 0.035), (W, D, Z), "steel", 0.006, 0.6)
    m.box((-W + 0.02, -D + 0.02, Z - 0.1), (W - 0.02, -D + 0.05, Z - 0.035), "black", 0.004)
    m.box((-W + 0.02, D - 0.05, Z - 0.1), (W - 0.02, D - 0.02, Z - 0.035), "black", 0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * (W - 0.05) - 0.025, sy * (D - 0.05) - 0.025, 0.02), (sx * (W - 0.05) + 0.025, sy * (D - 0.05) + 0.025, Z - 0.035), "black", 0.004)
            m.cyl((sx * (W - 0.05), sy * (D - 0.05), 0), 0.03, 0.02, "rubber", 12)
        m.box((sx * (W - 0.05) - 0.02, -D + 0.05, 0.14), (sx * (W - 0.05) + 0.02, D - 0.05, 0.17), "black", 0.004)
    m.box((-W + 0.06, -0.3, 0.17), (W - 0.06, 0.3, 0.19), "steel", 0.003)  # lower shelf
    # back upright with a shelf and a light bar
    for sx in (-1, 1):
        m.box((sx * (W - 0.04) - 0.02, D - 0.06, Z), (sx * (W - 0.04) + 0.02, D - 0.02, 1.75), "black", 0.004)
    m.box((-W + 0.03, D - 0.2, 1.36), (W - 0.03, D - 0.02, 1.38), "steel", 0.003)
    m.box((-W + 0.03, D - 0.16, 1.7), (W - 0.03, D - 0.02, 1.75), "black", 0.006)
    m.quad([(-W + 0.06, D - 0.04, 1.6995), (W - 0.06, D - 0.04, 1.6995), (W - 0.06, D - 0.14, 1.6995), (-W + 0.06, D - 0.14, 1.6995)], "led_white", ((0, 0), (6, 0), (6, 0.5), (0, 0.5)))
    # LEFT: white product tray with a rim
    tx, ty = TRAY
    tw, td, th = 0.19, 0.15, 0.035
    m.box((tx - tw, ty - td, Z), (tx + tw, ty + td, Z + 0.006), "pwhite", 0.003, 0.3)
    for (mn, mx) in (((tx - tw, ty - td, Z), (tx + tw, ty - td + 0.008, Z + th)), ((tx - tw, ty + td - 0.008, Z), (tx + tw, ty + td, Z + th)),
                     ((tx - tw, ty - td, Z), (tx - tw + 0.008, ty + td, Z + th)), ((tx + tw - 0.008, ty - td, Z), (tx + tw, ty + td, Z + th))):
        m.box(mn, mx, "pwhite", 0.003, 0.3)
    # MIDDLE: self-healing cutting mat
    mx_, my_ = MAT_C
    m.box((mx_ - 0.24, my_ - 0.2, Z), (mx_ + 0.24, my_ + 0.24, Z + 0.004), "cutmat", 0.0, 0.25)
    # RIGHT: hatch box (chute) with an opening on top; the lid is a separate prop
    hx, hy = HATCH
    hw, hd, hh = HATCH_W, HATCH_D, HATCH_H
    wall = 0.012
    for (mn, mx) in (((hx - hw, hy - hd, Z), (hx + hw, hy - hd + wall, Z + hh)), ((hx - hw, hy + hd - wall, Z), (hx + hw, hy + hd, Z + hh)),
                     ((hx - hw, hy - hd, Z), (hx - hw + wall, hy + hd, Z + hh)), ((hx + hw - wall, hy - hd, Z), (hx + hw, hy + hd, Z + hh))):
        m.box(mn, mx, "steel", 0.003, 0.3)
    m.box((hx - hw + wall, hy - hd + wall, Z + 0.001), (hx + hw - wall, hy + hd - wall, Z + 0.004), "dark")   # dark shaft
    m.box((hx - 0.06, hy - hd - 0.002, Z + 0.05), (hx + 0.06, hy - hd, Z + 0.1), "teal", 0.002)            # teal plate
    # hinge barrel at the back
    m.cyl((hx - hw + 0.01, hy + hd - 0.005, Z + hh + 0.006), 0.007, 2 * hw - 0.02, "steel", 10, axis="x")
    # drop bin under the table, below the hatch
    m.box((hx - 0.16, hy - 0.2, 0.2), (hx + 0.16, hy + 0.2, 0.22), "black", 0.003)
    for (mn, mx) in (((hx - 0.16, hy - 0.2, 0.2), (hx + 0.16, hy - 0.19, 0.5)), ((hx - 0.16, hy + 0.19, 0.2), (hx + 0.16, hy + 0.2, 0.5)),
                     ((hx - 0.16, hy - 0.2, 0.2), (hx - 0.15, hy + 0.2, 0.5)), ((hx + 0.15, hy - 0.2, 0.2), (hx + 0.16, hy + 0.2, 0.5))):
        m.box(mn, mx, "pblack", 0.003, 0.3)
    m.box((hx - hw, hy - hd, Z - 0.1), (hx + hw, hy + hd, Z - 0.035), "steel", 0.003)  # chute under the top
    # small scale on the back shelf + roll of baggies
    m.box((0.12, D - 0.17, Z), (0.3, D - 0.05, Z + 0.03), "black", 0.006)
    m.box((0.14, D - 0.15, Z + 0.03), (0.28, D - 0.07, Z + 0.034), "steel", 0.002)
    m.quad([(0.17, D - 0.1705 , Z + 0.008), (0.25, D - 0.1705, Z + 0.008), (0.25, D - 0.1705, Z + 0.024), (0.17, D - 0.1705, Z + 0.024)], "led_white", ((0, 0), (0.3, 0), (0.3, 0.1), (0, 0.1)))
    boxes = [((-W, -D, Z - 0.1), (W, D, Z)), ((-W, -D, 0), (W, D, 0.2)), ((-W, D - 0.06, Z), (W, D, 1.75)),
             ((hx - hw, hy - hd, Z), (hx + hw, hy + hd, Z + hh))]
    return drawable(m, boxes, 100)


def pack_hatch():
    """hatch lid. origin = hinge (back edge, top). Lid spans -Y. Rotate on X, negative opens."""
    m = Model("nzw_packstation_hatch")
    w, d = HATCH_W + 0.004, 2 * HATCH_D + 0.004
    m.box((-w, -d, -0.002), (w, 0.0, 0.012), "steel", 0.003, 0.3)
    m.box((-w + 0.02, -d + 0.02, 0.012), (w - 0.02, -0.02, 0.015), "black", 0.002)
    # handle
    m.box((-0.05, -d - 0.022, 0.0), (0.05, -d - 0.012, 0.03), "black", 0.003)
    for x in (-0.045, 0.045):
        m.box((x - 0.006, -d - 0.016, 0.0), (x + 0.006, -d + 0.002, 0.012), "black", 0.002)
    m.quad([(-0.06, -d / 2 - 0.03, 0.0151), (0.06, -d / 2 - 0.03, 0.0151), (0.06, -d / 2 + 0.03, 0.0151), (-0.06, -d / 2 + 0.03, 0.0151)], "lbl_jar", ((0, 0), (1, 0), (1, 1), (0, 1)))
    return drawable(m, [((-w, -d, -0.002), (w, 0.0, 0.015))], 60)


# ── mixing station ─────────────────────────────────────────────
MX_W, MX_D, MX_TOP = 0.62, 0.32, 0.9
BOWL = (0.28, 0.0)
BOWL_Z = MX_TOP + 0.22


def mix_station():
    m = Model("nzw_mixstation")
    W, D, Z = MX_W, MX_D, MX_TOP
    m.box((-W, -D, Z - 0.04), (W, D, Z), "steel", 0.006, 0.6)
    m.box((-W + 0.03, -D + 0.03, 0.12), (W - 0.03, D - 0.03, 0.14), "steel", 0.003)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.cyl((sx * (W - 0.05), sy * (D - 0.05), 0.0), 0.022, Z - 0.04, "steel", 14, scale=0.4)
            m.cyl((sx * (W - 0.05), sy * (D - 0.05), 0.0), 0.028, 0.02, "rubber", 14)
    # machine: base cabinet, column, head over the bowl
    bx, by = BOWL
    m.box((bx - 0.2, by - 0.22, Z), (bx + 0.2, by + 0.2, Z + 0.2), "white", 0.012, 0.4)
    m.quad([(bx - 0.18, by - 0.2205, Z + 0.02), (bx + 0.18, by - 0.2205, Z + 0.02), (bx + 0.18, by - 0.2205, Z + 0.18), (bx - 0.18, by - 0.2205, Z + 0.18)], "panel_mixer")
    m.cyl((bx, by, Z + 0.2), 0.12, 0.02, "steel", 32)                     # turntable the bowl sits on
    m.box((bx - 0.07, by + 0.12, Z + 0.2), (bx + 0.07, by + 0.2, Z + 0.62), "white", 0.012, 0.4)  # column
    m.box((bx - 0.09, by - 0.1, Z + 0.56), (bx + 0.09, by + 0.2, Z + 0.68), "white", 0.02, 0.4)    # head
    m.cyl((bx, by, Z + 0.47), 0.02, 0.09, "chrome", 14)                  # spindle
    # dough-hook style paddle in the bowl
    m.rod((bx, by, Z + 0.47), (bx + 0.04, by, Z + 0.3), 0.01, "chrome", 10)
    m.rod((bx + 0.04, by, Z + 0.3), (bx - 0.02, by + 0.02, Z + 0.25), 0.01, "chrome", 10)
    # buttons (physical, the panel shows the rest)
    for i, k in enumerate(("btn_green", "btn_red")):
        m.cyl((bx + 0.05 + i * 0.09, by - 0.232, Z + 0.135), 0.022, 0.014, k, 18, axis="y")
    # ingredient tray (left) + product spot
    m.box((-0.5, -0.18, Z), (-0.08, 0.18, Z + 0.004), "cutmat", 0.0, 0.25)
    m.box((-0.5, 0.2, Z), (-0.08, 0.28, Z + 0.1), "black", 0.006)       # tool caddy
    boxes = [((-W, -D, 0), (W, D, Z)), ((bx - 0.2, by - 0.22, Z), (bx + 0.2, by + 0.2, Z + 0.2)), ((bx - 0.09, by - 0.1, Z + 0.2), (bx + 0.09, by + 0.2, Z + 0.68))]
    return drawable(m, boxes, 100)


def mix_bowl():
    """origin = centre of the bowl's base. Spins on Z."""
    m = Model("nzw_mixstation_bowl")
    prof = [(0.0001, 0.0), (0.06, 0.0), (0.1, 0.02), (0.125, 0.07), (0.135, 0.13), (0.14, 0.15), (0.146, 0.152),
            (0.132, 0.148), (0.127, 0.13), (0.117, 0.075), (0.093, 0.028), (0.055, 0.01), (0.0001, 0.01)]
    m.lathe(prof, "steel", 48, scale=0.3)
    for a in (0, math.pi):
        m.torus((math.cos(a) * 0.15, 0, 0.12), 0.02, 0.005, "steel", 12, 6, axis="y", arc=math.pi)
    return drawable(m, [((-0.146, -0.146, 0), (0.146, 0.146, 0.152))], 60)


# ── brick press ─────────────────────────────────────────────
BP_TOP = 0.82            # top of the cabinet / mould floor
BP_RAM_Z = 1.5           # bottom of the cylinder = top of the plate prop
BP_LEVER = (0.36, -0.05, 0.98)


def brick_press():
    m = Model("nzw_brickpress")
    Z = BP_TOP
    # cabinet
    m.box((-0.34, -0.28, 0.0), (0.34, 0.28, Z), "red", 0.012, 0.6)
    m.box((-0.3, -0.282, 0.4), (0.3, -0.28, 0.75), "black", 0.0)
    m.quad([(-0.24, -0.2835, 0.45), (0.24, -0.2835, 0.45), (0.24, -0.2835, 0.7), (-0.24, -0.2835, 0.7)], "panel_press")
    m.box((-0.36, -0.3, 0.0), (0.36, 0.3, 0.05), "black", 0.006)
    # mould box (open top)
    w, d, h = 0.16, 0.11, 0.12
    for (mn, mx) in (((-w, -d, Z), (w, -d + 0.015, Z + h)), ((-w, d - 0.015, Z), (w, d, Z + h)), ((-w, -d, Z), (-w + 0.015, d, Z + h)), ((w - 0.015, -d, Z), (w, d, Z + h))):
        m.box(mn, mx, "steel", 0.003, 0.3)
    m.box((-w, -d, Z), (w, d, Z + 0.01), "steel", 0.0, 0.3)
    # columns + top beam + cylinder
    for x in (-0.25, 0.25):
        m.cyl((x, 0, Z), 0.03, 1.02, "chrome", 20, scale=0.4)
        m.cyl((x, 0, Z), 0.05, 0.03, "black", 20)
        m.cyl((x, 0, Z + 0.86), 0.05, 0.03, "black", 20)
    m.box((-0.33, -0.1, Z + 0.88), (0.33, 0.1, Z + 1.04), "red", 0.012, 0.5)
    m.cyl((0, 0, BP_RAM_Z), 0.085, Z + 0.88 - BP_RAM_Z, "black", 28)
    m.cyl((0, 0, BP_RAM_Z - 0.01), 0.07, 0.01, "steel", 28)
    m.cyl((0, 0, Z + 1.04), 0.05, 0.08, "black", 20)
    m.cyl((-0.02, -0.06, Z + 1.06), 0.03, 0.03, "chrome", 16, axis="y")   # gauge
    m.cyl((-0.02, -0.061, Z + 1.06), 0.026, 0.002, "pwhite", 16, axis="y")
    # hydraulic hose + pump housing for the lever
    m.box((0.3, -0.12, 0.85), (0.42, 0.04, 1.0), "black", 0.01)
    m.rod((0.36, 0.0, 1.0), (0.2, 0.0, Z + 0.95), 0.012, "rubber", 8)
    boxes = [((-0.36, -0.3, 0), (0.36, 0.3, Z)), ((-0.33, -0.1, Z + 0.88), (0.33, 0.1, Z + 1.12)),
             ((-0.28, -0.03, Z), (-0.22, 0.03, Z + 0.9)), ((0.22, -0.03, Z), (0.28, 0.03, Z + 0.9)), ((0.3, -0.12, 0.85), (0.42, 0.04, 1.0))]
    return drawable(m, boxes, 100)


def press_plate():
    """origin = top of the ram (sits at BP_RAM_Z). Slide down on -Z."""
    m = Model("nzw_brickpress_plate")
    m.cyl((0, 0, -0.32), 0.045, 0.32, "chrome", 24, scale=0.3)
    m.box((-0.145, -0.095, -0.36), (0.145, 0.095, -0.32), "steel", 0.004, 0.3)
    m.box((-0.15, -0.1, -0.33), (0.15, 0.1, -0.31), "black", 0.003)
    return drawable(m, [((-0.15, -0.1, -0.36), (0.15, 0.1, 0.0))], 60)


def press_lever():
    """origin = pivot of the pump handle. Rest = up and back; rotate on X to pump."""
    m = Model("nzw_brickpress_lever")
    m.cyl((-0.03, 0, 0), 0.025, 0.06, "black", 16, axis="x")
    m.rod((0, 0, 0), (0, -0.05, 0.6), 0.013, "chrome", 12)
    m.cyl((0, -0.05, 0.6), 0.022, 0.14, "rubber", 16)   # grip
    return drawable(m, [((-0.03, -0.08, -0.03), (0.03, 0.03, 0.75))], 60)


# ── packaging + product ─────────────────────────────────────────────
def jar():
    m = Model("nzw_jar")
    prof = [(0.0001, 0.0), (0.04, 0.0), (0.046, 0.006), (0.047, 0.09), (0.042, 0.1), (0.036, 0.104), (0.036, 0.118)]
    m.lathe(prof, "glass", 32, scale=0.1)
    m.lathe([(0.0365, 0.106), (0.0385, 0.108), (0.0365, 0.11), (0.0385, 0.112), (0.0365, 0.114)], "glass", 32, scale=0.1)  # thread
    m.label_band((0, 0, 0), 0.0475, 0.03, 0.07, -math.pi * 0.8, -math.pi * 0.2, "lbl_jar")
    return drawable(m, [((-0.047, -0.047, 0), (0.047, 0.047, 0.118))], 40)


def jar_lid():
    m = Model("nzw_jar_lid")
    m.lathe([(0.038, 0.0), (0.041, 0.0), (0.04, 0.018), (0.036, 0.02), (0.0001, 0.02)], "pblack", 32, scale=0.05)
    for i in range(36):
        a = i * TAU / 36
        m.box((math.cos(a) * 0.0405 - 0.001, math.sin(a) * 0.0405 - 0.001, 0.002), (math.cos(a) * 0.0405 + 0.001, math.sin(a) * 0.0405 + 0.001, 0.017), "pblack")
    m.cyl((0, 0, 0.0201), 0.026, 0.0008, "teal", 24)
    return drawable(m, [((-0.041, -0.041, 0), (0.041, 0.041, 0.02))], 40)


def bag_sheets(m, w, h, puff, mouth):
    """two plastic sheets, bowed out, with an optional open mouth"""
    nx, nz = 6, 8
    for side in (-1, 1):
        pts = []
        for j in range(nz + 1):
            row = []
            for i in range(nx + 1):
                u, v = i / nx, j / nz
                x = (u - 0.5) * w
                z = v * h
                bow = puff * math.sin(u * math.pi) * math.sin(min(1.0, v * 1.15) * math.pi * 0.9)
                y = side * (0.0008 + bow)
                if mouth and v > 0.82:
                    y += side * mouth * ((v - 0.82) / 0.18) ** 1.5 * math.sin(u * math.pi)
                row.append((x, y, z))
            pts.append(row)
        for j in range(nz):
            for i in range(nx):
                q = [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
                uv = [(i / nx, j / nz), ((i + 1) / nx, j / nz), ((i + 1) / nx, (j + 1) / nz), (i / nx, (j + 1) / nz)]
                if side > 0:
                    q, uv = list(reversed(q)), list(reversed(uv))
                m.quad(q, "bag", uv, double=True)
    # zip strip + write-on band
    zt = h - 0.014
    for side in (-1, 1):
        y = side * (0.0012 + (mouth * 0.5 if mouth else 0.0))
        m.box((-w / 2 + 0.002, y - 0.0006, zt), (w / 2 - 0.002, y + 0.0006, zt + 0.004), "pblue")
    m.quad([(-w / 2 + 0.006, -0.0025, h * 0.62), (w / 2 - 0.006, -0.0025, h * 0.62), (w / 2 - 0.006, -0.0025, h * 0.74), (-w / 2 + 0.006, -0.0025, h * 0.74)], "pwhite", ((0, 0), (0.2, 0), (0.2, 0.05), (0, 0.05)))


def baggie(name, mouth):
    m = Model(name)
    bag_sheets(m, 0.075, 0.1, 0.012 if mouth else 0.015, 0.012 if mouth else 0.0)
    return drawable(m, [((-0.04, -0.02, 0), (0.04, 0.02, 0.1))], 30)


def brick():
    m = Model("nzw_brick")
    L, W, H = 0.12, 0.08, 0.05
    m.box((-L, -W, 0), (L, W, H), "compressed", 0.012, 0.12, 3)
    m.box((-L - 0.002, -W - 0.002, -0.001), (L + 0.002, W + 0.002, H + 0.002), "cling", 0.014, 0.3, 3)
    # tape band + marker label
    m.box((-0.045, -W - 0.003, -0.002), (0.045, W + 0.003, H + 0.003), "tape", 0.012, 0.2, 3)
    m.quad([(-0.04, -0.02, H + 0.0035), (0.04, -0.02, H + 0.0035), (0.04, 0.02, H + 0.0035), (-0.04, 0.02, H + 0.0035)], "lbl_brick")
    return drawable(m, [((-L, -W, 0), (L, W, H))], 40)


def bud(name, key, seed):
    random.seed(seed)
    m = Model(name)
    height = 0.075
    n = 16
    for i in range(n):
        t = i / (n - 1)
        z = 0.008 + t * height * 0.88
        r = (0.017 * math.sin(min(1.0, t * 1.1) * math.pi) + 0.006) * (0.85 + random.random() * 0.3)
        a = random.random() * TAU
        off = 0.006 * (1 - t)
        m.blob((math.cos(a) * off, math.sin(a) * off, z), r, key, 2, 0.35, (1, 1, 1.25), seed * 10 + i, 0.05)
    # small sugar leaves
    for i in range(5):
        a = random.random() * TAU
        z = 0.015 + random.random() * 0.04
        base = Vector((math.cos(a) * 0.012, math.sin(a) * 0.012, z))
        out = Vector((math.cos(a), math.sin(a), 0.5)).normalized()
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.005
        tip = base + out * 0.03
        mid = base + out * 0.015
        m.quad([base - side * 0.3, mid - side, tip, mid + side], "leaf", ((0.4, 0), (0, 0.5), (0.5, 1), (1, 0.5)), double=True)
    m.cyl((0, 0, -0.006), 0.0025, 0.014, "leaf", 6)
    for v in m.bm.verts:
        v.co *= 0.68
    return drawable(m, [((-0.016, -0.016, -0.004), (0.016, 0.016, 0.056))], 30)


# ── consumables / tools ─────────────────────────────────────────────
def bottle_speed():
    m = Model("nzw_speedgrow")
    prof = [(0.0001, 0.0), (0.038, 0.0), (0.042, 0.006), (0.043, 0.15), (0.036, 0.18), (0.016, 0.2), (0.015, 0.215)]
    m.lathe(prof, "pblack", 32, scale=0.2)
    m.label_band((0, 0, 0), 0.0436, 0.03, 0.14, -math.pi * 0.95, -math.pi * 0.05, "lbl_speed", 24)
    m.lathe([(0.0001, 0.212), (0.019, 0.212), (0.02, 0.24), (0.017, 0.245), (0.0001, 0.245)], "porange", 24, scale=0.05)
    return drawable(m, [((-0.043, -0.043, 0), (0.043, 0.043, 0.245))], 40)


def bottle_pgr():
    m = Model("nzw_pgr")
    # square-ish jug with a handle
    m.box((-0.05, -0.035, 0.0), (0.05, 0.035, 0.17), "pwhite", 0.02, 0.2, 3)
    m.lathe([(0.03, 0.165), (0.018, 0.19), (0.016, 0.205)], "pwhite", 24, scale=0.05)
    m.lathe([(0.0001, 0.2), (0.02, 0.2), (0.021, 0.225), (0.0001, 0.226)], "red", 24, scale=0.05)
    m.torus((0.035, 0.0, 0.135), 0.03, 0.009, "pwhite", 16, 8, axis="y", arc=math.pi)
    m.quad([(-0.045, -0.0355, 0.025), (0.045, -0.0355, 0.025), (0.045, -0.0355, 0.125), (-0.045, -0.0355, 0.125)], "lbl_pgr", ((0, 0.05), (1, 0.05), (1, 0.95), (0, 0.95)))
    return drawable(m, [((-0.05, -0.035, 0), (0.07, 0.035, 0.226))], 40)


def bottle_fert():
    m = Model("nzw_fertilizer")
    prof = [(0.0001, 0.0), (0.04, 0.0), (0.044, 0.008), (0.044, 0.15), (0.03, 0.18), (0.015, 0.195), (0.015, 0.205)]
    m.lathe(prof, "pwhite", 32, scale=0.2)
    m.label_band((0, 0, 0), 0.0445, 0.03, 0.14, -math.pi * 0.95, -math.pi * 0.05, "lbl_fert", 24)
    # trigger sprayer head
    m.cyl((0, 0, 0.2), 0.02, 0.03, "pgreen", 20)
    m.box((-0.018, -0.07, 0.225), (0.018, 0.02, 0.26), "pgreen", 0.008)
    m.box((-0.008, -0.085, 0.235), (0.008, -0.07, 0.25), "pblack", 0.002)
    m.box((-0.012, -0.06, 0.17), (0.012, -0.035, 0.225), "pgreen", 0.006)   # trigger
    m.rod((0, 0.0, 0.2), (0.0, 0.0, 0.02), 0.003, "pwhite", 6)            # dip tube
    return drawable(m, [((-0.044, -0.085, 0), (0.044, 0.044, 0.26))], 40)


def soil_bag():
    m = Model("nzw_soilbag")
    w, d, h = 0.2, 0.07, 0.5
    m.box((-w, -d, 0), (w, d, h), "pblack", 0.05, 0.3, 4)
    # crimped top seal
    m.box((-w + 0.01, -0.012, h - 0.01), (w - 0.01, 0.012, h + 0.03), "pblack", 0.006)
    for side, uvs in ((-1, ((0, 0.08), (1, 0.08), (1, 0.98), (0, 0.98))), (1, ((0, 0.08), (1, 0.08), (1, 0.98), (0, 0.98)))):
        y = side * (d + 0.0015)
        pts = [(-w + 0.03, y, 0.04), (w - 0.03, y, 0.04), (w - 0.03, y, h - 0.04), (-w + 0.03, y, h - 0.04)]
        if side > 0:
            pts = [pts[1], pts[0], pts[3], pts[2]]
        m.quad(pts, "lbl_soil", uvs)
    return drawable(m, [((-w, -d, 0), (w, d, h + 0.03))], 60)


def watering_can():
    m = Model("nzw_wateringcan")
    prof = [(0.0001, 0.0), (0.09, 0.0), (0.095, 0.01), (0.095, 0.2), (0.085, 0.22), (0.05, 0.235), (0.045, 0.24)]
    m.lathe(prof, "galv", 36, scale=0.3)
    m.torus((0, 0, 0.005), 0.093, 0.006, "galv", 36, 6)
    m.cyl((0, 0, 0.24), 0.045, 0.02, "galv", 24, caps=False)
    # spout + rose
    m.rod((0, -0.07, 0.04), (0, -0.33, 0.27), 0.012, "galv", 12)
    m.cyl((0, -0.345, 0.285), 0.028, 0.012, "steel", 20, axis="y")
    # handle (top arc) + back grip
    m.torus((0, 0.0, 0.24), 0.07, 0.01, "galv", 20, 8, axis="x", arc=math.pi)
    m.rod((0, 0.095, 0.2), (0, 0.12, 0.08), 0.01, "galv", 10)
    return drawable(m, [((-0.095, -0.35, 0), (0.095, 0.13, 0.32))], 50)


def trimmers():
    m = Model("nzw_trimmers")
    # blades (pointing -Y) + spring + loop handles
    for s in (-1, 1):
        m.beam((s * 0.002, 0.0, 0.004), (s * 0.006, -0.07, 0.004), 0.006, 0.0025, "steel", bevel=0.0005)
        m.beam((0.0, 0.01, 0.004), (s * 0.03, 0.08, 0.004), 0.012, 0.012, "pgreen", bevel=0.003)
        m.torus((s * 0.032, 0.09, 0.004), 0.016, 0.005, "pgreen", 18, 6)
    m.cyl((0, 0.0, 0.0), 0.005, 0.01, "chrome", 12)
    m.torus((0, 0.03, 0.004), 0.01, 0.0015, "steel", 12, 4)
    return drawable(m, [((-0.05, -0.07, 0), (0.05, 0.11, 0.012))], 30)


def seed_vial():
    m = Model("nzw_seedvial")
    m.lathe([(0.0001, 0.0), (0.011, 0.0), (0.013, 0.004), (0.013, 0.06)], "glass", 20, scale=0.05)
    m.label_band((0, 0, 0), 0.0134, 0.012, 0.045, -math.pi * 0.9, -math.pi * 0.1, "lbl_seeds", 12)
    for i, z in enumerate((0.006, 0.012, 0.009)):
        m.blob(((i - 1) * 0.005, 0.002 * (i - 1), z), 0.0035, "seed", 1, 0.1, (1, 0.75, 1.35), i, 0.01)
    m.lathe([(0.0001, 0.058), (0.0145, 0.058), (0.0145, 0.075), (0.0001, 0.075)], "pgreen", 20, scale=0.05)
    return drawable(m, [((-0.0145, -0.0145, 0), (0.0145, 0.0145, 0.075))], 20)


# ═══════════════════════════ build ═══════════════════════════
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

pot()
soil()
grow_tent()
suspension_rack()
light_halogen()
light_led()
light_fullspec()
drying_rack()
pack_station()
pack_hatch()
mix_station()
mix_bowl()
brick_press()
press_plate()
press_lever()
jar()
jar_lid()
baggie("nzw_baggie", True)
baggie("nzw_baggie_sealed", False)
brick()
for color, seed in (("green", 1), ("purple", 2), ("lime", 3), ("golden", 4)):
    bud("nzw_bud_" + color, "bud_" + color, seed)
bottle_speed()
bottle_pgr()
bottle_fert()
soil_bag()
watering_can()
trimmers()
seed_vial()

bpy.context.view_layer.update()

# anchors the script uses (printed so config/equipment.lua can be checked against them)
ANCHORS = {
    "pot_soil_z": POT_TOP - 0.04,
    "tent_soil_z": TENT_POT_TOP - 0.03,
    "rack_hang": RACK_HANG,
    "dry_slots": dry_anchors(),
    "pack": {"top": PK_TOP, "tray": TRAY, "mat": MAT_C, "hatch": HATCH, "hatch_hinge": (HATCH[0], HATCH[1] + HATCH_D, PK_TOP + HATCH_H + 0.006)},
    "mix": {"top": MX_TOP, "bowl": (BOWL[0], BOWL[1], MX_TOP + 0.22)},
    "press": {"top": BP_TOP, "ram": BP_RAM_Z, "lever": BP_LEVER},
}
json.dump({"bounds": BOUNDS, "anchors": ANCHORS}, open(os.path.join(BUILD, "bounds.json"), "w"), indent=1)
for name, b in BOUNDS.items():
    print("BOUNDS", name, b["min"], b["max"])

# shared texture dictionary (CodeWalker XML)
items = []
for name in sorted(TEX):
    t = TEX[name]
    items.append(f"""  <Item>
    <Name>{name}</Name>
    <Unk32 value="0" />
    <Usage>DEFAULT</Usage>
    <ExtraFlags value="0" />
    <Width value="{t['size'][0]}" />
    <Height value="{t['size'][1]}" />
    <MipLevels value="0" />
    <Format>{t['format']}</Format>
    <FileName>{name}.dds</FileName>
  </Item>""")
open(os.path.join(XML, "nzw_weedlab.ytd.xml"), "w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n<TextureDictionary>\n' + "\n".join(items) + "\n</TextureDictionary>\n")

bpy.ops.object.select_all(action="DESELECT")
for r in ROOTS:
    r.select_set(True)
res = bpy.ops.sollumz.export_assets(
    directory=XML, direct_export=True, use_custom_settings=True,
    target_formats={"CWXML"}, target_versions={"GEN8"}, limit_to_selected=True,
    exclude_skeleton=False, ymap_exclude_entities=False, ymap_box_occluders=False, ymap_model_occluders=False,
)
print("EXPORT", res)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BUILD, "weedlab_props.blend"))
